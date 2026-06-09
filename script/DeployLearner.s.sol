// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HajarThreatLearner} from "../src/HajarThreatLearner.sol";

/// @notice Deploys Hajar's self-learning threat-intelligence engine, seeds the exploit taxonomy
///         with real external learning sources, and funds it for agent scans.
///
/// Env:
///   SOMNIA_PLATFORM - Agents platform (testnet 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776)
///   LLM_AGENT_ID    - LLM Inference agent id (12847293847561029384)
///   LEARNER_FUND    - optional wei to seed (default 1.5 STT)
contract DeployLearner is Script {
    uint256 constant JSON_AGENT = 13174292974160097713;
    uint256 constant PARSE_AGENT = 12875401142070969085;

    function run() external {
        address platform = vm.envAddress("SOMNIA_PLATFORM");
        uint256 llm = vm.envOr("LLM_AGENT_ID", uint256(12847293847561029384));
        uint256 fundAmount = vm.envOr("LEARNER_FUND", uint256(1.5 ether));

        vm.startBroadcast();

        HajarThreatLearner learner = new HajarThreatLearner(platform, JSON_AGENT, PARSE_AGENT, llm);

        // Seed the taxonomy with real, scrape-able security sources — Hajar learns each category's
        // current threat level from the live web (Parse Website agent reads the page + extracts a
        // 0..100 score against the category-specific prompt).
        learner.setSource(
            "oracle-manipulation",
            HajarThreatLearner.SourceKind.ParseWebsite,
            "https://rekt.news",
            "",
            "Assess how active oracle/price manipulation exploits are right now based on this security feed",
            1,
            40
        );
        learner.setSource(
            "reentrancy",
            HajarThreatLearner.SourceKind.ParseWebsite,
            "https://rekt.news",
            "",
            "Assess how active reentrancy exploits are right now based on this security feed",
            1,
            40
        );
        learner.setSource(
            "flash-loan",
            HajarThreatLearner.SourceKind.ParseWebsite,
            "https://rekt.news",
            "",
            "Assess how active flash-loan attacks are right now based on this security feed",
            1,
            40
        );
        // access-control / governance start in the taxonomy (classify-only) until a feed is added.
        learner.addCategory("access-control");
        learner.addCategory("governance");

        if (fundAmount > 0) learner.fund{value: fundAmount}();

        vm.stopBroadcast();

        console2.log("HajarThreatLearner:", address(learner));
        console2.log("categories        :", learner.categoryCount());
    }
}
