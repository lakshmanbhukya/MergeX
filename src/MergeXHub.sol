// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title MergeXHub – Decentralised bounty escrow with Race and Weight modes.
contract MergeXHub is ReentrancyGuard {
    // ─── Enums ────────────────────────────────────────────────────────────────
    enum Kind   { MilestoneRace, ContributionWeight }
    enum Status { Setup, Active, Completed }

    // ─── Errors ───────────────────────────────────────────────────────────────
    error NotHost();
    error NotOracle();
    error NotSetup();
    error NotActive();
    error WrongKind();
    error AlreadyFunded();
    error ZeroValue();
    error HandleTaken();
    error WalletTaken();
    error UnregisteredHandle();
    error DeadlineNotReached();
    error TransferFailed();

    // ─── Events ───────────────────────────────────────────────────────────────
    event DeveloperRegistered(string handle, address wallet);
    event PrizeFunded(address host, uint256 amount);
    event ScoreUpdated(string handle, uint256 score);
    event WinnerSettled(string handle, address wallet, uint256 amount);
    event RefundIssued(address host, uint256 amount);

    // ─── State ────────────────────────────────────────────────────────────────
    address public immutable oracle;
    Kind    public immutable kind;
    address public immutable host;
    uint256 public immutable deadline;

    Status  public status;
    uint256 public prizePool;

    mapping(string  => address payable) public githubToWallet;
    mapping(address => bool)            private _walletRegistered;
    mapping(string  => uint256)         public  scores;

    // ─── Constructor ──────────────────────────────────────────────────────────
    constructor(address _oracle, Kind _kind, uint256 _durationSeconds) {
        oracle   = _oracle;
        kind     = _kind;
        host     = msg.sender;
        deadline = block.timestamp + _durationSeconds;
        status   = Status.Setup;
    }

    // ─── Modifiers ────────────────────────────────────────────────────────────
    modifier onlyHost()   { if (msg.sender != host)   revert NotHost();   _; }
    modifier onlyOracle() { if (msg.sender != oracle) revert NotOracle(); _; }
    modifier onlySetup()  { if (status != Status.Setup)  revert NotSetup();  _; }
    modifier onlyActive() { if (status != Status.Active) revert NotActive(); _; }

    // ─── Registration ─────────────────────────────────────────────────────────
    /// @notice Link a GitHub handle to the caller's wallet. Setup phase only.
    function registerDeveloper(string calldata handle) external onlySetup {
        if (githubToWallet[handle] != address(0))  revert HandleTaken();
        if (_walletRegistered[msg.sender])          revert WalletTaken();
        githubToWallet[handle]       = payable(msg.sender);
        _walletRegistered[msg.sender] = true;
        emit DeveloperRegistered(handle, msg.sender);
    }

    // ─── Funding ──────────────────────────────────────────────────────────────
    /// @notice Fund the prize pool (host only, once, Setup → Active).
    function fundPrizePool() external payable onlyHost onlySetup {
        if (msg.value == 0) revert ZeroValue();
        prizePool = msg.value;
        status    = Status.Active;
        emit PrizeFunded(msg.sender, msg.value);
    }

    // ─── Race settlement ──────────────────────────────────────────────────────
    /// @notice Oracle settles the milestone race winner.
    function settleMilestoneWinner(string calldata handle)
        external
        onlyOracle
        onlyActive
        nonReentrant
    {
        if (kind != Kind.MilestoneRace) revert WrongKind();
        address payable winner = githubToWallet[handle];
        if (winner == address(0)) revert UnregisteredHandle();

        uint256 amount = prizePool;
        status    = Status.Completed;   // Effects before Interaction
        prizePool = 0;

        emit WinnerSettled(handle, winner, amount);

        (bool ok,) = winner.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    // ─── Weight mode ──────────────────────────────────────────────────────────
    /// @notice Oracle pushes a contribution score for a registered handle.
    function updateScore(string calldata handle, uint256 score)
        external
        onlyOracle
        onlyActive
    {
        if (kind != Kind.ContributionWeight) revert WrongKind();
        if (githubToWallet[handle] == address(0)) revert UnregisteredHandle();
        scores[handle] = score;
        emit ScoreUpdated(handle, score);
    }

    /// @notice Oracle finalises the weight tournament by naming the winner.
    function finalizeWeightTournament(string calldata winnerHandle)
        external
        onlyOracle
        onlyActive
        nonReentrant
    {
        if (kind != Kind.ContributionWeight) revert WrongKind();
        address payable winner = githubToWallet[winnerHandle];
        if (winner == address(0)) revert UnregisteredHandle();

        uint256 amount = prizePool;
        status    = Status.Completed;   // Effects before Interaction
        prizePool = 0;

        emit WinnerSettled(winnerHandle, winner, amount);

        (bool ok,) = winner.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    // ─── Refund ───────────────────────────────────────────────────────────────
    /// @notice Host reclaims funds after the deadline if the event is still Active.
    function refund() external onlyHost onlyActive nonReentrant {
        if (block.timestamp < deadline) revert DeadlineNotReached();

        uint256 amount = prizePool;
        status    = Status.Completed;   // Effects before Interaction
        prizePool = 0;

        emit RefundIssued(msg.sender, amount);

        (bool ok,) = payable(host).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
