// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice PulseAuction interface (DAA core).
interface IPulseAuction {
    // ------------- VIEW -------------

    /// @notice Return the current ask price.
    function getCurrentPrice() external view returns (uint256);

    /// @notice Whether the auction is open (`block.timestamp >= openTime`).
    function curveActive() external view returns (bool);

    /// @notice Return the current epoch index.
    function getEpochIndex() external view returns (uint64);

    /// @notice Immutable configuration used by frontends.
    function getConfig()
        external
        view
        returns (uint64 openTime, uint256 genesisPrice, uint256 genesisFloor, uint256 k, uint256 pts);

    /// @notice Live state used by frontends.
    function getState()
        external
        view
        returns (
            uint64 epochIndex,
            uint64 startTime,
            uint64 anchorTime,
            uint256 floorPrice,
            bool active
        );

    // ------------- ACTION -------------

    /// @notice Place a bid in the auction. Reverts if `maxPrice` is below the current ask.
    /// @dev If `paymentToken == address(0)`, this function expects `msg.value >= ask` and refunds surplus.
    function bid(uint256 maxPrice) external payable;

    /// @notice One-time initializer for mint adapter when constructor is deployed with zero adapter.
    function initializeMintAdapter(address adapter) external;
}
