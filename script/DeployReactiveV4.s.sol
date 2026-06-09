// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {HajarReactiveSubscriber} from "../src/HajarReactiveSubscriber.sol";

/// @notice Deploys the real Tier-3 Reactivity subscriber bound to guardian v4 + vault v4 and funds
///         it past the 32-STT subscription-owner requirement. After this, call
///         guardian.setMonitor(vault, subscriber) so the forwarded signal is authorized.
///
/// Env: SUB_FUND - wei to send with deploy (default 33 STT).
contract DeployReactiveV4 is Script {
    address constant GUARDIAN_V4 = 0xf47D21Afd23639870c5185462B2F418eF59d6F67;
    address constant VAULT_V4 = 0xe349707D8BAfA05BC7dd2A2dE16638CBE4673043;

    function run() external {
        uint256 fundAmount = vm.envOr("SUB_FUND", uint256(33 ether));

        vm.startBroadcast();
        HajarReactiveSubscriber sub =
            new HajarReactiveSubscriber{value: fundAmount}(GUARDIAN_V4, VAULT_V4);
        vm.stopBroadcast();

        console2.log("HajarReactiveSubscriber:", address(sub));
        console2.log("subscriptionId        :", sub.subscriptionId());
    }
}
