# Path (EVM / Solidity)

This folder contains the Ethereum Solidity port for the PATH stack in this repo.

Core contracts:

- `evm/src/PathNFT.sol`
- `evm/src/PathPulseAdapter.sol`
- `evm/src/PulseAuction.sol`

Test mocks:

- `evm/src/mocks/MockMovementMinter.sol`
- `evm/src/mocks/MockERC721Receiver.sol`
- `evm/src/mocks/RejectingERC721Receiver.sol`
- `evm/src/mocks/StubPathMinter.sol`
- `evm/src/mocks/BidBatcher.sol`

Legacy compatibility contracts remain in `evm/src/PathMinter.sol` and
`evm/src/PathMinterAdapter.sol`, but they are not part of the public issuance
path for new deploy bundles.

## Hardhat

```bash
cd evm
npm install
npm test
npm run estimate:deploy:cost
```

Override pricing assumptions if needed:

```bash
GAS_PRICE_GWEI=20 ETH_USD=3000 npm run estimate:deploy:cost
```

The estimator reports deployment/finalization gas and separate measured rows
for Spark role setup, issuer invitation, and recipient-paid claim.

## PATH Artifact Preview

Generate and verify exact token artwork snapshots from the current contracts:

```bash
npm run preview:generate
npm run preview:verify
```

Then open `preview/index.html`. The static viewer renders embedded
`PathNFT.tokenURI` images and needs no live RPC or frontend font.

Build and verify an address-free downstream release bundle:

```bash
npm run artifacts:downstream -- --tag v0.4.2
npm run artifacts:verify -- --tag v0.4.2
```

Versioned bundles are written under `../releases/<tag>/`. Network addresses
must come from a separately verified deployment release.

## Local Devnet (ETH Payment)

The local scripts deploy a full ETH-settled stack:

- `PathNFT`
- `PathPulseAdapter`
- `PulseAuction` (`paymentToken = address(0)`)

In one terminal:

```bash
cd evm
npm run node
```

In another terminal:

```bash
cd evm
npm run deploy:local:eth
npm run smoke:local:eth
npm run scenario:local:eth
```

Optional deploy parameter overrides (constructor inputs):

- Environment variables (`DEPLOY_*`)
- npm run args (`--deploy-*`), which map to script params
- JSON params file (`DEPLOY_PARAMS_FILE=...` or `--deploy-params-file=...`)

Precedence: npm args (`--deploy-*`) > env vars > params file > built-in defaults.

Launch time inputs:

- Preferred for formal launch: set absolute unix timestamp with `--deploy-open-time` or `DEPLOY_OPEN_TIME`.
- Local/testing convenience: `--deploy-start-delay-sec` / `DEPLOY_START_DELAY_SEC` is still supported and is converted to `openTime = latestBlock.timestamp + startDelaySec` (with a one-second minimum lead so `0` opens on the next block). If omitted on local networks, the deploy script uses a 60-second delay so wiring and freezes complete before open.
- Do not set both `openTime` and `startDelaySec` in the same deployment config.

Examples:

```bash
# Override by env vars
DEPLOY_FIRST_PUBLIC_ID=7 DEPLOY_EPOCH_BASE=7 npm run deploy:local:eth

# Include a Spark pass quota in deploy calldata
DEPLOY_RESERVED_CAP=99 DEPLOY_SPARK_CLAIM_DURATION_SEC=604800 npm run deploy:local:eth

# Override by npm args
npm run deploy:local:eth --deploy-first-public-id=7 --deploy-epoch-base=7 --deploy-name="PATH"

# Mainnet-style explicit launch time (unix seconds, UTC)
DEPLOY_OPEN_TIME=1767225600 npm run deploy:local:eth

# Override via params file
cat > /tmp/path.deploy.local.json <<'JSON'
{
  "name": "PATH",
  "symbol": "PATH",
  "openTime": "1767225600",
  "firstPublicId": "1",
  "epochBase": "1",
  "reservedCap": "99",
  "sparkClaimDurationSec": "604800",
  "thoughtMinter": "0x3333333333333333333333333333333333333333",
  "willMinter": "0x4444444444444444444444444444444444444444",
  "awaMinter": "0x5555555555555555555555555555555555555555",
  "genesisPrice": "1000",
  "genesisFloor": "900",
  "k": "600",
  "pts": "1",
  "paymentToken": "0x0000000000000000000000000000000000000000"
}
JSON
DEPLOY_PARAMS_FILE=/tmp/path.deploy.local.json npm run deploy:local:eth
```

Outputs:

- deployment metadata: `evm/deployments/localhost-eth.json`
- cascade scenario report: `evm/deployments/reports/localhost-path-cascade-eth-report.json`
- guided rehearsal: `docs/evm/localnet-rehearsal.md`

