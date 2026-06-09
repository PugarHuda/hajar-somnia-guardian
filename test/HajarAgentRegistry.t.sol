// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HajarAgentRegistry} from "../src/HajarAgentRegistry.sol";

contract HajarAgentRegistryTest is Test {
    HajarAgentRegistry reg;
    address hajar = address(0x4A3A);
    address other = address(0xB0B);

    function setUp() public {
        reg = new HajarAgentRegistry();
    }

    function test_Register_MintsIdentityToCaller() public {
        vm.prank(hajar);
        uint256 id = reg.register("https://hajar.app/.well-known/agent-card.json");
        assertEq(id, 1);
        assertEq(reg.ownerOf(id), hajar, "owner must be the caller, not the registry");
        assertEq(reg.balanceOf(hajar), 1);
        assertEq(reg.tokenURI(id), "https://hajar.app/.well-known/agent-card.json");
    }

    function test_Register_WithMetadata() public {
        HajarAgentRegistry.MetadataEntry[] memory md = new HajarAgentRegistry.MetadataEntry[](1);
        md[0] = HajarAgentRegistry.MetadataEntry({key: "category", value: bytes("defi-security")});
        vm.prank(hajar);
        uint256 id = reg.register("ipfs://card", md);
        assertEq(reg.getMetadata(id, "category"), bytes("defi-security"));
    }

    function test_SetAgentURI_OnlyOwner() public {
        vm.prank(hajar);
        uint256 id = reg.register("v1");

        vm.prank(other);
        vm.expectRevert(HajarAgentRegistry.NotAgentOwner.selector);
        reg.setAgentURI(id, "v2");

        vm.prank(hajar);
        reg.setAgentURI(id, "v2");
        assertEq(reg.tokenURI(id), "v2");
    }

    function test_AgentWallet_DefaultsToOwner_ThenSettable() public {
        vm.prank(hajar);
        uint256 id = reg.register("card");
        assertEq(reg.getAgentWallet(id), hajar, "defaults to owner");

        address opWallet = address(0xC0FFEE);
        vm.prank(hajar);
        reg.setAgentWallet(id, opWallet);
        assertEq(reg.getAgentWallet(id), opWallet);

        vm.prank(hajar);
        reg.unsetAgentWallet(id);
        assertEq(reg.getAgentWallet(id), hajar);
    }

    function test_Transfer_PortableIdentity() public {
        vm.prank(hajar);
        uint256 id = reg.register("card");

        vm.prank(other);
        vm.expectRevert(HajarAgentRegistry.NotAgentOwner.selector);
        reg.transferFrom(hajar, other, id);

        vm.prank(hajar);
        reg.transferFrom(hajar, other, id);
        assertEq(reg.ownerOf(id), other);
        assertEq(reg.balanceOf(hajar), 0);
        assertEq(reg.balanceOf(other), 1);
    }

    function test_SupportsInterface_ERC721() public view {
        assertTrue(reg.supportsInterface(0x80ac58cd), "ERC-721");
        assertTrue(reg.supportsInterface(0x5b5e139f), "ERC-721 Metadata");
        assertTrue(reg.supportsInterface(0x01ffc9a7), "ERC-165");
        assertFalse(reg.supportsInterface(0xdeadbeef));
    }

    function test_TokenURI_UnknownReverts() public {
        vm.expectRevert(HajarAgentRegistry.UnknownAgent.selector);
        reg.tokenURI(999);
    }
}
