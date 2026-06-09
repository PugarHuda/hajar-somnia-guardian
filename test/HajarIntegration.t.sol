// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HajarGuardian} from "../src/HajarGuardian.sol";
import {ProtectedVault} from "../src/ProtectedVault.sol";
import {HajarThreatLearner} from "../src/HajarThreatLearner.sol";
import {HajarAgentRegistry} from "../src/HajarAgentRegistry.sol";
import {MockAgentPlatform} from "./mocks/MockAgentPlatform.sol";

/// @dev Vault with a settable TVL (simulate a drain that bypasses the withdrawal hook).
contract MockTVLVault {
    uint256 public totalAssets;
    function setTotalAssets(uint256 v) external { totalAssets = v; }
}

/// @dev Vault that exposes a synchronous spot price and routes withdrawals through the guardian.
contract MockPricedVault {
    HajarGuardian public guardian;
    uint256 public totalAssets = 100 ether;
    uint256 public spotPrice = 1000;
    constructor(HajarGuardian g) { guardian = g; }
    function setSpot(uint256 v) external { spotPrice = v; }
    function probe(address u, uint256 a, uint256 t) external returns (bool) { return guardian.checkWithdrawal(u, a, t); }
}

/// End-to-end + edge-case QA across every hardening tier, the learner, and the registry.
contract HajarIntegrationTest is Test {
    HajarGuardian guardian;
    ProtectedVault vault;
    MockAgentPlatform platform;

    address alice = address(0xA11CE);
    address[5] sybils = [address(0x51B11), address(0x51B12), address(0x51B13), address(0x51B14), address(0x51B15)];
    uint256 constant AID = 12847293847561029384;

    function setUp() public {
        platform = new MockAgentPlatform();
        guardian = new HajarGuardian(address(platform), AID);
        vault = new ProtectedVault();
        vault.setGuardian(address(guardian));
        guardian.registerProtocol(address(vault), 0, 0, 0, 0);
        guardian.fund{value: 10 ether}();
    }

    function _seed(address who, uint256 amt) internal {
        vm.deal(who, amt);
        vm.prank(who);
        vault.deposit{value: amt}();
    }

    /*//////////////////////////////////////////////////////////////
                       SCENARIO: distributed sybil drain
    //////////////////////////////////////////////////////////////*/

    /// 5 sybils each pull 12% (under the 15% grey zone, so per-user never escalates), but the
    /// vault-wide budget stops the aggregate once it crosses 50%.
    function test_Scenario_SybilDrain_StoppedByBudget() public {
        for (uint256 i = 0; i < 5; i++) _seed(sybils[i], 100 ether); // TVL 500
        guardian.setOutflowBudget(address(vault), 5_000); // 50% of 500 = 250

        uint256 ok;
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(sybils[i]);
            try vault.withdraw(60 ether) { ok++; } catch { break; } // 60/500 = 12% each
        }
        // 60*4 = 240 (48%) pass; the 5th (cum 300 = 60%) is blocked.
        assertEq(ok, 4, "aggregate budget halts the sybil drain at the 5th");
        assertFalse(guardian.paused(address(vault)), "Tier-1 budget never latches");
    }

    /// Budget boundary: cumulative exactly == budget blocks (>=, not >).
    function test_OutflowBudget_BoundaryInclusive() public {
        _seed(alice, 100 ether);
        guardian.setOutflowBudget(address(vault), 2_000); // 20% = 20 ether
        vm.prank(alice);
        vm.expectRevert(ProtectedVault.BlockedByGuardian.selector);
        vault.withdraw(20 ether); // exactly 20% -> blocked (inclusive)
    }

    /// Disabling the budget (set 0) re-opens flow.
    function test_OutflowBudget_DisableReopens() public {
        _seed(alice, 100 ether);
        guardian.setOutflowBudget(address(vault), 1_000); // 10%
        vm.prank(alice);
        vm.expectRevert(ProtectedVault.BlockedByGuardian.selector);
        vault.withdraw(12 ether);
        guardian.setOutflowBudget(address(vault), 0); // disable
        vm.prank(alice);
        vault.withdraw(12 ether);
        assertEq(alice.balance, 12 ether);
    }

    /*//////////////////////////////////////////////////////////////
                  SCENARIO: drain that bypasses the hook
    //////////////////////////////////////////////////////////////*/

    function test_Scenario_BypassDrain_CaughtByTvlMonitor() public {
        MockTVLVault mock = new MockTVLVault();
        mock.setTotalAssets(100 ether);
        guardian.registerProtocol(address(mock), 0, 0, 0, 0);
        guardian.setTvlMonitor(address(mock), 2_000); // latch on >=20% unexplained

        // attacker drains 40% through a path the guardian never sees
        mock.setTotalAssets(60 ether);
        assertTrue(guardian.checkTvlDrop(address(mock)), "unexplained 40% drop latches");
        assertTrue(guardian.paused(address(mock)));
    }

    /// TVL growing (a deposit) then dropping back is not flagged — baseline re-syncs up.
    function test_TvlMonitor_GrowThenDrop_NoFalseLatch() public {
        MockTVLVault mock = new MockTVLVault();
        mock.setTotalAssets(100 ether);
        guardian.registerProtocol(address(mock), 0, 0, 0, 0);
        guardian.setTvlMonitor(address(mock), 2_000);

        mock.setTotalAssets(150 ether); // grew
        assertFalse(guardian.checkTvlDrop(address(mock))); // re-baselines to 150
        mock.setTotalAssets(140 ether); // 6.7% off the new baseline
        assertFalse(guardian.checkTvlDrop(address(mock)));
        assertFalse(guardian.paused(address(mock)));
    }

    /// syncTvlBaseline lets an admin clear a known legitimate flow before it looks like a drain.
    function test_TvlMonitor_SyncBaseline() public {
        MockTVLVault mock = new MockTVLVault();
        mock.setTotalAssets(100 ether);
        guardian.registerProtocol(address(mock), 0, 0, 0, 0);
        guardian.setTvlMonitor(address(mock), 2_000);
        mock.setTotalAssets(50 ether); // big legit move
        guardian.syncTvlBaseline(address(mock));
        assertFalse(guardian.checkTvlDrop(address(mock)), "no drop vs the synced baseline");
    }

    /*//////////////////////////////////////////////////////////////
                  SCENARIO: atomic flash-loan spot guard
    //////////////////////////////////////////////////////////////*/

    function test_Scenario_FlashLoanSpot_BlockedAtomically() public {
        MockPricedVault pv = new MockPricedVault(guardian);
        guardian.registerProtocol(address(pv), 0, 0, 0, 0);
        guardian.setSpotGuard(address(pv), 1000, 500); // 5% tol

        pv.setSpot(1080); // +8% manipulation
        assertFalse(pv.probe(alice, 1 ether, 100 ether), "manipulated price blocked in-tx");
        pv.setSpot(1030); // +3% within tol
        assertTrue(pv.probe(alice, 1 ether, 100 ether));
    }

    /// Spot guard with reference 0 is treated as disabled (no false block, no div-by-zero).
    function test_SpotGuard_ZeroReference_Disabled() public {
        MockPricedVault pv = new MockPricedVault(guardian);
        guardian.registerProtocol(address(pv), 0, 0, 0, 0);
        guardian.setSpotGuard(address(pv), 0, 500);
        assertTrue(pv.probe(alice, 1 ether, 100 ether), "ref 0 => disabled, allow");
    }

    function test_SpotGuard_SetReferenceUpdates() public {
        MockPricedVault pv = new MockPricedVault(guardian);
        guardian.registerProtocol(address(pv), 0, 0, 0, 0);
        guardian.setSpotGuard(address(pv), 1000, 500);
        guardian.setSpotReference(address(pv), 1100); // now ref 1100
        pv.setSpot(1100);
        assertTrue(pv.probe(alice, 1 ether, 100 ether), "spot == new ref -> ok");
    }

    /*//////////////////////////////////////////////////////////////
              SCENARIO: all hardening tiers on one vault
    //////////////////////////////////////////////////////////////*/

    /// Budget + TVL monitor enabled together compose without interfering on a normal withdrawal.
    function test_Scenario_AllTiersCompose_NormalFlowOk() public {
        _seed(alice, 100 ether);
        guardian.setOutflowBudget(address(vault), 7_000);
        guardian.setTvlMonitor(address(vault), 2_000);

        vm.prank(alice);
        vault.withdraw(5 ether); // 5% — fine
        assertEq(alice.balance, 5 ether);
        // the guarded outflow is accounted, so checkTvlDrop sees it as explained
        assertFalse(guardian.checkTvlDrop(address(vault)));
        assertFalse(guardian.paused(address(vault)));
    }

    /*//////////////////////////////////////////////////////////////
                        LEARNER — edge cases
    //////////////////////////////////////////////////////////////*/

    function test_Learner_MixedValidators_AveragesSuccesses() public {
        HajarThreatLearner learner = new HajarThreatLearner(address(platform), 1, 2, 3);
        learner.fund{value: 2 ether}();
        learner.setSource("oracle", HajarThreatLearner.SourceKind.Json, "u", "s", "", 0, 0);
        bytes32 id = keccak256(bytes("oracle"));
        uint256 req = learner.learn(id);

        int256[] memory scores = new int256[](3);
        uint8[] memory st = new uint8[](3);
        scores[0] = 60; st[0] = 2;
        scores[1] = 0; st[1] = 3; // failed -> ignored
        scores[2] = 80; st[2] = 2;
        platform.fulfillCustom(req, scores, st); // avg of successes = 70
        (, uint8 level,,,) = learner.knowledge(id);
        assertEq(level, 70);
    }

    function test_Learner_NoConsensus_NoRecord() public {
        HajarThreatLearner learner = new HajarThreatLearner(address(platform), 1, 2, 3);
        learner.fund{value: 2 ether}();
        learner.setSource("oracle", HajarThreatLearner.SourceKind.Json, "u", "s", "", 0, 0);
        bytes32 id = keccak256(bytes("oracle"));
        uint256 req = learner.learn(id);

        int256[] memory scores = new int256[](2);
        uint8[] memory st = new uint8[](2);
        scores[0] = 90; st[0] = 3; // both failed
        scores[1] = 90; st[1] = 4;
        platform.fulfillCustom(req, scores, st);
        (, uint8 level,, uint32 obs,) = learner.knowledge(id);
        assertEq(level, 0, "no successful validator -> nothing learned");
        assertEq(obs, 0);
    }

    function test_Learner_AccumulatesObservations() public {
        HajarThreatLearner learner = new HajarThreatLearner(address(platform), 1, 2, 3);
        learner.fund{value: 3 ether}();
        learner.setSource("oracle", HajarThreatLearner.SourceKind.Json, "u", "s", "", 0, 0);
        bytes32 id = keccak256(bytes("oracle"));
        platform.fulfillNumber(learner.learn(id), 40, 3);
        platform.fulfillNumber(learner.learn(id), 60, 3);
        (, uint8 level,, uint32 obs,) = learner.knowledge(id);
        assertEq(level, 60, "latest level");
        assertEq(obs, 2, "observations accumulate");
    }

    function test_Learner_LevelClampedTo100() public {
        HajarThreatLearner learner = new HajarThreatLearner(address(platform), 1, 2, 3);
        learner.fund{value: 2 ether}();
        learner.setSource("x", HajarThreatLearner.SourceKind.Json, "u", "s", "", 0, 0);
        bytes32 id = keccak256(bytes("x"));
        platform.fulfillNumber(learner.learn(id), 250, 3); // over 100
        (, uint8 level,,,) = learner.knowledge(id);
        assertEq(level, 100, "clamped");
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTRY — edge cases
    //////////////////////////////////////////////////////////////*/

    function test_Registry_MultipleAgents_IncrementIds() public {
        HajarAgentRegistry reg = new HajarAgentRegistry();
        vm.prank(alice);
        uint256 a = reg.register("a");
        vm.prank(address(0xBEEF));
        uint256 b = reg.register("b");
        assertEq(a, 1);
        assertEq(b, 2);
        assertEq(reg.ownerOf(2), address(0xBEEF));
    }

    function test_Registry_MetadataOverwrite() public {
        HajarAgentRegistry reg = new HajarAgentRegistry();
        vm.startPrank(alice);
        uint256 id = reg.register("a");
        reg.setMetadata(id, "k", bytes("v1"));
        reg.setMetadata(id, "k", bytes("v2"));
        vm.stopPrank();
        assertEq(reg.getMetadata(id, "k"), bytes("v2"));
    }

    function test_Registry_TransferMovesControl() public {
        HajarAgentRegistry reg = new HajarAgentRegistry();
        vm.prank(alice);
        uint256 id = reg.register("a");
        vm.prank(alice);
        reg.transferFrom(alice, address(0xBEEF), id);
        // old owner can no longer edit
        vm.prank(alice);
        vm.expectRevert(HajarAgentRegistry.NotAgentOwner.selector);
        reg.setAgentURI(id, "x");
        // new owner can
        vm.prank(address(0xBEEF));
        reg.setAgentURI(id, "x");
        assertEq(reg.tokenURI(id), "x");
    }

    function test_Registry_ApprovedCanTransfer() public {
        HajarAgentRegistry reg = new HajarAgentRegistry();
        vm.prank(alice);
        uint256 id = reg.register("a");
        vm.prank(alice);
        reg.approve(address(0xCAFE), id);
        vm.prank(address(0xCAFE));
        reg.transferFrom(alice, address(0xCAFE), id);
        assertEq(reg.ownerOf(id), address(0xCAFE));
    }

    receive() external payable {}
}
