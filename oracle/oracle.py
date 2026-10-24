#!/usr/bin/env python3
"""
MergeX Oracle – polls a GitHub (or mock) API for a release tag,
then calls settleMilestoneWinner on MergeXHub.

Environment variables:
  RPC_URL            – e.g. http://127.0.0.1:8545
  ORACLE_PRIVATE_KEY – hex private key for the oracle account
  HUB_ADDR           – deployed MergeXHub address
  GITHUB_API         – base URL (default https://api.github.com)
  REPO               – "owner/repo"
  TARGET_TAG         – release tag to watch for, e.g. v1.0.0
  GH_TOKEN           – optional GitHub personal access token
  POLL_SECONDS       – polling interval in seconds (default 5)
"""
import json
import logging
import os
import sys
import time
from pathlib import Path

import requests
from web3 import Web3
from web3.exceptions import ContractLogicError

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [oracle] %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("oracle")

# ── Config from environment ──────────────────────────────────────────────────
RPC_URL     = os.environ["RPC_URL"]
ORACLE_KEY  = os.environ["ORACLE_PRIVATE_KEY"]
HUB_ADDR    = os.environ["HUB_ADDR"]
GITHUB_API  = os.environ.get("GITHUB_API", "https://api.github.com").rstrip("/")
REPO        = os.environ["REPO"]
TARGET_TAG  = os.environ["TARGET_TAG"]
GH_TOKEN    = os.environ.get("GH_TOKEN", "")
POLL_SECS   = int(os.environ.get("POLL_SECONDS", "5"))

# ── Web3 setup ───────────────────────────────────────────────────────────────
w3   = Web3(Web3.HTTPProvider(RPC_URL))
acct = w3.eth.account.from_key(ORACLE_KEY)
log.info("Oracle address: %s", acct.address)

# Load ABI from Foundry output artefact
ABI_PATH = (
    Path(__file__).parent.parent
    / "out" / "MergeXHub.sol" / "MergeXHub.json"
)
if not ABI_PATH.exists():
    log.error("ABI not found at %s – run 'forge build' first.", ABI_PATH)
    sys.exit(1)

with ABI_PATH.open() as fh:
    artifact = json.load(fh)

abi      = artifact["abi"]
hub      = w3.eth.contract(address=Web3.to_checksum_address(HUB_ADDR), abi=abi)

# ── GitHub polling ───────────────────────────────────────────────────────────
def _gh_headers() -> dict:
    h = {"Accept": "application/vnd.github+json"}
    if GH_TOKEN:
        h["Authorization"] = f"Bearer {GH_TOKEN}"
    return h


def latest_release() -> tuple[str, str]:
    """Return (tag_name, author_login) of the latest release."""
    url = f"{GITHUB_API}/repos/{REPO}/releases/latest"
    resp = requests.get(url, headers=_gh_headers(), timeout=15)
    resp.raise_for_status()
    data = resp.json()
    return data["tag_name"], data["author"]["login"]


# ── Settlement ───────────────────────────────────────────────────────────────
def settle(handle: str) -> None:
    """Call settleMilestoneWinner and wait for the receipt."""
    log.info("Settling winner: %s", handle)
    nonce = w3.eth.get_transaction_count(acct.address)
    tx = hub.functions.settleMilestoneWinner(handle).build_transaction({
        "from":  acct.address,
        "nonce": nonce,
    })
    signed  = acct.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    log.info("Tx sent: %s – waiting for receipt…", tx_hash.hex())
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
    if receipt["status"] != 1:
        log.error("Transaction REVERTED: %s", tx_hash.hex())
        sys.exit(1)
    log.info("✓ Settled! tx=%s  block=%s", tx_hash.hex(), receipt["blockNumber"])
    print(tx_hash.hex())


# ── Main loop ────────────────────────────────────────────────────────────────
def main() -> None:
    log.info(
        "Watching %s/%s for tag '%s' (poll every %ds)",
        GITHUB_API, REPO, TARGET_TAG, POLL_SECS,
    )
    while True:
        try:
            tag, author = latest_release()
            log.info("Latest release: tag=%s  author=%s", tag, author)
            if tag == TARGET_TAG:
                settle(author)
                sys.exit(0)
        except ContractLogicError as exc:
            log.error("Contract reverted: %s", exc)
            sys.exit(1)
        except requests.RequestException as exc:
            log.warning("Network error (retrying): %s", exc)
        time.sleep(POLL_SECS)


if __name__ == "__main__":
    main()
