// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPathNFT {
    function safeMint(address recipient, uint256 tokenId, bytes calldata data) external;

    function burn(uint256 tokenId) external;

    function setMovementConfig(bytes32 movement, address minter, uint32 quota) external;

    function getAuthorizedMinter(bytes32 movement) external view returns (address);

    function getStage(uint256 tokenId) external view returns (uint8);

    function getStageMinted(uint256 tokenId) external view returns (uint32);

    function getMovementQuota(bytes32 movement) external view returns (uint32);

    function consumeUnit(uint256 pathId, bytes32 movement, address claimer) external returns (uint32);
}
