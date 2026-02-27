// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPulseAdapter} from "../interfaces/IPulseAdapter.sol";

contract StubPulseAuction {
    uint64 private _epochIndex;

    function setEpochIndex(uint64 epochIndex_) external {
        _epochIndex = epochIndex_;
    }

    function getEpochIndex() external view returns (uint64) {
        return _epochIndex;
    }

    function settleThroughAdapter(address adapter, address buyer, bytes calldata data)
        external
        returns (uint256 tokenId)
    {
        uint64 nextEpochIndex = _epochIndex + 1;
        tokenId = IPulseAdapter(adapter).settle(buyer, nextEpochIndex, data);
        _epochIndex = nextEpochIndex;
    }

    function settleThroughAdapterWithForwardedEpoch(
        address adapter,
        address buyer,
        uint64 forwardedEpoch,
        bytes calldata data
    ) external returns (uint256 tokenId) {
        tokenId = IPulseAdapter(adapter).settle(buyer, forwardedEpoch, data);
    }
}
