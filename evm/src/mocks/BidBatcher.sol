// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPulseAuction} from "../interfaces/IPulseAuction.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract BidBatcher is IERC721Receiver {
    function bidTwice(address auction, uint256 maxPrice1, uint256 maxPrice2) external payable {
        IPulseAuction(auction).bid{value: maxPrice1}(maxPrice1);
        IPulseAuction(auction).bid{value: maxPrice2}(maxPrice2);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
