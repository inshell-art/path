// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPulseAdapter} from "../interfaces/IPulseAdapter.sol";

contract StubPulseAdapter is IPulseAdapter {
    address private _target;

    constructor(address target_) {
        _target = target_;
    }

    function settle(address, uint64, bytes calldata) external pure override returns (uint256 tokenId) {
        return tokenId;
    }

    function target() external view override returns (address) {
        return _target;
    }
}
