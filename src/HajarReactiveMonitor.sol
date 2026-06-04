// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IHajarGuardian {
    function onReactiveSignal(address vault, address user, uint256 amount, uint256 tvlBefore) external;
}

/// @title HajarReactiveMonitor
/// @notice Keeper-driven Tier-3 forwarder, used for LOCAL tests where the Somnia reactivity
///         precompile is unavailable. In production use HajarReactiveSubscriber (a real
///         on-chain subscription). Set this contract as the protocol's `monitor`.
contract HajarReactiveMonitor {
    IHajarGuardian public immutable guardian;
    address public immutable vault;
    address public owner;
    address public subscription;

    event ReactiveForwarded(address indexed user, uint256 amount, uint256 tvlBefore);

    error NotAuthorized();

    constructor(address guardian_, address vault_) {
        guardian = IHajarGuardian(guardian_);
        vault = vault_;
        owner = msg.sender;
        subscription = msg.sender;
    }

    function setSubscription(address s) external {
        if (msg.sender != owner) revert NotAuthorized();
        subscription = s;
    }

    function onWithdrawn(address user, uint256 amount, uint256 tvlBefore) external {
        if (msg.sender != subscription) revert NotAuthorized();
        guardian.onReactiveSignal(vault, user, amount, tvlBefore);
        emit ReactiveForwarded(user, amount, tvlBefore);
    }
}