## Notes

- `PathNFT.tokenURI` returns on-chain metadata as a data URL: `data:application/json;base64,<...>`, with embedded image at `image = data:image/svg+xml;base64,<...>`.
- The token image is the canonical centered `THOUGHT WILL AWA` status line. It uses exact Inshell Mono 76 Regular `400` v0.1.0 native SVG paths, fills remaining progress with `#ffffff`, and clips consumed progress left-to-right with `#00ff35`.
- Only the nine required glyphs are embedded. `glyphs/inshell-mono-76-path-400.json` is the pinned source slice and `src/InshellMono76PathGlyphs.sol` is generated from it; `npm run glyphs:check` rejects path or provenance drift before compile/test.
- The root SVG records the font release commit, package manifest hash, source glyph JSON hash, and PATH glyph-slice hash. No full font file or runtime font dependency is deployed.
- `PathNFT` emits EIP-4906 `MetadataUpdate(tokenId)` on progression and `BatchMetadataUpdate(0, type(uint256).max)` when movement configuration changes.
- `PathNFT.contractURI` is available for optional contract-level collection metadata.
- `PathNFT.allowSparker(recipient, name)` lets a `RESERVED_ROLE` holder reserve one Spark slot and immutable display name for a recipient. That recipient pays gas to self-mint with `mintSparker(expectedNameHash, data)` before the deploy-time claim duration expires. Spark IDs start at `SPARK_BASE = 1_000_000_000_000_000`.
- Spark PATH tokens implement ERC-5192 and are permanently non-transferable awards. Regular PATH tokens remain transferable.
- This EVM stack has no separate renderer contract.

## Publish-Ready Invariants

Constructor params:

- `name` / `symbol`: marketplace-facing collection identity. The contract uses `PATH`; UI copy may render `$PATH`.
- `baseUri`: optional fallback base URI. The current marketplace path relies on on-chain data URLs.
- `reservedCap`: deploy-time Spark pass quota. Use `99` for the historical Spark quota when preparing that launch calldata.
- `sparkClaimDurationSec`: mandatory deploy-time Spark claim window in seconds. The current example uses `604800` (7 days).
- `thoughtMinter` / `willMinter` / `awaMinter`: mandatory nonzero movement-contract addresses on serious networks. Local deployment defaults them to the local deployer for rehearsal only.
- `admin`: direct Ledger-backed admin authority. On Sepolia this is `SEPOLIA_ADMIN_HW_A`.
- `openTime`: preferred formal launch input, unix seconds UTC. Do not combine with `startDelaySec`.
- `startDelaySec`: rehearsal convenience input that scripts convert to `openTime`.
- `k`, `genesisPrice`, `genesisFloor`, `pts`: Pulse pricing constants.
- `firstPublicId` / `epochBase`: token/epoch alignment constants.
- `paymentToken`: zero address for ETH.
- `treasury`: payment recipient. On Sepolia this must be the Safe address, not the Safe owner EOA.
- `treasurySignerRef`: on Sepolia this must be `SEPOLIA_TREASURY_SAFE_1OF1`.

Role and freeze model:

- `PathNFT.freezePublicMinter(expectedMinter)` is one-way and locks public minting to `PathPulseAdapter`.
- `PathNFT.safeMint` / `safe_mint` only mint public token IDs below `SPARK_BASE`.
- `PathNFT.RESERVED_ROLE` can call `allowSparker(recipient, name)`. This immediately moves one slot from available to pending and sets the invitation expiry to `block.timestamp + sparkClaimDuration`.
- The recipient reads `getSparkInvitation(recipient)`, confirms the immutable name, and calls `mintSparker(keccak256(bytes(name)), data)` from that wallet to mint and pay gas. The mint uses `SPARK_BASE + serial`.
- `getReservedRemaining()` reports available, unallocated slots. `getReservedPending()` reports slots held by active invitations. A claim permanently consumes a pending slot; `revokeSparker` or permissionless `releaseExpiredSparker` returns it to available capacity.
- `PathPulseAdapter.freezeWiring()` is one-way and locks its `PulseAuction` / `PathNFT` endpoints.
- `PulseAuction.mintAdapter` is the only public sale settlement caller and must point at `PathPulseAdapter`.
- The canonical deployment flow configures quotas `THOUGHT=1`, `WILL=10`, and `AWA=1` against the three supplied minter addresses, then explicitly freezes all three before auction wiring and authority handoff.
- Outside the canonical deployment flow, movement config remains one-way per movement: it can be explicitly frozen by admin or implicitly frozen on first successful consume.

Irreversible actions:

