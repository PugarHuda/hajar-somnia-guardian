// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HajarGuardian} from "../src/HajarGuardian.sol";
import {ProtectedVault} from "../src/ProtectedVault.sol";

/// @notice Deploys the multi-tenant Hajar guardian + a demo ProtectedVault, registers the
///         protocol, and funds the guardian for AI escalations.
///
/// Env:
///   SOMNIA_PLATFORM  - Agents platform (testnet 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776)
///   LLM_AGENT_ID     - LLM Inference agent id (12847293847561029384)
///   GUARDIAN_FUND    - optional wei to seed the guardian (default 0.5 STT)
///
/// The reactive subscriber (real Tier-3) is deployed separately — it needs >= 32 STT and the
/// live reactivity precompile, so it is not part of this script.
contract Deploy is Script {
    function run() external {
        address platform = vm.envAddress("SOMNIA_PLATFORM");
        uint256 llmAgentId = vm.envOr("LLM_AGENT_ID", uint256(0));
        uint256 fundAmount = vm.envOr("GUARDIAN_FUND", uint256(0.5 ether));

        vm.startBroadcast();

        HajarGuardian guardian = new HajarGuardian(platform, llmAgentId);
        ProtectedVault vault = new ProtectedVault();

        vault.setGuardian(address(guardian));
        guardian.registerProtocol(address(vault), 0, 0, 0, 0);
        if (fundAmount > 0) guardian.fund{value: fundAmount}();

        vm.stopBroadcast();

        console2.log("HajarGuardian :", address(guardian));
        console2.log("ProtectedVault:", address(vault));
        console2.log("Platform      :", platform);
        console2.log("LLM agent id  :", llmAgentId);
    }
}
