// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPathNFT {
    function safeMint(address recipient, uint256 tokenId, bytes calldata data) external;

    function safe_mint(address recipient, uint256 tokenId, bytes calldata data) external;

    function getReservedCap() external view returns (uint64);

    function getReservedRemaining() external view returns (uint64);

    function getReservedPending() external view returns (uint64);

    function isSparker(uint256 tokenId) external view returns (bool);

    function sparkClaimDuration() external view returns (uint64);

    function getSparkInvitation(address recipient) external view returns (uint64 expiresAt, string memory name);

    function sparkName(uint256 tokenId) external view returns (string memory);

    function allowSparker(address recipient, string calldata name) external returns (uint64);

    function revokeSparker(address recipient) external;

    function releaseExpiredSparker(address recipient) external;

    function mintSparker(bytes32 expectedNameHash, bytes calldata data) external returns (uint256);

    function freezePublicMinter(address expectedMinter) external;

    function setMovementConfig(bytes32 movement, address minter, uint32 quota) external;

    function freezeMovementConfig(bytes32 movement) external;

    function getAuthorizedMinter(bytes32 movement) external view returns (address);

    function isMovementFrozen(bytes32 movement) external view returns (bool);

    function getStage(uint256 tokenId) external view returns (uint8);

    function getStageMinted(uint256 tokenId) external view returns (uint32);

    function getMovementQuota(bytes32 movement) external view returns (uint32);

    function getConsumeNonce(address claimer) external view returns (uint256);

    function getPermissionEpoch(uint256 pathId) external view returns (uint256);

    function consumeUnit(
        uint256 pathId,
        bytes32 movement,
        address claimer,
        uint256 deadline,
        bytes calldata signature
    ) external returns (uint32);
}
