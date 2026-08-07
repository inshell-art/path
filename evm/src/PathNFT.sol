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
import {IERC5192} from "./interfaces/IERC5192.sol";
import {IPathNFT} from "./interfaces/IPathNFT.sol";
import {PathSvgRenderer} from "./PathSvgRenderer.sol";

/// @notice ERC-721 PATH NFT with staged movement progression.
/// @dev Current canonical implementation for the PATH NFT.
contract PathNFT is ERC721, AccessControl, IPathNFT, IERC4906, IERC5192 {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant RESERVED_ROLE = keccak256("RESERVED_ROLE");
    bytes32 public constant FROZEN_MINTER_ADMIN_ROLE = keccak256("FROZEN_MINTER_ADMIN_ROLE");
    bytes4 private constant _INTERFACE_ID_ERC4906 = 0x49064906;
    bytes4 private constant _INTERFACE_ID_ERC5192 = 0xb45a3c0e;
    uint256 public constant SPARK_BASE = 1_000_000_000_000_000;
    uint256 private constant _MAX_SPARK_NAME_BYTES = 31;
    uint256 private constant _SPARK_NAME_DATA_MASK = type(uint256).max << 8;

    bytes32 public constant MOVEMENT_THOUGHT = bytes32("THOUGHT");
    bytes32 public constant MOVEMENT_WILL = bytes32("WILL");
    bytes32 public constant MOVEMENT_AWA = bytes32("AWA");
    bytes32 private constant _CONSUME_AUTHORIZATION_TYPEHASH = keccak256(
        "ConsumeAuthorization(address pathNft,uint256 chainId,uint256 pathId,bytes32 movement,address claimer,address executor,uint256 permissionEpoch,uint256 nonce,uint256 deadline)"
    );

    string private _baseTokenUri;

    mapping(uint256 tokenId => uint8 stage) private _stage;
    mapping(uint256 tokenId => uint32 stageMinted) private _stageMinted;

    mapping(bytes32 movement => uint32 quota) private _movementQuota;
    mapping(bytes32 movement => bool frozen) private _movementFrozen;
    mapping(bytes32 movement => address minter) private _authorizedMinter;
    mapping(address claimer => uint256 nonce) private _consumeNonce;
    mapping(uint256 tokenId => uint256 epoch) private _permissionEpoch;
    mapping(uint256 tokenId => bool sparker) private _sparker;
    mapping(uint256 tokenId => bytes32 name) private _sparkName;
    mapping(address recipient => uint64 expiresAt) private _sparkAllowanceExpiresAt;
    mapping(address recipient => bytes32 name) private _sparkInvitationName;

    address public publicMinter;
    bool public publicMinterFrozen;
    uint64 public immutable sparkClaimDuration;
    uint64 private immutable _reservedCap;
    uint64 private _reservedAvailable;
    uint64 private _reservedPending;
    uint64 private _reservedMinted;

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
    event PublicMinterFrozen(address indexed publicMinter);
    event SparkerAllowed(address indexed recipient, uint64 expiresAt);
    event SparkerInvitationReleased(address indexed recipient);
    event SparkerMinted(address indexed to, uint256 indexed tokenId);
    event PermissionEpochAdvanced(
        uint256 indexed pathId,
        uint256 epoch,
        address indexed from,
        address indexed to
    );

    error InvalidSparkName();
    error BadConsumeAuthorization();
    error BadMovement();
    error BadMovementOrder();
    error BadStage();
    error ConsumeAuthorizationExpired();
    error MissingMinterRole();
    error MovementConfigFrozen();
    error MovementNotConfigured();
    error NoReservedSparkAvailable();
    error NotOwner();
    error NotPublicMinter();
    error PublicMinterAlreadyFrozen();
    error PublicMinterNotFrozen();
    error PublicTokenIdDomainExhausted();
    error QuotaExhausted();
    error SparkAllowanceOverflow();
    error SparkInvitationActive();
    error SparkInvitationExpired();
    error SparkInvitationMissing();
    error SparkNameMismatch();
    error SparkSoulbound();
    error UnauthorizedMovementMinter();
    error ZeroAdmin();
    error ZeroMinter();
    error ZeroPublicMinter();
    error ZeroQuota();
    error ZeroSparkClaimDuration();
    error ZeroSparkRecipient();

    constructor(
        address initialAdmin,
        string memory name_,
        string memory symbol_,
        string memory baseUri_,
        uint64 reservedCap_,
        uint64 sparkClaimDuration_
    ) ERC721(name_, symbol_) {
        if (initialAdmin == address(0)) revert ZeroAdmin();
        if (sparkClaimDuration_ == 0) revert ZeroSparkClaimDuration();

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setRoleAdmin(FROZEN_MINTER_ADMIN_ROLE, FROZEN_MINTER_ADMIN_ROLE);
        _baseTokenUri = baseUri_;
        sparkClaimDuration = sparkClaimDuration_;
        _reservedCap = reservedCap_;
        _reservedAvailable = reservedCap_;
    }

    function safeMint(address recipient, uint256 tokenId, bytes calldata data) external override onlyRole(MINTER_ROLE) {
        _assertPublicMinter();
        _assertPublicTokenId(tokenId);
        _mintPath(recipient, tokenId, data);
    }

    /// @notice Snake-case alias kept for backward compatibility with older integrations.
    function safe_mint(address recipient, uint256 tokenId, bytes calldata data) external override onlyRole(MINTER_ROLE) {
        _assertPublicMinter();
        _assertPublicTokenId(tokenId);
        _mintPath(recipient, tokenId, data);
    }

    function getReservedCap() external view override returns (uint64) {
        return _reservedCap;
    }

    function getReservedRemaining() external view override returns (uint64) {
        return _reservedAvailable;
    }

    function getReservedPending() external view override returns (uint64) {
        return _reservedPending;
    }

    function isSparker(uint256 tokenId) external view override returns (bool) {
        return _sparker[tokenId];
    }

    function locked(uint256 tokenId) external view override returns (bool) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _sparker[tokenId];
    }

    function getSparkInvitation(address recipient)
        external
        view
        override
        returns (uint64 expiresAt, string memory name)
    {
        return (_sparkAllowanceExpiresAt[recipient], _unpackSparkName(_sparkInvitationName[recipient]));
    }

    function sparkName(uint256 tokenId) external view override returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _unpackSparkName(_sparkName[tokenId]);
    }

    function allowSparker(address recipient, string calldata name)
        external
        override
        onlyRole(RESERVED_ROLE)
        returns (uint64 expiresAt)
    {
        if (recipient == address(0)) revert ZeroSparkRecipient();
        bytes32 packedName = _validateAndPackSparkName(name);

        uint256 expiry = block.timestamp + uint256(sparkClaimDuration);
        if (expiry > type(uint64).max) revert SparkAllowanceOverflow();
        expiresAt = uint64(expiry);

        uint64 existingExpiry = _sparkAllowanceExpiresAt[recipient];
        if (existingExpiry != 0) {
            if (block.timestamp <= uint256(existingExpiry)) {
                if (_sparkInvitationName[recipient] != packedName) revert SparkNameMismatch();
                _sparkAllowanceExpiresAt[recipient] = expiresAt;
                emit SparkerAllowed(recipient, expiresAt);
                return expiresAt;
            }

            _releaseSparkInvitation(recipient);
            emit SparkerInvitationReleased(recipient);
        }

        if (_reservedAvailable == 0) revert NoReservedSparkAvailable();
        _reservedAvailable -= 1;
        _reservedPending += 1;

        _sparkAllowanceExpiresAt[recipient] = expiresAt;
        _sparkInvitationName[recipient] = packedName;

        emit SparkerAllowed(recipient, expiresAt);
    }

    function revokeSparker(address recipient) external override onlyRole(RESERVED_ROLE) {
        if (_sparkAllowanceExpiresAt[recipient] == 0) revert SparkInvitationMissing();
        _releaseSparkInvitation(recipient);
        emit SparkerInvitationReleased(recipient);
    }

    function releaseExpiredSparker(address recipient) external override {
        uint64 expiresAt = _sparkAllowanceExpiresAt[recipient];
        if (expiresAt == 0) revert SparkInvitationMissing();
        if (block.timestamp <= uint256(expiresAt)) revert SparkInvitationActive();
        _releaseSparkInvitation(recipient);
        emit SparkerInvitationReleased(recipient);
    }

    function mintSparker(bytes32 expectedNameHash, bytes calldata data)
        external
        override
        returns (uint256 id)
    {
        address recipient = _msgSender();
        uint64 expiresAt = _sparkAllowanceExpiresAt[recipient];
        if (expiresAt == 0) revert SparkInvitationMissing();
        if (block.timestamp > uint256(expiresAt)) revert SparkInvitationExpired();
        bytes32 name = _sparkInvitationName[recipient];
        if (_sparkNameHash(name) != expectedNameHash) revert SparkNameMismatch();

        id = SPARK_BASE + uint256(_reservedMinted);
        _reservedPending -= 1;
        _reservedMinted += 1;
        delete _sparkAllowanceExpiresAt[recipient];
        delete _sparkInvitationName[recipient];
        _sparker[id] = true;
        _sparkName[id] = name;

        _mintPath(recipient, id, data);
        emit SparkerMinted(recipient, id);
    }

    function freezePublicMinter(address expectedMinter) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (publicMinterFrozen) revert PublicMinterAlreadyFrozen();
        if (expectedMinter == address(0)) revert ZeroPublicMinter();
        if (!hasRole(MINTER_ROLE, expectedMinter)) revert MissingMinterRole();

        publicMinter = expectedMinter;
        publicMinterFrozen = true;
        _setRoleAdmin(MINTER_ROLE, FROZEN_MINTER_ADMIN_ROLE);

        emit PublicMinterFrozen(expectedMinter);
    }

    function setMovementConfig(bytes32 movement, address minter, uint32 quota) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertValidMovement(movement);
        if (_movementFrozen[movement]) revert MovementConfigFrozen();
        if (minter == address(0)) revert ZeroMinter();
        if (quota == 0) revert ZeroQuota();

        _authorizedMinter[movement] = minter;
        _movementQuota[movement] = quota;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function freezeMovementConfig(bytes32 movement) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertValidMovement(movement);
        if (_movementFrozen[movement]) revert MovementConfigFrozen();
        if (_authorizedMinter[movement] == address(0)) revert MovementNotConfigured();
        if (_movementQuota[movement] == 0) revert ZeroQuota();

        _movementFrozen[movement] = true;
        emit MovementFrozen(movement);
    }

    function getAuthorizedMinter(bytes32 movement) external view override returns (address) {
        return _authorizedMinter[movement];
    }

    function isMovementFrozen(bytes32 movement) external view override returns (bool) {
        _assertValidMovement(movement);
        return _movementFrozen[movement];
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

    function getPermissionEpoch(uint256 pathId) external view override returns (uint256) {
        require(_exists(pathId), "ERC721: invalid token ID");
        return _permissionEpoch[pathId];
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
        if (authorized == address(0) || _msgSender() != authorized) revert UnauthorizedMovementMinter();
        uint256 nonce = _validateConsumeAuthorization(pathId, movement, claimer, _msgSender(), deadline, signature);

        uint8 current = _stage[pathId];
        if (movement != _expectedMovementForStage(current)) revert BadMovementOrder();

        uint32 quota = _movementQuota[movement];
        if (quota == 0) revert ZeroQuota();

        uint32 minted = _stageMinted[pathId];
        if (minted >= quota) revert QuotaExhausted();

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
        if (block.timestamp > deadline) revert ConsumeAuthorizationExpired();
        require(_exists(pathId), "ERC721: invalid token ID");
        if (ownerOf(pathId) != claimer) revert NotOwner();

        nonce = _consumeNonce[claimer];
        uint256 permissionEpoch = _permissionEpoch[pathId];
        bytes32 structHash = keccak256(
            abi.encode(
                _CONSUME_AUTHORIZATION_TYPEHASH,
                address(this),
                uint256(block.chainid),
                pathId,
                movement,
                claimer,
                executor,
                permissionEpoch,
                nonce,
                deadline
            )
        );
        bytes32 digest = ECDSA.toEthSignedMessageHash(structHash);
        if (!SignatureChecker.isValidSignatureNow(claimer, digest, signature)) revert BadConsumeAuthorization();
    }

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        override
    {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        if (from == address(0) || to == address(0)) return;

        for (uint256 i = 0; i < batchSize; ++i) {
            if (_sparker[firstTokenId + i]) revert SparkSoulbound();
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        override
    {
        super._afterTokenTransfer(from, to, firstTokenId, batchSize);
        if (from == address(0) || to == address(0)) return;

        for (uint256 i = 0; i < batchSize; ++i) {
            uint256 pathId = firstTokenId + i;
            uint256 epoch = _permissionEpoch[pathId] + 1;
            _permissionEpoch[pathId] = epoch;
            emit PermissionEpochAdvanced(pathId, epoch, from, to);
        }
    }

    function _releaseSparkInvitation(address recipient) internal {
        delete _sparkAllowanceExpiresAt[recipient];
        delete _sparkInvitationName[recipient];
        _reservedPending -= 1;
        _reservedAvailable += 1;
    }

    function _assertPublicMinter() internal view {
        if (!publicMinterFrozen) revert PublicMinterNotFrozen();
        if (_msgSender() != publicMinter) revert NotPublicMinter();
    }

    function _assertPublicTokenId(uint256 tokenId) internal pure {
        if (tokenId >= SPARK_BASE) revert PublicTokenIdDomainExhausted();
    }

    function _mintPath(address recipient, uint256 tokenId, bytes calldata data) internal {
        _safeMint(recipient, tokenId, data);
        _stage[tokenId] = 0;
        _stageMinted[tokenId] = 0;
        if (_sparker[tokenId]) {
            emit Locked(tokenId);
        } else {
            emit Unlocked(tokenId);
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _tokenUriData(tokenId);
    }

    /// @notice Contract-level metadata used by marketplaces that support collection metadata.
    function contractURI() external pure returns (string memory) {
        string memory svg = _contractSvg();
        string memory image = string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg)));
        string memory json = string(
            abi.encodePacked(
                '{"name":"PATH","description":"',
                _contractDescription(),
                '","image":"',
                image,
                '","external_link":"https://github.com/inshell-art/path"}'
            )
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _tokenUriData(uint256 tokenId) internal view returns (string memory) {
        RenderState memory state = _tokenRenderState(tokenId);
        string memory tokenIdStr = Strings.toString(tokenId);
        string memory itemName = string.concat("PATH #", tokenIdStr);
        string memory itemDescription = _description();
        if (_sparker[tokenId]) {
            string memory sparkNumber = Strings.toString(tokenId - SPARK_BASE + 1);
            itemName = string.concat(
                "PATH Spark #",
                sparkNumber,
                ": ",
                _unpackSparkName(_sparkName[tokenId])
            );
            itemDescription = _sparkDescription();
        }
        string memory stageLabel = _stageLabel(state.stage);
        string memory thoughtProgress = _manifestProgress(state.thoughtMinted, state.thoughtQuota);
        string memory willProgress = _manifestProgress(state.willMinted, state.willQuota);
        string memory awaProgress = _manifestProgress(state.awaMinted, state.awaQuota);
        string memory svg = _buildSvg(
            state.thoughtMinted,
            state.thoughtQuota,
            state.willMinted,
            state.willQuota,
            state.awaMinted,
            state.awaQuota
        );
        string memory image = string.concat(
            "data:image/svg+xml;base64,",
            Base64.encode(bytes(svg))
        );
        string memory attrs = _attributesJson(stageLabel, thoughtProgress, willProgress, awaProgress);
        string memory json = _metadataJson(
            itemName,
            itemDescription,
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
        string memory itemName,
        string memory itemDescription,
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
                '{"name":"',
                itemName,
                '","description":"',
                itemDescription,
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
        return "PATH is a permission token for Inshell generative artworks. Holding PATH authorizes movement mints in order: THOUGHT, WILL, then AWA. The image and traits show this PATH token's movement progress.";
    }

    function _sparkDescription() internal pure returns (string memory) {
        return "Spark is a permanent acknowledgment by Inshell of those who resonate with Inshell's artistic vision, inviting them to participate in the unfolding journey of a movement. This soulbound PATH carries movement permission in order: THOUGHT, WILL, then AWA.";
    }

    function _contractDescription() internal pure returns (string memory) {
        return "PATH is the permission-token collection for Inshell generative artworks. Each PATH progresses through THOUGHT, WILL, and AWA by consuming movement units.";
    }

    function _contractSvg() internal pure returns (string memory) {
        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 600 600' width='600' height='600' role='img' aria-label='PATH collection'>",
            "<rect width='600' height='600' fill='black'/>",
            "<text x='50%' y='50%' dominant-baseline='middle' text-anchor='middle' fill='white' font-size='64' font-family='monospace'>PATH</text>",
            "</svg>"
        );
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
        return interfaceId == _INTERFACE_ID_ERC4906 || interfaceId == _INTERFACE_ID_ERC5192
            || super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenUri;
    }

    function _assertValidMovement(bytes32 movement) internal pure {
        if (movement != MOVEMENT_THOUGHT && movement != MOVEMENT_WILL && movement != MOVEMENT_AWA) {
            revert BadMovement();
        }
    }

    function _validateAndPackSparkName(string calldata name) internal pure returns (bytes32 packedName) {
        bytes calldata value = bytes(name);
        uint256 length = value.length;
        if (length == 0 || length > _MAX_SPARK_NAME_BYTES) revert InvalidSparkName();
        for (uint256 i = 0; i < length; ++i) {
            uint8 character = uint8(value[i]);
            if (
                character < 0x20 || character > 0x7e || character == 0x22 || character == 0x5c
                    || (character == 0x20 && (i == 0 || i + 1 == length))
            ) {
                revert InvalidSparkName();
            }
        }

        assembly {
            packedName := calldataload(name.offset)
        }
        packedName = bytes32((uint256(packedName) & _SPARK_NAME_DATA_MASK) | length);
    }

    function _unpackSparkName(bytes32 packedName) internal pure returns (string memory) {
        uint256 length = uint8(uint256(packedName));
        bytes memory name = new bytes(length);
        bytes32 data = bytes32(uint256(packedName) & _SPARK_NAME_DATA_MASK);
        assembly {
            mstore(add(name, 0x20), data)
        }
        return string(name);
    }

    function _sparkNameHash(bytes32 packedName) internal pure returns (bytes32) {
        return keccak256(bytes(_unpackSparkName(packedName)));
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
        revert BadStage();
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
        uint32 thoughtQuota,
        uint32 willMinted,
        uint32 willQuota,
        uint32 awaMinted,
        uint32 awaQuota
    ) internal pure returns (string memory) {
        return PathSvgRenderer.render(
            thoughtMinted,
            thoughtQuota,
            willMinted,
            willQuota,
            awaMinted,
            awaQuota
        );
    }
}
