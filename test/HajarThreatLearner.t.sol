// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HajarThreatLearner} from "../src/HajarThreatLearner.sol";
import {MockAgentPlatform} from "./mocks/MockAgentPlatform.sol";
import {Response, Request, ResponseStatus} from "../src/interfaces/ISomniaAgents.sol";

contract HajarThreatLearnerTest is Test {
    HajarThreatLearner learner;
    MockAgentPlatform platform;
    address attacker = address(0xBAD);

    bytes32 constant ORACLE = keccak256(bytes("oracle-manipulation"));
    bytes32 constant REENTRANCY = keccak256(bytes("reentrancy"));

    function setUp() public {
        platform = new MockAgentPlatform();
        learner = new HajarThreatLearner(address(platform), 1, 2, 3); // json/parse/llm agent ids
        learner.fund{value: 5 ether}();
    }

    function _level(bytes32 cat) internal view returns (uint8 level) {
        (, level,,,) = learner.knowledge(cat);
    }

    function _observations(bytes32 cat) internal view returns (uint32 obs) {
        (,,, obs,) = learner.knowledge(cat);
    }

    /// JSON-feed learning: scrape a structured score → recorded into the knowledge base.
    function test_Learn_Json_RecordsThreatLevel() public {
        learner.setSource(
            "oracle-manipulation", HajarThreatLearner.SourceKind.Json,
            "https://api.x/threat?cat=oracle", "data.score", "", 0, 0
        );
        uint256 id = learner.learn(ORACLE);
        assertEq(_level(ORACLE), 0, "not learned until consensus");

        platform.fulfillNumber(id, 82, 3); // validators agree threat 82
        assertEq(_level(ORACLE), 82, "learned threat level from the JSON feed");
        assertEq(_observations(ORACLE), 1);
    }

    /// Parse-Website learning: scrape a security page → extract + record a threat level.
    function test_Learn_ParseWebsite_RecordsThreatLevel() public {
        learner.setSource(
            "reentrancy", HajarThreatLearner.SourceKind.ParseWebsite,
            "https://rekt.news", "", "rate reentrancy exploit activity", 1, 50
        );
        uint256 id = learner.learn(REENTRANCY);
        platform.fulfillNumber(id, 47, 3);
        assertEq(_level(REENTRANCY), 47);
    }

    /// inferString classification: the LLM tags an observed pattern onto the taxonomy.
    function test_Classify_TagsObservedCategory() public {
        learner.addCategory("oracle-manipulation");
        string[] memory allowed = new string[](2);
        allowed[0] = "oracle-manipulation";
        allowed[1] = "reentrancy";
        uint256 id = learner.classify("price spiked 40% in one tx then a large withdrawal", allowed);

        platform.fulfillString(id, "oracle-manipulation", 3);
        assertEq(_observations(ORACLE), 1, "classified pattern increments that category");
    }

    /// A label the taxonomy doesn't know is ignored gracefully (no crash, no bogus record).
    function test_Classify_UnknownLabel_Ignored() public {
        learner.addCategory("reentrancy");
        string[] memory allowed = new string[](1);
        allowed[0] = "reentrancy";
        uint256 id = learner.classify("weird activity", allowed);
        platform.fulfillString(id, "something-we-never-registered", 3);
        assertEq(_observations(REENTRANCY), 0);
    }

    /// highestThreat surfaces the most dangerous learned category for policy / the dashboard.
    function test_HighestThreat_TracksMax() public {
        learner.setSource("reentrancy", HajarThreatLearner.SourceKind.Json, "u", "s", "", 0, 0);
        learner.setSource("oracle-manipulation", HajarThreatLearner.SourceKind.Json, "u", "s", "", 0, 0);
        platform.fulfillNumber(learner.learn(REENTRANCY), 30, 3);
        platform.fulfillNumber(learner.learn(ORACLE), 75, 3);

        (string memory name, uint8 level) = learner.highestThreat();
        assertEq(level, 75);
        assertEq(name, "oracle-manipulation");
    }

    function test_Learn_Unconfigured_Reverts() public {
        vm.expectRevert(HajarThreatLearner.NotConfigured.selector);
        learner.learn(keccak256(bytes("never-set")));
    }

    function test_Learn_Underfunded_ReturnsZero() public {
        learner.setSource("reentrancy", HajarThreatLearner.SourceKind.Json, "u", "s", "", 0, 0);
        learner.withdrawFunds(address(learner).balance);
        assertEq(learner.learn(REENTRANCY), 0, "fails open when it can't pay validators");
    }

    function test_HandleResponse_OnlyPlatform() public {
        Response[] memory empty = new Response[](0);
        Request memory req;
        vm.prank(attacker);
        vm.expectRevert(HajarThreatLearner.NotPlatform.selector);
        learner.handleResponse(1, empty, ResponseStatus.Success, req);
    }

    function test_Classify_Gated() public {
        string[] memory allowed = new string[](1);
        allowed[0] = "reentrancy";
        vm.prank(attacker);
        vm.expectRevert(HajarThreatLearner.NotOwner.selector);
        learner.classify("x", allowed);
    }

    receive() external payable {}
}
