// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPathMinter} from "./interfaces/IPathMinter.sol";
import {IPathNFT} from "./interfaces/IPathNFT.sol";

/// @notice Shared minting proxy for PathNFT.
/// @dev Solidity port of `legacy/cairo/contracts/path_minter/src/path_minter.cairo`.
contract PathMinter is AccessControl, IPathMinter {
    bytes32 public constant SALES_ROLE = keccak256("SALES_ROLE");
    bytes32 public constant RESERVED_ROLE = keccak256("RESERVED_ROLE");
    bytes32 public constant FROZEN_SALES_ADMIN_ROLE = keccak256("FROZEN_SALES_ADMIN_ROLE");

    uint256 public constant SPARK_BASE = 1_000_000_000_000_000;

    error BadSalesCaller(address caller, address expected);
    error SalesCallerNotFrozen();

    event SalesCallerFrozen(address indexed caller);

    address public immutable pathNft;
    uint256 public nextId;
    address public salesCaller;
    bool public salesCallerFrozen;
    uint64 private immutable _reservedCap;
    uint64 private _reservedRemaining;

    constructor(address admin, address pathNftAddr, uint256 firstTokenId, uint64 reservedCap_) {
        require(admin != address(0), "ZERO_ADMIN");
        require(pathNftAddr != address(0), "ZERO_PATH_NFT");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(FROZEN_SALES_ADMIN_ROLE, FROZEN_SALES_ADMIN_ROLE);
        pathNft = pathNftAddr;
        nextId = firstTokenId;
        _reservedCap = reservedCap_;
        _reservedRemaining = reservedCap_;
    }

    function getReservedCap() external view override returns (uint64) {
        return _reservedCap;
    }

    function getReservedRemaining() external view override returns (uint64) {
        return _reservedRemaining;
    }

    function freezeSalesCaller(address expectedCaller) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!salesCallerFrozen, "SALES_CALLER_FROZEN");
        require(expectedCaller != address(0), "ZERO_SALES_CALLER");
        require(hasRole(SALES_ROLE, expectedCaller), "MISSING_SALES_ROLE");

        salesCaller = expectedCaller;
        salesCallerFrozen = true;
        _setRoleAdmin(SALES_ROLE, FROZEN_SALES_ADMIN_ROLE);

        emit SalesCallerFrozen(expectedCaller);
    }

    function mintPublic(address to, bytes calldata data) external override returns (uint256 id) {
        if (!salesCallerFrozen) {
            revert SalesCallerNotFrozen();
        }
        if (msg.sender != salesCaller) {
            revert BadSalesCaller(msg.sender, salesCaller);
        }

        id = nextId;
        require(id < SPARK_BASE, "PUBLIC_ID_DOMAIN_EXHAUSTED");
        IPathNFT(pathNft).safeMint(to, id, data);
        nextId = id + 1;
    }

    function mintSparker(address to, bytes calldata data)
        external
        override
        onlyRole(RESERVED_ROLE)
        returns (uint256 id)
    {
        uint64 remaining = _reservedRemaining;
        require(remaining > 0, "NO_RESERVED_LEFT");

        uint64 mintedSoFar = _reservedCap - remaining;
        id = SPARK_BASE + uint256(mintedSoFar);

        IPathNFT(pathNft).safeMint(to, id, data);
        _reservedRemaining = remaining - 1;
    }
}
