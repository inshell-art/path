// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPulseAdapter} from "./interfaces/IPulseAdapter.sol";
import {IPulseAuction} from "./interfaces/IPulseAuction.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

library SafeERC20Minimal {
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, from, to, value)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }
}

/// @notice PulseAuction – Decentralized Automatic Auction (DAA).
/// @dev Port of `vendors/pulse/legacy/cairo/crates/pulse_auction/src/pulse_auction.cairo` to Ethereum.
contract PulseAuction is IPulseAuction {
    using SafeERC20Minimal for address;

    event Sale(
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 price,
        uint64 timestamp,
        uint64 anchorA,
        uint256 floorB,
        uint64 epochIndex
    );

    uint64 public openTime;
    uint64 public genesisTime;
    uint256 public genesisPrice;
    uint256 public genesisFloor;
    bool public override curveActive;
    uint64 public epochIndex;

    uint256 public curveK;
    uint64 public anchorTime;
    uint256 public floorPrice;
    uint64 public curveStartTime;
    uint64 public lastBlock;
    uint256 public pts;

    address public paymentToken;
    address public mintAdapter;
    address public treasury;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _reentrancyStatus = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "REENTRANCY");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    constructor(
        uint64 startDelaySec,
        uint256 k,
        uint256 _genesisPrice,
        uint256 _genesisFloor,
        uint256 initialPts,
        address _paymentToken,
        address _treasury,
        address _mintAdapter
    ) {
        _validateConstructorArgs(k, _genesisPrice, _genesisFloor, initialPts);

        uint64 nowTs = uint64(block.timestamp);

        openTime = nowTs + startDelaySec;
        curveActive = false;
        curveK = k;
        genesisPrice = _genesisPrice;
        genesisFloor = _genesisFloor;
        pts = initialPts;
        epochIndex = 0;

        paymentToken = _paymentToken;
        treasury = _treasury;
        mintAdapter = _mintAdapter;
    }

    function getCurrentPrice() public view override returns (uint256) {
        return _getCurrentPrice(uint64(block.timestamp));
    }

    function getConfig() external view override returns (uint64, uint256, uint256, uint256, uint256) {
        return (openTime, genesisPrice, genesisFloor, curveK, pts);
    }

    function getState() external view override returns (uint64, uint64, uint64, uint256, bool) {
        return (epochIndex, curveStartTime, anchorTime, floorPrice, curveActive);
    }

    function bid(uint256 maxPrice) external payable override nonReentrant {
        uint64 nowTs = uint64(block.timestamp);
        uint64 blk = uint64(block.number);
        bytes memory data = "";

        require(nowTs >= openTime, "AUCTION_NOT_OPEN");
        require(uint256(blk) > uint256(lastBlock), "ONE_BID_PER_BLOCK");

        uint256 ask = curveActive ? _getCurrentPrice(nowTs) : genesisPrice;
        require(ask <= maxPrice, "ASK_ABOVE_MAX_PRICE");

        if (paymentToken == address(0)) {
            require(msg.value == ask, "INVALID_MSG_VALUE");
            (bool sent,) = payable(treasury).call{value: ask}("");
            require(sent, "ETH_TRANSFER_FAILED");
        } else {
            require(msg.value == 0, "ETH_NOT_ACCEPTED");
            paymentToken.safeTransferFrom(msg.sender, treasury, ask);
        }

        uint256 mintedId = IPulseAdapter(mintAdapter).settle(msg.sender, data);

        if (!curveActive) {
            uint256 nextFloor = genesisFloor;
            uint64 startTime = nowTs;
            uint64 a = _calculateAnchorTime(genesisPrice, nextFloor, curveK, startTime);

            anchorTime = a;
            genesisTime = startTime;
            curveActive = true;
            floorPrice = nextFloor;
            curveStartTime = startTime;
            lastBlock = blk;
        } else {
            uint256 lastPrice = ask;
            uint256 premium = uint256(nowTs - curveStartTime) * pts;
            uint256 initialAsk = lastPrice + premium;
            uint256 nextFloor = lastPrice;
            uint64 startTime = nowTs;
            uint64 a = _calculateAnchorTime(initialAsk, nextFloor, curveK, startTime);

            anchorTime = a;
            floorPrice = nextFloor;
            curveStartTime = startTime;
            lastBlock = blk;
        }

        epochIndex += 1;

        emit Sale(msg.sender, mintedId, ask, nowTs, anchorTime, floorPrice, epochIndex);
    }

    function _validateConstructorArgs(
        uint256 k,
        uint256 _genesisPrice,
        uint256 _genesisFloor,
        uint256 initialPts
    ) internal pure {
        require(k != 0, "K_ZERO_OR_NEGATIVE");
        require(_genesisPrice > _genesisFloor, "GAP_ZERO_OR_NEGATIVE");
        require(initialPts != 0, "PTS_ZERO_OR_NEGATIVE");
        require(initialPts <= type(uint128).max, "PTS_OUT_OF_RANGE");
    }

    function _calculateAnchorTime(
        uint256 initialAsk,
        uint256 _floorPrice,
        uint256 k,
        uint64 _curveStartTime
    ) internal pure returns (uint64) {
        require(initialAsk > _floorPrice, "ASK_LESS_THAN_FLOOR");

        uint256 gap = initialAsk - _floorPrice;
        require(gap > 0, "GAP_ZERO_OR_NEGATIVE");

        uint256 kOverGap = k / gap;
        require(kOverGap <= type(uint64).max, "K_OVER_GAP_OVERFLOW");

        uint64 kOverGapU64 = uint64(kOverGap);
        require(_curveStartTime > kOverGapU64, "ANCHOR_TIME_UNDERFLOW");

        return _curveStartTime - kOverGapU64;
    }

    function _getCurrentPrice(uint64 nowTs) internal view returns (uint256) {
        if (!curveActive) {
            return genesisPrice;
        }

        uint256 k = curveK;
        uint64 a = anchorTime;
        uint256 b = floorPrice;

        if (nowTs <= a) {
            return b + k;
        }

        return (k / uint256(nowTs - a)) + b;
    }
}
