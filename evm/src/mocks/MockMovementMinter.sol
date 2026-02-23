// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPathNFT} from "../interfaces/IPathNFT.sol";

contract MockMovementMinter {
    function consume(address pathNft, uint256 pathId, bytes32 movement, address claimer) external returns (uint32) {
        return IPathNFT(pathNft).consumeUnit(pathId, movement, claimer);
    }
}
