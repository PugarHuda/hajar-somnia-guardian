// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    ISomniaAgents,
    IAgentCallback,
    ILLMInferenceAgent,
    Response,
    Request,
    ResponseStatus,
    ConsensusType
} from "../interfaces/ISomniaAgents.sol";

/// @title MockAgentPlatform
/// @notice Local stand-in for the Somnia Agents platform so the full async flow can be
///         tested without a live network. It records requests and lets the test harness
///         "fulfill" them with a chosen risk score across N simulated validators.
/// @dev    Mirrors the REAL platform's request/callback shape exactly, so swapping in the
///         live address requires no contract changes — only config.
contract MockAgentPlatform is ISomniaAgents {
    uint256 public nextId = 1;
    uint256 public reserve = 0.01 ether;

    struct Stored {
        address callbackAddress;
        bytes4 callbackSelector;
        uint256 agentId;
        address requester;
        uint256 deposit;
        uint256 subcommitteeSize;
        bool fulfilled;
    }

    mapping(uint256 => Stored) public requests;

    event RequestCreated(uint256 indexed requestId, uint256 agentId, address requester);

    function getRequestDeposit() external view returns (uint256) {
        return reserve;
    }

    function createRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata /* payload */
    ) external payable returns (uint256 requestId) {
        return _store(agentId, callbackAddress, callbackSelector, 3);
    }

    function createAdvancedRequest(
        uint256 agentId,
        address callbackAddress,
        bytes4 callbackSelector,
        bytes calldata, /* payload */
        uint256 subcommitteeSize,
        uint256, /* threshold */
        ConsensusType, /* consensusType */
        uint256 /* timeout */
    ) external payable returns (uint256 requestId) {
        return _store(agentId, callbackAddress, callbackSelector, subcommitteeSize);
    }

    function _store(uint256 agentId, address cb, bytes4 sel, uint256 size) internal returns (uint256 id) {
        id = nextId++;
        requests[id] = Stored({
            callbackAddress: cb,
            callbackSelector: sel,
            agentId: agentId,
            requester: msg.sender,
            deposit: msg.value,
            subcommitteeSize: size,
            fulfilled: false
        });
        emit RequestCreated(id, agentId, msg.sender);
    }

    /// @notice Test helper: simulate `validatorCount` validators all returning `riskScore`.
    function fulfillNumber(uint256 requestId, uint256 riskScore, uint256 validatorCount) external {
        Stored storage r = requests[requestId];
        require(!r.fulfilled, "already fulfilled");
        r.fulfilled = true;

        Response[] memory responses = new Response[](validatorCount);
        for (uint256 i = 0; i < validatorCount; i++) {
            responses[i] = Response({
                validator: address(uint160(0xA11DA700 + i)),
                result: abi.encode(riskScore),
                status: ResponseStatus.Success,
                receipt: requestId * 1000 + i,
                timestamp: block.timestamp,
                executionCost: 0.07 ether
            });
        }

        Request memory details = Request({
            agentId: r.agentId,
            requester: r.requester,
            callbackAddress: r.callbackAddress,
            callbackSelector: r.callbackSelector,
            deposit: r.deposit
        });

        IAgentCallback(r.callbackAddress).handleResponse(
            requestId, responses, ResponseStatus.Success, details
        );
    }
}
