// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IAgentRequester,
    ILLMInferenceAgent,
    IToolsChatAgent,
    IJsonApiAgent,
    IParseWebsiteAgent,
    Response,
    Request,
    ResponseStatus
} from "./interfaces/ISomniaAgents.sol";

interface IVaultTVL {
    function totalAssets() external view returns (uint256);
}

/// @notice Optional: a protocol may expose a synchronous spot price (e.g. its own AMM/pool quote)
///         so the guardian can atomically reject manipulated-price withdrawals in the SAME tx —
///         the only thing that can stop an atomic flash-loan attack (async AI is always too late).
interface IVaultSpotPrice {
    function spotPrice() external view returns (uint256);
}

/// @title HajarGuardian
/// @notice A multi-tenant, three-tier autonomous security layer for DeFi protocols on Somnia.
///         ANY protocol can `registerProtocol()` its vault and instantly get exploit protection
///         ("Hajar-as-a-Service"). Each protocol has its own admin, thresholds, and circuit
///         breaker.
///
///         Tier 1 (sync, same-block): deterministic hard rules (single-tx drain + velocity)
///                 revert blatant attacks instantly.
///         Tier 2 (async, AI): grey-zone activity is escalated to Somnia's LLM Inference agent;
///                 validators reach consensus on a 0–100 risk score that can latch the breaker.
///         Tier 3 (event-driven): a real Somnia Reactivity subscription latches the breaker
///                 in a separate, validator-triggered execution.
contract HajarGuardian {
    /*//////////////////////////////////////////////////////////////
                          PLATFORM-LEVEL CONFIG
    //////////////////////////////////////////////////////////////*/

    IAgentRequester public immutable platform;
    address public owner; // controls agent config + guardian STT (AI fees)
    address public pendingOwner; // two-step ownership transfer

    uint256 public llmAgentId; // 12847293847561029384
    uint256 public jsonAgentId = 13174292974160097713; // JSON API Request agent (price oracle)
    uint256 public parseAgentId = 12875401142070969085; // LLM Parse Website agent (threat intel)
    uint256 public subcommitteeSize = 3;
    uint256 public costPerValidator = 0.07 ether; // LLM inference cost / validator
    uint256 public toolsCostPerValidator = 0.07 ether; // LLM tools-chat cost / validator
    uint256 public jsonCostPerValidator = 0.03 ether; // JSON API cost / validator (verified live)
    uint256 public parseCostPerValidator = 0.1 ether; // Parse Website cost / validator
    uint256 public escalationCooldown = 60;
    uint256 public windowSeconds = 300;

    /*//////////////////////////////////////////////////////////////
                          PER-PROTOCOL STATE
    //////////////////////////////////////////////////////////////*/

    struct Protocol {
        bool registered;
        bool paused;
        address admin; // can configure / reset this protocol
        address monitor; // authorized reactive subscriber (Tier 3)
        uint256 hardBps; // single-tx drain limit
        uint256 rapidBps; // velocity (windowed) drain limit
        uint256 greyBps; // escalate-to-AI threshold
        uint256 risk; // AI score that latches the breaker
    }

    mapping(address vault => Protocol) public protocols;

    struct Window {
        uint64 start;
        uint192 cumAmount;
    }

    mapping(address vault => mapping(address user => Window)) public windows;
    mapping(address vault => mapping(address user => uint256)) public lastEscalation;
    mapping(address vault => mapping(address user => bool)) public whitelisted;

    enum Kind {
        Risk, // LLM inference risk score
        Price, // JSON API external price
        Threat, // Parse Website threat-intel score
        Tools // LLM tools-chat autonomous remediation (agent emits tool calls)
    }

    struct PendingContext {
        address vault;
        address user;
        uint256 amount;
        uint256 tvl;
        bool active;
        Kind kind;
    }

    mapping(uint256 requestId => PendingContext) public pending;

    /// @notice Self-updating threat-intelligence feed per protocol (learns about new exploits).
    ///         Supports TWO sources: a Parse-Website scrape (flexible, learns from any page) and
    ///         a JSON API endpoint (reliable, structured numeric score). Both yield a 0..100
    ///         threat score and share the same threshold/verdict path.
    struct ThreatFeed {
        bool enabled;
        string url; // Parse Website: a security feed (advisory / incident page)
        string prompt; // Parse Website: what to assess
        string jsonUrl; // JSON API: endpoint returning a numeric threat score
        string jsonSelector; // JSON API: json-path to the score
        uint8 threatThreshold; // 0..100 score that latches the breaker
        uint8 confidenceThreshold;
        uint8 numPages;
    }

    mapping(address vault => ThreatFeed) public threatFeeds;

    /// @notice Optional external price-sanity feed per protocol (oracle-manipulation detection).
    struct PriceFeed {
        bool enabled;
        string url; // public JSON endpoint
        string selector; // json-path, e.g. "ethereum.usd"
        uint8 decimals;
        uint256 referencePrice; // the protocol's own/expected price to compare against
        uint256 maxDivergenceBps; // alarm if |market - reference| exceeds this share
    }

    mapping(address vault => PriceFeed) public priceFeeds;

    /// @notice Tier-1d — vault-wide cumulative outflow budget (catches a SLOW, DISTRIBUTED drain).
    ///         The per-user velocity window can be defeated by sybils: many addresses each
    ///         withdrawing under the per-user limit. This aggregates outflow across ALL users in a
    ///         window and atomically blocks once the vault has bled `budgetBps` of its window-start
    ///         TVL — no matter how many addresses it was spread across.
    struct OutflowBudget {
        bool enabled;
        uint64 start; // window start (unix seconds)
        uint192 cumAmount; // cumulative outflow across all users this window
        uint256 budgetBps; // block once cumAmount >= budgetBps of baselineTvl
        uint256 baselineTvl; // TVL snapshot at window start
    }

    mapping(address vault => OutflowBudget) public outflowBudgets;

    /// @notice TVL-drop detector — catches drains that BYPASS the withdrawal hook entirely
    ///         (a bug in another function, a direct transfer, any path that doesn't call
    ///         `checkWithdrawal`). The guardian samples the vault's reported TVL and latches the
    ///         breaker when it falls by `dropBps` MORE than the guarded outflow we actually saw.
    ///         Runs in a separate execution (admin/monitor/reactive) so it CAN latch.
    struct TvlMonitor {
        bool enabled;
        uint256 dropBps; // latch if the UNEXPLAINED drop >= dropBps of baseline
        uint256 baselineTvl; // last known-healthy TVL
        uint256 accountedOutflow; // guarded outflow recorded since baseline (the "explained" part)
    }

    mapping(address vault => TvlMonitor) public tvlMonitors;

    /// @notice Tier-1c — synchronous spot-price deviation guard. If the protocol exposes a
    ///         `spotPrice()`, the guardian reads it INLINE on every withdrawal and atomically
    ///         reverts when it diverges from the trusted reference beyond `maxDeviationBps`. Unlike
    ///         the async Tier-2b oracle check, this fires in the same tx — the only tier that can
    ///         stop an atomic flash-loan price manipulation before the funds leave.
    struct SpotGuard {
        bool enabled;
        uint256 referencePrice; // trusted/expected price
        uint256 maxDeviationBps; // atomic block once |spot - referencePrice| / referencePrice >= this
    }

    mapping(address vault => SpotGuard) public spotGuards;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProtocolRegistered(address indexed vault, address indexed admin);
    event ThresholdsUpdated(address indexed vault, uint256 hardBps, uint256 rapidBps, uint256 greyBps, uint256 risk);
    event MonitorSet(address indexed vault, address indexed monitor);
    event WhitelistSet(address indexed vault, address indexed who, bool ok);
    event HardBlock(address indexed vault, address indexed user, uint256 bps);
    event EscalatedToAI(uint256 indexed requestId, address indexed vault, address user, uint256 amount);
    event EscalationSkipped(address indexed vault, address indexed user, string reason);
    event AIVerdict(uint256 indexed requestId, address indexed vault, uint256 riskScore, uint256 validatorCount, bool tripped);
    event PriceFeedSet(address indexed vault, string url, string selector);
    event PriceChecked(uint256 indexed requestId, address indexed vault);
    event PriceVerdict(uint256 indexed requestId, address indexed vault, uint256 marketPrice, uint256 referencePrice, uint256 divergenceBps, bool alarm);
    event ThreatFeedSet(address indexed vault, string url);
    event ThreatScanned(uint256 indexed requestId, address indexed vault);
    event ThreatVerdict(uint256 indexed requestId, address indexed vault, uint256 threatScore, bool alarm);
    event RemediationRequested(uint256 indexed requestId, address indexed vault);
    event RemediationVerdict(uint256 indexed requestId, address indexed vault, string finishReason, bool acted);
    event OutflowBudgetSet(address indexed vault, uint256 budgetBps);
    event OutflowBudgetBlocked(address indexed vault, address indexed user, uint256 cumBps);
    event TvlMonitorSet(address indexed vault, uint256 dropBps, uint256 baselineTvl);
    event TvlChecked(address indexed vault, uint256 currentTvl, uint256 unexplainedBps, bool latched);
    event SpotGuardSet(address indexed vault, uint256 referencePrice, uint256 maxDeviationBps);
    event SpotPriceBlocked(address indexed vault, address indexed user, uint256 spotPrice, uint256 divergenceBps);
    event CircuitBreakerTripped(address indexed vault, string reason);
    event CircuitBreakerReset(address indexed vault);
    event OwnershipTransferStarted(address indexed from, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);
    event Funded(address indexed from, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotOwner();
    error NotProtocolAdmin();
    error NotMonitor();
    error NotPlatform();
    error NotRegistered();
    error AlreadyRegistered();
    error UnknownRequest();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyProtocolAdmin(address vault) {
        if (msg.sender != protocols[vault].admin) revert NotProtocolAdmin();
        _;
    }

    constructor(address platform_, uint256 llmAgentId_) {
        platform = IAgentRequester(platform_);
        llmAgentId = llmAgentId_;
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                            REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Register a protocol's vault for protection. Caller becomes its admin.
    ///         Pass 0 for any threshold to use the sensible default.
    function registerProtocol(address vault, uint256 hardBps, uint256 rapidBps, uint256 greyBps, uint256 risk)
        external
    {
        Protocol storage p = protocols[vault];
        if (p.registered) revert AlreadyRegistered();
        p.registered = true;
        p.admin = msg.sender;
        p.hardBps = hardBps == 0 ? 4_000 : hardBps;
        p.rapidBps = rapidBps == 0 ? 6_000 : rapidBps;
        p.greyBps = greyBps == 0 ? 1_500 : greyBps;
        p.risk = risk == 0 ? 70 : risk;
        emit ProtocolRegistered(vault, msg.sender);
        emit ThresholdsUpdated(vault, p.hardBps, p.rapidBps, p.greyBps, p.risk);
    }

    function paused(address vault) external view returns (bool) {
        return protocols[vault].paused;
    }

    /*//////////////////////////////////////////////////////////////
                          TIER 1 — SYNCHRONOUS
    //////////////////////////////////////////////////////////////*/

    /// @notice Called synchronously by a registered vault on every withdrawal.
    function checkWithdrawal(address user, uint256 amount, uint256 tvlBefore)
        external
        returns (bool allowed)
    {
        address vault = msg.sender;
        Protocol storage p = protocols[vault];
        if (!p.registered) revert NotRegistered();
        if (whitelisted[vault][user]) {
            // A whitelisted withdrawal still passes THROUGH the guardian, so it's a *seen* outflow:
            // record it for the TVL-drop detector or its TVL drop would look unexplained (false latch).
            TvlMonitor storage wm = tvlMonitors[vault];
            if (wm.enabled) wm.accountedOutflow += amount;
            return true;
        }
        if (tvlBefore == 0) return true;

        uint256 bps = (amount * 10_000) / tvlBefore;
        _record(vault, user, amount);
        uint256 windowBps = _windowBps(vault, user, tvlBefore);

        // Tier 1: deterministic block (per-tx; does not latch — see onReactiveSignal/handleResponse).
        if (bps >= p.hardBps || windowBps >= p.rapidBps) {
            emit HardBlock(vault, user, bps);
            return false;
        }

        // Tier 1c: synchronous spot-price deviation guard (atomic — the ONLY tier that can stop an
        // in-tx flash-loan price manipulation; async AI is always one block too late).
        if (!_spotPriceOk(vault, user)) return false;

        // Tier 1d: vault-wide cumulative outflow budget (catches a slow drain sprayed over sybils).
        if (!_outflowBudgetOk(vault, user, amount, tvlBefore)) return false;

        // This withdrawal is allowed: record it as "explained" outflow for the TVL-drop detector,
        // so a later checkTvlDrop() doesn't mistake legitimate guarded outflow for a hidden drain.
        TvlMonitor storage tm = tvlMonitors[vault];
        if (tm.enabled) tm.accountedOutflow += amount;

        // Tier 2: grey zone -> escalate to AI (async, best-effort, never blocks).
        if (bps >= p.greyBps || windowBps >= p.greyBps) {
            _escalateToAI(vault, user, amount, tvlBefore, bps, windowBps);
        }
        return true;
    }

    function _record(address vault, address user, uint256 amount) internal {
        Window storage w = windows[vault][user];
        if (block.timestamp > uint256(w.start) + windowSeconds) {
            w.start = uint64(block.timestamp);
            w.cumAmount = 0;
        }
        w.cumAmount += uint192(amount);
    }

    function _windowBps(address vault, address user, uint256 tvl) internal view returns (uint256) {
        Window storage w = windows[vault][user];
        if (tvl == 0 || block.timestamp > uint256(w.start) + windowSeconds) return 0;
        return (uint256(w.cumAmount) * 10_000) / tvl;
    }

    /// @dev Tier-1c: returns false (→ atomic block) when an enabled spot-price guard sees the
    ///      vault's live `spotPrice()` diverge from the reference beyond the limit. Default-off, so
    ///      protocols without a `spotPrice()` are never called.
    function _spotPriceOk(address vault, address user) internal returns (bool) {
        SpotGuard storage sg = spotGuards[vault];
        if (!sg.enabled || sg.referencePrice == 0) return true;
        // Fail-OPEN if the price can't be read (vault missing spotPrice(), reverting view): an infra
        // problem must never brick withdrawals (SECURITY.md). Fail-CLOSED only on a real divergence.
        try IVaultSpotPrice(vault).spotPrice() returns (uint256 spot) {
            uint256 divBps = (_absDiff(spot, sg.referencePrice) * 10_000) / sg.referencePrice;
            if (divBps >= sg.maxDeviationBps) {
                emit SpotPriceBlocked(vault, user, spot, divBps);
                return false;
            }
        } catch {}
        return true;
    }

    /// @dev Tier-1d: accumulates outflow across ALL users in a rolling window and returns false
    ///      (→ atomic block) once the vault has bled `budgetBps` of its window-start TVL. The
    ///      accumulator only persists for withdrawals that actually go through — a blocked call
    ///      reverts in the vault, rolling the increment back (same no-latch invariant as Tier-1).
    function _outflowBudgetOk(address vault, address user, uint256 amount, uint256 tvlBefore)
        internal
        returns (bool)
    {
        OutflowBudget storage ob = outflowBudgets[vault];
        if (!ob.enabled) return true;
        if (block.timestamp > uint256(ob.start) + windowSeconds || ob.baselineTvl == 0) {
            ob.start = uint64(block.timestamp);
            ob.cumAmount = 0;
            ob.baselineTvl = tvlBefore;
        }
        ob.cumAmount += uint192(amount);
        uint256 cumBps = (uint256(ob.cumAmount) * 10_000) / ob.baselineTvl;
        if (cumBps >= ob.budgetBps) {
            emit OutflowBudgetBlocked(vault, user, cumBps);
            return false;
        }
        return true;
    }

    /// @notice Enable/update the vault-wide outflow budget. `budgetBps` of TVL may flow out (across
    ///         all users combined) per velocity window before withdrawals are blocked.
    function setOutflowBudget(address vault, uint256 budgetBps) external onlyProtocolAdmin(vault) {
        OutflowBudget storage ob = outflowBudgets[vault];
        ob.enabled = budgetBps != 0;
        ob.budgetBps = budgetBps;
        ob.start = 0; // force a fresh window on the next withdrawal
        ob.cumAmount = 0;
        ob.baselineTvl = 0;
        emit OutflowBudgetSet(vault, budgetBps);
    }

    /// @notice Enable/update the synchronous spot-price guard. The vault must expose `spotPrice()`.
    function setSpotGuard(address vault, uint256 referencePrice, uint256 maxDeviationBps)
        external
        onlyProtocolAdmin(vault)
    {
        spotGuards[vault] = SpotGuard(true, referencePrice, maxDeviationBps);
        emit SpotGuardSet(vault, referencePrice, maxDeviationBps);
    }

    function setSpotReference(address vault, uint256 referencePrice) external onlyProtocolAdmin(vault) {
        spotGuards[vault].referencePrice = referencePrice;
    }

    /*//////////////////////////////////////////////////////////////
              TVL-DROP DETECTOR — catches bypass-hook drains
    //////////////////////////////////////////////////////////////*/

    /// @notice Enable the TVL-drop detector and snapshot the current healthy TVL as the baseline.
    /// @param dropBps the UNEXPLAINED drop (beyond guarded outflow) that latches the breaker.
    function setTvlMonitor(address vault, uint256 dropBps) external onlyProtocolAdmin(vault) {
        TvlMonitor storage tm = tvlMonitors[vault];
        tm.enabled = true;
        tm.dropBps = dropBps;
        tm.baselineTvl = IVaultTVL(vault).totalAssets();
        tm.accountedOutflow = 0;
        emit TvlMonitorSet(vault, dropBps, tm.baselineTvl);
    }

    /// @notice Re-snapshot the baseline to the current TVL (call after legitimate large flows).
    function syncTvlBaseline(address vault) external onlyProtocolAdmin(vault) {
        TvlMonitor storage tm = tvlMonitors[vault];
        if (!tm.enabled) revert NotRegistered();
        tm.baselineTvl = IVaultTVL(vault).totalAssets();
        tm.accountedOutflow = 0;
    }

    /// @notice Sample the vault's TVL and latch the breaker if it dropped MORE than the guarded
    ///         outflow we recorded — i.e. value left through a path the guardian never saw. Call on
    ///         a schedule (cron) or wire it to the reactive monitor. Runs in a separate execution,
    ///         so it CAN latch (unlike synchronous Tier-1).
    function checkTvlDrop(address vault) external returns (bool latched) {
        Protocol storage p = protocols[vault];
        if (msg.sender != p.admin && msg.sender != p.monitor) revert NotProtocolAdmin();
        TvlMonitor storage tm = tvlMonitors[vault];
        if (!tm.enabled) revert NotRegistered();

        uint256 current = IVaultTVL(vault).totalAssets();
        uint256 unexplainedBps;
        if (current < tm.baselineTvl) {
            uint256 drop = tm.baselineTvl - current;
            uint256 explained = tm.accountedOutflow >= drop ? drop : tm.accountedOutflow;
            uint256 unexplained = drop - explained;
            unexplainedBps = (unexplained * 10_000) / tm.baselineTvl;
            if (unexplainedBps >= tm.dropBps) {
                p.paused = true;
                latched = true;
                emit CircuitBreakerTripped(vault, "tvl-drop-bypass");
            }
        }
        // Re-baseline either way so a single observed drop isn't re-detected on every subsequent call.
        tm.baselineTvl = current;
        tm.accountedOutflow = 0;
        emit TvlChecked(vault, current, unexplainedBps, latched);
    }

    /*//////////////////////////////////////////////////////////////
                          TIER 2 — ASYNC (AI)
    //////////////////////////////////////////////////////////////*/

    function _escalateToAI(
        address vault,
        address user,
        uint256 amount,
        uint256 tvl,
        uint256 bps,
        uint256 windowBps
    ) internal returns (uint256) {
        uint256 last = lastEscalation[vault][user];
        if (last != 0 && block.timestamp < last + escalationCooldown) {
            emit EscalationSkipped(vault, user, "cooldown");
            return 0;
        }
        uint256 needed = platform.getRequestDeposit() + (costPerValidator * subcommitteeSize);
        if (address(this).balance < needed) {
            emit EscalationSkipped(vault, user, "underfunded");
            return 0; // fail open
        }

        lastEscalation[vault][user] = block.timestamp;
        bytes memory payload = abi.encodeWithSelector(
            ILLMInferenceAgent.inferNumber.selector,
            _buildPrompt(user, amount, tvl, bps, windowBps),
            SYSTEM_PROMPT,
            int256(0),
            int256(100),
            false
        );
        uint256 requestId = platform.createRequest{value: needed}(
            llmAgentId, address(this), this.handleResponse.selector, payload
        );
        pending[requestId] =
            PendingContext({vault: vault, user: user, amount: amount, tvl: tvl, active: true, kind: Kind.Risk});
        emit EscalatedToAI(requestId, vault, user, amount);
        return requestId;
    }

    /*//////////////////////////////////////////////////////////////
            EXTERNAL PRICE ORACLE (JSON API agent) — Tier 2b
    //////////////////////////////////////////////////////////////*/

    /// @notice Configure a protocol's external price-sanity feed.
    function setPriceFeed(
        address vault,
        string calldata url,
        string calldata selector,
        uint8 decimals,
        uint256 referencePrice,
        uint256 maxDivergenceBps
    ) external onlyProtocolAdmin(vault) {
        priceFeeds[vault] =
            PriceFeed(true, url, selector, decimals, referencePrice, maxDivergenceBps);
        emit PriceFeedSet(vault, url, selector);
    }

    function setReferencePrice(address vault, uint256 referencePrice) external onlyProtocolAdmin(vault) {
        priceFeeds[vault].referencePrice = referencePrice;
    }

    /// @notice Fetch the real market price via Somnia's JSON API agent and compare it to the
    ///         protocol's reference price. A large divergence latches the breaker — catching
    ///         oracle manipulation / depeg that the velocity & LLM tiers can't see.
    function requestPriceCheck(address vault) external returns (uint256 requestId) {
        Protocol storage p = protocols[vault];
        if (msg.sender != p.admin && msg.sender != p.monitor) revert NotProtocolAdmin();
        PriceFeed memory f = priceFeeds[vault];
        if (!f.enabled) revert NotRegistered();

        uint256 needed = platform.getRequestDeposit() + (jsonCostPerValidator * subcommitteeSize);
        if (address(this).balance < needed) {
            emit EscalationSkipped(vault, address(this), "underfunded");
            return 0;
        }

        bytes memory payload =
            abi.encodeWithSelector(IJsonApiAgent.fetchUint.selector, f.url, f.selector, f.decimals);
        requestId = platform.createRequest{value: needed}(
            jsonAgentId, address(this), this.handleResponse.selector, payload
        );
        pending[requestId] =
            PendingContext({vault: vault, user: address(this), amount: 0, tvl: 0, active: true, kind: Kind.Price});
        emit PriceChecked(requestId, vault);
    }

    /*//////////////////////////////////////////////////////////////
        SELF-UPDATING THREAT INTELLIGENCE (Parse Website agent) — Tier 2c
    //////////////////////////////////////////////////////////////*/

    /// @notice Configure a protocol's threat-intel feed (a security/advisory page to learn from).
    function setThreatFeed(
        address vault,
        string calldata url,
        string calldata prompt,
        uint8 threatThreshold,
        uint8 confidenceThreshold,
        uint8 numPages
    ) external onlyProtocolAdmin(vault) {
        ThreatFeed storage f = threatFeeds[vault];
        f.enabled = true;
        f.url = url;
        f.prompt = prompt;
        f.threatThreshold = threatThreshold;
        f.confidenceThreshold = confidenceThreshold;
        f.numPages = numPages == 0 ? 1 : numPages;
        emit ThreatFeedSet(vault, url);
    }

    /// @notice Configure the JSON-API threat source (reliable, structured numeric score).
    function setThreatFeedJson(address vault, string calldata jsonUrl, string calldata jsonSelector)
        external
        onlyProtocolAdmin(vault)
    {
        ThreatFeed storage f = threatFeeds[vault];
        f.enabled = true;
        f.jsonUrl = jsonUrl;
        f.jsonSelector = jsonSelector;
        emit ThreatFeedSet(vault, jsonUrl);
    }

    /// @notice Scrape the protocol's security feed via the Parse Website agent and extract a
    ///         0..100 threat score. A high score latches the breaker. Call on a schedule (cron)
    ///         so the guardian continuously LEARNS about new exploits and stays up to date.
    function requestThreatScan(address vault) external returns (uint256 requestId) {
        Protocol storage p = protocols[vault];
        if (msg.sender != p.admin && msg.sender != p.monitor) revert NotProtocolAdmin();
        ThreatFeed memory t = threatFeeds[vault];
        if (!t.enabled) revert NotRegistered();

        uint256 needed = platform.getRequestDeposit() + (parseCostPerValidator * subcommitteeSize);
        if (address(this).balance < needed) {
            emit EscalationSkipped(vault, address(this), "underfunded");
            return 0;
        }

        bytes memory payload = abi.encodeWithSelector(
            IParseWebsiteAgent.ExtractANumber.selector,
            "threat_level",
            "Active-exploit threat level for this DeFi protocol or pattern, 0=none 100=under attack",
            uint256(0),
            uint256(100),
            t.prompt,
            t.url,
            true, // resolveUrl
            t.numPages,
            t.confidenceThreshold
        );
        requestId = platform.createRequest{value: needed}(
            parseAgentId, address(this), this.handleResponse.selector, payload
        );
        pending[requestId] =
            PendingContext({vault: vault, user: address(this), amount: 0, tvl: 0, active: true, kind: Kind.Threat});
        emit ThreatScanned(requestId, vault);
    }

    /// @notice Threat scan via the JSON API agent (reliable, structured). Point `jsonUrl` at a
    ///         threat-intel API that returns a 0..100 score at `jsonSelector`. Same verdict path.
    function requestThreatScanJson(address vault) external returns (uint256 requestId) {
        Protocol storage p = protocols[vault];
        if (msg.sender != p.admin && msg.sender != p.monitor) revert NotProtocolAdmin();
        ThreatFeed memory t = threatFeeds[vault];
        if (!t.enabled || bytes(t.jsonUrl).length == 0) revert NotRegistered();

        uint256 needed = platform.getRequestDeposit() + (jsonCostPerValidator * subcommitteeSize);
        if (address(this).balance < needed) {
            emit EscalationSkipped(vault, address(this), "underfunded");
            return 0;
        }

        bytes memory payload =
            abi.encodeWithSelector(IJsonApiAgent.fetchUint.selector, t.jsonUrl, t.jsonSelector, uint8(0));
        requestId = platform.createRequest{value: needed}(
            jsonAgentId, address(this), this.handleResponse.selector, payload
        );
        pending[requestId] =
            PendingContext({vault: vault, user: address(this), amount: 0, tvl: 0, active: true, kind: Kind.Threat});
        emit ThreatScanned(requestId, vault);
    }

    /// @notice Proactive 24/7 autonomous monitoring for a protocol (admin/monitor-triggered).
    function requestRiskCheck(address vault) external returns (uint256) {
        Protocol storage p = protocols[vault];
        if (msg.sender != p.admin && msg.sender != p.monitor) revert NotProtocolAdmin();
        uint256 tvl = IVaultTVL(vault).totalAssets();
        uint256 windowBps = _windowBps(vault, address(this), tvl);
        return _escalateToAI(vault, address(this), 0, tvl, 0, windowBps);
    }

    /*//////////////////////////////////////////////////////////////
        AUTONOMOUS REMEDIATION (LLM tools-chat) — Tier 2d (agent acts)
    //////////////////////////////////////////////////////////////*/

    /// @notice Ask the LLM agent — given a set of on-chain tools — to decide whether to ACT, not
    ///         just score. The agent is offered a single SAFE tool (pause). If it returns a tool
    ///         call (finishReason != "stop"), the callback latches this vault's breaker. We never
    ///         execute arbitrary agent-supplied calldata: the only consequence is a pause, which a
    ///         protocol admin can `resetBreaker`. This is the agent-first endgame for Somnia —
    ///         the AI takes autonomous on-chain action, verified by validator consensus.
    /// @dev    Uses the LLM Inference agent (`llmAgentId`) via `inferToolsChat`
    ///         (selector 0xd0683905). The exact tools-chat callback-tuple delivery format is still
    ///         being confirmed on the live platform; this handler decodes only the leading
    ///         `finishReason` string (safe) inside a try/catch.
    function requestAutonomousRemediation(address vault) external returns (uint256 requestId) {
        Protocol storage p = protocols[vault];
        if (msg.sender != p.admin && msg.sender != p.monitor) revert NotProtocolAdmin();

        uint256 needed = platform.getRequestDeposit() + (toolsCostPerValidator * subcommitteeSize);
        if (address(this).balance < needed) {
            emit EscalationSkipped(vault, address(this), "underfunded");
            return 0;
        }

        string[] memory roles = new string[](1);
        roles[0] = "user";
        string[] memory messages = new string[](1);
        messages[0] = _buildRemediationPrompt(vault);
        string[] memory mcp = new string[](0);
        IToolsChatAgent.OnchainTool[] memory tools = new IToolsChatAgent.OnchainTool[](1);
        tools[0] = IToolsChatAgent.OnchainTool({
            signature: "pause()",
            description: "Pause the protocol / latch the circuit breaker ONLY if you have strong "
                "evidence it is under an active drain or exploit. Otherwise return without calling it."
        });

        bytes memory payload = abi.encodeWithSelector(
            IToolsChatAgent.inferToolsChat.selector, roles, messages, mcp, tools, uint256(3), true
        );
        requestId = platform.createRequest{value: needed}(
            llmAgentId, address(this), this.handleResponse.selector, payload
        );
        pending[requestId] =
            PendingContext({vault: vault, user: address(this), amount: 0, tvl: 0, active: true, kind: Kind.Tools});
        emit RemediationRequested(requestId, vault);
    }

    function _buildRemediationPrompt(address vault) internal view returns (string memory) {
        uint256 tvl = IVaultTVL(vault).totalAssets();
        return string.concat(
            "You guard DeFi protocol ",
            _toHexString(vault),
            " (TVL ",
            _toString(tvl),
            " wei). If you judge it is under an active exploit, call pause(). If it looks safe, do nothing."
        );
    }

    /// @notice keccak256("pause()")[:4] — the one safe remediation tool the agent may invoke.
    bytes4 internal constant PAUSE_SELECTOR = 0x8456cb59;

    /// @dev Fully decode the `inferToolsChat` return tuple
    ///      `(string,string,string[],string[],uint256[],bytes[])` — confirmed against live
    ///      platform bytes — and report whether the agent emitted a `pause()` tool call.
    ///      External so it runs under `try`, isolating any decode failure from the callback.
    function decodeToolsRemediation(bytes calldata result)
        external
        pure
        returns (bool pauseRequested, string memory finishReason)
    {
        bytes[] memory calls;
        (finishReason,,,,, calls) =
            abi.decode(result, (string, string, string[], string[], uint256[], bytes[]));
        for (uint256 i = 0; i < calls.length; i++) {
            bytes memory c = calls[i];
            if (c.length >= 4) {
                bytes4 sel;
                assembly {
                    sel := mload(add(c, 0x20))
                }
                if (sel == PAUSE_SELECTOR) {
                    pauseRequested = true;
                    break;
                }
            }
        }
    }

    function handleResponse(
        uint256 requestId,
        Response[] calldata responses,
        ResponseStatus status,
        Request calldata /* details */
    ) external {
        if (msg.sender != address(platform)) revert NotPlatform();
        PendingContext memory ctx = pending[requestId];
        if (!ctx.active) revert UnknownRequest();
        delete pending[requestId];

        if (status != ResponseStatus.Success || responses.length == 0) {
            emit AIVerdict(requestId, ctx.vault, 0, responses.length, false);
            return;
        }

        if (ctx.kind == Kind.Tools) {
            // Tools-chat: fully decode the return tuple and act iff the agent emitted a `pause()`
            // tool call. Fail-closed — only the whitelisted pause selector latches; arbitrary
            // agent-supplied calldata is NEVER executed. Decode is isolated in try/catch.
            bool acted;
            string memory finishReason;
            for (uint256 i = 0; i < responses.length; i++) {
                if (responses[i].status == ResponseStatus.Success && responses[i].result.length >= 192) {
                    try this.decodeToolsRemediation(responses[i].result) returns (bool pauseReq, string memory fr) {
                        finishReason = fr;
                        if (pauseReq) acted = true;
                    } catch {}
                    if (acted) break;
                }
            }
            if (acted) {
                protocols[ctx.vault].paused = true;
                emit CircuitBreakerTripped(ctx.vault, "tier2d-ai-remediation");
            }
            emit RemediationVerdict(requestId, ctx.vault, finishReason, acted);
            return;
        }

        uint256 sum;
        uint256 n;
        for (uint256 i = 0; i < responses.length; i++) {
            if (responses[i].status == ResponseStatus.Success && responses[i].result.length == 32) {
                int256 v = abi.decode(responses[i].result, (int256));
                if (v < 0) v = 0; // never underflow; upper-clamp (risk 0..100) is applied below
                sum += uint256(v);
                n++;
            }
        }
        if (n == 0) {
            emit AIVerdict(requestId, ctx.vault, 0, 0, false);
            return;
        }

        uint256 value = sum / n;

        if (ctx.kind == Kind.Price) {
            // External price sanity: divergence from the protocol's reference price.
            PriceFeed memory f = priceFeeds[ctx.vault];
            uint256 ref = f.referencePrice;
            uint256 divBps = ref == 0 ? 0 : (_absDiff(value, ref) * 10_000) / ref;
            bool alarm = ref != 0 && divBps >= f.maxDivergenceBps;
            if (alarm) {
                protocols[ctx.vault].paused = true;
                emit CircuitBreakerTripped(ctx.vault, "tier2b-oracle-divergence");
            }
            emit PriceVerdict(requestId, ctx.vault, value, ref, divBps, alarm);
            return;
        }

        if (ctx.kind == Kind.Threat) {
            // Self-updating threat intel: a high scraped threat score latches the breaker.
            uint256 threat = value > 100 ? 100 : value;
            bool alarm = threat >= threatFeeds[ctx.vault].threatThreshold;
            if (alarm) {
                protocols[ctx.vault].paused = true;
                emit CircuitBreakerTripped(ctx.vault, "tier2c-threat-intel");
            }
            emit ThreatVerdict(requestId, ctx.vault, threat, alarm);
            return;
        }

        uint256 score = value > 100 ? 100 : value; // risk scores are clamped to 0..100
        bool tripped = score >= protocols[ctx.vault].risk;
        if (tripped) {
            protocols[ctx.vault].paused = true;
            emit CircuitBreakerTripped(ctx.vault, "tier2-ai-judgment");
        }
        emit AIVerdict(requestId, ctx.vault, score, n, tripped);
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    string internal constant SYSTEM_PROMPT =
        "You are an autonomous DeFi security guardian. Given a withdrawal's context, rate how "
        "likely it is a malicious exploit on a scale of 0 (clearly safe) to 100 (certain attack). "
        "Weigh the single-tx share of TVL AND the cumulative velocity share: a high velocity share "
        "signals a looping drain even when each tx is small. Reply with the integer only.";

    function _buildPrompt(address user, uint256 amount, uint256 tvl, uint256 bps, uint256 windowBps)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "Withdrawal: ",
            _toString(amount),
            " wei (",
            _toString(bps / 100),
            "% of TVL). Cumulative velocity this user this window: ",
            _toString(windowBps / 100),
            "% of TVL. TVL before (wei): ",
            _toString(tvl),
            ". User: ",
            _toHexString(user),
            "."
        );
    }

    /*//////////////////////////////////////////////////////////////
                       TIER 3 — REACTIVITY (event-driven)
    //////////////////////////////////////////////////////////////*/

    /// @notice Latch-on-detection, called by a protocol's authorized reactive subscriber in a
    ///         separate (validator-triggered) execution — so it CAN persistently latch.
    function onReactiveSignal(address vault, address user, uint256 amount, uint256 tvlBefore) external {
        Protocol storage p = protocols[vault];
        if (msg.sender != p.monitor) revert NotMonitor();
        if (tvlBefore == 0) return;

        uint256 bps = (amount * 10_000) / tvlBefore;
        uint256 windowBps = _windowBps(vault, user, tvlBefore);
        if (bps >= p.hardBps || windowBps >= p.rapidBps) {
            p.paused = true;
            emit CircuitBreakerTripped(vault, "tier3-reactivity");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        PER-PROTOCOL ADMIN
    //////////////////////////////////////////////////////////////*/

    function setMonitor(address vault, address monitor) external onlyProtocolAdmin(vault) {
        protocols[vault].monitor = monitor;
        emit MonitorSet(vault, monitor);
    }

    function setThresholds(address vault, uint256 hardBps, uint256 rapidBps, uint256 greyBps, uint256 risk)
        external
        onlyProtocolAdmin(vault)
    {
        Protocol storage p = protocols[vault];
        p.hardBps = hardBps;
        p.rapidBps = rapidBps;
        p.greyBps = greyBps;
        p.risk = risk;
        emit ThresholdsUpdated(vault, hardBps, rapidBps, greyBps, risk);
    }

    function setWhitelist(address vault, address who, bool ok) external onlyProtocolAdmin(vault) {
        whitelisted[vault][who] = ok;
        emit WhitelistSet(vault, who, ok);
    }

    function resetBreaker(address vault) external onlyProtocolAdmin(vault) {
        protocols[vault].paused = false;
        emit CircuitBreakerReset(vault);
    }

    function transferProtocolAdmin(address vault, address newAdmin) external onlyProtocolAdmin(vault) {
        if (newAdmin == address(0)) revert ZeroAddress();
        protocols[vault].admin = newAdmin;
    }

    /*//////////////////////////////////////////////////////////////
                        PLATFORM-LEVEL ADMIN
    //////////////////////////////////////////////////////////////*/

    function setLlmAgentId(uint256 id) external onlyOwner {
        llmAgentId = id;
    }

    function setSubcommittee(uint256 size, uint256 costPerValidator_) external onlyOwner {
        subcommitteeSize = size;
        costPerValidator = costPerValidator_;
    }

    function setEscalationCooldown(uint256 secondsCooldown) external onlyOwner {
        escalationCooldown = secondsCooldown;
    }

    function setWindow(uint256 secondsWindow) external onlyOwner {
        windowSeconds = secondsWindow;
    }

    /// @notice Two-step ownership transfer (safer for a security product than single-step).
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotOwner();
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function fund() external payable {
        emit Funded(msg.sender, msg.value);
    }

    function withdrawFunds(uint256 amount) external onlyOwner {
        (bool ok,) = owner.call{value: amount}("");
        require(ok, "withdraw failed");
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                              STRING UTILS
    //////////////////////////////////////////////////////////////*/

    function _toString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 j = v;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory b = new bytes(len);
        while (v != 0) {
            len--;
            b[len] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(b);
    }

    function _toHexString(address a) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes20 data = bytes20(a);
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}
