// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IPathNFT} from "./interfaces/IPathNFT.sol";

/// @notice ERC-721 PATH NFT with staged movement progression.
/// @dev Solidity port of `legacy/cairo/contracts/path_nft/src/path_nft.cairo`.
contract PathNFT is ERC721, AccessControl, IPathNFT {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    bytes32 public constant MOVEMENT_THOUGHT = bytes32("THOUGHT");
    bytes32 public constant MOVEMENT_WILL = bytes32("WILL");
    bytes32 public constant MOVEMENT_AWA = bytes32("AWA");

    string private _baseTokenUri;

    mapping(uint256 tokenId => uint8 stage) private _stage;
    mapping(uint256 tokenId => uint32 stageMinted) private _stageMinted;

    mapping(bytes32 movement => uint32 quota) private _movementQuota;
    mapping(bytes32 movement => bool frozen) private _movementFrozen;
    mapping(bytes32 movement => address minter) private _authorizedMinter;

    event MovementConsumed(uint256 indexed pathId, bytes32 indexed movement, address indexed claimer, uint32 serial);
    event MovementFrozen(bytes32 indexed movement);

    constructor(
        address initialAdmin,
        string memory name_,
        string memory symbol_,
        string memory baseUri_
    ) ERC721(name_, symbol_) {
        require(initialAdmin != address(0), "ZERO_ADMIN");

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _baseTokenUri = baseUri_;
    }

    function safeMint(address recipient, uint256 tokenId, bytes calldata data) external override onlyRole(MINTER_ROLE) {
        _safeMint(recipient, tokenId, data);
        _stage[tokenId] = 0;
        _stageMinted[tokenId] = 0;
    }

    /// @notice Snake-case alias maintained for Cairo parity.
    function safe_mint(address recipient, uint256 tokenId, bytes calldata data) external onlyRole(MINTER_ROLE) {
        _safeMint(recipient, tokenId, data);
        _stage[tokenId] = 0;
        _stageMinted[tokenId] = 0;
    }

    function setMovementConfig(bytes32 movement, address minter, uint32 quota) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertValidMovement(movement);
        require(!_movementFrozen[movement], "MOVEMENT_FROZEN");
        require(minter != address(0), "ZERO_MINTER");
        require(quota != 0, "ZERO_QUOTA");

        _authorizedMinter[movement] = minter;
        _movementQuota[movement] = quota;
    }

    function getAuthorizedMinter(bytes32 movement) external view override returns (address) {
        return _authorizedMinter[movement];
    }

    function getStage(uint256 tokenId) external view override returns (uint8) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _stage[tokenId];
    }

    function getStageMinted(uint256 tokenId) external view override returns (uint32) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _stageMinted[tokenId];
    }

    function getMovementQuota(bytes32 movement) external view override returns (uint32) {
        return _movementQuota[movement];
    }

    function consumeUnit(uint256 pathId, bytes32 movement, address claimer) external override returns (uint32 serial) {
        _assertValidMovement(movement);

        address authorized = _authorizedMinter[movement];
        require(authorized != address(0) && _msgSender() == authorized, "ERR_UNAUTHORIZED_MINTER");
        require(claimer == tx.origin, "BAD_CLAIMER");
        require(_exists(pathId), "ERC721: invalid token ID");

        uint8 current = _stage[pathId];
        bytes32 expected = _expectedMovementForStage(current);
        require(movement == expected, "BAD_MOVEMENT_ORDER");

        require(_isApprovedOrOwner(claimer, pathId), "ERR_NOT_OWNER");

        uint32 quota = _movementQuota[movement];
        require(quota != 0, "ZERO_QUOTA");

        uint32 minted = _stageMinted[pathId];
        require(minted < quota, "QUOTA_EXHAUSTED");

        serial = minted;
        uint32 mintedNext = minted + 1;

        if (!_movementFrozen[movement]) {
            _movementFrozen[movement] = true;
            emit MovementFrozen(movement);
        }

        if (mintedNext == quota) {
            _stage[pathId] = current + 1;
            _stageMinted[pathId] = 0;
        } else {
            _stageMinted[pathId] = mintedNext;
        }

        emit MovementConsumed(pathId, movement, claimer, serial);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return string.concat(_baseTokenUri, Strings.toString(tokenId));
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenUri;
    }

    function _assertValidMovement(bytes32 movement) internal pure {
        require(
            movement == MOVEMENT_THOUGHT || movement == MOVEMENT_WILL || movement == MOVEMENT_AWA,
            "BAD_MOVEMENT"
        );
    }

    function _expectedMovementForStage(uint8 stage) internal pure returns (bytes32) {
        if (stage == 0) {
            return MOVEMENT_THOUGHT;
        }
        if (stage == 1) {
            return MOVEMENT_WILL;
        }
        if (stage == 2) {
            return MOVEMENT_AWA;
        }
        revert("BAD_STAGE");
    }
}
