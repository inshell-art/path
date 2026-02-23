// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract StubPathMinter {
    address public lastTo;
    bytes public lastData;
    uint256 public nextTokenId;
    bool public shouldRevert;

    constructor(uint256 firstId) {
        nextTokenId = firstId;
    }

    function setNextTokenId(uint256 tokenId) external {
        nextTokenId = tokenId;
    }

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }

    function mintPublic(address to, bytes calldata data) external returns (uint256 tokenId) {
        require(!shouldRevert, "MINT_REVERT");
        lastTo = to;
        lastData = data;

        tokenId = nextTokenId;
        nextTokenId = tokenId + 1;
    }
}
