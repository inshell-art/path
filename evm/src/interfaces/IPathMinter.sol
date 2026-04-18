// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPathMinter {
    function nextId() external view returns (uint256);

    function freezeSalesCaller(address expectedCaller) external;

    function mintPublic(address to, bytes calldata data) external returns (uint256);
}
