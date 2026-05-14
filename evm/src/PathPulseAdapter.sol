// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPathNFT} from "./interfaces/IPathNFT.sol";
import {IPulseAdapter} from "./interfaces/IPulseAdapter.sol";
import {IPulseAuction} from "./interfaces/IPulseAuction.sol";

/// @notice Direct adapter that lets PulseAuction mint PATH NFTs without a separate public minter.
/// @dev Canonical PATH/Pulse settlement adapter for new deployments.
contract PathPulseAdapter is Ownable, IPulseAdapter {
    error EpochBeforeBase(uint256 epoch, uint256 epochBase);
    error EpochMismatch(uint256 observed, uint256 forwarded);
    error InvalidAuction();
    error InvalidPathNft();
    error NotAuction();
    error WiringFrozen();
    error WiringNotFrozen();

    address public auction;
    address public pathNft;
    uint256 public immutable tokenBase;
    uint256 public immutable epochBase;
    bool public wiringFrozen;

    event AuctionSet(address indexed oldAuction, address indexed newAuction);
    event PathNftSet(address indexed oldPathNft, address indexed newPathNft);
    event WiringFrozenSet();
    event EpochMinted(uint256 indexed epoch, uint256 indexed tokenId, address indexed to);

    constructor(address owner_, address auction_, address pathNft_, uint256 tokenBase_, uint256 epochBase_) {
        require(owner_ != address(0), "ZERO_OWNER");
        _assertValidPathNft(pathNft_);
        if (auction_ != address(0)) {
            _assertValidAuction(auction_);
        }

        _transferOwnership(owner_);
        auction = auction_;
        pathNft = pathNft_;
        tokenBase = tokenBase_;
        epochBase = epochBase_;
    }

    function setAuction(address auction_) external onlyOwner {
        if (wiringFrozen) revert WiringFrozen();
        _assertValidAuction(auction_);
        address old = auction;
        auction = auction_;
        emit AuctionSet(old, auction_);
    }

    function setPathNft(address pathNft_) external onlyOwner {
        if (wiringFrozen) revert WiringFrozen();
        _assertValidPathNft(pathNft_);
        address old = pathNft;
        pathNft = pathNft_;
        emit PathNftSet(old, pathNft_);
    }

    function freezeWiring() external onlyOwner {
        if (wiringFrozen) revert WiringFrozen();
        _assertValidAuction(auction);
        _assertValidPathNft(pathNft);
        wiringFrozen = true;
        emit WiringFrozenSet();
    }

    function getConfig() external view returns (address auction_, address pathNft_) {
        return (auction, pathNft);
    }

    function getAuthorizedAuction() external view returns (address) {
        return auction;
    }

    function getPathNftTarget() external view returns (address) {
        return pathNft;
    }

    function target() external view override returns (address) {
        return auction;
    }

    function settle(address buyer, uint64 epochIndex, bytes calldata data) external override returns (uint256 tokenId) {
        if (msg.sender != auction) revert NotAuction();
        if (!wiringFrozen) revert WiringNotFrozen();

        uint256 epoch = uint256(IPulseAuction(auction).getEpochIndex()) + 1;
        if (epoch != uint256(epochIndex)) revert EpochMismatch(epoch, uint256(epochIndex));
        if (epoch < epochBase) revert EpochBeforeBase(epoch, epochBase);

        tokenId = tokenBase + (epoch - epochBase);
        IPathNFT(pathNft).safeMint(buyer, tokenId, data);

        emit EpochMinted(epoch, tokenId, buyer);
    }

    function _assertValidAuction(address auction_) private view {
        if (auction_ == address(0) || auction_.code.length == 0) {
            revert InvalidAuction();
        }
    }

    function _assertValidPathNft(address pathNft_) private view {
        if (pathNft_ == address(0) || pathNft_.code.length == 0) {
            revert InvalidPathNft();
        }
    }
}
