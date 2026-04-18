# EVM Tasks

Tracking open follow-ups discovered during local rehearsal and contract walkthrough.

## Task EVM-001: Adapter API naming cleanup (ethers v6 DX)

- Status: completed
- Priority: medium
- Area: `evm/src/PathMinterAdapter.sol`, `evm/src/interfaces/IPulseAdapter.sol`, docs

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

- Status: completed
- Priority: medium
- Area: `evm/src/PathMinterAdapter.sol`, `evm/src/PathMinter.sol`, interfaces, tests/docs

### Problem

`epochIndex` (auction sale counter) and public `tokenId` are currently correlated by flow, but not enforced by contract-level invariant. Alignment can drift if `mintPublic` is called outside auction flow.

### Implementation summary

1. Kept `PulseAuction` upstream and token-id agnostic; coupling is enforced in `PathMinterAdapter`.
2. Added adapter bases: `tokenBase` and `epochBase` with mapping:
   `tokenId = tokenBase + (epochIndex - epochBase)`.
3. Adapter now derives current settlement epoch via `auction.getEpochIndex() + 1` and verifies the forwarded epoch matches.
4. Adapter checks `minter.nextId()` against expected token id before mint and checks returned minted id after mint.
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
