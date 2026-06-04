// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IAgentRequester,
    ILLMInferenceAgent,
    Response,
    Request,
    ResponseStatus
} from "./interfaces/ISomniaAgents.sol";

interface IVaultTVL {
    function totalAssets() external view returns (uint256);
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
    uint256 public subcommitteeSize = 3;
    uint256 public costPerValidator = 0.07 ether;
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

    struct PendingContext {
        address vault;
        address user;
        uint256 amount;
        uint256 tvl;
        bool active;
    }

    mapping(uint256 requestId => PendingContext) public pending;

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
        if (whitelisted[vault][user]) return true;
        if (tvlBefore == 0) return true;

        uint256 bps = (amount * 10_000) / tvlBefore;
        _record(vault, user, amount);
        uint256 windowBps = _windowBps(vault, user, tvlBefore);

        // Tier 1: deterministic block (per-tx; does not latch — see onReactiveSignal/handleResponse).
        if (bps >= p.hardBps || windowBps >= p.rapidBps) {
            emit HardBlock(vault, user, bps);
            return false;
        }

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
        pending[requestId] = PendingContext({vault: vault, user: user, amount: amount, tvl: tvl, active: true});
        emit EscalatedToAI(requestId, vault, user, amount);
        return requestId;
    }

    /// @notice Proactive 24/7 autonomous monitoring for a protocol (admin/monitor-triggered).
    function requestRiskCheck(address vault) external returns (uint256) {
        Protocol storage p = protocols[vault];
        if (msg.sender != p.admin && msg.sender != p.monitor) revert NotProtocolAdmin();
        uint256 tvl = IVaultTVL(vault).totalAssets();
        uint256 windowBps = _windowBps(vault, address(this), tvl);
        return _escalateToAI(vault, address(this), 0, tvl, 0, windowBps);
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

        uint256 sum;
        uint256 n;
        for (uint256 i = 0; i < responses.length; i++) {
            if (responses[i].status == ResponseStatus.Success && responses[i].result.length == 32) {
                int256 v = abi.decode(responses[i].result, (int256));
                if (v < 0) v = 0;
                if (v > 100) v = 100;
                sum += uint256(v);
                n++;
            }
        }
        if (n == 0) {
            emit AIVerdict(requestId, ctx.vault, 0, 0, false);
            return;
        }

        uint256 riskScore = sum / n;
        bool tripped = riskScore >= protocols[ctx.vault].risk;
        if (tripped) {
            protocols[ctx.vault].paused = true;
            emit CircuitBreakerTripped(ctx.vault, "tier2-ai-judgment");
        }
        emit AIVerdict(requestId, ctx.vault, riskScore, n, tripped);
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
