// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IPathNFT} from "../interfaces/IPathNFT.sol";

contract MockMovementToken is ERC721 {
    IPathNFT public immutable pathNft;
    bytes32 public immutable movement;
    uint256 public nextTokenId;

    event MovementTokenMinted(uint256 indexed tokenId, uint256 indexed pathId, address indexed owner, uint32 serial);

    constructor(address pathNft_, bytes32 movement_) ERC721("Mock Movement", "MOVE") {
        pathNft = IPathNFT(pathNft_);
        movement = movement_;
    }

    function mintWithPath(uint256 pathId, uint256 deadline, bytes calldata signature)
        external
        returns (uint256 tokenId)
    {
        uint32 serial = pathNft.consumeUnit(pathId, movement, msg.sender, deadline, signature);
        tokenId = nextTokenId++;
        _safeMint(msg.sender, tokenId);
        emit MovementTokenMinted(tokenId, pathId, msg.sender, serial);
    }
}
