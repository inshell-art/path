// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPulseAuction {
    function getCurrentPrice() external view returns (uint256);

    function curveActive() external view returns (bool);

    function getConfig()
        external
        view
        returns (uint64 openTime, uint256 genesisPrice, uint256 genesisFloor, uint256 k, uint256 pts);

    function getState()
        external
        view
        returns (uint64 epochIndex, uint64 startTime, uint64 anchorTime, uint256 floorB, bool active);

    function getEpochIndex() external view returns (uint64);

    function bid(uint256 maxPrice) external payable;

    function initializeMintAdapter(address adapter) external;
}
