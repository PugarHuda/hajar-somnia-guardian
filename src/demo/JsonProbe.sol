// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentRequester, Response, Request, ResponseStatus} from "../interfaces/ISomniaAgents.sol";

interface IJsonApiAgent {
    function fetchUint(string calldata url, string calldata selector, uint8 decimals)
        external
        returns (uint256);
}

/// @notice Standalone empirical probe to VERIFY the live Somnia JSON API Request agent and its
///         fetchUint signature before wiring it into the guardian. Not part of the product.
contract JsonProbe {
    IAgentRequester public immutable platform;
    uint256 public constant JSON_AGENT_ID = 13174292974160097713;
    uint256 public constant COST = 0.03 ether;
    uint256 public constant SUB = 3;

    uint256 public lastPrice;
    uint8 public lastStatus;
    uint256 public lastValidators;

    constructor(address platform_) payable {
        platform = IAgentRequester(platform_);
    }

    function probe(string calldata url, string calldata selector, uint8 decimals)
        external
        returns (uint256 requestId)
    {
        bytes memory payload = abi.encodeWithSelector(IJsonApiAgent.fetchUint.selector, url, selector, decimals);
        uint256 needed = platform.getRequestDeposit() + COST * SUB;
        requestId = platform.createRequest{value: needed}(
            JSON_AGENT_ID, address(this), this.handleResponse.selector, payload
        );
    }

    function handleResponse(uint256, Response[] calldata responses, ResponseStatus status, Request calldata) external {
        require(msg.sender == address(platform), "only platform");
        lastStatus = uint8(status);
        uint256 sum;
        uint256 n;
        for (uint256 i = 0; i < responses.length; i++) {
            if (responses[i].status == ResponseStatus.Success && responses[i].result.length == 32) {
                sum += abi.decode(responses[i].result, (uint256));
                n++;
            }
        }
        lastValidators = n;
        if (n > 0) lastPrice = sum / n;
    }

    function fund() external payable {}
    receive() external payable {}
}
