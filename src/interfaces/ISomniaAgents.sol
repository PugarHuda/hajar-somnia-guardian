// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                    SOMNIA AGENTS INTERFACE
//////////////////////////////////////////////////////////////*/

/// @dev Status of an individual validator response.
///      Numbers are fixed per Somnia docs: None=0, Pending=1, Success=2, Failed=3, TimedOut=4.
enum ResponseStatus {
    None,
    Pending,
    Success,
    Failed,
    TimedOut
}

/// @dev Consensus strategy for advanced requests.
enum ConsensusType {
    Majority,
    Unanimous,
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

/// @dev Metadata about the original request, echoed back in the callback.
/// @notice TODO(verify): reconcile this struct with the official Somnia ISomniaAgents
///         ABI before deploying to testnet/mainnet. Decoding the callback depends on it.
struct Request {
    uint256 agentId;
    address requester;
    address callbackAddress;
    bytes4 callbackSelector;
    uint256 deposit;
}

/// @notice The Somnia Agents platform contract.
/// @dev Platform addresses (from docs):
///        Mainnet (chainId 5031):  0x5E5205CF39E766118C01636bED000A54D93163E6
///        Testnet (chainId 50312): 0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776
interface ISomniaAgents {
    /// @notice Create a request to an agent with default subcommittee settings.
    /// @param agentId          Agent id from https://agents.somnia.network
    /// @param callbackAddress  Contract that receives the response (usually address(this)).
    /// @param callbackSelector Selector of the callback fn (e.g. this.handleResponse.selector).
    /// @param payload          abi.encodeWithSelector(IAgentFn.method.selector, args...)
    /// @return requestId       Tracking id; the response arrives later via the callback.
    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload
    ) external payable returns (uint256 requestId);

    /// @notice Create a request with explicit consensus controls.
    function createAdvancedRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata payload,
        uint256 subcommitteeSize,
        uint256 threshold,
        ConsensusType consensusType,
        uint256 timeout
    ) external payable returns (uint256 requestId);

    /// @notice Reserve portion of the deposit (covers gas refunds/operations).
    /// @dev Total to send = getRequestDeposit() + (pricePerAgent * subcommitteeSize).
    function getRequestDeposit() external view returns (uint256);
}

/// @notice The callback your contract MUST implement to receive agent results.
interface IAgentCallback {
    function handleResponse(
        uint256 requestId,
        Response[] calldata responses,
        ResponseStatus status,
        Request calldata details
    ) external;
}

/*//////////////////////////////////////////////////////////////
                    BASE AGENT PAYLOAD INTERFACES
    Used only for abi.encodeWithSelector(...) to build payloads.
    These are never *called* directly on-chain.
//////////////////////////////////////////////////////////////*/

/// @notice LLM Inference Agent (Qwen3-30B, deterministic). Cost ~0.07 STT / validator.
/// @dev TODO(verify): confirm exact selectors/signatures against the live agent ABI.
interface ILLMInferenceAgent {
    /// @notice Single integer output, clamped to [min, max]. Ideal for risk scores.
    function inferNumber(string calldata prompt, uint256 min, uint256 max) external returns (uint256);

    /// @notice Single-turn classification constrained to one of `allowed` values.
    function inferString(string calldata prompt, string[] calldata allowed) external returns (string memory);
}

/// @notice JSON API Request Agent. Cost ~0.03 STT / validator.
interface IJsonApiAgent {
    /// @notice Fetch a public JSON endpoint and extract a uint via a json-path selector.
    function fetchUint(string calldata url, string calldata selector, uint8 decimals) external returns (uint256);
}
