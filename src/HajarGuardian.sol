// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    ISomniaAgents,
    ILLMInferenceAgent,
    Response,
    Request,
    ResponseStatus
} from "./interfaces/ISomniaAgents.sol";

/// @title HajarGuardian
/// @notice A two-tier autonomous security layer for DeFi protocols on Somnia.
///
///         Tier 1 (hot path, deterministic, same-block): hard rules run
///         synchronously inside the protected protocol's withdraw() call. A blatant
///         drain is blocked instantly — no AI, no waiting.
///
///         Tier 2 (warm path, AI, async): ambiguous "grey zone" activity is escalated
///         to Somnia's LLM Inference agent. Validators run the model deterministically
///         and reach consensus; the result returns via handleResponse(). If the agent
///         judges the activity malicious, Hajar trips the circuit breaker so that
///         subsequent withdrawals are paused.
///
/// @dev    Why this split? Agent calls on Somnia are asynchronous (request now,
///         callback later). You therefore CANNOT block an in-flight tx on an AI verdict.
///         Tier 1 is what actually prevents the worst case in real time; Tier 2 adds
///         nuanced, consensus-verified judgment for everything Tier 1 can't cleanly call.
contract HajarGuardian {
    /*//////////////////////////////////////////////////////////////
                                CONFIG
    //////////////////////////////////////////////////////////////*/

    ISomniaAgents public immutable platform;
    address public owner;
    address public vault; // the protected protocol allowed to call checkWithdrawal

    uint256 public llmAgentId; // from https://agents.somnia.network
    uint256 public subcommitteeSize = 3;
    uint256 public costPerValidator = 0.07 ether; // STT per validator for LLM inference

    // --- tunable policy knobs (basis points of TVL; 10_000 = 100%) ---
    uint256 public hardWithdrawalBps = 4_000; // >=40% of TVL in ONE tx => instant block
    uint256 public rapidDrainBps = 6_000; // >=60% by one user within window => instant block
    uint256 public greyZoneBps = 1_500; // >=15% => allow but escalate to AI
    uint256 public riskThreshold = 70; // AI score (0..100) at/above which we pause
    uint256 public windowSeconds = 300; // velocity window for rapid-drain detection

    bool public paused;
    mapping(address => bool) public whitelisted; // trusted addresses skip checks
    address public reactiveMonitor; // authorized Somnia Reactivity handler (Tier 3)

    // rolling-window velocity tracking per user
    struct Window {
        uint64 start;
        uint192 cumAmount;
    }

    mapping(address => Window) public windows;

    // anti-griefing: rate-limit how often a user can trigger a (paid) AI escalation
    uint256 public escalationCooldown = 60; // seconds between escalations per user
    mapping(address => uint256) public lastEscalation;

    // request bookkeeping for the async callback
    struct PendingContext {
        address user;
        uint256 amount;
        uint256 tvl;
        bool active;
    }

    mapping(uint256 => PendingContext) public pending;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event HardBlock(address indexed user, uint256 amount, uint256 bps);
    event EscalatedToAI(uint256 indexed requestId, address indexed user, uint256 amount);
    event EscalationSkipped(address indexed user, string reason);
    event AIVerdict(uint256 indexed requestId, uint256 riskScore, uint256 validatorCount, bool tripped);
    event CircuitBreakerTripped(string reason);
    event CircuitBreakerReset();
    event OwnershipTransferred(address indexed from, address indexed to);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotOwner();
    error NotVault();
    error NotPlatform();
    error NotMonitor();
    error UnknownRequest();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address platform_, uint256 llmAgentId_) {
        platform = ISomniaAgents(platform_);
        llmAgentId = llmAgentId_;
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                          TIER 1 — SYNCHRONOUS
    //////////////////////////////////////////////////////////////*/

    /// @notice Called synchronously by the protected vault on every withdrawal.
    /// @return allowed True if the withdrawal may proceed this block.
    function checkWithdrawal(address user, uint256 amount, uint256 tvlBefore)
        external
        returns (bool allowed)
    {
        if (msg.sender != vault) revert NotVault();
        if (whitelisted[user]) return true;
        if (tvlBefore == 0) return true;

        uint256 bps = (amount * 10_000) / tvlBefore;
        // velocity: record this withdrawal, then read cumulative share within the window.
        // Only successful (non-reverted) withdrawals persist here, so blocked attempts
        // never inflate the counter. Recording happens ONLY on this synchronous path so a
        // later reactivity event for the same withdrawal cannot double-count it.
        _record(user, amount);
        uint256 windowBps = _windowBps(user, tvlBefore);

        // --- Tier 1: deterministic hard rule (instant, same-block) ---
        // We block the offending withdrawal by returning false (the vault reverts).
        // We deliberately do NOT latch `paused` here: reverting the trigger tx would
        // roll the latch back anyway, and the deterministic rule re-blocks every retry,
        // so per-tx blocking already protects the funds. The global breaker is latched
        // only via Tier 2 (async AI callback) or Tier 3 (reactivity monitor) — paths
        // that run in a separate execution and therefore survive.
        if (_isHardViolation(user, amount, tvlBefore, bps, windowBps)) {
            emit HardBlock(user, amount, bps);
            return false;
        }

        // --- Tier 2: grey zone => allow now, ask AI to judge (async) ---
        if (bps >= greyZoneBps || windowBps >= greyZoneBps) {
            _escalateToAI(user, amount, tvlBefore);
        }

        return true;
    }

    /// @notice THE policy brain. Returns true if this withdrawal is a blatant attack that
    ///         must be stopped immediately, no AI needed.
    /// @dev    This is the single most important design decision in Hajar — tune it to
    ///         the protocol you protect. Too strict => false pauses (protocol unusable);
    ///         too loose => an exploit drains funds before Tier 2's AI can react.
    ///
    ///         Lending/vault-aware defaults, two deterministic signals:
    ///           1. Single-tx drain: one withdrawal taking >= hardWithdrawalBps of TVL.
    ///           2. Rapid drain (velocity): one user pulling >= rapidDrainBps of TVL
    ///              within `windowSeconds` — the classic loop/re-entry exploit shape.
    /// @param bps        this withdrawal's share of TVL, in basis points.
    /// @param windowBps  this user's cumulative share within the rolling window.
    function _isHardViolation(
        address, /* user */
        uint256, /* amount */
        uint256, /* tvlBefore */
        uint256 bps,
        uint256 windowBps
    ) internal view returns (bool) {
        if (bps >= hardWithdrawalBps) return true; // signal 1: single-tx drain
        if (windowBps >= rapidDrainBps) return true; // signal 2: rapid/looped drain
        return false;
    }

    /// @dev Records a withdrawal into the user's rolling velocity window (resets if expired).
    function _record(address user, uint256 amount) internal {
        Window storage w = windows[user];
        if (block.timestamp > uint256(w.start) + windowSeconds) {
            w.start = uint64(block.timestamp);
            w.cumAmount = 0;
        }
        // amounts are bounded by vault TVL; uint192 cannot realistically overflow here.
        w.cumAmount += uint192(amount);
    }

    /// @dev Read-only: the user's cumulative withdrawal share of TVL within the window.
    ///      Returns 0 if the window has expired (mirrors the reset in `_record`).
    function _windowBps(address user, uint256 tvl) internal view returns (uint256) {
        Window storage w = windows[user];
        if (tvl == 0 || block.timestamp > uint256(w.start) + windowSeconds) return 0;
        return (uint256(w.cumAmount) * 10_000) / tvl;
    }

    /*//////////////////////////////////////////////////////////////
                          TIER 2 — ASYNC (AI)
    //////////////////////////////////////////////////////////////*/

    /// @dev Best-effort escalation. MUST NOT revert: it runs inside the user's withdrawal,
    ///      so any revert here would block a legitimate withdrawal (availability DoS). If we
    ///      can't escalate (underfunded or on cooldown) we skip and let Tier-3/owner cover it.
    function _escalateToAI(address user, uint256 amount, uint256 tvl) internal {
        // anti-griefing: one paid escalation per user per cooldown window.
        // (lastEscalation == 0 means "never escalated" — always allow the first one.)
        if (lastEscalation[user] != 0 && block.timestamp < lastEscalation[user] + escalationCooldown) {
            emit EscalationSkipped(user, "cooldown");
            return;
        }

        uint256 reserve = platform.getRequestDeposit();
        uint256 reward = costPerValidator * subcommitteeSize;
        uint256 needed = reserve + reward;
        if (address(this).balance < needed) {
            emit EscalationSkipped(user, "underfunded");
            return; // fail open — never block the withdrawal
        }

        lastEscalation[user] = block.timestamp;
        string memory prompt = _buildPrompt(user, amount, tvl);
        bytes memory payload = abi.encodeWithSelector(
            ILLMInferenceAgent.inferNumber.selector,
            prompt,
            uint256(0),
            uint256(100)
        );

        uint256 requestId = platform.createRequest{value: needed}(
            llmAgentId,
            address(this),
            this.handleResponse.selector,
            payload
        );

        pending[requestId] = PendingContext({user: user, amount: amount, tvl: tvl, active: true});
        emit EscalatedToAI(requestId, user, amount);
    }

    /// @notice Async callback invoked by the Somnia platform with all validator responses.
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
            emit AIVerdict(requestId, 0, responses.length, false);
            return;
        }

        // Aggregate validator scores (consensus is already enforced by the platform;
        // we average successful responses for a robust single number).
        uint256 sum;
        uint256 n;
        for (uint256 i = 0; i < responses.length; i++) {
            // require exactly 32 bytes so a malformed validator result can't revert the
            // whole callback (which would otherwise strand the request).
            if (responses[i].status == ResponseStatus.Success && responses[i].result.length == 32) {
                sum += abi.decode(responses[i].result, (uint256));
                n++;
            }
        }
        if (n == 0) {
            emit AIVerdict(requestId, 0, 0, false);
            return;
        }

        uint256 riskScore = sum / n;
        bool tripped = riskScore >= riskThreshold;
        if (tripped) {
            paused = true;
            emit CircuitBreakerTripped("tier2-ai-judgment");
        }
        emit AIVerdict(requestId, riskScore, n, tripped);
    }

    /// @dev Builds the natural-language context handed to the LLM agent.
    ///      Keep it deterministic and information-dense — the better the context,
    ///      the more meaningful the risk score.
    function _buildPrompt(address user, uint256 amount, uint256 tvl) internal pure returns (string memory) {
        return string.concat(
            "You are a DeFi security guardian. Rate how likely this withdrawal is a malicious ",
            "exploit on a scale of 0 (safe) to 100 (certain attack). Reply with the number only. ",
            "Withdrawal amount (wei): ",
            _toString(amount),
            ". Total value locked before (wei): ",
            _toString(tvl),
            ". User address: ",
            _toHexString(user),
            "."
        );
    }

    /*//////////////////////////////////////////////////////////////
                       TIER 3 — REACTIVITY (event-driven)
    //////////////////////////////////////////////////////////////*/

    /// @notice Latch-on-detection path, meant to be driven by a Somnia Reactivity
    ///         subscription that fires on the vault's `Withdrawn` event. Because this runs
    ///         in a SEPARATE (validator-triggered) execution — not inside the withdrawal tx —
    ///         it CAN persistently latch the breaker, which Tier 1 cannot.
    /// @dev    In production you register a subscription whose handler calls this. Here it is
    ///         guarded to `reactiveMonitor` so it can also be driven by an off-chain keeper
    ///         during the demo. Same deterministic rule as Tier 1, but it pauses globally.
    function onReactiveSignal(address user, uint256 amount, uint256 tvlBefore) external {
        if (msg.sender != reactiveMonitor) revert NotMonitor();
        if (tvlBefore == 0) return;

        // Read-only velocity: the withdrawal was already recorded by the synchronous
        // checkWithdrawal path, so we must NOT record again here (avoids double-counting).
        uint256 bps = (amount * 10_000) / tvlBefore;
        uint256 windowBps = _windowBps(user, tvlBefore);

        if (_isHardViolation(user, amount, tvlBefore, bps, windowBps)) {
            paused = true;
            emit CircuitBreakerTripped("tier3-reactivity");
        }
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    function setVault(address v) external onlyOwner {
        vault = v;
    }

    function setReactiveMonitor(address m) external onlyOwner {
        reactiveMonitor = m;
    }

    function setThresholds(uint256 hardBps, uint256 rapidBps, uint256 greyBps, uint256 risk)
        external
        onlyOwner
    {
        hardWithdrawalBps = hardBps;
        rapidDrainBps = rapidBps;
        greyZoneBps = greyBps;
        riskThreshold = risk;
    }

    function setWindow(uint256 secondsWindow) external onlyOwner {
        windowSeconds = secondsWindow;
    }

    function setEscalationCooldown(uint256 secondsCooldown) external onlyOwner {
        escalationCooldown = secondsCooldown;
    }

    /// @notice Transfer ownership. Roadmap: replace with a multisig/timelock so a single key
    ///         can't unilaterally pause the protocol or move guardian funds.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setLlmAgentId(uint256 id) external onlyOwner {
        llmAgentId = id;
    }

    function setSubcommittee(uint256 size, uint256 costPerValidator_) external onlyOwner {
        subcommitteeSize = size;
        costPerValidator = costPerValidator_;
    }

    function setWhitelist(address who, bool ok) external onlyOwner {
        whitelisted[who] = ok;
    }

    function resetBreaker() external onlyOwner {
        paused = false;
        emit CircuitBreakerReset();
    }

    /// @notice Fund the guardian with STT so it can pay for AI escalations.
    function fund() external payable {}

    function withdrawFunds(uint256 amount) external onlyOwner {
        (bool ok,) = owner.call{value: amount}("");
        require(ok, "withdraw failed");
    }

    /// @dev Rebates from the platform are pushed back automatically — must accept them.
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