- Public PATH mint creates an ERC-721 token and cannot be undone by protocol code.
- Spark PATH self-claim creates a permanently locked ERC-721 award and cannot be undone by protocol code. The Spark quota is bounded by `reservedCap`; pending invitations reserve capacity and expired or revoked invitations release it.
- `consumeUnit` consumes one movement unit, advances movement progress/stage, increments the owner nonce, emits `MetadataUpdate`, and cannot be replayed.
- Public minter, adapter wiring, and frozen movement configs cannot be changed after freeze.

Secondary transfer and permission authorization:

- Regular PATH remains ERC-721 transferable. Spark PATH is permanently non-transferable and reports `locked(tokenId) = true` through ERC-5192. Movement progress and remaining quota stay attached to `tokenId` in both cases.
- Only the current `ownerOf(pathId)` may sign movement-consume authorization. ERC-721 token approvals and `setApprovalForAll` authorize transfer only; they do not grant movement-consume rights.
- Every successful non-mint regular PATH transfer, including a self-transfer, increments `getPermissionEpoch(pathId)` and emits `PermissionEpochAdvanced`. Spark transfer attempts revert and cannot advance the epoch.
- Consume signatures bind the current permission epoch. A signature created before a transfer cannot be used after that transfer or revived by transferring PATH back to the previous owner.
- Movement tokens already minted from PATH remain owned by their existing owners when PATH is transferred.

Metadata and indexer expectations:

- `tokenURI` is self-contained JSON with embedded SVG.
- Spark `tokenURI.description` uses the permanent acknowledgment and invitation-to-create language; regular PATH retains the permission-token description.
- The token SVG contains no browser-font dependency, `<text>`, external image, or off-chain renderer call.
- Rendering remains movement-agnostic beyond the three fixed PATH movements: each word's clip width is derived from its on-chain `minted / quota` state.
- `contractURI` is self-contained collection metadata.
- `attributes` keep stable trait names: `Stage`, `THOUGHT`, `WILL`, and `AWA`.
- Frontends should use `PathNFT.isSparker(tokenId)` to identify Spark tokens and ERC-5192 `locked(tokenId)` for transferability instead of hard-coding a token-ID threshold.
- `sparkName(tokenId)` returns the immutable issuer-supplied name for a Spark token. Spark metadata uses `PATH Spark #<serial>: <name>` as its top-level name, where `serial = tokenId - SPARK_BASE + 1` is an unpadded decimal. The ERC-721 token ID remains unchanged, and no `Spark` or `Name` trait is added.
- ERC-5192 mint signaling emits `Locked(tokenId)` for Spark PATH and `Unlocked(tokenId)` for regular PATH.
- `MetadataUpdate(tokenId)` is emitted on every movement consume. Marketplaces that do not honor EIP-4906 may require manual metadata refresh.
- `MovementConsumed(pathId,movement,claimer,serial)` is the canonical movement-consumption event.

Deploy-time assumptions:

- Sepolia treasury uses Safe custody: `safeAddress=0xE524EDf82c2D0d8243eE4fF21FB020Bd8b45D47F`, `treasurySignerRef=SEPOLIA_TREASURY_SAFE_1OF1`, `threshold=1`, owner ref `SEPOLIA_TREASURY_HW_A`.
- Sepolia ADMIN remains the direct Ledger-backed `SEPOLIA_ADMIN_HW_A`.
- Sepolia deploy has no normal post-deploy handoff of ADMIN or treasury; deploy scripts must freeze the public mint path instead.
- Safe-backed deploy bundles must include verified `treasury_safe.json` evidence in the immutable bundle manifest.

## Marketplace Metadata Contract

`PathNFT` metadata is intended to be enough for generic NFT marketplaces:

- `name`: `PATH #<tokenId>` for regular PATH; `PATH Spark #<serial>: <issuer-supplied name>` for Spark, with unpadded `serial = tokenId - SPARK_BASE + 1`
- `description`: protocol-level PATH description
- `image`: embedded SVG data URL
- `image_data`: same SVG inline for clients that prefer raw SVG
- `attributes`: stable traits `Stage`, `THOUGHT`, `WILL`, `AWA`

Progress traits currently use `Minted(x/y)` for every movement. If a movement is not configured yet, its quota is `0`, so the raw on-chain value is `Minted(0/0)`.

Marketplace refresh depends on the marketplace. The contract emits EIP-4906 `MetadataUpdate(tokenId)` on every successful movement consume; marketplaces that honor EIP-4906 can refresh automatically, while others may need manual refresh.

Spark and regular PATH tokens share this collection metadata surface. Generic
marketplaces can classify Spark through `isSparker`, discover permanent locking
through ERC-5192 `locked`, and display the Spark name from the top-level metadata
`name`. The stable trait list remains unchanged.
