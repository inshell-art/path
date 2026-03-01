// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPathMinter} from "./interfaces/IPathMinter.sol";
import {IPulseAdapter} from "./interfaces/IPulseAdapter.sol";
import {IPulseAuction} from "./interfaces/IPulseAuction.sol";

/// @notice Adapter that allows PulseAuction to settle into PathMinter.
/// @dev Solidity port of `legacy/cairo/contracts/path_minter_adapter/src/path_minter_adapter.cairo`.
contract PathMinterAdapter is Ownable, IPulseAdapter {
    error NotAuction();
    error EpochMismatch(uint256 observed, uint256 forwarded);
    error EpochBeforeBase(uint256 epoch, uint256 epochBase);
    error MintIdMismatch(uint256 epoch, uint256 expected, uint256 observed);
    error WiringFrozen();

    address public auction;
    address public minter;
    uint256 public immutable tokenBase;
    uint256 public immutable epochBase;
    bool public wiringFrozen;

    event AuctionSet(address indexed oldAuction, address indexed newAuction);
    event MinterSet(address indexed oldMinter, address indexed newMinter);
    event WiringFrozenSet();
    event EpochMinted(uint256 indexed epoch, uint256 indexed tokenId, address indexed to);

    constructor(address owner_, address auction_, address minter_, uint256 tokenBase_, uint256 epochBase_) {
        require(owner_ != address(0), "ZERO_OWNER");
        _transferOwnership(owner_);
        auction = auction_;
        minter = minter_;
        tokenBase = tokenBase_;
        epochBase = epochBase_;
    }

    function setAuction(address auction_) external onlyOwner {
        if (wiringFrozen) revert WiringFrozen();
        require(auction_ != address(0), "ZERO_AUCTION");
        address old = auction;
        auction = auction_;
        emit AuctionSet(old, auction_);
    }

    function setMinter(address minter_) external onlyOwner {
        if (wiringFrozen) revert WiringFrozen();
        require(minter_ != address(0), "ZERO_MINTER");
        address old = minter;
        minter = minter_;
        emit MinterSet(old, minter_);
    }

    function freezeWiring() external onlyOwner {
        if (wiringFrozen) revert WiringFrozen();
        wiringFrozen = true;
        emit WiringFrozenSet();
    }

    function getConfig() external view returns (address auction_, address minter_) {
        return (auction, minter);
    }

    function getAuthorizedAuction() external view returns (address) {
        return auction;
    }

    function getMinterTarget() external view returns (address) {
        return minter;
    }

    function target() external view override returns (address) {
        return auction;
    }

    function settle(address buyer, uint64 epochIndex, bytes calldata data) external override returns (uint256 tokenId) {
        if (msg.sender != auction) revert NotAuction();

        uint256 epoch = uint256(IPulseAuction(auction).getEpochIndex()) + 1;
        if (epoch != uint256(epochIndex)) revert EpochMismatch(epoch, uint256(epochIndex));
        if (epoch < epochBase) revert EpochBeforeBase(epoch, epochBase);

        uint256 expectedId = tokenBase + (epoch - epochBase);
        uint256 next = IPathMinter(minter).nextId();
        if (next != expectedId) revert MintIdMismatch(epoch, expectedId, next);

        tokenId = IPathMinter(minter).mintPublic(buyer, data);
        if (tokenId != expectedId) revert MintIdMismatch(epoch, expectedId, tokenId);

        emit EpochMinted(epoch, tokenId, buyer);
    }
}
