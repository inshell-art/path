// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPathMinter} from "./interfaces/IPathMinter.sol";
import {IPulseAdapter} from "./interfaces/IPulseAdapter.sol";

/// @notice Adapter that allows PulseAuction to settle into PathMinter.
/// @dev Solidity port of `legacy/cairo/contracts/path_minter_adapter/src/path_minter_adapter.cairo`.
contract PathMinterAdapter is Ownable, IPulseAdapter {
    address public auction;
    address public minter;

    event AuctionSet(address indexed oldAuction, address indexed newAuction);
    event MinterSet(address indexed oldMinter, address indexed newMinter);

    constructor(address owner_, address auction_, address minter_) {
        require(owner_ != address(0), "ZERO_OWNER");
        _transferOwnership(owner_);
        auction = auction_;
        minter = minter_;
    }

    function setAuction(address auction_) external onlyOwner {
        require(auction_ != address(0), "ZERO_AUCTION");
        address old = auction;
        auction = auction_;
        emit AuctionSet(old, auction_);
    }

    function setMinter(address minter_) external onlyOwner {
        require(minter_ != address(0), "ZERO_MINTER");
        address old = minter;
        minter = minter_;
        emit MinterSet(old, minter_);
    }

    function getConfig() external view returns (address auction_, address minter_) {
        return (auction, minter);
    }

    function settle(address buyer, bytes calldata data) external override returns (uint256 tokenId) {
        require(msg.sender == auction, "ONLY_AUCTION");
        tokenId = IPathMinter(minter).mintPublic(buyer, data);
    }

    function target() external view override returns (address) {
        return auction;
    }
}
