// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract StubPathMinterBadReturn {
    uint256 public nextTokenId;

    constructor(uint256 firstId) {
        nextTokenId = firstId;
    }

    function nextId() external view returns (uint256) {
        return nextTokenId;
    }

    function mintPublic(address, bytes calldata) external returns (uint256 tokenId) {
        tokenId = nextTokenId + 1;
        nextTokenId += 1;
    }
}
