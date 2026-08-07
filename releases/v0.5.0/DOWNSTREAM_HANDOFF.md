# PATH v0.5.0 Downstream Handoff

## Pin

Consume the repository at tag `v0.5.0`. The canonical integration artifacts are:

- `releases/v0.5.0/abi/PathNFT.json`
- `releases/v0.5.0/abi/PathPulseAdapter.json`
- `releases/v0.5.0/abi/PulseAuction.json`
- `releases/v0.5.0/hardhat/*.json` for ABI plus bytecode
- `releases/v0.5.0/manifest.json` and `SHA256SUMS.txt` for verification

This bundle contains no network addresses. Import addresses only from a separately
verified deployment release for the target chain.

## Compatibility

This release changes the `PathNFT` ABI, bytecode, and consume-authorization
payload relative to `v0.4.2`. A new `PathNFT` deployment is required; do not
point this ABI or signing code at an older deployment. Import all addresses from
the separately verified deployment release for the target chain.

The Solidity arguments to `consumeUnit` are unchanged. Its signed EIP-191
struct now includes `permissionEpoch` between `executor` and `nonce`.
Old signing code fails with the `BadConsumeAuthorization()` custom error. PATH-specific
reverts are typed custom errors in this release; decode them from the release ABI.

The manifest distinguishes the Hardhat runtime template hash from the preview's
deployed-instance runtime hash. `PathNFT` has constructor immutables, so deployed
runtime hashes vary with constructor values even when the source artifact matches.

The public issuance path remains:

`PulseAuction -> PathPulseAdapter -> PathNFT.safeMint`

Do not use legacy `PathMinter` or `PathMinterAdapter` for new integrations.

## PATH NFT Integration

- Collection name and symbol are both `PATH`.
- Read `tokenURI(tokenId)`, decode its JSON data URL, and render the embedded
  `image` SVG data URL directly. Do not rebuild the token image in the frontend.
- Stable traits are `Stage`, `THOUGHT`, `WILL`, and `AWA`.
- Movement order is fixed: THOUGHT, WILL, AWA.
- Regular PATH remains ERC-721 transferable. Spark PATH is a permanently locked
  ERC-5192 award. Progress and remaining quota stay attached to the token ID.
- Only the current `ownerOf(pathId)` may sign movement authorization. ERC-721
  token approvals and operators have transfer rights only.
- Read `getPermissionEpoch(pathId)` before signing. Every successful non-mint
  regular PATH transfer increments the epoch and emits `PermissionEpochAdvanced`,
  invalidating older signatures even if the PATH later returns to the same owner.
- Movement tokens minted before a PATH transfer remain with their existing owners.
- The canonical deploy flow configures and freezes quotas `1 / 10 / 1` before
  auction wiring. Still read deployed movement quotas from
  `getMovementQuota(bytes32)` rather than hard-coding them in clients.
- Classify Spark tokens with `isSparker(tokenId)`. Spark is intentionally not a
  metadata trait and consumers should not infer it from an unpinned raw threshold.
- Read ERC-5192 `locked(tokenId)` for transferability. Spark returns `true`;
  regular PATH returns `false`. Mint logs emit `Locked` for Spark and
  `Unlocked` for regular PATH.
- `RESERVED_ROLE` creates an invitation with `allowSparker(recipient, name)`.
  It reserves one slot immediately. Read it with `getSparkInvitation(recipient)`.
- The recipient confirms the returned name, hashes its exact UTF-8 bytes, and calls
  `mintSparker(expectedNameHash, data)` before expiry. Read the minted immutable
  value with `sparkName(tokenId)`. The top-level metadata name is
  `PATH Spark #<serial>: <name>`, where the unpadded decimal
  `serial = tokenId - SPARK_BASE + 1`; the ERC-721 token ID remains unchanged.
- Spark metadata uses the permanent acknowledgment and invitation-to-create
  description; regular PATH retains the permission-token description.
- `getReservedRemaining()` is available capacity and `getReservedPending()`
  is invitation-held capacity. `revokeSparker` or permissionless
  `releaseExpiredSparker` returns a pending slot; a successful claim consumes it.
- Spark names are 1-31 printable ASCII bytes, excluding quote and backslash, with
  no leading or trailing spaces. No `Spark` or `Name` metadata trait is added.

Frontend implementers must follow
`docs/evm/PATH_REMAINING_ENTITLEMENT_FE_HANDOFF.md`, including the exact signed
field order and the pre-purchase `Remaining entitlement` display.

## Renderer

The PATH image is self-contained native SVG. It embeds only the nine Inshell Mono
76 glyph paths required for `THOUGHT WILL AWA`; no font installation, webfont,
off-chain renderer, or frontend text substitution is required.

Open `evm/preview/index.html` from this tag to inspect eight exact `tokenURI`
states. Regenerate it after contract renderer changes with:

`npm run evm:preview:generate`

## Verification

From the repository root:

`npm run evm:artifacts:verify -- --tag v0.5.0`

The verifier checks every bundle checksum, ABI-to-artifact equality, bytecode
hashes, and the PathNFT artifact hash used to generate the exact preview snapshot.
