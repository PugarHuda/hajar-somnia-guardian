// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HajarGuardian} from "../src/HajarGuardian.sol";
import {ProtectedVault} from "../src/ProtectedVault.sol";
import {MockAgentPlatform} from "./mocks/MockAgentPlatform.sol";

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
        vault.setGuardian(address(guardian));
        guardian.registerProtocol(address(vault), 0, 0, 0, 0);
        guardian.fund{value: 10 ether}();
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 100 ether}();
    }

    function _hardBps() internal view returns (uint256 h) {
        (,,,, h,,,) = guardian.protocols(address(vault));
    }

    function test_Reentrancy_CannotDrainOthers() public {
        ReentrantWithdrawer atk = new ReentrantWithdrawer(vault);
        vm.deal(address(this), 10 ether);
        atk.seed{value: 10 ether}();

        atk.attack(5 ether);

        assertEq(vault.totalAssets(), 100 ether, "alice's 100 STT untouched");
        assertEq(vault.balanceOf(address(atk)), 0, "atk only pulled its own deposit");
        assertLe(address(atk).balance, 10 ether);
    }

    function test_VelocityWindow_ResetsAfterExpiry() public {
        vm.prank(alice);
        vault.withdraw(30 ether);
        vm.warp(block.timestamp + guardian.windowSeconds() + 1);
        vm.prank(alice);
        vault.withdraw(20 ether);
        assertEq(alice.balance, 50 ether);
        assertFalse(guardian.paused(address(vault)));
    }

    function test_Whitelist_StillBlockedWhenPaused() public {
        guardian.setWhitelist(address(vault), alice, true);
        uint256 reqId = guardian.requestRiskCheck(address(vault));
        platform.fulfillNumber(reqId, 90, 3);
        assertTrue(guardian.paused(address(vault)));

        vm.prank(alice);
        vm.expectRevert(ProtectedVault.ProtocolPaused.selector);
        vault.withdraw(1 ether);
    }

    function test_AI_MixedValidators_AveragesSuccessesOnly() public {
        uint256 reqId = guardian.requestRiskCheck(address(vault));
        int256[] memory scores = new int256[](3);
        uint8[] memory statuses = new uint8[](3);
        scores[0] = 80; statuses[0] = 2;
        scores[1] = 0;  statuses[1] = 3; // failed, ignored
        scores[2] = 80; statuses[2] = 2;
        platform.fulfillCustom(reqId, scores, statuses); // avg successes = 80 -> trip
        assertTrue(guardian.paused(address(vault)));
    }

    function test_AI_NegativeScore_ClampedNoTrip() public {
        uint256 reqId = guardian.requestRiskCheck(address(vault));
        int256[] memory scores = new int256[](2);
        uint8[] memory statuses = new uint8[](2);
        scores[0] = -50; statuses[0] = 2;
        scores[1] = -10; statuses[1] = 2;
        platform.fulfillCustom(reqId, scores, statuses);
        assertFalse(guardian.paused(address(vault)));
    }

    function test_RiskCheck_Underfunded_ReturnsZero() public {
        guardian.withdrawFunds(address(guardian).balance);
        uint256 reqId = guardian.requestRiskCheck(address(vault));
        assertEq(reqId, 0);
    }

    function testFuzz_HardDrainAlwaysBlocked(uint256 amount) public {
        uint256 tvl = vault.totalAssets();
        uint256 hardBps = _hardBps();
        uint256 floor = (tvl * hardBps) / 10_000;
        amount = bound(amount, floor, vault.balanceOf(alice));
        vm.assume((amount * 10_000) / tvl >= hardBps);

        vm.prank(alice);
        vm.expectRevert(ProtectedVault.BlockedByGuardian.selector);
        vault.withdraw(amount);
    }

    receive() external payable {}
}
