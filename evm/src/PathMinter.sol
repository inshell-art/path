// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPathMinter} from "./interfaces/IPathMinter.sol";
import {IPathNFT} from "./interfaces/IPathNFT.sol";

/// @notice Shared minting proxy for PathNFT.
/// @dev Current canonical implementation for PATH minting.
contract PathMinter is AccessControl, IPathMinter {
    bytes32 public constant SALES_ROLE = keccak256("SALES_ROLE");
    bytes32 public constant FROZEN_SALES_ADMIN_ROLE = keccak256("FROZEN_SALES_ADMIN_ROLE");

    error BadSalesCaller(address caller, address expected);
    error SalesCallerNotFrozen();

    event SalesCallerFrozen(address indexed caller);

    address public immutable pathNft;
    uint256 public nextId;
    address public salesCaller;
    bool public salesCallerFrozen;

    constructor(address admin, address pathNftAddr, uint256 firstTokenId) {
        require(admin != address(0), "ZERO_ADMIN");
        require(pathNftAddr != address(0), "ZERO_PATH_NFT");
        require(pathNftAddr.code.length > 0, "INVALID_PATH_NFT");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setRoleAdmin(FROZEN_SALES_ADMIN_ROLE, FROZEN_SALES_ADMIN_ROLE);
        pathNft = pathNftAddr;
        nextId = firstTokenId;
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
        IPathNFT(pathNft).safeMint(to, id, data);
        nextId = id + 1;
    }
}
