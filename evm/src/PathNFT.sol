// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IPathNFT} from "./interfaces/IPathNFT.sol";

/// @notice ERC-721 PATH NFT with staged movement progression.
/// @dev Solidity port of `legacy/cairo/contracts/path_nft/src/path_nft.cairo`.
contract PathNFT is ERC721, AccessControl, IPathNFT, IERC4906 {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes4 private constant _INTERFACE_ID_ERC4906 = 0x49064906;

    bytes32 public constant MOVEMENT_THOUGHT = bytes32("THOUGHT");
    bytes32 public constant MOVEMENT_WILL = bytes32("WILL");
    bytes32 public constant MOVEMENT_AWA = bytes32("AWA");
    bytes32 private constant _CONSUME_AUTHORIZATION_TYPEHASH = keccak256(
        "ConsumeAuthorization(address pathNft,uint256 chainId,uint256 pathId,bytes32 movement,address claimer,address executor,uint256 nonce,uint256 deadline)"
    );

    string private _baseTokenUri;

    mapping(uint256 tokenId => uint8 stage) private _stage;
    mapping(uint256 tokenId => uint32 stageMinted) private _stageMinted;

    mapping(bytes32 movement => uint32 quota) private _movementQuota;
    mapping(bytes32 movement => bool frozen) private _movementFrozen;
    mapping(bytes32 movement => address minter) private _authorizedMinter;
    mapping(address claimer => uint256 nonce) private _consumeNonce;

    struct RenderState {
        uint8 stage;
        uint32 thoughtQuota;
        uint32 willQuota;
        uint32 awaQuota;
        uint32 thoughtMinted;
        uint32 willMinted;
        uint32 awaMinted;
    }

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

    function getConsumeNonce(address claimer) external view override returns (uint256) {
        return _consumeNonce[claimer];
    }

    function consumeUnit(
        uint256 pathId,
        bytes32 movement,
        address claimer,
        uint256 deadline,
        bytes calldata signature
    ) external override returns (uint32 serial) {
        _assertValidMovement(movement);

        address authorized = _authorizedMinter[movement];
        require(authorized != address(0) && _msgSender() == authorized, "ERR_UNAUTHORIZED_MINTER");
        uint256 nonce = _validateConsumeAuthorization(pathId, movement, claimer, _msgSender(), deadline, signature);

        uint8 current = _stage[pathId];
        require(movement == _expectedMovementForStage(current), "BAD_MOVEMENT_ORDER");

        require(_isApprovedOrOwner(claimer, pathId), "ERR_NOT_OWNER");

        uint32 quota = _movementQuota[movement];
        require(quota != 0, "ZERO_QUOTA");

        uint32 minted = _stageMinted[pathId];
        require(minted < quota, "QUOTA_EXHAUSTED");

        serial = minted;
        uint32 mintedNext = minted + 1;
        _consumeNonce[claimer] = nonce + 1;

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

        emit MetadataUpdate(pathId);
        emit MovementConsumed(pathId, movement, claimer, serial);
    }

    function _validateConsumeAuthorization(
        uint256 pathId,
        bytes32 movement,
        address claimer,
        address executor,
        uint256 deadline,
        bytes calldata signature
    ) internal view returns (uint256 nonce) {
        require(block.timestamp <= deadline, "CONSUME_AUTH_EXPIRED");
        require(_exists(pathId), "ERC721: invalid token ID");

        nonce = _consumeNonce[claimer];
        bytes32 structHash = keccak256(
            abi.encode(
                _CONSUME_AUTHORIZATION_TYPEHASH,
                address(this),
                uint256(block.chainid),
                pathId,
                movement,
                claimer,
                executor,
                nonce,
                deadline
            )
        );
        bytes32 digest = ECDSA.toEthSignedMessageHash(structHash);
        require(SignatureChecker.isValidSignatureNow(claimer, digest, signature), "BAD_CONSUME_AUTH");
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _tokenUriData(tokenId);
    }

    function _tokenUriData(uint256 tokenId) internal view returns (string memory) {
        RenderState memory state = _tokenRenderState(tokenId);
        string memory tokenIdStr = Strings.toString(tokenId);
        string memory stageLabel = _stageLabel(state.stage);
        string memory thoughtProgress = _manifestProgress(state.thoughtMinted, state.thoughtQuota);
        string memory willProgress = _manifestProgress(state.willMinted, state.willQuota);
        string memory awaProgress = _manifestProgress(state.awaMinted, state.awaQuota);
        string memory svg = _buildSvg(state.thoughtMinted, state.willMinted, state.awaMinted, state.willQuota);
        string memory image = string.concat(
            "data:image/svg+xml;base64,",
            Base64.encode(bytes(svg))
        );
        string memory attrs = _attributesJson(stageLabel, thoughtProgress, willProgress, awaProgress);
        string memory json = _metadataJson(
            tokenIdStr,
            image,
            attrs,
            stageLabel,
            thoughtProgress,
            willProgress,
            awaProgress,
            svg
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _metadataJson(
        string memory tokenIdStr,
        string memory image,
        string memory attrs,
        string memory stageLabel,
        string memory thoughtProgress,
        string memory willProgress,
        string memory awaProgress,
        string memory svg
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '{"name":"PATH #',
                tokenIdStr,
                '","description":"',
                _description(),
                '","image":"',
                image,
                '","attributes":',
                attrs,
                ',"token":"',
                tokenIdStr,
                '","stage":"',
                stageLabel,
                '","thought":"',
                thoughtProgress,
                '","will":"',
                willProgress,
                '","awa":"',
                awaProgress,
                '","image_data":"',
                svg,
                '"}'
            )
        );
    }

    function _description() internal pure returns (string memory) {
        return "PATH is a permission token. Holding PATH authorizes minting THOUGHT to WILL to AWA in order. The image and traits show quota usage and progress for this PATH token.";
    }

    function _attributesJson(
        string memory stageLabel,
        string memory thoughtProgress,
        string memory willProgress,
        string memory awaProgress
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '[{"trait_type":"Stage","value":"',
                stageLabel,
                '"},{"trait_type":"THOUGHT","value":"',
                thoughtProgress,
                '"},{"trait_type":"WILL","value":"',
                willProgress,
                '"},{"trait_type":"AWA","value":"',
                awaProgress,
                '"}]'
            )
        );
    }

    function _tokenRenderState(uint256 tokenId) internal view returns (RenderState memory state) {
        state.stage = _stage[tokenId];
        uint32 stageMinted = _stageMinted[tokenId];
        state.thoughtQuota = _movementQuota[MOVEMENT_THOUGHT];
        state.willQuota = _movementQuota[MOVEMENT_WILL];
        state.awaQuota = _movementQuota[MOVEMENT_AWA];

        (state.thoughtMinted, state.willMinted, state.awaMinted) = _progressCounts(
            state.stage,
            stageMinted,
            state.thoughtQuota,
            state.willQuota,
            state.awaQuota
        );
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl, IERC165)
        returns (bool)
    {
        return interfaceId == _INTERFACE_ID_ERC4906 || super.supportsInterface(interfaceId);
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

    function _progressCounts(
        uint8 stage,
        uint32 stageMinted,
        uint32 thoughtQuota,
        uint32 willQuota,
        uint32 awaQuota
    ) internal pure returns (uint32 thoughtMinted, uint32 willMinted, uint32 awaMinted) {
        thoughtMinted = stage > 0 ? thoughtQuota : stageMinted;

        if (stage > 1) {
            willMinted = willQuota;
        } else if (stage == 1) {
            willMinted = stageMinted;
        } else {
            willMinted = 0;
        }

        if (stage > 2) {
            awaMinted = awaQuota;
        } else if (stage == 2) {
            awaMinted = stageMinted;
        } else {
            awaMinted = 0;
        }
    }

    function _stageLabel(uint8 stage) internal pure returns (string memory) {
        if (stage == 0) {
            return "THOUGHT";
        }
        if (stage == 1) {
            return "WILL";
        }
        if (stage == 2) {
            return "AWA";
        }
        if (stage == 3) {
            return "COMPLETE";
        }
        return "UNKNOWN";
    }

    function _manifestProgress(uint32 minted, uint32 quota) internal pure returns (string memory) {
        return string.concat(
            string.concat("Minted(", Strings.toString(uint256(minted))),
            string.concat("/", string.concat(Strings.toString(uint256(quota)), ")"))
        );
    }

    function _buildSvg(
        uint32 thoughtMinted,
        uint32 willMinted,
        uint32 awaMinted,
        uint32 willQuota
    ) internal pure returns (string memory) {
        string memory thoughtDisplay = thoughtMinted > 0 ? "inline" : "none";
        string memory willDisplay = willMinted > 0 ? "inline" : "none";
        string memory awaDisplay = awaMinted > 0 ? "inline" : "none";

        uint256 willFillWidth = 0;
        if (willQuota > 0 && willMinted > 0) {
            willFillWidth = (60 * uint256(willMinted)) / uint256(willQuota);
            if (willFillWidth > 60) {
                willFillWidth = 60;
            }
        }

        string memory willFillRect = "";
        if (willMinted > 0 && willFillWidth > 0) {
            willFillRect = string.concat(
                "<rect id='will-fill' x='270' y='270' width='",
                Strings.toString(willFillWidth),
                "' height='60' fill='white' display='inline'/>"
            );
        }

        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 600 600' width='600' height='600' role='img' aria-label='PATH progress'>",
            "<rect width='600' height='600' fill='black'/>",
            "<rect id='thought-box' x='180' y='270' width='60' height='60' fill='white' display='",
            thoughtDisplay,
            "'/>",
            "<rect id='will-box' x='270' y='270' width='60' height='60' fill='none' display='",
            willDisplay,
            "'/>",
            willFillRect,
            "<rect id='awa-box' x='360' y='270' width='60' height='60' fill='white' display='",
            awaDisplay,
            "'/>",
            "</svg>"
        );
    }
}
