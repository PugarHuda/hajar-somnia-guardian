// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                    SOMNIA AGENTS INTERFACE
   Reconciled against the LIVE platform ABI (agents.somnia.network).
//////////////////////////////////////////////////////////////*/

/// @dev Status of a request / individual validator response.
///      None=0, Pending=1, Success=2, Failed=3, TimedOut=4.
enum ResponseStatus {
    None,
    Pending,
    Success,
    Failed,
    TimedOut
}

/// @dev Consensus strategy. NOTE: the live platform exposes exactly { Majority, Threshold }.
enum ConsensusType {
    Majority,
    Threshold
}

/// @dev One validator's response to an agent request.
struct Response {
    address validator;
    bytes result;
    ResponseStatus status;
    uint256 receipt;
    uint256 timestamp;
    uint256 executionCost;
}

/// @dev Full request metadata echoed back in the callback. MUST match the live ABI exactly
///      or the callback fails to decode.
struct Request {
    uint256 id;
    address requester;
    address callbackAddress;
    bytes4 callbackSelector;
    address[] subcommittee;
    Response[] responses;
    uint256 responseCount;
    uint256 failureCount;
    uint256 threshold;
    uint256 createdAt;
    uint256 deadline;
    ResponseStatus status;
    ConsensusType consensusType;
    uint256 remainingBudget;
    uint256 perAgentBudget;
}

/// @notice The Somnia Agents platform contract.
/// @dev Platform addresses:
///        Mainnet (chainId 5031):  0x5E5205CF39E766118C01636bED000A54D93163E6
///        Testnet (chainId 50312): 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776
///      AgentRegistry (browse): 0xaD3101C37F091593fEe7cb471e92b5E9A1205194
interface IAgentRequester {
    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload
    ) external payable returns (uint256 requestId);

    /// @notice Reserve portion of the deposit. Total to send =
    ///         getRequestDeposit() + (perAgentExecutionCost * subcommitteeSize).
    function getRequestDeposit() external view returns (uint256);
}

/// @notice The callback your contract MUST implement to receive agent results.
interface IAgentRequesterHandler {
    function handleResponse(
        uint256 requestId,
        Response[] calldata responses,
        ResponseStatus status,
        Request calldata details
    ) external;
}

/*//////////////////////////////////////////////////////////////
        BASE AGENT PAYLOAD INTERFACES (live signatures)
   Used only for abi.encodeWithSelector(...) to build payloads.
//////////////////////////////////////////////////////////////*/

/// @notice LLM Inference Agent (Qwen3-30B, deterministic). agentId 12847293847561029384.
///         ~0.07 STT / validator.
interface ILLMInferenceAgent {
    /// @notice Single signed-integer output, clamped to [minValue, maxValue]. Ideal for risk scores.
    function inferNumber(
        string calldata prompt,
        string calldata system,
        int256 minValue,
        int256 maxValue,
        bool chainOfThought
    ) external returns (int256 response);

    /// @notice Single-turn classification constrained to one of `allowedValues`.
    function inferString(
        string calldata prompt,
        string calldata system,
        bool chainOfThought,
        string[] calldata allowedValues
    ) external returns (string memory response);
}

/// @notice LLM Inference Agent — tools-chat method (autonomous on-chain remediation).
/// @dev    Same agentId as the LLM Inference agent (12847293847561029384). The agent is given a
///         set of on-chain tools and decides whether to call them. Canonical signature
///         `inferToolsChat(string[],string[],string[],(string,string)[],uint256,bool)` →
///         selector 0xd0683905 (confirmed by the Somnia team). The LLM returns a finishReason
///         ("stop" | "tool_calls" | ...), the assistant text, the updated conversation, and
///         `pendingToolCalls` (ABI-encoded calldata per tool the agent chose to invoke).
interface IToolsChatAgent {
    struct OnchainTool {
        string signature; // e.g. "pause()"
        string description; // natural-language hint for the LLM
    }

    function inferToolsChat(
        string[] calldata roles,
        string[] calldata messages,
        string[] calldata mcpServerUrls,
        OnchainTool[] calldata onchainTools,
        uint256 maxIterations,
        bool chainOfThought
    )
        external
        returns (
            string memory finishReason,
            string memory response,
            string[] memory updatedRoles,
            string[] memory updatedMessages,
            uint256[] memory pendingToolCallIds,
            bytes[] memory pendingToolCalls
        );
}

/// @notice JSON API Request Agent. agentId 13174292974160097713. ~0.03 STT / validator.
interface IJsonApiAgent {
    function fetchUint(string calldata url, string calldata selector, uint8 decimals)
        external
        returns (uint256);
}

/// @notice LLM Parse Website Agent. agentId 12875401142070969085. ~0.10 STT / validator.
/// @dev Selector is case-sensitive: "ExtractANumber".
interface IParseWebsiteAgent {
    function ExtractANumber(
        string calldata key,
        string calldata description,
        uint256 min,
        uint256 max,
        string calldata prompt,
        string calldata url,
        bool resolveUrl,
        uint8 numPages,
        uint8 confidenceThreshold
    ) external returns (uint256 output);
}
