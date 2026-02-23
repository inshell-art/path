// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPathMinter {
    function getReservedCap() external view returns (uint64);

    function getReservedRemaining() external view returns (uint64);

    function mintPublic(address to, bytes calldata data) external returns (uint256);

    function mintSparker(address to, bytes calldata data) external returns (uint256);
}
