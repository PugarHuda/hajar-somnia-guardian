// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ProtectedVault
/// @notice A minimal deposit/withdraw vault that delegates withdrawal safety
///         decisions to a Hajar guardian. Stands in for any real DeFi protocol
///         (lending market, yield vault, AMM treasury) you want to protect.
/// @dev    The vault itself stays dumb: it only knows "is the guardian letting
///         this withdrawal through, and is the protocol paused right now?".
interface IGuardian {
    /// @return allowed Whether this specific withdrawal may proceed this block.
    function checkWithdrawal(address user, uint256 amount, uint256 tvlBefore)
        external
        returns (bool allowed);

    /// @param vault the protocol whose breaker state to read (multi-tenant guardian).
    function paused(address vault) external view returns (bool);
}

contract ProtectedVault {
    IGuardian public guardian;
    address public owner;

    mapping(address => uint256) public balanceOf;
    uint256 public totalAssets; // == address(this).balance, tracked for the guardian

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event GuardianSet(address indexed guardian);
    event WithdrawalBlocked(address indexed user, uint256 amount, string reason);

    error NotOwner();
    error ProtocolPaused();
    error BlockedByGuardian();
    error InsufficientBalance();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setGuardian(address g) external onlyOwner {
        guardian = IGuardian(g);
        emit GuardianSet(g);
    }

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        totalAssets += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw `amount`. The guardian gets the final say (Tier-1 hard rules
    ///         run synchronously here; Tier-2 AI escalation happens async inside it).
    function withdraw(uint256 amount) external {
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        // Hard global pause (set by guardian's circuit breaker).
        if (address(guardian) != address(0) && guardian.paused(address(this))) {
            emit WithdrawalBlocked(msg.sender, amount, "paused");
            revert ProtocolPaused();
        }

        // Per-withdrawal synchronous check (Tier-1 deterministic rules).
        if (address(guardian) != address(0)) {
            bool ok = guardian.checkWithdrawal(msg.sender, amount, totalAssets);
            if (!ok) {
                emit WithdrawalBlocked(msg.sender, amount, "guardian-rule");
                revert BlockedByGuardian();
            }
        }

        balanceOf[msg.sender] -= amount;
        totalAssets -= amount;
        emit Withdrawn(msg.sender, amount);

        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "transfer failed");
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
        totalAssets += msg.value;
    }
}
