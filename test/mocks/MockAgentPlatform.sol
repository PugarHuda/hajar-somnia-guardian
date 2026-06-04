// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    IAgentRequester,
    IAgentRequesterHandler,
    Response,
    Request,
    ResponseStatus,
    ConsensusType
} from "../../src/interfaces/ISomniaAgents.sol";

/// @title MockAgentPlatform
/// @notice Local stand-in for the Somnia Agents platform so the full async flow can be
///         tested without a live network. Mirrors the REAL request/callback shape (15-field
///         Request, int256-encoded inferNumber result), so swapping in the live address
///         requires no contract changes — only config.
contract MockAgentPlatform is IAgentRequester {
    uint256 public nextId = 1;
    uint256 public reserve = 0.01 ether;

    struct Stored {
        address callbackAddress;
        bytes4 callbackSelector;
        uint256 agentId;
        address requester;
        uint256 deposit;
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
        requestId = nextId++;
        requests[requestId] = Stored({
            callbackAddress: callbackAddress,
            callbackSelector: callbackSelector,
            agentId: agentId,
            requester: msg.sender,
            deposit: msg.value,
            fulfilled: false
        });
        emit RequestCreated(requestId, agentId, msg.sender);
    }

    /// @notice Test helper: simulate `validatorCount` validators all returning `riskScore`
    ///         (inferNumber returns int256), then invoke the requester's callback.
    function fulfillNumber(uint256 requestId, uint256 riskScore, uint256 validatorCount) external {
        Stored storage r = requests[requestId];
        require(!r.fulfilled, "already fulfilled");
        r.fulfilled = true;

        Response[] memory responses = new Response[](validatorCount);
        address[] memory committee = new address[](validatorCount);
        for (uint256 i = 0; i < validatorCount; i++) {
            address v = address(uint160(0xA11DA700 + i));
            committee[i] = v;
            responses[i] = Response({
                validator: v,
                result: abi.encode(int256(uint256(riskScore))),
                status: ResponseStatus.Success,
                receipt: requestId * 1000 + i,
                timestamp: block.timestamp,
                executionCost: 0.07 ether
            });
        }

        Request memory details;
        details.id = requestId;
        details.requester = r.requester;
        details.callbackAddress = r.callbackAddress;
        details.callbackSelector = r.callbackSelector;
        details.subcommittee = committee;
        details.responses = responses;
        details.responseCount = validatorCount;
        details.threshold = validatorCount;
        details.status = ResponseStatus.Success;
        details.consensusType = ConsensusType.Majority;

        IAgentRequesterHandler(r.callbackAddress).handleResponse(
            requestId, responses, ResponseStatus.Success, details
        );
    }

    /// @notice Flexible fulfill: per-validator score + status (test mixed/failed/negative).
    function fulfillCustom(uint256 requestId, int256[] calldata scores, uint8[] calldata statuses)
        external
    {
        Stored storage r = requests[requestId];
        require(!r.fulfilled, "already fulfilled");
        require(scores.length == statuses.length, "len");
        r.fulfilled = true;

        uint256 cnt = scores.length;
        Response[] memory responses = new Response[](cnt);
        for (uint256 i = 0; i < cnt; i++) {
            responses[i] = Response({
                validator: address(uint160(0xA11DA700 + i)),
                result: abi.encode(scores[i]),
                status: ResponseStatus(statuses[i]),
                receipt: requestId * 1000 + i,
                timestamp: block.timestamp,
                executionCost: 0.07 ether
            });
        }

        Request memory details;
        details.id = requestId;
        details.requester = r.requester;
        details.callbackAddress = r.callbackAddress;
        details.callbackSelector = r.callbackSelector;
        details.responses = responses;
        details.responseCount = cnt;
        details.status = ResponseStatus.Success;

        IAgentRequesterHandler(r.callbackAddress).handleResponse(
            requestId, responses, ResponseStatus.Success, details
        );
    }
}
