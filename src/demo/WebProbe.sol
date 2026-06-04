// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentRequester, IParseWebsiteAgent, Response, Request, ResponseStatus} from "../interfaces/ISomniaAgents.sol";

/// @notice Empirical probe to VERIFY the live Somnia LLM Parse Website agent (ExtractANumber)
///         and its selector before relying on it. Not part of the product.
contract WebProbe {
    IAgentRequester public immutable platform;
    uint256 public constant PARSE_AGENT_ID = 12875401142070969085;
    uint256 public constant COST = 0.1 ether;
    uint256 public constant SUB = 3;

    uint256 public lastNumber;
    uint8 public lastStatus;
    uint256 public lastValidators;

    constructor(address platform_) payable {
        platform = IAgentRequester(platform_);
    }

    function probe(string calldata url, string calldata prompt, uint256 maxVal)
        external
        returns (uint256 requestId)
    {
        bytes memory payload = abi.encodeWithSelector(
            IParseWebsiteAgent.ExtractANumber.selector,
            "value",
            "Extract the requested number from the page",
            uint256(0),
            maxVal,
            prompt,
            url,
            true,
            uint8(1),
            uint8(40)
        );
        uint256 needed = platform.getRequestDeposit() + COST * SUB;
        requestId = platform.createRequest{value: needed}(
            PARSE_AGENT_ID, address(this), this.handleResponse.selector, payload
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
        if (n > 0) lastNumber = sum / n;
    }

    function fund() external payable {}
    receive() external payable {}
}
