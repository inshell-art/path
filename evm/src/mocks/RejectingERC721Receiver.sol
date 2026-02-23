// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract RejectingERC721Receiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return 0x00000000;
    }
}
