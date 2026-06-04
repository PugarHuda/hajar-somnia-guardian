// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HajarGuardian} from "../src/HajarGuardian.sol";
import {ProtectedVault} from "../src/ProtectedVault.sol";
import {MockAgentPlatform} from "../src/mocks/MockAgentPlatform.sol";

/// A withdrawer that tries to re-enter the vault during the payout call.
contract ReentrantWithdrawer {
    ProtectedVault public vault;
    uint256 public reenterAmount;
    bool public reentered;

    constructor(ProtectedVault v) {
        vault = v;
    }

    function seed() external payable {
        vault.deposit{value: msg.value}();
    }

    function attack(uint256 amount) external {
        reenterAmount = amount;
        vault.withdraw(amount);
    }

    receive() external payable {
        if (!reentered && reenterAmount > 0) {
            reentered = true;
            // attempt a second withdrawal mid-payout
            try vault.withdraw(reenterAmount) {} catch {}
        }
    }
}

contract HajarEdgeCasesTest is Test {
    HajarGuardian guardian;
    ProtectedVault vault;
    MockAgentPlatform platform;

    address alice = address(0xA11CE);
    uint256 constant AID = 12847293847561029384;

    function setUp() public {
        platform = new MockAgentPlatform();
        guardian = new HajarGuardian(address(platform), AID);
        vault = new ProtectedVault();
        guardian.setVault(address(vault));
        vault.setGuardian(address(guardian));
        guardian.fund{value: 10 ether}();
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}();
    }

    /// Reentrancy: a malicious recipient that re-enters during payout cannot touch other
    /// users' funds. CEI (balance decremented before the external call) keeps the vault safe.
    function test_Reentrancy_CannotDrainOthers() public {
        ReentrantWithdrawer atk = new ReentrantWithdrawer(vault);
        vm.deal(address(this), 10 ether);
        atk.seed{value: 10 ether}(); // atk deposits its own 10; TVL=110, atk balanceOf=10

        atk.attack(5 ether); // withdraws 5, receive() re-enters and withdraws the other 5

        assertEq(vault.totalAssets(), 100 ether, "alice's 100 STT must be untouched");
        assertEq(vault.balanceOf(address(atk)), 0, "atk could only ever pull its own deposit");
        assertLe(address(atk).balance, 10 ether, "no extra funds extracted");
    }

    /// Velocity window resets after it expires — old withdrawals stop counting.
    function test_VelocityWindow_ResetsAfterExpiry() public {
        // two 30% withdrawals just inside the window would be 60% (== rapid limit) and block;
        // separate them by > windowSeconds so each is treated fresh and both pass.
        vm.prank(alice);
        vault.withdraw(30 ether); // 30% of 100
        vm.warp(block.timestamp + guardian.windowSeconds() + 1);
        vm.prank(alice);
        vault.withdraw(20 ether); // window reset -> 20/70 ~28%, allowed
        assertEq(alice.balance, 50 ether);
        assertFalse(guardian.paused());
    }

    /// A whitelisted address still cannot withdraw while the breaker is latched
    /// (the vault enforces `paused` before per-withdrawal checks).
    function test_Whitelist_StillBlockedWhenPaused() public {
        guardian.setWhitelist(alice, true);
        // latch via Tier-2
        vm.prank(alice);
        vault.withdraw(20 ether); // escalates (alice whitelisted? -> returns true early, no escalate)
        // alice is whitelisted so no escalation; latch manually through a fresh request instead:
        // trigger a proactive check and trip it
        uint256 reqId = guardian.requestRiskCheck();
        platform.fulfillNumber(reqId, 90, 3);
        assertTrue(guardian.paused());

        vm.prank(alice);
        vm.expectRevert(ProtectedVault.ProtocolPaused.selector);
        vault.withdraw(1 ether);
    }

    /// Mixed validator responses: failed ones are ignored, average of successes decides.
    function test_AI_MixedValidators_AveragesSuccessesOnly() public {
        uint256 reqId = guardian.requestRiskCheck();
        int256[] memory scores = new int256[](3);
        uint8[] memory statuses = new uint8[](3);
        scores[0] = 80; statuses[0] = 2; // Success
        scores[1] = 0;  statuses[1] = 3; // Failed (ignored)
        scores[2] = 80; statuses[2] = 2; // Success
        platform.fulfillCustom(reqId, scores, statuses); // avg of successes = 80 >= 70 -> trip
        assertTrue(guardian.paused(), "should trip on avg of successful validators");
    }

    /// Negative AI scores are clamped to 0 and never underflow.
    function test_AI_NegativeScore_ClampedNoTrip() public {
        uint256 reqId = guardian.requestRiskCheck();
        int256[] memory scores = new int256[](2);
        uint8[] memory statuses = new uint8[](2);
        scores[0] = -50; statuses[0] = 2;
        scores[1] = -10; statuses[1] = 2;
        platform.fulfillCustom(reqId, scores, statuses); // clamps to 0 -> no trip, no revert
        assertFalse(guardian.paused());
    }

    /// requestRiskCheck on an underfunded guardian returns 0 and does not revert.
    function test_RiskCheck_Underfunded_ReturnsZero() public {
        guardian.withdrawFunds(address(guardian).balance);
        uint256 reqId = guardian.requestRiskCheck();
        assertEq(reqId, 0, "should skip when it cannot pay");
    }

    /// Fuzz: ANY single withdrawal at/above the hard threshold is always blocked.
    /// Stateless — only exercises the reverting path, so runs don't drain balances.
    function testFuzz_HardDrainAlwaysBlocked(uint256 amount) public {
        uint256 tvl = vault.totalAssets(); // 100 ether
        uint256 floor = (tvl * guardian.hardWithdrawalBps()) / 10_000; // 40 ether
        amount = bound(amount, floor, vault.balanceOf(alice)); // [40, 100] ether
        vm.assume((amount * 10_000) / tvl >= guardian.hardWithdrawalBps());

        vm.prank(alice);
        vm.expectRevert(ProtectedVault.BlockedByGuardian.selector);
        vault.withdraw(amount);
    }

    receive() external payable {}
}
