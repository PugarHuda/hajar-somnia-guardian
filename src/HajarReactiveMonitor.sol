// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IHajarGuardian {
    function onReactiveSignal(address user, uint256 amount, uint256 tvlBefore) external;
}

/// @title HajarReactiveMonitor
/// @notice Tier-3 latch-on-detection. This contract is the target of a **Somnia Reactivity
///         subscription** registered against the protected vault's `Withdrawn` event.
///
///         Flow on Somnia:
///           1. Register a subscription: "on ProtectedVault.Withdrawn(user, amount) => call
///              HajarReactiveMonitor.onWithdrawn(...)".
///           2. Validators trigger this handler automatically, in a SEPARATE execution from
///              the withdrawal tx — so it can persistently latch the guardian's breaker
///              (something the synchronous Tier-1 path cannot do).
///
/// @dev    Set this contract as the guardian's `reactiveMonitor`. During local/demo runs
///         without a live subscription, an authorized keeper can call `onWithdrawn` directly.
contract HajarReactiveMonitor {
    IHajarGuardian public immutable guardian;
    address public owner;
    address public subscription; // the Somnia subscription executor (or demo keeper)

    event ReactiveForwarded(address indexed user, uint256 amount, uint256 tvlBefore);

    error NotAuthorized();

    constructor(address guardian_) {
        guardian = IHajarGuardian(guardian_);
        owner = msg.sender;
        subscription = msg.sender; // until wired to the real subscription executor
    }

    function setSubscription(address s) external {
        if (msg.sender != owner) revert NotAuthorized();
        subscription = s;
    }

    /// @notice Handler invoked by the Somnia Reactivity subscription on each Withdrawn event.
    function onWithdrawn(address user, uint256 amount, uint256 tvlBefore) external {
        if (msg.sender != subscription) revert NotAuthorized();
        guardian.onReactiveSignal(user, amount, tvlBefore);
        emit ReactiveForwarded(user, amount, tvlBefore);
    }
}
