#!/usr/bin/env bash
# demo.sh – MergeX end-to-end demo
# Usage: bash demo.sh
# Requires: forge, anvil, cast (Foundry), python3, web3.py, requests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Cleanup on exit ───────────────────────────────────────────────────────────
PIDS=()
cleanup() {
  echo ""
  echo "==> Cleaning up background processes..."
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

# ── 1. Start Anvil ───────────────────────────────────────────────────────────
echo "==> Starting Anvil..."
anvil --port 8545 --block-time 1 >/tmp/anvil.log 2>&1 &
ANVIL_PID=$!
PIDS+=("$ANVIL_PID")
sleep 2
echo "    Anvil running (pid $ANVIL_PID)"

RPC="http://127.0.0.1:8545"

PYTHON_BIN="python"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import web3' >/dev/null 2>&1; then
  PYTHON_BIN="python3"
fi

# Anvil deterministic accounts (indices 0-3)
HOST_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
BOB_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
EVE_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
ORACLE_KEY="0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"

HOST_ADDR="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
BOB_ADDR="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
ORACLE_ADDR="0x90F79bf6EB2c4f870365E785982E1f101E93b906"

# ── 2. Build contracts ────────────────────────────────────────────────────────
echo ""
echo "==> Building contracts..."
forge build --quiet

# ── 3. Deploy MergeXHub (Race, 3600s deadline) ───────────────────────────────
echo ""
echo "==> Deploying MergeXHub (MilestoneRace, 3600s deadline)..."
DEPLOY_OUT=$(forge create src/MergeXHub.sol:MergeXHub \
  --broadcast \
  --rpc-url "$RPC" \
  --private-key "$HOST_KEY" \
  --constructor-args "$ORACLE_ADDR" 0 3600 2>&1)
HUB_ADDR=$(echo "$DEPLOY_OUT" | grep "Deployed to:" | awk '{print $3}')
echo "    MergeXHub (Race) deployed at: $HUB_ADDR"

# ── 4. Register dev_bob and dev_eve ──────────────────────────────────────────
echo ""
echo "==> Registering dev_bob..."
cast send "$HUB_ADDR" "registerDeveloper(string)" "dev_bob" \
  --rpc-url "$RPC" --private-key "$BOB_KEY" --quiet

echo "==> Registering dev_eve..."
cast send "$HUB_ADDR" "registerDeveloper(string)" "dev_eve" \
  --rpc-url "$RPC" --private-key "$EVE_KEY" --quiet

# ── 5. Fund the prize pool ────────────────────────────────────────────────────
echo ""
echo "==> Funding prize pool with 1 ETH..."
cast send "$HUB_ADDR" "fundPrizePool()" \
  --value 1ether \
  --rpc-url "$RPC" --private-key "$HOST_KEY" --quiet

# ── 6. Balance before settlement ─────────────────────────────────────────────
echo ""
BOB_BEFORE=$(cast balance "$BOB_ADDR" --rpc-url "$RPC")
echo "==> dev_bob balance BEFORE settlement: $BOB_BEFORE wei"

# ── 7. Start mock GitHub API ─────────────────────────────────────────────────
echo ""
echo "==> Starting mock GitHub API on port 8000..."
"$PYTHON_BIN" -m http.server 8000 --directory mock >/tmp/mock_server.log 2>&1 &
MOCK_PID=$!
PIDS+=("$MOCK_PID")
sleep 1
echo "    Mock server running (pid $MOCK_PID, current tag: v0.9.0)"

# ── 8. Start oracle ───────────────────────────────────────────────────────────
echo ""
echo "==> Starting oracle (watching for v1.0.0)..."
export RPC_URL="$RPC"
export ORACLE_PRIVATE_KEY="$ORACLE_KEY"
export HUB_ADDR="$HUB_ADDR"
export GITHUB_API="http://127.0.0.1:8000"
export REPO="demo/demo"
export TARGET_TAG="v1.0.0"
export POLL_SECONDS="2"

"$PYTHON_BIN" oracle/oracle.py >/tmp/oracle.log 2>&1 &
ORACLE_PID=$!
PIDS+=("$ORACLE_PID")
echo "    Oracle running (pid $ORACLE_PID) – polling every 2s"
sleep 3

# ── 9. Flip mock release to v1.0.0 ───────────────────────────────────────────
echo ""
echo "==> Flipping mock release tag to v1.0.0 / dev_bob..."
cat > mock/repos/demo/demo/releases/latest <<'JSON'
{
  "tag_name": "v1.0.0",
  "author": {
    "login": "dev_bob"
  }
}
JSON

echo "    Waiting for oracle to detect and settle (up to 20s)..."
for i in $(seq 1 20); do
  sleep 1
  kill -0 "$ORACLE_PID" 2>/dev/null || break
done

# ── 10. Balance after settlement ──────────────────────────────────────────────
echo ""
BOB_AFTER=$(cast balance "$BOB_ADDR" --rpc-url "$RPC")
echo "==> dev_bob balance AFTER  settlement: $BOB_AFTER wei"
GAINED=$("$PYTHON_BIN" -c "print($BOB_AFTER - $BOB_BEFORE)")
echo "    Gained: $GAINED wei  ($("$PYTHON_BIN" -c "print($GAINED / 10**18)") ETH)"

echo ""
echo "==> Oracle log:"
cat /tmp/oracle.log

# ── 11. Refund demo (Weight hub, short deadline) ──────────────────────────────
echo ""
echo "=========================================="
echo "==> REFUND DEMO (ContributionWeight, 5s deadline)"
echo "=========================================="

DEPLOY2=$(forge create src/MergeXHub.sol:MergeXHub \
  --broadcast \
  --rpc-url "$RPC" \
  --private-key "$HOST_KEY" \
  --constructor-args "$ORACLE_ADDR" 1 5 2>&1)
HUB2_ADDR=$(echo "$DEPLOY2" | grep "Deployed to:" | awk '{print $3}')
echo "==> Hub2 deployed at: $HUB2_ADDR"

cast send "$HUB2_ADDR" "registerDeveloper(string)" "dev_bob" \
  --rpc-url "$RPC" --private-key "$BOB_KEY" --quiet

cast send "$HUB2_ADDR" "fundPrizePool()" \
  --value 0.5ether \
  --rpc-url "$RPC" --private-key "$HOST_KEY" --quiet

HOST_BEFORE=$(cast balance "$HOST_ADDR" --rpc-url "$RPC")
echo "==> Host balance BEFORE refund: $HOST_BEFORE wei"

echo "==> Advancing chain time by 10s (evm_increaseTime)..."
cast rpc --rpc-url "$RPC" evm_increaseTime 10
cast rpc --rpc-url "$RPC" evm_mine

echo "==> Calling refund()..."
cast send "$HUB2_ADDR" "refund()" \
  --rpc-url "$RPC" --private-key "$HOST_KEY" --quiet

HOST_AFTER=$(cast balance "$HOST_ADDR" --rpc-url "$RPC")
echo "==> Host balance AFTER  refund: $HOST_AFTER wei"

echo ""
echo "==> MergeX demo complete."

# Reset mock to initial state for re-runs
cat > mock/repos/demo/demo/releases/latest <<'JSON'
{
  "tag_name": "v0.9.0",
  "author": {
    "login": "dev_bob"
  }
}
JSON
