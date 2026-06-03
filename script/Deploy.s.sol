// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HajarGuardian} from "../src/HajarGuardian.sol";
import {ProtectedVault} from "../src/ProtectedVault.sol";

/// @notice Deploys Hajar + a demo ProtectedVault and wires them together.
///
/// Usage (testnet):
///   forge script script/Deploy.s.sol \
///     --rpc-url somnia_testnet --broadcast \
///     --private-key $PRIVATE_KEY
///
/// Required env:
///   SOMNIA_PLATFORM  - Agents platform address for the target chain
///                      (testnet 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776)
///   LLM_AGENT_ID     - LLM Inference agent id from https://agents.somnia.network
contract Deploy is Script {
    function run() external {
        address platform = vm.envAddress("SOMNIA_PLATFORM");
        uint256 llmAgentId = vm.envUint("LLM_AGENT_ID");

        vm.startBroadcast();

        HajarGuardian guardian = new HajarGuardian(platform, llmAgentId);
        ProtectedVault vault = new ProtectedVault();

        guardian.setVault(address(vault));
        vault.setGuardian(address(guardian));

        // Seed the guardian so it can pay for AI escalations (tune as needed).
        guardian.fund{value: 1 ether}();

        vm.stopBroadcast();

        console2.log("HajarGuardian :", address(guardian));
        console2.log("ProtectedVault:", address(vault));
        console2.log("Platform      :", platform);
        console2.log("LLM agent id  :", llmAgentId);
    }
}
