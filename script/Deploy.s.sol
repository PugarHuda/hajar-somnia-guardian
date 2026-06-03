// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HajarGuardian} from "../src/HajarGuardian.sol";
import {ProtectedVault} from "../src/ProtectedVault.sol";
import {HajarReactiveMonitor} from "../src/HajarReactiveMonitor.sol";

/// @notice Deploys the full Hajar stack and wires it together.
///
/// Usage (testnet):
///   forge script script/Deploy.s.sol \
///     --rpc-url somnia_testnet --broadcast --private-key $PRIVATE_KEY
///
/// Env:
///   SOMNIA_PLATFORM  - Agents platform (testnet 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776)
///   LLM_AGENT_ID     - optional; defaults to 0 (set later via setLlmAgentId once you have
///                      the id from https://agents.somnia.network). Tier-1/Tier-3 work without it.
///   GUARDIAN_FUND    - optional wei to seed the guardian for AI escalations (default 0.3 STT)
contract Deploy is Script {
    function run() external {
        address platform = vm.envAddress("SOMNIA_PLATFORM");
        uint256 llmAgentId = vm.envOr("LLM_AGENT_ID", uint256(0));
        uint256 fundAmount = vm.envOr("GUARDIAN_FUND", uint256(0.3 ether));

        vm.startBroadcast();

        HajarGuardian guardian = new HajarGuardian(platform, llmAgentId);
        ProtectedVault vault = new ProtectedVault();
        HajarReactiveMonitor monitor = new HajarReactiveMonitor(address(guardian));

        guardian.setVault(address(vault));
        guardian.setReactiveMonitor(address(monitor));
        vault.setGuardian(address(guardian));

        if (fundAmount > 0) {
            guardian.fund{value: fundAmount}();
        }

        vm.stopBroadcast();

        console2.log("HajarGuardian      :", address(guardian));
        console2.log("ProtectedVault     :", address(vault));
        console2.log("HajarReactiveMonitor:", address(monitor));
        console2.log("Platform           :", platform);
        console2.log("LLM agent id       :", llmAgentId);
    }
}
