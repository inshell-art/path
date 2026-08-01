# PATH v0.4.2 Downstream Handoff

## Pin

Consume the repository at tag `v0.4.2`. The canonical integration artifacts are:

- `releases/v0.4.2/abi/PathNFT.json`
- `releases/v0.4.2/abi/PathPulseAdapter.json`
- `releases/v0.4.2/abi/PulseAuction.json`
- `releases/v0.4.2/hardhat/*.json` for ABI plus bytecode
- `releases/v0.4.2/manifest.json` and `SHA256SUMS.txt` for verification

This bundle contains no network addresses. Import addresses only from a separately
verified deployment release for the target chain.

## Compatibility

This release adds the in-repository exact-artifact preview and downstream bundle.
The three canonical contract ABIs and bytecode are unchanged from `v0.4.1`.
No redeployment is required solely for the preview or packaging change.

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
- The preview uses quotas `1 / 10 / 1` as a concrete inspection fixture; read
  deployed movement quotas from `getMovementQuota(bytes32)` in production.
- Classify Spark tokens with `isSparker(tokenId)`. Spark is intentionally not a
  metadata trait and consumers should not infer it from an unpinned raw threshold.
- Spark recipients self-claim with `mintSparker(bytes)` after `RESERVED_ROLE`
  calls `allowSparker(address)`, and before `sparkAllowanceExpiresAt(address)`.

## Renderer

The PATH image is self-contained native SVG. It embeds only the nine Inshell Mono
76 glyph paths required for `THOUGHT WILL AWA`; no font installation, webfont,
off-chain renderer, or frontend text substitution is required.

Open `evm/preview/index.html` from this tag to inspect eight exact `tokenURI`
states. Regenerate it after contract renderer changes with:

`npm run evm:preview:generate`

## Verification

From the repository root:

`npm run evm:artifacts:verify -- --tag v0.4.2`

The verifier checks every bundle checksum, ABI-to-artifact equality, bytecode
hashes, and the PathNFT artifact hash used to generate the exact preview snapshot.
