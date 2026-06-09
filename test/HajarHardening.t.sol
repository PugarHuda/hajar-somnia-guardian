// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HajarGuardian} from "../src/HajarGuardian.sol";
import {ProtectedVault} from "../src/ProtectedVault.sol";
import {MockAgentPlatform} from "./mocks/MockAgentPlatform.sol";

/// @dev A vault whose reported TVL can be moved directly — lets us simulate a drain that BYPASSES
///      the withdrawal hook (a bug in another function, a direct transfer, etc.).
contract MockTVLVault {
    uint256 public totalAssets;

    function setTotalAssets(uint256 v) external {
        totalAssets = v;
    }
}

/// @dev A vault that exposes a synchronous spot price and routes withdrawals through the guardian,
///      so we can exercise the Tier-1c atomic spot-price guard.
contract MockPricedVault {
    HajarGuardian public guardian;
    uint256 public totalAssets = 100 ether;
    uint256 public spotPrice = 1000;

    constructor(HajarGuardian g) {
        guardian = g;
    }

    function setSpot(uint256 v) external {
        spotPrice = v;
    }

    function probe(address user, uint256 amount, uint256 tvl) external returns (bool) {
        return guardian.checkWithdrawal(user, amount, tvl);
    }
}

contract HajarHardeningTest is Test {
    HajarGuardian guardian;
    ProtectedVault vault;
    MockAgentPlatform platform;

    address alice = address(0xA11CE);
    address attacker = address(0xBAD);
    uint256 constant AID = 12847293847561029384;

    function setUp() public {
        platform = new MockAgentPlatform();
        guardian = new HajarGuardian(address(platform), AID);
        vault = new ProtectedVault();
        vault.setGuardian(address(guardian));
        guardian.registerProtocol(address(vault), 0, 0, 0, 0); // defaults; test = admin
        guardian.fund{value: 5 ether}();

        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}();
    }

    /*//////////////////////////////////////////////////////////////
        #3 — VAULT-WIDE OUTFLOW BUDGET (slow, distributed drain)
    //////////////////////////////////////////////////////////////*/

    /// Four sybil users each withdraw 12.5% of TVL — every single one is UNDER the 15% grey zone,
    /// so the per-user velocity tier never fires. The vault-wide budget still stops the aggregate
    /// drain once 30% of TVL has left across all of them combined.
    function test_OutflowBudget_BlocksDistributedDrain() public {
        (address[4] memory users) = _fourFundedUsers(); // TVL now 100 (alice) + 4*100 = 500
        uint256 tvl = vault.totalAssets();
        assertEq(tvl, 500 ether);

        guardian.setOutflowBudget(address(vault), 3_000); // 30% of TVL may flow out per window

        // baseline TVL = 500 at first withdrawal; budget = 30% = 150 ether cumulative.
        // each withdrawal is 60 ether = 12% of 500 (< 15% grey, so no per-user escalation).
        vm.prank(users[0]);
        vault.withdraw(60 ether); // cum 60 (12%)
        vm.prank(users[1]);
        vault.withdraw(60 ether); // cum 120 (24%)

        // third pushes cumulative to 180 = 36% >= 30% budget -> atomic block
        vm.prank(users[2]);
        vm.expectRevert(ProtectedVault.BlockedByGuardian.selector);
        vault.withdraw(60 ether);

        assertFalse(guardian.paused(address(vault)), "Tier-1 budget must NOT latch (sync revert)");
    }

    /// Opt-in: with no budget configured the same three withdrawals all pass.
    function test_OutflowBudget_DisabledByDefault() public {
        (address[4] memory users) = _fourFundedUsers();
        vm.prank(users[0]);
        vault.withdraw(60 ether);
        vm.prank(users[1]);
        vault.withdraw(60 ether);
        vm.prank(users[2]);
        vault.withdraw(60 ether);
        assertEq(users[2].balance, 60 ether, "no budget set -> all pass");
    }

    /// The budget is a rolling window: after it expires the aggregate counter resets.
    function test_OutflowBudget_WindowResets() public {
        (address[4] memory users) = _fourFundedUsers();
        guardian.setOutflowBudget(address(vault), 3_000);

        vm.prank(users[0]);
        vault.withdraw(60 ether);
        vm.prank(users[1]);
        vault.withdraw(60 ether); // cum 120 (24%)

        vm.warp(block.timestamp + guardian.windowSeconds() + 1);

        // fresh window, new baseline -> this 12% withdrawal is fine again
        vm.prank(users[2]);
        vault.withdraw(60 ether);
        assertEq(users[2].balance, 60 ether);
    }

    /*//////////////////////////////////////////////////////////////
        #1 — TVL-DROP DETECTOR (drain that bypasses the hook)
    //////////////////////////////////////////////////////////////*/

    /// A drain through a path the guardian never sees (no guarded outflow recorded) shows up as an
    /// UNEXPLAINED TVL drop and latches the breaker.
    function test_TvlDrop_UnexplainedDrain_Latches() public {
        MockTVLVault mock = new MockTVLVault();
        mock.setTotalAssets(100 ether);
        guardian.registerProtocol(address(mock), 0, 0, 0, 0);
        guardian.setTvlMonitor(address(mock), 2_000); // latch on >= 20% unexplained drop

        mock.setTotalAssets(70 ether); // 30% vanished, none of it via checkWithdrawal

        bool latched = guardian.checkTvlDrop(address(mock));
        assertTrue(latched, "30% unexplained drop must latch");
        assertTrue(guardian.paused(address(mock)));
    }

    /// A drop fully explained by legitimate guarded withdrawals must NOT latch.
    function test_TvlDrop_ExplainedByGuardedOutflow_NoLatch() public {
        guardian.setTvlMonitor(address(vault), 2_000); // baseline = 100 (alice's deposit)

        vm.prank(alice);
        vault.withdraw(10 ether); // guarded, recorded as accounted outflow; TVL now 90

        bool latched = guardian.checkTvlDrop(address(vault));
        assertFalse(latched, "drop fully explained by guarded outflow");
        assertFalse(guardian.paused(address(vault)));
    }

    /// A small unexplained drop under the threshold does not latch, and the baseline re-syncs.
    function test_TvlDrop_BelowThreshold_NoLatch() public {
        MockTVLVault mock = new MockTVLVault();
        mock.setTotalAssets(100 ether);
        guardian.registerProtocol(address(mock), 0, 0, 0, 0);
        guardian.setTvlMonitor(address(mock), 2_000);

        mock.setTotalAssets(90 ether); // 10% < 20% threshold
        assertFalse(guardian.checkTvlDrop(address(mock)));
        assertFalse(guardian.paused(address(mock)));

        // baseline re-synced to 90: a further 10% (to 81) is again under threshold, no false latch.
        mock.setTotalAssets(81 ether);
        assertFalse(guardian.checkTvlDrop(address(mock)));
    }

    /// Regression: a whitelisted withdrawal is a guardian-SEEN outflow, so it must be accounted —
    /// otherwise its legitimate TVL drop looks unexplained and falsely latches the breaker.
    function test_TvlDrop_WhitelistedOutflow_Accounted_NoFalseLatch() public {
        guardian.setTvlMonitor(address(vault), 2_000); // baseline = 100
        guardian.setWhitelist(address(vault), alice, true);

        vm.prank(alice);
        vault.withdraw(30 ether); // whitelisted; bypasses rules but must still be accounted; TVL 70

        bool latched = guardian.checkTvlDrop(address(vault));
        assertFalse(latched, "whitelisted outflow must be accounted, not flagged as a hidden drain");
        assertFalse(guardian.paused(address(vault)));
    }

    function test_TvlDrop_Gated() public {
        guardian.setTvlMonitor(address(vault), 2_000);
        vm.prank(attacker);
        vm.expectRevert(HajarGuardian.NotProtocolAdmin.selector);
        guardian.checkTvlDrop(address(vault));
    }

    /*//////////////////////////////////////////////////////////////
        #2 — SYNCHRONOUS SPOT-PRICE GUARD (atomic flash-loan)
    //////////////////////////////////////////////////////////////*/

    /// When the vault's live spot price diverges from the reference beyond tolerance, the guardian
    /// rejects the withdrawal IN THE SAME TX (returns false) — the only tier fast enough for an
    /// atomic flash-loan price manipulation.
    function test_SpotGuard_DivergenceBlocksAtomically() public {
        MockPricedVault pv = new MockPricedVault(guardian);
        guardian.registerProtocol(address(pv), 0, 0, 0, 0);
        guardian.setSpotGuard(address(pv), 1000, 500); // ref 1000, max 5% divergence

        pv.setSpot(1100); // +10% -> manipulated
        bool ok = pv.probe(alice, 1 ether, 100 ether);
        assertFalse(ok, "manipulated spot price must be blocked atomically");
        assertFalse(guardian.paused(address(pv)), "sync tier must not latch");
    }

    /// A spot price within tolerance passes.
    function test_SpotGuard_InRangePasses() public {
        MockPricedVault pv = new MockPricedVault(guardian);
        guardian.registerProtocol(address(pv), 0, 0, 0, 0);
        guardian.setSpotGuard(address(pv), 1000, 500);

        pv.setSpot(1020); // +2% < 5%
        bool ok = pv.probe(alice, 1 ether, 100 ether);
        assertTrue(ok, "in-range price should pass");
    }

    /// Robustness: enabling the spot guard on a vault that has no `spotPrice()` must NOT brick
    /// withdrawals — an unreadable price is an infra problem and fails OPEN (allow), per SECURITY.md.
    function test_SpotGuard_MissingSpotPrice_FailsOpen() public {
        // `vault` (ProtectedVault) has no spotPrice(); enable the guard anyway.
        guardian.setSpotGuard(address(vault), 1000, 500);
        vm.prank(alice);
        vault.withdraw(5 ether); // 5% normal withdrawal must still succeed
        assertEq(alice.balance, 5 ether, "missing spotPrice() must fail open, not brick the vault");
    }

    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/

    function _fourFundedUsers() internal returns (address[4] memory users) {
        users[0] = address(0x1001);
        users[1] = address(0x1002);
        users[2] = address(0x1003);
        users[3] = address(0x1004);
        for (uint256 i = 0; i < 4; i++) {
            vm.deal(users[i], 100 ether);
            vm.prank(users[i]);
            vault.deposit{value: 100 ether}();
        }
    }

    receive() external payable {}
}
