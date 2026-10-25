# MergeX

A decentralized bounty escrow and tournament system for open-source software. MergeX lets sponsors lock prize pools in a smart contract vault, lets developers compete on GitHub, and uses an off-chain oracle to automatically verify releases and trigger payouts without intermediaries.

---

## Tech Stack

| Layer | Technologies |
| :--- | :--- |
| **Smart Contracts** | ![Solidity](https://img.shields.io/badge/Solidity_0.8.24-363636?style=for-the-badge&logo=solidity&logoColor=white) ![Foundry](https://img.shields.io/badge/Foundry-black?style=for-the-badge&logo=ethereum&logoColor=white) ![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin_Contracts-4E5EE4?style=for-the-badge&logo=openzeppelin&logoColor=white) |
| **Oracle & Automation** | ![Python](https://img.shields.io/badge/Python_3.10+-3776AB?style=for-the-badge&logo=python&logoColor=white) ![Web3.py](https://img.shields.io/badge/Web3.py-F16822?style=for-the-badge&logo=ethereum&logoColor=white) ![Requests](https://img.shields.io/badge/Requests-2CA5E0?style=for-the-badge&logo=python&logoColor=white) |
| **Integration & Testing** | ![GitHub API](https://img.shields.io/badge/GitHub_API-181717?style=for-the-badge&logo=github&logoColor=white) ![Anvil](https://img.shields.io/badge/Anvil_Local_EVM-5A5A5A?style=for-the-badge&logo=ethereum&logoColor=white) ![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white) |

---

## System Architecture

```mermaid
flowchart TD
    subgraph GitHub["GitHub Platform"]
        DEV["Developer<br/>(Tags / Releases / PRs)"] -->|Publishes Milestone Release| GH_API["GitHub REST API<br/>(/releases/latest)"]
    end

    subgraph OffChain["Off-Chain Oracle Layer"]
        ORACLE["Python Oracle<br/>(oracle/oracle.py)"]
        GH_API -->|Polls release tag & author| ORACLE
    end

    subgraph OnChain["MergeX On-Chain Escrow (EVM)"]
        SPONSOR["Sponsor / Host"] -->|"1. fundPrizePool(ETH)"| HUB["MergeXHub Vault<br/>(src/MergeXHub.sol)"]
        DEV_WALLET["Winner Wallet"] -->|"0. registerDeveloper(handle)"| HUB
        ORACLE -->|"2. settleMilestoneWinner(author) or finalizeWeightTournament()"| HUB
        HUB -->|"3. Atomic ETH Payout"| DEV_WALLET
        HUB -.->|"Refund if deadline reached without winner"| SPONSOR
    end
```

### Core Architecture Components

1. **`MergeXHub.sol` (Vault Escrow & Settlement)**:
   - Manages tournament lifecycles through distinct states: `Setup`, `Active`, and `Completed`.
   - Supports dual modes: **Milestone Race** (first-to-ship target release) and **Contribution Weight** (proportional / scored contributions).
   - Enforces strict role isolation (`onlyHost`, `onlyOracle`), Checks-Effects-Interactions pattern, and OpenZeppelin `ReentrancyGuard`.
2. **Oracle Bridge (`oracle/oracle.py`)**:
   - Continuously monitors repository activity via GitHub's API.
   - Verifies milestone tags against registered developer handles.
   - Signs and submits settlement transactions directly to the smart contract.
3. **Escrow Guarantee**:
   - Developers are guaranteed trustless, automatic compensation upon successful release verification.
   - Sponsors are protected by programmatic refund windows if deliverables are not met before the configured deadline.

---

## How It Works

1. **Setup & Developer Registration**:
   - The sponsor deploys `MergeXHub` configured with the trusted oracle address, tournament kind (`MilestoneRace` or `ContributionWeight`), and a duration timestamp.
   - Developers call `registerDeveloper(handle)` during the `Setup` phase to bind their GitHub handle to their EVM wallet address (write-once, immutable binding).
2. **Escrow Funding**:
   - The sponsor deposits ETH via `fundPrizePool()`, transitioning the tournament from `Setup` to `Active`. No further developer registrations are accepted once funded.
3. **Off-Chain Verification & Settlement**:
   - The Python oracle monitors the target repository releases endpoint.
   - Upon detecting the target milestone release tag, the oracle invokes `settleMilestoneWinner(author)`.
   - The contract verifies oracle authorization, resolves the author's registered payout address, transitions to `Completed`, and executes an atomic ETH transfer.
4. **Deadline & Host Refund**:
   - If no valid milestone release is verified before the deadline expires, the sponsor can call `refund()` to safely withdraw the locked prize pool.

---

## Quickstart

### Prerequisites
- [Foundry](https://getfoundry.sh/) (`forge`, `anvil`)
- Python 3.10+ & `pip`

### Getting Started

```bash
git clone <repo> && cd MergeX          # Clone the repository
pip install web3 requests               # Install Python oracle dependencies
forge build                             # Compile Solidity contracts
forge test                              # Run test suite
bash demo.sh                            # Run end-to-end demo on local Anvil
```
