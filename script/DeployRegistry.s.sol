// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HajarAgentRegistry} from "../src/HajarAgentRegistry.sol";

/// @notice Deploys the ERC-8004 Identity Registry and registers Hajar as a Trustless Agent whose
///         tokenURI points at the live Agent Registration File (the agent-card JSON). After this,
///         set web/app/lib/somnia.ts REGISTRY.address + agentId so the agent-card emits its
///         on-chain `registrations` entry.
///
/// Env:
///   AGENT_CARD_URI - https://hajar-somnia-guardian.vercel.app/.well-known/agent-card.json
contract DeployRegistry is Script {
    function run() external {
        string memory cardURI = vm.envOr(
            "AGENT_CARD_URI",
            string("https://hajar-somnia-guardian.vercel.app/.well-known/agent-card.json")
        );

        vm.startBroadcast();

        HajarAgentRegistry registry = new HajarAgentRegistry();

        // Attach a couple of useful indexable metadata fields at registration time.
        HajarAgentRegistry.MetadataEntry[] memory md = new HajarAgentRegistry.MetadataEntry[](2);
        md[0] = HajarAgentRegistry.MetadataEntry({key: "category", value: bytes("defi-security")});
        md[1] = HajarAgentRegistry.MetadataEntry({key: "standard", value: bytes("erc-7265+erc-8004")});
        uint256 agentId = registry.register(cardURI, md);

        vm.stopBroadcast();

        console2.log("HajarAgentRegistry:", address(registry));
        console2.log("Hajar agentId     :", agentId);
        console2.log("Agent card URI    :", cardURI);
    }
}
