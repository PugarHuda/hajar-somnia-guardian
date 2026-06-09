// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title HajarAgentRegistry
/// @notice A minimal ERC-8004 "Trustless Agents" Identity Registry on Somnia. An agent registers
///         with a URI pointing at its Agent Registration File (the agent-card JSON), receives a
///         portable ERC-721 `agentId`, and can attach on-chain metadata. This lets other agents
///         discover and verify Hajar (and any agent) across organizational boundaries with no
///         pre-existing trust — the core of Somnia's agent-native thesis.
/// @dev    ERC-8004-aligned (https://eips.ethereum.org/EIPS/eip-8004). Implements the ERC-721
///         identity surface + register/metadata. `setAgentWallet` is simplified to owner-only
///         (no EIP-712 signature) to keep the hackathon implementation lean; everything else
///         follows the spec's function names and events.
contract HajarAgentRegistry {
    struct MetadataEntry {
        string key;
        bytes value;
    }

    // --- ERC-721 identity state ---
    string public constant name = "Hajar Trustless Agents";
    string public constant symbol = "HAJAR8004";

    uint256 public totalAgents;
    mapping(uint256 agentId => address) public ownerOf;
    mapping(address owner => uint256) public balanceOf;
    mapping(uint256 agentId => string) internal _agentURI;
    mapping(uint256 agentId => mapping(bytes32 keyHash => bytes)) internal _metadata;
    mapping(uint256 agentId => address) internal _agentWallet;
    mapping(uint256 agentId => address) public getApproved;

    // --- ERC-8004 events ---
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event MetadataSet(uint256 indexed agentId, string indexed indexedKey, string key, bytes value);
    event AgentWalletSet(uint256 indexed agentId, address wallet);
    // --- ERC-721 events ---
    event Transfer(address indexed from, address indexed to, uint256 indexed agentId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed agentId);

    error NotAgentOwner();
    error UnknownAgent();
    error ZeroAddress();

    modifier onlyAgentOwner(uint256 agentId) {
        if (msg.sender != ownerOf[agentId]) revert NotAgentOwner();
        _;
    }

    /// @notice Register a new agent with its Agent Registration File URI + initial metadata.
    function register(string calldata agentURI, MetadataEntry[] calldata metadata)
        external
        returns (uint256 agentId)
    {
        agentId = _register(agentURI);
        for (uint256 i = 0; i < metadata.length; i++) {
            _setMetadata(agentId, metadata[i].key, metadata[i].value);
        }
    }

    function register(string calldata agentURI) external returns (uint256 agentId) {
        return _register(agentURI);
    }

    function register() external returns (uint256 agentId) {
        return _register("");
    }

    /// @dev Internal mint — keeps msg.sender as the original caller (an external `this.register`
    ///      self-call would wrongly set the registry contract as the owner).
    function _register(string memory agentURI) internal returns (uint256 agentId) {
        agentId = ++totalAgents; // agentIds start at 1
        ownerOf[agentId] = msg.sender;
        unchecked {
            balanceOf[msg.sender] += 1;
        }
        _agentURI[agentId] = agentURI;
        emit Transfer(address(0), msg.sender, agentId);
        emit Registered(agentId, agentURI, msg.sender);
    }

    /// @notice Point the agent at a new Agent Registration File (e.g. after a redeploy).
    function setAgentURI(uint256 agentId, string calldata newURI) external onlyAgentOwner(agentId) {
        _agentURI[agentId] = newURI;
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    /// @notice ERC-721 metadata: the tokenURI IS the agent card URI.
    function tokenURI(uint256 agentId) external view returns (string memory) {
        if (ownerOf[agentId] == address(0)) revert UnknownAgent();
        return _agentURI[agentId];
    }

    function setMetadata(uint256 agentId, string calldata key, bytes calldata value)
        external
        onlyAgentOwner(agentId)
    {
        _setMetadata(agentId, key, value);
    }

    function _setMetadata(uint256 agentId, string memory key, bytes memory value) internal {
        _metadata[agentId][keccak256(bytes(key))] = value;
        emit MetadataSet(agentId, key, key, value);
    }

    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory) {
        return _metadata[agentId][keccak256(bytes(key))];
    }

    /// @notice Operational wallet the agent uses to act on-chain (simplified owner-only setter).
    function setAgentWallet(uint256 agentId, address wallet) external onlyAgentOwner(agentId) {
        if (wallet == address(0)) revert ZeroAddress();
        _agentWallet[agentId] = wallet;
        emit AgentWalletSet(agentId, wallet);
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        address w = _agentWallet[agentId];
        return w == address(0) ? ownerOf[agentId] : w;
    }

    function unsetAgentWallet(uint256 agentId) external onlyAgentOwner(agentId) {
        delete _agentWallet[agentId];
        emit AgentWalletSet(agentId, address(0));
    }

    // --- minimal ERC-721 transfer surface (identities are portable per the spec) ---
    function approve(address to, uint256 agentId) external onlyAgentOwner(agentId) {
        getApproved[agentId] = to;
        emit Approval(msg.sender, to, agentId);
    }

    function transferFrom(address from, address to, uint256 agentId) public {
        if (from != ownerOf[agentId]) revert NotAgentOwner();
        if (msg.sender != from && msg.sender != getApproved[agentId]) revert NotAgentOwner();
        if (to == address(0)) revert ZeroAddress();
        unchecked {
            balanceOf[from] -= 1;
            balanceOf[to] += 1;
        }
        ownerOf[agentId] = to;
        delete getApproved[agentId];
        emit Transfer(from, to, agentId);
    }

    /// @notice ERC-165: advertises ERC-721 + ERC-721 Metadata so existing NFT tooling can index agents.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC-165
            || interfaceId == 0x80ac58cd // ERC-721
            || interfaceId == 0x5b5e139f; // ERC-721 Metadata
    }
}
