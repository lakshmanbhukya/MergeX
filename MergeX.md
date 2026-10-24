# MergeX
### A Decentralized Bounty Escrow & Tournament System for Open-Source Software

> **One-liner:** MergeX lets anyone fund an open-source goal, lets developers compete to deliver it on GitHub, and pays the winner automatically from a smart-contract vault, with no need for either side to trust the other.

---

## Table of Contents
1. [Project Summary](#1-project-summary)
2. [WHY: Problem & Motivation](#2-why-problem--motivation)
3. [WHAT: Scope & Features](#3-what-scope--features)
4. [WHO: Actors & Roles](#4-who-actors--roles)
5. [HOW: Architecture](#5-how-architecture)
6. [HOW: Smart Contracts](#6-how-smart-contracts)
7. [HOW: The Oracle / Relayer](#7-how-the-oracle--relayer)
8. [HOW: Identity Linking (GitHub to Wallet)](#8-how-identity-linking-github--wallet)
9. [HOW: Tournament Models & Scoring](#9-how-tournament-models--scoring)
10. [WHEN: Lifecycle & Timeline](#10-when-lifecycle--timeline)
11. [Security & Trust Analysis](#11-security--trust-analysis)
12. [Known Limitations & Planned Fixes](#12-known-limitations--planned-fixes)
13. [Technology Stack](#13-technology-stack)
14. [Testing & Deployment Plan](#14-testing--deployment-plan)
15. [Development Roadmap](#15-development-roadmap)
16. [FAQ (Why / What / How / When)](#16-faq)
17. [Glossary](#17-glossary)
18. [Open Items / TODO](#18-open-items--todo)

---

## 1. Project Summary

| Item | Detail |
|---|---|
| **Name** | MergeX |
| **Type** | Web3 + Web2 hybrid (Solidity smart contracts + GitHub API + off-chain oracle) |
| **Core idea** | Escrow-backed bounties and tournaments for open-source contributions, settled automatically based on verified GitHub activity |
| **Chain** | EVM-compatible (Ethereum / testnet such as Sepolia for development) |
| **Contract language** | Solidity ^0.8.24 |
| **Oracle language** | Python (polls GitHub REST API, signs and sends transactions) |
| **Status** | Prototype: three contract iterations built, oracle designed, hardening pending |

**Evolution of the project**

| Phase | Contract | What it proved |
|---|---|---|
| 1 | `SimpleEscrow.sol` | Basic locked-funds escrow with release and time-locked refund |
| 2 | `SimpleBounty.sol` | An oracle can trigger payment when a GitHub milestone (e.g. tag `v1.0.0`) is detected |
| 3 | `AdvancedBountyHub.sol` | Multi-developer competitions with a GitHub-handle to wallet registry |

---

## 2. WHY: Problem & Motivation

### 2.1 The problem
Open-source work is valuable but poorly funded, and paying for it is awkward:

- **Sponsors** fear paying upfront for work that is never delivered.
- **Developers** fear doing the work and never being paid, or being paid late.
- **Maintainers** spend time manually verifying work and arranging payouts.
- Existing bounty platforms are **centralized**: they hold the money, take fees, can freeze accounts, and are a single point of failure.
- Hackathon prizes are often decided **subjectively and opaquely**.

### 2.2 Why blockchain?
| Need | How a smart contract helps |
|---|---|
| Sponsor needs proof the money is real | Funds are locked on-chain and publicly auditable |
| Developer needs a guarantee of payment | Payout rules are code; nobody can quietly change them |
| Neither party trusts a middleman | The contract is the neutral escrow |
| Sponsor needs protection if nothing ships | Time-locked refund returns funds after the deadline |

### 2.3 Why GitHub?
GitHub is where open-source work already happens. Pull requests, merges, issues and release tags are objective, timestamped, public events, so they make good evidence for settlement.

### 2.4 Why an oracle?
Smart contracts are sandboxed: they **cannot make HTTP calls**. A contract cannot ask GitHub "was `v1.0.0` released?". A trusted off-chain component must fetch the data and submit it as a transaction. That component is the oracle (see Section 7).

### 2.5 Goals
1. Trustless (or trust-minimized) escrow between sponsor and developer.
2. Automatic payout based on verifiable GitHub events.
3. Support both **speed races** and **quality-weighted tournaments**.
4. Time-bounded safety: sponsors can always recover funds if nothing is delivered.
5. Keep the design simple enough to audit and demo.

### 2.6 Non-goals (for now)
- Replacing GitHub or code review.
- Judging code quality fully automatically with AI.
- Supporting non-EVM chains or fiat payments.
- Handling disputes through a full DAO governance system.

---

## 3. WHAT: Scope & Features

### 3.1 What MergeX is
A system of three cooperating parts:

1. **GitHub (Web2):** source of truth for contributions.
2. **Oracle / Relayer (bridge):** reads GitHub, computes results, submits proofs on-chain.
3. **Smart contract vault (Web3):** holds funds, stores the registry, and pays out.

```text
┌─────────────────────────────┐    ┌─────────────────────────────┐    ┌─────────────────────────────┐
│       1. WEB2 WORLD         │    │        2. THE BRIDGE        │    │     3. WEB3 BLOCKCHAIN      │
│  (GitHub Platform)          │    │  (Off-chain Oracle/Relayer) │    │  (Settlement Vault)         │
├─────────────────────────────┤    ├─────────────────────────────┤    ├─────────────────────────────┤
│ • Devs write code           │───>│ • Polls GitHub REST API     │───>│ • Holds escrowed funds      │
│ • Open Pull Requests        │API │ • Computes scores           │ Tx │ • Stores handle→wallet map  │
│ • Maintainers merge         │    │ • Sends signed transactions │    │ • Pays out atomically       │
└─────────────────────────────┘    └─────────────────────────────┘    └─────────────────────────────┘
```

### 3.2 Feature list

| # | Feature | Status |
|---|---|---|
| F1 | Sponsor-funded escrow vault | Implemented |
| F2 | Time-locked sponsor refund | Implemented (Phase 1 only; to be added to Hub) |
| F3 | Oracle-triggered payout on release tag | Implemented (Phase 2) |
| F4 | GitHub-handle to wallet registry | Implemented (needs verification, see 8) |
| F5 | Milestone Speed Race (winner takes all) | Implemented |
| F6 | Contribution Weight Tournament (score-based) | Implemented (basic leader tracking) |
| F7 | Python oracle service | Designed, reference sketch in Section 7 |
| F8 | Prize splitting (1st/2nd/3rd) | Planned |
| F9 | Verified identity linking (gist/signature) | Planned |
| F10 | Frontend dashboard | Planned |

---

## 4. WHO: Actors & Roles

| Actor | Description | Powers | Trust required |
|---|---|---|---|
| **Sponsor / Host** | Funds the bounty or tournament | Deploy, fund, refund after deadline, finalize | None beyond own funds |
| **Developer** | Competes by contributing on GitHub | Register handle, receive prize | Trusts oracle to report honestly |
| **Oracle / Jury** | Off-chain service (or committee) that reports GitHub results | Settle winner, update scores | **Highest trust in the system** |
| **Maintainer** | Merges PRs in the target repo | Indirect: merges become the evidence | Trusted by repo convention |
| **Observer** | Anyone | Read contract state and events | None |

---

## 5. HOW: Architecture

### 5.1 Layered view

| Layer | Component | Responsibility |
|---|---|---|
| Data source | GitHub REST API | Provides PRs, merges, tags, issues |
| Bridge | Python oracle | Fetch, validate, score, sign, submit |
| Settlement | Solidity contracts | Escrow, registry, payout, refund |
| Client (planned) | Web dashboard | Create events, register, view leaderboard |

### 5.2 End-to-end flow (Milestone Race)

```text
[Sponsor] deploys vault ──> locks prize pool + sets target milestone
        │
[Developers] call registerDeveloper("github_handle")
        │
[Developers] work on GitHub, open PRs
        │
[Oracle] polls GitHub API on a schedule
        │
   ┌────┴─────────────────────────────┐
   ▼ milestone completed              ▼ deadline passes with no winner
settleMilestoneWinner(handle)     refund path returns funds to sponsor
   │
   ▼
Atomic payout to winner's wallet
```

### 5.3 Sequence (numbered)
1. **Registration:** developers link GitHub handle to wallet.
2. **Funding:** host locks ETH in the vault.
3. **Monitoring:** oracle watches the repository.
4. **Settlement relay:** oracle submits the winner (or scores).
5. **Payout:** contract transfers funds in the same transaction as the state change.

---

## 6. HOW: Smart Contracts

### 6.1 Phase 1: `SimpleEscrow.sol`
| Function | Caller | Purpose |
|---|---|---|
| `constructor(payee, durationMinutes)` | Sponsor | Sets roles and deadline = `block.timestamp + minutes` |
| `deposit()` | Sponsor only | Locks ETH (once) |
| `release()` | Sponsor only | Pays the payee |
| `refund()` | Sponsor only, after deadline | Returns ETH to sponsor |

### 6.2 Phase 2: `SimpleBounty.sol`
| Function | Caller | Purpose |
|---|---|---|
| `constructor(developer, oracle, release)` | Sponsor | Fixes developer, oracle, and expected tag |
| `fundBounty()` | Sponsor only | Locks ETH |
| `settleBounty(detectedRelease)` | Oracle only | Compares `keccak256` of the detected tag to the expected one, then pays |

String comparison uses `keccak256(abi.encodePacked(...))` because Solidity has no native string equality.

### 6.3 Phase 3: `AdvancedBountyHub.sol`
| Element | Purpose |
|---|---|
| `enum TournamentType { MilestoneRace, ContributionWeight }` | Selects the competition model |
| `enum Status { Setup, Active, Completed }` | Lifecycle state |
| `mapping(string => address payable) githubToWallet` | Identity registry |
| `mapping(address => uint256) contributionScores` | Leaderboard scores |
| `currentLeader`, `highestScore` | Running leader tracking |
| `registerDeveloper(handle)` | Developer links handle to wallet |
| `fundPrizePool()` | Host funds and activates event |
| `settleMilestoneWinner(handle)` | Oracle pays single winner (Race) |
| `updateScore(handle, score)` | Oracle pushes scores (Weight) |
| `finalizeWeightTournament()` | Host/oracle pays the leader |

### 6.4 State machine

```text
Setup ──fundPrizePool()──> Active ──settle / finalize──> Completed
```

### 6.5 Events (recommended addition)
Emit events for off-chain indexing and transparency: `DeveloperRegistered`, `PrizeFunded`, `ScoreUpdated`, `WinnerSettled`, `RefundIssued`.

---

## 7. HOW: The Oracle / Relayer

### 7.1 Responsibilities
1. Poll GitHub REST API (e.g. `/repos/{owner}/{repo}/releases`, `/pulls`, `/issues`).
2. Decide whether a settlement condition is met.
3. Sign and send a transaction from the **oracle address** stored in the contract.
4. Log every decision for auditability.

### 7.2 Reference sketch (Python, web3.py)

```python
import os, time, requests
from web3 import Web3

GITHUB_API = "https://api.github.com"
REPO = "owner/repo"
TARGET_TAG = "v1.0.0"

w3 = Web3(Web3.HTTPProvider(os.environ["RPC_URL"]))
acct = w3.eth.account.from_key(os.environ["ORACLE_PRIVATE_KEY"])
contract = w3.eth.contract(address=os.environ["CONTRACT_ADDR"], abi=ABI)

def latest_tag():
    r = requests.get(f"{GITHUB_API}/repos/{REPO}/releases/latest",
                     headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}"},
                     timeout=15)
    r.raise_for_status()
    return r.json()["tag_name"]

while True:
    if latest_tag() == TARGET_TAG:
        tx = contract.functions.settleBounty(TARGET_TAG).build_transaction({
            "from": acct.address,
            "nonce": w3.eth.get_transaction_count(acct.address),
        })
        signed = acct.sign_transaction(tx)
        w3.eth.send_raw_transaction(signed.raw_transaction)
        break
    time.sleep(300)  # poll every 5 minutes
```

> This is a sketch: production code needs retries, gas estimation, confirmation waiting, rate-limit handling, and secure key storage.

### 7.3 Oracle operational concerns
| Concern | Mitigation |
|---|---|
| Private key leak | Use a secrets manager / hardware wallet; limit funds the oracle can influence |
| GitHub rate limits | Authenticated token, conditional requests (ETag), sensible poll interval |
| Downtime | Deadline-based refund so funds are never stuck |
| Dishonest oracle | Multi-sig / committee of oracles, dispute window (see Section 12) |

---

## 8. HOW: Identity Linking (GitHub ↔ Wallet)

**Problem:** the blockchain knows `0x...` addresses; GitHub knows logins like `dev_bob`. Something must connect them.

**Current approach:** developers call `registerDeveloper("dev_bob")` before the event.

**Weakness:** nothing proves the caller *owns* `dev_bob`. Anyone could register someone else's handle, or overwrite an existing registration.

**Recommended improvement (planned):**
1. Developer signs a message with their wallet: `"I am dev_bob, wallet 0xABC..."`.
2. Developer publishes the signature in a **public GitHub Gist** under their account.
3. Oracle fetches the gist, verifies the signature and gist owner, then registers the pair (or the contract accepts an oracle-signed attestation).
4. Registration becomes **write-once** per handle.

---

## 9. HOW: Tournament Models & Scoring

### 9.1 Model A: Milestone Speed Race
- Several developers compete concurrently.
- The one who completes the final piece (e.g. merges the PR that closes the target issue or ships the tag) wins 100% of the pool.
- **Pros:** simple, objective, easy to verify. **Cons:** favors speed over quality; risk of rushed work.

### 9.2 Model B: Contribution Weight Tournament
- Fixed multi-week window; many PRs allowed.
- The oracle computes a score per developer and pushes it on-chain.
- Highest score at the end wins.

**Suggested scoring formula (tunable):**

```text
score = Σ over MERGED PRs of ( w_pr + w_lines·min(lines_changed, cap) + w_review·approvals + w_issue·linked_issues_closed )
```

| Signal | Why it matters | Anti-gaming note |
|---|---|---|
| Merged PR count | Rewards accepted work, not just opened PRs | Count only **merged** PRs |
| Lines changed | Rough effort proxy | Cap per PR to stop padding |
| Maintainer approvals | Quality signal | Exclude self-approvals |
| Linked issues closed | Real impact | Only issues pre-labeled for the event |

### 9.3 Anti-gaming considerations
- Sybil accounts (one person, many handles): require verified identity, account-age thresholds.
- Trivial PRs (whitespace, typos): minimum-change rules, maintainer label `counts-for-mergex`.
- Colluding maintainers: neutral jury or multi-oracle for high-value events.

---

## 10. WHEN: Lifecycle & Timeline

### 10.1 Event timeline
| Stage | When | What happens | Contract status |
|---|---|---|---|
| T0 Setup | Before start | Host deploys, sets oracle, type, rules | `Setup` |
| T1 Registration | Setup window | Developers link handle to wallet | `Setup` |
| T2 Funding | Before start | Host calls `fundPrizePool()` | `Active` |
| T3 Competition | Start → end | Developers work; oracle polls and updates | `Active` |
| T4 Settlement | At milestone or end | Oracle settles or host finalizes | `Completed` |
| T5 Fallback refund | After deadline | If unsettled, sponsor reclaims funds | `Completed` (refunded) |

### 10.2 When does the oracle act?
- **Race:** as soon as the milestone condition is observed (poll interval, e.g. 5 min).
- **Weight:** periodic score pushes (e.g. daily) plus a final push before finalization.

### 10.3 When can money move?
| Action | Allowed when |
|---|---|
| Fund | Status `Setup`, host only |
| Payout to winner | Status `Active`, oracle (or host for weight finalize) |
| Sponsor refund | After deadline, if not already paid |

---

## 11. Security & Trust Analysis

### 11.1 Trust model
| Party | What they can do | What they cannot do |
|---|---|---|
| Sponsor | Fund, refund after deadline | Cancel early or redirect to a friend after funding (once refund timing enforced) |
| Oracle | Choose settlement winner / scores | Withdraw funds to itself (should be enforced: only registered wallets can win) |
| Developer | Register, receive | Force a payout without oracle |

### 11.2 Honest summary
MergeX removes trust in a **platform** but still relies on an **oracle**. The oracle is the main centralization point; decentralizing it is the biggest open design question.

---

## 12. Known Limitations & Planned Fixes

These issues exist in the current prototype code and should be fixed before any real-money use. Documenting them honestly is a strength for the project report.

| # | Issue | Where | Fix |
|---|---|---|---|
| 1 | **Handle squatting / hijacking**: anyone can register or overwrite any GitHub handle | `registerDeveloper` | Make registration write-once; add gist-signature verification (Section 8) |
| 2 | **No refund path in the Hub**: if the oracle disappears, funds are stuck | `AdvancedBountyHub` | Add `deadline` and `refund()` like Phase 1 |
| 3 | **Leader tracking bug**: if a leader's score is later *lowered* or another dev's score is corrected, `currentLeader` is not recomputed | `updateScore` | Compute winner at finalize time (oracle submits final winner) or use a sorted/verified snapshot |
| 4 | **`transfer()` usage**: forwards only 2300 gas and can fail for contract wallets | `settleMilestoneWinner`, `finalizeWeightTournament` | Use `call{value:}` with checks-effects-interactions, or a pull-payment (`withdraw`) pattern |
| 5 | **Anyone's funding activates the event**; repeated `fundPrizePool` calls possible | `fundPrizePool` | Single funding, require `msg.value > 0`, lock rules once active |
| 6 | **Single oracle = single point of trust/failure** | Whole design | Multi-sig oracle set (m-of-n), or optimistic settlement with a dispute window |
| 7 | **No ties / no prize splitting** | Weight model | Add ranked payouts (e.g. 50/30/20) and tie-break rules |
| 8 | **Missing events** | All contracts | Emit events for every state change |
| 9 | **`Setup` status check missing in `registerDeveloper`** (can register anytime) | Hub | Restrict registration window |
| 10 | **Oracle key management** | Off-chain | Secrets manager, key rotation function (`setOracle`) with timelock |

**Recommended hardening checklist:** reentrancy guard, custom errors, OpenZeppelin `Ownable`/`ReentrancyGuard`, Foundry/Hardhat tests with fuzzing, static analysis (Slither), and a manual review before mainnet.

---

## 13. Technology Stack

| Layer | Technology |
|---|---|
| Smart contracts | Solidity ^0.8.24, OpenZeppelin (planned) |
| Dev framework | Foundry or Hardhat |
| Test network | Sepolia (Ethereum testnet) |
| Oracle | Python 3, `web3.py`, `requests` |
| Data source | GitHub REST API v3 |
| Frontend (planned) | React + ethers.js / wagmi |
| Tools used so far | Remix IDE for prototyping |

---

## 14. Testing & Deployment Plan

### 14.1 Test cases (minimum)
| # | Scenario | Expected |
|---|---|---|
| 1 | Non-sponsor tries to fund | Revert |
| 2 | Non-oracle calls `settleMilestoneWinner` | Revert |
| 3 | Unregistered winner handle | Revert |
| 4 | Settle twice | Revert (status Completed) |
| 5 | Refund before deadline | Revert |
| 6 | Refund after deadline, unpaid | Funds return to sponsor |
| 7 | Wrong tournament type function call | Revert |
| 8 | Score updates and leader selection | Correct winner paid |
| 9 | Re-registration of an existing handle | Revert (after fix) |
| 10 | Reentrancy attempt from malicious wallet | Blocked |

### 14.2 Deployment steps
1. Write tests and run locally.
2. Deploy to Sepolia with a dedicated oracle address.
3. Create a demo GitHub repo with an issue and a release tag.
4. Run oracle script against the demo repo.
5. Record a demo: register → fund → merge/tag → automatic payout.

---

## 15. Development Roadmap

| Milestone | Deliverables |
|---|---|
| **M1: Foundations** (done) | `SimpleEscrow`, `SimpleBounty`, `AdvancedBountyHub` prototypes |
| **M2: Hardening** | Fix Section 12 issues; add deadline/refund, events, tests |
| **M3: Oracle v1** | Production-style Python service with retries, logging, key safety |
| **M4: Identity** | Gist-signature verification and write-once registry |
| **M5: Prize splitting** | Ranked payouts, tie-breaks |
| **M6: Frontend** | Dashboard for hosts and developers, live leaderboard |
| **M7: Decentralized oracle** | Multi-sig / committee or optimistic dispute window |
| **M8: Audit & testnet pilot** | Static analysis, review, small real pilot on testnet |

---

## 16. FAQ

**WHY**
- **Why not just use PayPal/Bountysource-style platforms?** They are custodial and centralized; MergeX makes the rules and escrow public and automatic.
- **Why can't the contract read GitHub itself?** Contracts are deterministic and isolated; they need an oracle to bring external data.
- **Why escrow instead of paying on completion?** Escrow proves funds exist and protects both sides.
- **Why have both Race and Weight models?** Race suits a single well-defined goal; Weight suits ongoing contribution and rewards quality and volume.

**WHAT**
- **What if nobody completes the milestone?** The sponsor refunds after the deadline.
- **What is the oracle exactly?** An off-chain script/service whose wallet address is authorized in the contract to submit results.
- **What chain and currency?** EVM chain, native ETH (ERC-20 stablecoin support is a possible extension).
- **What stops a developer from faking work?** Only merged PRs/tags in the designated repo count; oracle reads the repo directly, not developer claims.

**HOW**
- **How does a developer get paid?** The contract sends ETH to the wallet registered for the winning handle, in the same transaction that marks the event completed.
- **How is the winner chosen in Race mode?** The oracle detects the milestone completion on GitHub and submits the author's handle.
- **How is the score computed in Weight mode?** By the formula in Section 9, calculated off-chain and pushed on-chain.
- **How do we avoid trusting one oracle?** Planned: m-of-n multi-sig oracles or an optimistic challenge window.

**WHEN**
- **When must developers register?** Before the competition starts (registration window).
- **When does the oracle check GitHub?** On a polling schedule (e.g. every few minutes for races, daily for scores).
- **When can the sponsor get money back?** Only after the deadline and only if nothing was paid.
- **When is the event over?** When status becomes `Completed` via settlement, finalization, or refund.

---

## 17. Glossary
| Term | Meaning |
|---|---|
| **Escrow** | A neutral holder of funds until conditions are met |
| **Oracle** | Off-chain agent that feeds external data to a contract |
| **Relayer** | Component that submits transactions on someone's behalf |
| **Bounty** | A reward for completing a specified task |
| **Tag / Release** | A named GitHub version marker (e.g. `v1.0.0`) |
| **`keccak256`** | Ethereum's hash function, used here to compare strings |
| **Sybil attack** | One person pretending to be many participants |
| **Reentrancy** | Exploit where a receiving contract calls back before state is updated |
| **Checks-Effects-Interactions** | Pattern: validate, update state, then send ETH |
| **Pull payment** | Recipient withdraws funds instead of the contract pushing them |

---

## 18. Open Items / TODO
- [ ] Confirm final project name styling and tagline with instructor.
- [ ] Decide which tournament model(s) to demo (Race, Weight, or both).
- [ ] Decide oracle design for the demo (single trusted vs. multi-sig).
- [ ] Fix Section 12 issues #1 to #5 before the live demo.
- [ ] Prepare demo GitHub repository and testnet wallets.
- [ ] Add team members, course name, and submission date to the cover section.
- [ ] Add architecture diagram image (see prompt below).

### Diagram generation prompt
```text
Create a clean tech-blueprint architecture diagram for "MergeX", a competitive blockchain bounty vault.
Three horizontal zones: (1) THE COMPETITORS, (2) THE TRACKING INFRASTRUCTURE, (3) THE BLOCKCHAIN ESCROW.
Competitors: multiple developers pre-registering wallet associations.
Tracking: GitHub main repository with public REST API, polled by an off-chain Python oracle.
Escrow: smart-contract vault holding an ETH prize pool with a handle-to-wallet registry.
Number the flow: 1 Registration -> 2 Lock Escrow Funds -> 3 API Verification -> 4 Settlement Relay -> 5 Atomic Payout.
```
