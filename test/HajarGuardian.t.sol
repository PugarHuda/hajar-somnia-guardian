// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HajarGuardian} from "../src/HajarGuardian.sol";
import {ProtectedVault} from "../src/ProtectedVault.sol";
import {MockAgentPlatform} from "../src/mocks/MockAgentPlatform.sol";
import {HajarReactiveMonitor} from "../src/HajarReactiveMonitor.sol";
import {Exploiter} from "../src/demo/Exploiter.sol";
import {Response, Request, ResponseStatus} from "../src/interfaces/ISomniaAgents.sol";

contract HajarGuardianTest is Test {
    HajarGuardian guardian;
    ProtectedVault vault;
    MockAgentPlatform platform;

    address owner = address(this);
    address alice = address(0xA11CE);
    address attacker = address(0xBAD);

    uint256 constant LLM_AGENT_ID = 42;

    function setUp() public {
        platform = new MockAgentPlatform();
        guardian = new HajarGuardian(address(platform), LLM_AGENT_ID);
        vault = new ProtectedVault();

        guardian.setVault(address(vault));
        vault.setGuardian(address(guardian));

        // fund the guardian so it can pay for AI escalations
        guardian.fund{value: 5 ether}();

        // seed the vault with deposits (TVL = 100 ether)
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}();
    }

    /// Tier 1: a blatant drain (>=40% of TVL) is blocked instantly, same block.
    /// Per-tx deterministic block — funds untouched. (Latch is a Tier-2/reactivity job.)
    function test_Tier1_HardDrain_BlockedSameBlock() public {
        vm.prank(alice);
        vm.expectRevert(ProtectedVault.BlockedByGuardian.selector);
        vault.withdraw(50 ether); // 50% of TVL -> hard violation

        assertEq(alice.balance, 0, "no funds should leave");
        assertEq(vault.balanceOf(alice), 100 ether, "balance intact");
        assertFalse(guardian.paused(), "tier-1 blocks per-tx, does not latch");
    }

    /// Normal small withdrawal passes untouched, no escalation, no pause.
    function test_NormalWithdrawal_Passes() public {
        vm.prank(alice);
        vault.withdraw(5 ether); // 5% of TVL -> below grey zone

        assertEq(alice.balance, 5 ether);
        assertFalse(guardian.paused());
    }

    /// Tier 2: grey-zone withdrawal is allowed but escalates; a high AI score trips breaker.
    function test_Tier2_GreyZone_AITrippsBreaker() public {
        vm.recordLogs();
        vm.prank(alice);
        vault.withdraw(20 ether); // 20% -> grey zone, allowed, escalated

        assertEq(alice.balance, 20 ether, "grey-zone withdrawal should succeed");
        assertFalse(guardian.paused(), "not paused until AI responds");

        // simulate 3 validators returning a high risk score (90)
        platform.fulfillNumber(1, 90, 3);
        assertTrue(guardian.paused(), "AI verdict should trip the breaker");
    }

    /// Tier 2: a low AI score leaves the protocol running.
    function test_Tier2_GreyZone_LowScore_NoTrip() public {
        vm.prank(alice);
        vault.withdraw(20 ether);

        platform.fulfillNumber(1, 10, 3); // low risk
        assertFalse(guardian.paused());
    }

    /// Once the breaker is latched (via Tier-2 AI), all withdrawals are rejected until reset.
    function test_PauseBlocksEveryone_UntilReset() public {
        vm.prank(alice);
        vault.withdraw(20 ether); // grey zone -> escalates (request id 1)

        platform.fulfillNumber(1, 95, 3); // AI verdict: attack -> latch breaker
        assertTrue(guardian.paused(), "AI should latch the breaker");

        vm.prank(alice);
        vm.expectRevert(ProtectedVault.ProtocolPaused.selector);
        vault.withdraw(1 ether); // globally paused now

        guardian.resetBreaker();

        vm.prank(alice);
        vault.withdraw(1 ether); // works again
        assertEq(alice.balance, 21 ether); // 20 + 1
    }

    /// Whitelisted addresses bypass all checks (e.g. protocol treasury).
    function test_Whitelist_Bypasses() public {
        guardian.setWhitelist(alice, true);
        vm.prank(alice);
        vault.withdraw(50 ether); // would normally hard-block
        assertEq(alice.balance, 50 ether);
        assertFalse(guardian.paused());
    }

    /// Callback must reject non-platform callers (anti-spoofing).
    function test_handleResponse_OnlyPlatform() public {
        Response[] memory empty = new Response[](0);
        Request memory req = Request({
            agentId: LLM_AGENT_ID,
            requester: address(guardian),
            callbackAddress: address(guardian),
            callbackSelector: HajarGuardian.handleResponse.selector,
            deposit: 0
        });

        vm.prank(attacker);
        vm.expectRevert(HajarGuardian.NotPlatform.selector);
        guardian.handleResponse(1, empty, ResponseStatus.Success, req);
    }

    /// Velocity: looped medium withdrawals (each below the single-tx limit) are caught by
    /// the rapid-drain rule once cumulative share crosses rapidDrainBps.
    function test_Velocity_RapidDrain_Blocked() public {
        Exploiter exploiter = new Exploiter(address(vault));
        vm.deal(address(this), 100 ether);
        exploiter.fundPosition{value: 100 ether}(); // TVL now 200, exploiter owns 100

        // chunks of 30 (15% of 200, below 40% hard limit) repeated; cumulative trips 60%.
        uint256 succeeded = exploiter.attack(30 ether, 5);

        assertEq(succeeded, 2, "should be blocked on the 3rd looped withdrawal");
        assertGt(vault.balanceOf(address(exploiter)), 0, "attacker could not fully drain");
    }

    /// Tier 3: a reactivity-driven signal latches the breaker in a SEPARATE execution
    /// (no revert), then subsequent withdrawals are paused.
    function test_Tier3_Reactivity_LatchesBreaker() public {
        HajarReactiveMonitor monitor = new HajarReactiveMonitor(address(guardian));
        guardian.setReactiveMonitor(address(monitor));
        // monitor.subscription defaults to this test (the demo keeper)

        // simulate the subscription firing on a drain-sized Withdrawn event
        monitor.onWithdrawn(attacker, 50 ether, 100 ether); // 50% -> hard violation
        assertTrue(guardian.paused(), "reactivity should latch the breaker");

        vm.prank(alice);
        vm.expectRevert(ProtectedVault.ProtocolPaused.selector);
        vault.withdraw(1 ether);
    }

    /// Tier 3 access control: only the configured monitor may signal.
    function test_onReactiveSignal_OnlyMonitor() public {
        vm.prank(attacker);
        vm.expectRevert(HajarGuardian.NotMonitor.selector);
        guardian.onReactiveSignal(attacker, 50 ether, 100 ether);
    }

    /// P1 #4: an underfunded guardian must NOT block grey-zone withdrawals (fail open).
    function test_Underfunded_GreyZone_DoesNotBlock() public {
        guardian.withdrawFunds(address(guardian).balance); // drain guardian STT
        vm.prank(alice);
        vault.withdraw(20 ether); // grey zone -> escalation skipped, withdrawal still succeeds
        assertEq(alice.balance, 20 ether, "withdrawal must succeed even if AI can't be paid");
    }

    /// P1 #5: a user cannot trigger repeated paid escalations within the cooldown window.
    function test_EscalationCooldown_PreventsDrainingBudget() public {
        uint256 balBefore = address(guardian).balance;
        vm.prank(alice);
        vault.withdraw(16 ether); // grey zone -> one escalation (pays)
        uint256 afterFirst = address(guardian).balance;
        assertLt(afterFirst, balBefore, "first escalation should spend STT");

        vm.prank(alice);
        vault.withdraw(16 ether); // within cooldown -> skipped, no spend
        assertEq(address(guardian).balance, afterFirst, "second escalation must be on cooldown");
    }

    /// P1 #6: the same withdrawal must not be counted twice across sync + reactive paths.
    function test_Velocity_NoDoubleCount_AcrossReactive() public {
        HajarReactiveMonitor monitor = new HajarReactiveMonitor(address(guardian));
        guardian.setReactiveMonitor(address(monitor));

        // single 30% withdrawal: recorded once by checkWithdrawal
        vm.prank(alice);
        vault.withdraw(30 ether); // 30% of 100, below 60% rapid limit -> allowed
        assertEq(alice.balance, 30 ether);

        // reactivity fires for that SAME withdrawal (tvlBefore = 100, as the event carries),
        // read-only velocity is still 30%, below both limits, so it must NOT latch.
        monitor.onWithdrawn(alice, 30 ether, 100 ether);
        assertFalse(guardian.paused(), "reactive path must not double-count into a false trip");
    }

    receive() external payable {}
}
