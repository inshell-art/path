# EVM Tasks

Tracking open follow-ups discovered during local rehearsal and contract walkthrough.

## Task EVM-001: Adapter API naming cleanup (ethers v6 DX)

- Status: completed, superseded for new deployments by `PathPulseAdapter`
- Priority: medium
- Area: legacy `evm/src/PathMinterAdapter.sol`, `evm/src/interfaces/IPulseAdapter.sol`, docs

### Problem

`PathMinterAdapter` had ambiguous naming around `target`. In ethers v6, contract instances also expose a built-in `.target` address property, which causes confusion in scripts/console usage.

### Why this matters

- Reduces operator confusion during rehearsals/debugging.
- Makes scripts/console snippets less error-prone.
- Preserves backward compatibility while improving developer ergonomics.

### Acceptance criteria

- Explicit role-aware getters exist (`getAuthorizedAuction`, `getMinterTarget`).
- Legacy `target()` is removed from adapter interface/implementation.
- Docs updated (`docs/evm/localnet-rehearsal.md` and relevant references).
- Smoke-level call check uses explicit getters only.

### Implementation summary

1. Added `getAuthorizedAuction()` and `getMinterTarget()` to `PathMinterAdapter`.
2. Removed `target()` from `IPulseAdapter` and `PathMinterAdapter`.
3. Updated adapter behavior tests to validate explicit getters only.
4. Updated smoke checks in `evm/scripts/smoke-local-eth.js` to use explicit getters only.
5. Updated rehearsal/testing docs to prefer explicit getters.

## Walkthrough Checkpoint

- Scope: contract-by-contract EVM familiarization after `PulseAuction`.
- Current position: post-walkthrough follow-ups implemented (`EVM-001`..`EVM-004`).
- Next walkthrough step: monitor integration stability and gather downstream feedback for any follow-on refinements.

## Task EVM-002: Hard on-chain coupling for `epochIndex` and public `tokenId`

- Status: completed, superseded for new deployments by direct `PathPulseAdapter`
- Priority: medium
- Area: legacy `evm/src/PathMinterAdapter.sol`, `evm/src/PathMinter.sol`, current `evm/src/PathPulseAdapter.sol`, interfaces, tests/docs

### Problem

`epochIndex` (auction sale counter) and public `tokenId` are currently correlated by flow, but not enforced by contract-level invariant. Alignment can drift if `mintPublic` is called outside auction flow.

### Implementation summary

1. Kept `PulseAuction` upstream and token-id agnostic; coupling is enforced in the settlement adapter.
2. Added adapter bases: `tokenBase` and `epochBase` with mapping:
   `tokenId = tokenBase + (epochIndex - epochBase)`.
3. Adapter now derives current settlement epoch via `auction.getEpochIndex() + 1` and verifies the forwarded epoch matches.
4. New `PathPulseAdapter` mints the expected token id directly into `PathNFT`; legacy `PathMinterAdapter` checked `minter.nextId()`.
5. Added explicit adapter errors/events for drift detection:
   `EpochMismatch`, `EpochBeforeBase`, `MintIdMismatch`, `EpochMinted`.
6. Extended tests with a stub auction caller to validate happy path and all coupling failure modes.

## Task EVM-004: Remove public `burn()` from `PathNFT`

- Status: completed
- Priority: high
- Area: `evm/src/PathNFT.sol`, `evm/src/interfaces/IPathNFT.sol`, `evm/test/pathNft.behavior.test.js`

### Problem

Public `burn(tokenId)` provides a destructive end-user action without movement-system benefit and increases operational risk.

### Decision

Remove `burn()` from the EVM `PathNFT` public interface and contract implementation.

### Applied changes

1. Deleted `burn(uint256 tokenId)` from `IPathNFT`.
2. Deleted `burn(uint256 tokenId)` public function from `PathNFT`.
3. Removed burn behavior test coverage from `pathNft.behavior.test.js`.

### Result

- PATH NFTs can no longer be burned via `PathNFT`.
- `approve` / `balanceOf` remain standard inherited ERC-721 behavior.

## Task EVM-005: Recover Spark pass minting on `PathNFT`

- Status: completed
- Priority: high
- Area: `evm/src/PathNFT.sol`, `evm/src/interfaces/IPathNFT.sol`, deploy/export scripts, tests/docs

### Decision

Recover Spark using the later `SPARK_BASE` model, not the original `type(uint256).max - 1`
descending token-ID model.

### Applied changes

1. Added `PathNFT.SPARK_BASE = 1_000_000_000_000_000`.
2. Added deploy-time `reservedCap`, deploy-time `sparkClaimDurationSec`, `getReservedCap()`, `getReservedRemaining()`, and `getReservedPending()`.
3. Added `RESERVED_ROLE`-gated `allowSparker(address,string)`, which reserves one slot and immutable name for a recipient's time-limited self-claim window.
4. Added recipient-paid `mintSparker(bytes32,bytes)`, binding the claim to the displayed name and minting IDs as `SPARK_BASE + serial`.
5. Added `isSparker(tokenId)` so downstream clients do not need to classify Spark by a raw high-ID threshold.
6. Reinstated the public token-ID boundary: `safeMint` and `safe_mint` reject IDs at or above `SPARK_BASE`.
7. Added revoke and permissionless expired-invitation cleanup so pending capacity returns to the reserved pool without overbooking.
8. Added permanent ERC-5192 locking for Spark while keeping regular PATH transferable.
9. Added ERC-5192 `Locked` / `Unlocked` mint signaling and a Spark-specific acknowledgment and invitation-to-create metadata description.
10. Canonical deployment now configures and explicitly freezes `THOUGHT=1`, `WILL=10`, and `AWA=1` before auction wiring.
11. Movement configuration emits collection-wide ERC-4906 `BatchMetadataUpdate` for indexer refresh.

### Result

- Spark quota is deployment calldata, so the historical quota `99` can be supplied per deploy.
- Public PATH issuance remains `PathPulseAdapter -> PathNFT.safeMint`.
- Spark issuance is separate from `MINTER_ROLE`; issuers reserve named invitations, recipients confirm the name and self-claim while paying gas, and available plus pending plus minted supply remains equal to the deploy-time reserved cap.
