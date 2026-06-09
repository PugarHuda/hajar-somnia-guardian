// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IAgentRequester,
    ILLMInferenceAgent,
    IJsonApiAgent,
    IParseWebsiteAgent,
    Response,
    Request,
    ResponseStatus
} from "./interfaces/ISomniaAgents.sol";

/// @title HajarThreatLearner
/// @notice Hajar's self-updating threat-intelligence brain. It does NOT train a model on-chain
///         (infeasible); instead it runs a real, autonomous *knowledge loop* using all three
///         Somnia agents to keep learning about exploits from the outside world:
///
///           1. SCRAPE  — the Parse Website agent reads a live security feed (rekt.news, an
///                        advisory/incident page) and extracts a 0..100 threat level for a given
///                        exploit category.
///           2. FEED    — the JSON API agent pulls a structured threat/CVE score for a category.
///           3. CLASSIFY— the LLM Inference agent (`inferString`) maps a free-form description of
///                        observed activity onto the exploit taxonomy (reentrancy, oracle-manip,
///                        flash-loan, access-control, …) — so Hajar can name a pattern it sees.
///
///         Every result is written into an on-chain knowledge base keyed by exploit category, so
///         the system ACCUMULATES and stays current. The guardian and other agents can read it
///         (highestThreat / threatLevel) to inform policy. Driven on a schedule by the keeper, this
///         is genuine "learn from the web, keep updating" behavior — honest about being knowledge
///         accumulation + adaptation, not neural training.
contract HajarThreatLearner {
    IAgentRequester public immutable platform;
    address public owner;

    uint256 public jsonAgentId;
    uint256 public parseAgentId;
    uint256 public llmAgentId;
    uint256 public subcommitteeSize = 3;
    uint256 public jsonCost = 0.03 ether;
    uint256 public parseCost = 0.10 ether;
    uint256 public llmCost = 0.07 ether;

    enum SourceKind {
        Json, // JSON API agent: fetchUint(url, selector)
        ParseWebsite // Parse Website agent: ExtractANumber(... url ...)
    }

    struct Source {
        bool enabled;
        SourceKind kind;
        string url;
        string selector; // JSON: json-path to the score
        string prompt; // Parse: what to assess on the page
        uint8 numPages;
        uint8 confidence;
    }

    /// @notice What Hajar has learned about one exploit category.
    struct Knowledge {
        bool known;
        uint8 level; // latest learned threat level 0..100
        uint64 lastUpdated;
        uint32 observations; // times this category was scanned or classified
        string name;
    }

    bytes32[] public categoryIds;
    mapping(bytes32 categoryId => Source) public sources;
    mapping(bytes32 categoryId => Knowledge) public knowledge;

    enum ReqKind {
        Scan, // a numeric threat-level scan (Parse or JSON)
        Classify // an inferString taxonomy classification
    }

    struct Pending {
        bool active;
        bytes32 category; // set for Scan; 0 for Classify (resolved from the returned string)
        ReqKind kind;
    }

    mapping(uint256 requestId => Pending) public pending;

    event CategoryAdded(bytes32 indexed id, string name);
    event SourceSet(bytes32 indexed id, uint8 kind, string url);
    event LearnRequested(uint256 indexed requestId, bytes32 indexed category, uint8 kind);
    event Learned(bytes32 indexed category, uint8 level, uint32 observations, uint256 validatorCount);
    event ClassifyRequested(uint256 indexed requestId);
    event Classified(bytes32 indexed category, string name, uint32 observations);
    event ScanSkipped(bytes32 indexed category, string reason);
    event Funded(address indexed from, uint256 amount);

    error NotOwner();
    error NotPlatform();
    error NotConfigured();
    error UnknownRequest();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address platform_, uint256 jsonAgentId_, uint256 parseAgentId_, uint256 llmAgentId_) {
        platform = IAgentRequester(platform_);
        jsonAgentId = jsonAgentId_;
        parseAgentId = parseAgentId_;
        llmAgentId = llmAgentId_;
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                          KNOWLEDGE-BASE CONFIG
    //////////////////////////////////////////////////////////////*/

    /// @notice Add an exploit category to the taxonomy (e.g. "reentrancy", "oracle-manipulation").
    function addCategory(string calldata name) public onlyOwner returns (bytes32 id) {
        id = keccak256(bytes(name));
        if (!knowledge[id].known) {
            knowledge[id].known = true;
            knowledge[id].name = name;
            categoryIds.push(id);
            emit CategoryAdded(id, name);
        }
    }

    /// @notice Configure where Hajar learns a category's threat level from (a scrape or a feed).
    function setSource(
        string calldata name,
        SourceKind kind,
        string calldata url,
        string calldata selector,
        string calldata prompt,
        uint8 numPages,
        uint8 confidence
    ) external onlyOwner {
        bytes32 id = addCategory(name);
        sources[id] = Source({
            enabled: true,
            kind: kind,
            url: url,
            selector: selector,
            prompt: prompt,
            numPages: numPages == 0 ? 1 : numPages,
            confidence: confidence
        });
        emit SourceSet(id, uint8(kind), url);
    }

    /*//////////////////////////////////////////////////////////////
                              THE LEARNING LOOP
    //////////////////////////////////////////////////////////////*/

    /// @notice SCRAPE/FEED: ask the right Somnia agent for `category`'s current threat level and
    ///         record it. Call on a schedule (keeper) so the knowledge base stays current.
    function learn(bytes32 category) external returns (uint256 requestId) {
        Source memory s = sources[category];
        if (!s.enabled) revert NotConfigured();

        if (s.kind == SourceKind.Json) {
            uint256 needed = platform.getRequestDeposit() + (jsonCost * subcommitteeSize);
            if (address(this).balance < needed) {
                emit ScanSkipped(category, "underfunded");
                return 0;
            }
            bytes memory payload =
                abi.encodeWithSelector(IJsonApiAgent.fetchUint.selector, s.url, s.selector, uint8(0));
            requestId = platform.createRequest{value: needed}(
                jsonAgentId, address(this), this.handleResponse.selector, payload
            );
        } else {
            uint256 needed = platform.getRequestDeposit() + (parseCost * subcommitteeSize);
            if (address(this).balance < needed) {
                emit ScanSkipped(category, "underfunded");
                return 0;
            }
            bytes memory payload = abi.encodeWithSelector(
                IParseWebsiteAgent.ExtractANumber.selector,
                "threat_level",
                "Current active-exploit threat level for this category, 0=none 100=under attack",
                uint256(0),
                uint256(100),
                s.prompt,
                s.url,
                true, // resolveUrl
                s.numPages,
                s.confidence
            );
            requestId = platform.createRequest{value: needed}(
                parseAgentId, address(this), this.handleResponse.selector, payload
            );
        }
        pending[requestId] = Pending({active: true, category: category, kind: ReqKind.Scan});
        emit LearnRequested(requestId, category, uint8(s.kind));
    }

    /// @notice CLASSIFY: hand the LLM a free-form description and the taxonomy, and let it name the
    ///         most likely exploit class. The returned label increments that category's observation
    ///         count — Hajar literally tags what it sees. `allowedValues` MUST be category names.
    function classify(string calldata description, string[] calldata allowedValues)
        external
        onlyOwner
        returns (uint256 requestId)
    {
        uint256 needed = platform.getRequestDeposit() + (llmCost * subcommitteeSize);
        if (address(this).balance < needed) {
            emit ScanSkipped(bytes32(0), "underfunded");
            return 0;
        }
        bytes memory payload = abi.encodeWithSelector(
            ILLMInferenceAgent.inferString.selector,
            description,
            "You are a DeFi security classifier. Given a description of on-chain activity, reply with "
            "the single exploit category it most resembles, chosen ONLY from the allowed values.",
            false,
            allowedValues
        );
        requestId = platform.createRequest{value: needed}(
            llmAgentId, address(this), this.handleResponse.selector, payload
        );
        pending[requestId] = Pending({active: true, category: bytes32(0), kind: ReqKind.Classify});
        emit ClassifyRequested(requestId);
    }

    function handleResponse(
        uint256 requestId,
        Response[] calldata responses,
        ResponseStatus status,
        Request calldata /* details */
    ) external {
        if (msg.sender != address(platform)) revert NotPlatform();
        Pending memory ctx = pending[requestId];
        if (!ctx.active) revert UnknownRequest();
        delete pending[requestId];

        if (status != ResponseStatus.Success || responses.length == 0) {
            emit ScanSkipped(ctx.category, "no-consensus");
            return;
        }

        if (ctx.kind == ReqKind.Classify) {
            // Take the first successful string label; map it onto a known category.
            for (uint256 i = 0; i < responses.length; i++) {
                if (responses[i].status == ResponseStatus.Success && responses[i].result.length >= 64) {
                    string memory label = abi.decode(responses[i].result, (string));
                    bytes32 id = keccak256(bytes(label));
                    if (knowledge[id].known) {
                        Knowledge storage k = knowledge[id];
                        k.observations += 1;
                        k.lastUpdated = uint64(block.timestamp);
                        emit Classified(id, label, k.observations);
                    }
                    return;
                }
            }
            emit ScanSkipped(ctx.category, "unmatched-label");
            return;
        }

        // Scan: average the numeric threat levels across successful validators.
        uint256 sum;
        uint256 n;
        for (uint256 i = 0; i < responses.length; i++) {
            if (responses[i].status == ResponseStatus.Success && responses[i].result.length == 32) {
                int256 v = abi.decode(responses[i].result, (int256));
                if (v < 0) v = 0;
                sum += uint256(v);
                n++;
            }
        }
        if (n == 0) {
            emit ScanSkipped(ctx.category, "no-valid-result");
            return;
        }
        uint256 level = sum / n;
        if (level > 100) level = 100;

        Knowledge storage know = knowledge[ctx.category];
        know.level = uint8(level);
        know.lastUpdated = uint64(block.timestamp);
        know.observations += 1;
        emit Learned(ctx.category, uint8(level), know.observations, n);
    }

    /*//////////////////////////////////////////////////////////////
                              KNOWLEDGE READOUTS
    //////////////////////////////////////////////////////////////*/

    function categoryCount() external view returns (uint256) {
        return categoryIds.length;
    }

    /// @notice The most dangerous category Hajar currently knows about (for policy + the dashboard).
    function highestThreat() external view returns (string memory name, uint8 level) {
        for (uint256 i = 0; i < categoryIds.length; i++) {
            Knowledge storage k = knowledge[categoryIds[i]];
            if (k.level >= level) {
                level = k.level;
                name = k.name;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    function setAgents(uint256 json_, uint256 parse_, uint256 llm_) external onlyOwner {
        jsonAgentId = json_;
        parseAgentId = parse_;
        llmAgentId = llm_;
    }

    function setSubcommittee(uint256 size, uint256 jsonCost_, uint256 parseCost_, uint256 llmCost_)
        external
        onlyOwner
    {
        subcommitteeSize = size;
        jsonCost = jsonCost_;
        parseCost = parseCost_;
        llmCost = llmCost_;
    }

    function fund() external payable {
        emit Funded(msg.sender, msg.value);
    }

    function withdrawFunds(uint256 amount) external onlyOwner {
        (bool ok,) = owner.call{value: amount}("");
        require(ok, "withdraw failed");
    }

    receive() external payable {}
}
