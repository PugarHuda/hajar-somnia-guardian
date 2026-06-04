// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SomniaEventHandler} from "@somnia-chain/reactivity-contracts/contracts/SomniaEventHandler.sol";
import {SomniaExtensions} from "@somnia-chain/reactivity-contracts/contracts/interfaces/SomniaExtensions.sol";

interface IHajarGuardianSignal {
    function onReactiveSignal(address vault, address user, uint256 amount, uint256 tvlBefore) external;
}

interface IVaultView {
    function totalAssets() external view returns (uint256);
}

/// @title HajarReactiveSubscriber
/// @notice REAL Tier-3: a genuine Somnia on-chain Reactivity subscription. On deploy it
///         registers a subscription against the protected vault's `Withdrawn` event with the
///         reactivity precompile (0x0100). When a withdrawal happens, **validators trigger
///         `onEvent` automatically** in a separate execution — no keeper, no off-chain bot —
///         and this contract forwards the signal to the guardian, which can latch the breaker.
///
/// @dev    This is the validator-triggered path (vs. the keeper-driven HajarReactiveMonitor
///         used for local tests). The subscription OWNER (this contract) must hold >= 32 STT
///         to cover callback gas; fund it on/after deploy. Set this contract as the guardian's
///         `reactiveMonitor`.
contract HajarReactiveSubscriber is SomniaEventHandler {
    /// keccak256("Withdrawn(address,uint256)")
    bytes32 public constant WITHDRAWN_TOPIC =
        0x7084f5476618d8e60b11ef0d7d3f06914655adb8793e28ff7f018d4c76d505d5;

    IHajarGuardianSignal public immutable guardian;
    address public immutable vault;
    uint256 public subscriptionId;
    address public owner;

    event Subscribed(uint256 subscriptionId, address vault);
    event ReactiveForwarded(address indexed user, uint256 amount, uint256 tvlBefore);

    error NotOwner();

    /// @param guardian_ the HajarGuardian to signal
    /// @param vault_    the protected vault whose Withdrawn events we watch
    /// @dev send >= 33 STT with deployment so the owner-balance requirement (32) is met.
    constructor(address guardian_, address vault_) payable {
        guardian = IHajarGuardianSignal(guardian_);
        vault = vault_;
        owner = msg.sender;

        SomniaExtensions.SubscriptionFilter memory filter = SomniaExtensions.SubscriptionFilter({
            eventTopics: [WITHDRAWN_TOPIC, bytes32(0), bytes32(0), bytes32(0)],
            origin: address(0),
            emitter: vault_
        });

        subscriptionId = SomniaExtensions.subscribe(
            address(this),
            filter,
            SomniaExtensions.defaultSubscriptionOptions()
        );
        emit Subscribed(subscriptionId, vault_);
    }

    /// @dev Invoked by the reactivity precompile when a matching Withdrawn event fires.
    ///      topics[0] = WITHDRAWN_TOPIC, topics[1] = indexed user, data = abi.encode(amount).
    function _onEvent(address, bytes32[] calldata eventTopics, bytes calldata data) internal override {
        address user = address(uint160(uint256(eventTopics[1])));
        uint256 amount = abi.decode(data, (uint256));
        // TVL after the withdrawal; reconstruct the pre-withdrawal TVL for the guardian's rule.
        uint256 tvlAfter = IVaultView(vault).totalAssets();
        uint256 tvlBefore = tvlAfter + amount;
        guardian.onReactiveSignal(vault, user, amount, tvlBefore);
        emit ReactiveForwarded(user, amount, tvlBefore);
    }

    /// @notice Cancel the subscription (owner only).
    function unsubscribe() external {
        if (msg.sender != owner) revert NotOwner();
        SomniaExtensions.unsubscribe(subscriptionId);
    }

    /// @notice Top up the subscription owner balance (covers callback gas).
    function fund() external payable {}

    /// @notice Recover STT (e.g. after unsubscribe). Owner only.
    function withdraw(uint256 amount) external {
        if (msg.sender != owner) revert NotOwner();
        (bool ok,) = owner.call{value: amount}("");
        require(ok, "withdraw failed");
    }

    receive() external payable {}
}
