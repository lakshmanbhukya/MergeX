// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MergeXHub} from "../src/MergeXHub.sol";

/// @title MergeXHub test suite – all required scenarios.
contract MergeXHubTest is Test {
    // ─── Accounts ─────────────────────────────────────────────────────────────
    address host   = makeAddr("host");
    address oracle = makeAddr("oracle");
    address bob    = makeAddr("bob");
    address eve    = makeAddr("eve");
    address rando  = makeAddr("rando");

    // ─── Helpers ──────────────────────────────────────────────────────────────
    uint256 constant DURATION = 7 days;
    uint256 constant PRIZE    = 1 ether;

    function _raceHub() internal returns (MergeXHub) {
        vm.prank(host);
        return new MergeXHub(oracle, MergeXHub.Kind.MilestoneRace, DURATION);
    }

    function _weightHub() internal returns (MergeXHub) {
        vm.prank(host);
        return new MergeXHub(oracle, MergeXHub.Kind.ContributionWeight, DURATION);
    }

    function _registerAndFundRace() internal returns (MergeXHub hub) {
        hub = _raceHub();
        vm.prank(bob); hub.registerDeveloper("dev_bob");
        vm.prank(eve); hub.registerDeveloper("dev_eve");
        vm.deal(host, PRIZE);
        vm.prank(host); hub.fundPrizePool{value: PRIZE}();
    }

    // ─── Tests ────────────────────────────────────────────────────────────────

    // 1. Non-host fund reverts
    function test_nonHostFundReverts() public {
        MergeXHub hub = _raceHub();
        vm.deal(rando, PRIZE);
        vm.prank(rando);
        vm.expectRevert(MergeXHub.NotHost.selector);
        hub.fundPrizePool{value: PRIZE}();
    }

    // 2. Non-oracle settle reverts
    function test_nonOracleSettleReverts() public {
        MergeXHub hub = _registerAndFundRace();
        vm.prank(rando);
        vm.expectRevert(MergeXHub.NotOracle.selector);
        hub.settleMilestoneWinner("dev_bob");
    }

    // 3. Unregistered winner reverts
    function test_unregisteredWinnerReverts() public {
        MergeXHub hub = _registerAndFundRace();
        vm.prank(oracle);
        vm.expectRevert(MergeXHub.UnregisteredHandle.selector);
        hub.settleMilestoneWinner("ghost_user");
    }

    // 4. Settle twice reverts
    function test_settleTwiceReverts() public {
        MergeXHub hub = _registerAndFundRace();
        vm.prank(oracle); hub.settleMilestoneWinner("dev_bob");
        vm.prank(oracle);
        vm.expectRevert(MergeXHub.NotActive.selector);
        hub.settleMilestoneWinner("dev_bob");
    }

    // 5. Duplicate handle registration reverts
    function test_duplicateHandleReverts() public {
        MergeXHub hub = _raceHub();
        vm.prank(bob); hub.registerDeveloper("dev_bob");
        vm.prank(eve);
        vm.expectRevert(MergeXHub.HandleTaken.selector);
        hub.registerDeveloper("dev_bob");
    }

    // Same wallet cannot register twice
    function test_duplicateWalletReverts() public {
        MergeXHub hub = _raceHub();
        vm.prank(bob); hub.registerDeveloper("dev_bob");
        vm.prank(bob);
        vm.expectRevert(MergeXHub.WalletTaken.selector);
        hub.registerDeveloper("dev_bob2");
    }

    // 6. Register after funding reverts (status is Active, not Setup)
    function test_registerAfterFundingReverts() public {
        MergeXHub hub = _raceHub();
        vm.deal(host, PRIZE);
        vm.prank(host); hub.fundPrizePool{value: PRIZE}();
        vm.prank(bob);
        vm.expectRevert(MergeXHub.NotSetup.selector);
        hub.registerDeveloper("dev_bob");
    }

    // 7. Refund before the deadline reverts
    function test_refundBeforeDeadlineReverts() public {
        MergeXHub hub = _registerAndFundRace();
        vm.prank(host);
        vm.expectRevert(MergeXHub.DeadlineNotReached.selector);
        hub.refund();
    }

    // 8. Refund after the deadline pays the host
    function test_refundAfterDeadlinePaysHost() public {
        MergeXHub hub = _registerAndFundRace();
        vm.warp(block.timestamp + DURATION + 1);
        uint256 before = host.balance;
        vm.prank(host); hub.refund();
        assertEq(host.balance - before, PRIZE);
        assertEq(uint8(hub.status()), uint8(MergeXHub.Status.Completed));
    }

    // 9. Weight flow pays the finalized winner
    function test_weightFlowPaysWinner() public {
        MergeXHub hub = _weightHub();
        vm.prank(bob); hub.registerDeveloper("dev_bob");
        vm.prank(eve); hub.registerDeveloper("dev_eve");
        vm.deal(host, PRIZE);
        vm.prank(host); hub.fundPrizePool{value: PRIZE}();

        vm.prank(oracle); hub.updateScore("dev_bob", 100);
        vm.prank(oracle); hub.updateScore("dev_eve", 80);

        uint256 before = bob.balance;
        vm.prank(oracle); hub.finalizeWeightTournament("dev_bob");
        assertEq(bob.balance - before, PRIZE);
        assertEq(uint8(hub.status()), uint8(MergeXHub.Status.Completed));
    }

    // 10. Reentrancy attempt from a malicious winner wallet is blocked
    function test_reentrancyBlocked() public {
        // Test reentrancy on refund() where host is the recipient and caller
        MaliciousHost maliciousHost = new MaliciousHost();
        vm.deal(address(maliciousHost), PRIZE);

        maliciousHost.createHub(oracle, DURATION);
        maliciousHost.registerAndFund{value: PRIZE}("some_dev");

        vm.warp(block.timestamp + DURATION + 1);

        // Expect revert due to ReentrancyGuard: reentrant call or TransferFailed
        vm.expectRevert();
        maliciousHost.triggerRefund();
    }

    // Race settle happy path – winner receives funds
    function test_raceSettlesPaysWinner() public {
        MergeXHub hub = _registerAndFundRace();
        uint256 before = bob.balance;
        vm.prank(oracle);
        hub.settleMilestoneWinner("dev_bob");
        assertEq(bob.balance - before, PRIZE);
        assertEq(uint8(hub.status()), uint8(MergeXHub.Status.Completed));
    }

    // Wrong-kind guard: weight fn on race hub reverts
    function test_wrongKindReverts() public {
        MergeXHub hub = _registerAndFundRace();
        vm.prank(oracle);
        vm.expectRevert(MergeXHub.WrongKind.selector);
        hub.updateScore("dev_bob", 50);
    }
}

/// @dev A malicious host contract that attempts to re-enter refund() upon receiving ETH.
contract MaliciousHost {
    MergeXHub public hub;

    function createHub(address _oracle, uint256 _duration) external returns (MergeXHub) {
        hub = new MergeXHub(_oracle, MergeXHub.Kind.MilestoneRace, _duration);
        return hub;
    }

    function registerAndFund(string calldata handle) external payable {
        hub.registerDeveloper(handle);
        hub.fundPrizePool{value: msg.value}();
    }

    function triggerRefund() external {
        hub.refund();
    }

    receive() external payable {
        // Attempt reentrant refund
        hub.refund();
    }
}
