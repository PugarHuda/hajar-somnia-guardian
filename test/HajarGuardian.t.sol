// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HajarGuardian} from "../src/HajarGuardian.sol";
import {ProtectedVault} from "../src/ProtectedVault.sol";
import {MockAgentPlatform} from "./mocks/MockAgentPlatform.sol";
import {HajarReactiveMonitor} from "../src/HajarReactiveMonitor.sol";
import {Exploiter} from "../src/demo/Exploiter.sol";
import {Response, Request, ResponseStatus} from "../src/interfaces/ISomniaAgents.sol";

contract HajarGuardianTest is Test {
    HajarGuardian guardian;
    ProtectedVault vault;
    MockAgentPlatform platform;

    address alice = address(0xA11CE);
    address attacker = address(0xBAD);
    uint256 constant LLM_AGENT_ID = 42;

    function setUp() public {
        platform = new MockAgentPlatform();
        guardian = new HajarGuardian(address(platform), LLM_AGENT_ID);
        vault = new ProtectedVault();

        vault.setGuardian(address(guardian));
        guardian.registerProtocol(address(vault), 0, 0, 0, 0); // defaults; this test = admin
        guardian.fund{value: 5 ether}();

        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}();
    }

    function test_Tier1_HardDrain_BlockedSameBlock() public {
        vm.prank(alice);
        vm.expectRevert(ProtectedVault.BlockedByGuardian.selector);
        vault.withdraw(50 ether);

        assertEq(alice.balance, 0);
        assertEq(vault.balanceOf(alice), 100 ether);
        assertFalse(guardian.paused(address(vault)));
    }

    function test_NormalWithdrawal_Passes() public {
        vm.prank(alice);
        vault.withdraw(5 ether);
        assertEq(alice.balance, 5 ether);
        assertFalse(guardian.paused(address(vault)));
    }

    function test_Tier2_GreyZone_AITrippsBreaker() public {
        vm.prank(alice);
        vault.withdraw(20 ether); // grey zone -> escalates (request id 1)
        assertEq(alice.balance, 20 ether);
        assertFalse(guardian.paused(address(vault)));

        platform.fulfillNumber(1, 90, 3);
        assertTrue(guardian.paused(address(vault)));
    }

    function test_Tier2_GreyZone_LowScore_NoTrip() public {
        vm.prank(alice);
        vault.withdraw(20 ether);
        platform.fulfillNumber(1, 10, 3);
        assertFalse(guardian.paused(address(vault)));
    }

    function test_PauseBlocksEveryone_UntilReset() public {
        vm.prank(alice);
        vault.withdraw(20 ether);
        platform.fulfillNumber(1, 95, 3);
        assertTrue(guardian.paused(address(vault)));

        vm.prank(alice);
        vm.expectRevert(ProtectedVault.ProtocolPaused.selector);
        vault.withdraw(1 ether);

        guardian.resetBreaker(address(vault));

        vm.prank(alice);
        vault.withdraw(1 ether);
        assertEq(alice.balance, 21 ether);
    }

    function test_Whitelist_Bypasses() public {
        guardian.setWhitelist(address(vault), alice, true);
        vm.prank(alice);
        vault.withdraw(50 ether);
        assertEq(alice.balance, 50 ether);
        assertFalse(guardian.paused(address(vault)));
    }

    function test_handleResponse_OnlyPlatform() public {
        Response[] memory empty = new Response[](0);
        Request memory req;
        req.id = 1;
        req.requester = address(guardian);
        req.callbackAddress = address(guardian);
        req.callbackSelector = HajarGuardian.handleResponse.selector;

        vm.prank(attacker);
        vm.expectRevert(HajarGuardian.NotPlatform.selector);
        guardian.handleResponse(1, empty, ResponseStatus.Success, req);
    }

    function test_Velocity_RapidDrain_Blocked() public {
        Exploiter exploiter = new Exploiter(address(vault));
        vm.deal(address(this), 100 ether);
        exploiter.fundPosition{value: 100 ether}(); // TVL 200, exploiter owns 100

        uint256 succeeded = exploiter.attack(30 ether, 5);
        assertEq(succeeded, 2, "blocked on the 3rd looped withdrawal");
        assertGt(vault.balanceOf(address(exploiter)), 0);
    }

    function test_Tier3_Reactivity_LatchesBreaker() public {
        HajarReactiveMonitor monitor = new HajarReactiveMonitor(address(guardian), address(vault));
        guardian.setMonitor(address(vault), address(monitor));

        monitor.onWithdrawn(attacker, 50 ether, 100 ether); // 50% -> hard violation
        assertTrue(guardian.paused(address(vault)));

        vm.prank(alice);
        vm.expectRevert(ProtectedVault.ProtocolPaused.selector);
        vault.withdraw(1 ether);
    }

    function test_onReactiveSignal_OnlyMonitor() public {
        vm.prank(attacker);
        vm.expectRevert(HajarGuardian.NotMonitor.selector);
        guardian.onReactiveSignal(address(vault), attacker, 50 ether, 100 ether);
    }

    function test_Underfunded_GreyZone_DoesNotBlock() public {
        guardian.withdrawFunds(address(guardian).balance);
        vm.prank(alice);
        vault.withdraw(20 ether);
        assertEq(alice.balance, 20 ether, "withdrawal succeeds even if AI can't be paid");
    }

    function test_EscalationCooldown_PreventsDrainingBudget() public {
        uint256 balBefore = address(guardian).balance;
        vm.prank(alice);
        vault.withdraw(16 ether);
        uint256 afterFirst = address(guardian).balance;
        assertLt(afterFirst, balBefore);

        vm.prank(alice);
        vault.withdraw(16 ether);
        assertEq(address(guardian).balance, afterFirst, "second escalation on cooldown");
    }

    function test_Velocity_NoDoubleCount_AcrossReactive() public {
        HajarReactiveMonitor monitor = new HajarReactiveMonitor(address(guardian), address(vault));
        guardian.setMonitor(address(vault), address(monitor));

        vm.prank(alice);
        vault.withdraw(30 ether); // 30% of 100
        assertEq(alice.balance, 30 ether);

        monitor.onWithdrawn(alice, 30 ether, 100 ether); // read-only velocity, must not trip
        assertFalse(guardian.paused(address(vault)));
    }

    function test_RequestRiskCheck_Autonomous() public {
        uint256 reqId = guardian.requestRiskCheck(address(vault));
        assertGt(reqId, 0);
        assertFalse(guardian.paused(address(vault)));

        platform.fulfillNumber(reqId, 88, 3);
        assertTrue(guardian.paused(address(vault)));
    }

    function test_RequestRiskCheck_Gated() public {
        vm.prank(attacker);
        vm.expectRevert(HajarGuardian.NotProtocolAdmin.selector);
        guardian.requestRiskCheck(address(vault));
    }

    /// Multi-tenant: a second protocol is isolated — pausing one does not pause the other.
    function test_MultiTenant_Isolation() public {
        ProtectedVault vault2 = new ProtectedVault();
        vault2.setGuardian(address(guardian));
        guardian.registerProtocol(address(vault2), 0, 0, 0, 0);
        vm.deal(address(0xCAFE), 100 ether);
        vm.prank(address(0xCAFE));
        vault2.deposit{value: 100 ether}();

        // trip vault (protocol 1) via AI
        vm.prank(alice);
        vault.withdraw(20 ether);
        platform.fulfillNumber(1, 95, 3);
        assertTrue(guardian.paused(address(vault)));
        assertFalse(guardian.paused(address(vault2)), "vault2 must stay active");

        // vault2 still works
        vm.prank(address(0xCAFE));
        vault2.withdraw(5 ether);
        assertEq(address(0xCAFE).balance, 5 ether);
    }

    /// Price oracle (JSON API agent): market price diverging from reference latches the breaker.
    function test_PriceOracle_DivergenceTrips() public {
        guardian.setPriceFeed(address(vault), "https://api.x/eth", "ethereum.usd", 0, 2000, 1000); // ref 2000, max 10%
        uint256 reqId = guardian.requestPriceCheck(address(vault));
        platform.fulfillNumber(reqId, 1500, 3); // market 1500 vs ref 2000 = 25% divergence
        assertTrue(guardian.paused(address(vault)), "oracle divergence should latch breaker");
    }

    /// Price within tolerance does not trip.
    function test_PriceOracle_InRange_NoTrip() public {
        guardian.setPriceFeed(address(vault), "https://api.x/eth", "ethereum.usd", 0, 2000, 1000);
        uint256 reqId = guardian.requestPriceCheck(address(vault));
        platform.fulfillNumber(reqId, 2050, 3); // 2.5% divergence < 10%
        assertFalse(guardian.paused(address(vault)));
    }

    /// Threat intel (Parse Website agent): a high scraped threat score latches the breaker.
    function test_ThreatIntel_HighScoreTrips() public {
        guardian.setThreatFeed(address(vault), "https://rekt.news", "is this protocol exploited", 70, 50, 1);
        uint256 reqId = guardian.requestThreatScan(address(vault));
        platform.fulfillNumber(reqId, 85, 3); // scraped threat 85 >= 70
        assertTrue(guardian.paused(address(vault)), "high threat should latch breaker");
    }

    /// Threat intel via JSON API (reliable source): high score latches the breaker.
    function test_ThreatIntelJson_HighScoreTrips() public {
        guardian.setThreatFeedJson(address(vault), "https://api.x/threat?proto=foo", "data.score");
        guardian.setThreatFeed(address(vault), "", "", 70, 50, 1); // sets threshold=70
        uint256 reqId = guardian.requestThreatScanJson(address(vault));
        platform.fulfillNumber(reqId, 90, 3); // structured threat score 90 >= 70
        assertTrue(guardian.paused(address(vault)));
    }

    /// Low threat score keeps the protocol running.
    function test_ThreatIntel_LowScore_NoTrip() public {
        guardian.setThreatFeed(address(vault), "https://rekt.news", "is this protocol exploited", 70, 50, 1);
        uint256 reqId = guardian.requestThreatScan(address(vault));
        platform.fulfillNumber(reqId, 20, 3);
        assertFalse(guardian.paused(address(vault)));
    }

    receive() external payable {}
}
