// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPulseAdapter {
    function settle(address buyer, uint64 epochIndex, bytes calldata data) external returns (uint256 tokenId);

    function target() external view returns (address);
}
