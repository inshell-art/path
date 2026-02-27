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

## Task EVM-003: Refactor Sparker ID domain to `SPARK_BASE`

- Status: completed
- Priority: medium
- Area: `evm/src/PathMinter.sol`, `evm/src/PulseAuction.sol`, interfaces/tests/docs

### Proposal

Use bounded reserved/public ID domains:

- `SPARK_BASE = 1_000_000_000_000_000` (`1e15`)
- `sparkSerial = reservedCap - reservedRemaining` (`0,1,2,...`)
- `sparkTokenId = SPARK_BASE + sparkSerial`
- public safety bound: enforce public stream stays below `SPARK_BASE`
- classification helper: `isSpark(tokenId) = tokenId >= SPARK_BASE`

### Risks / constraints to address

1. Enforce collision guard in the right place:
   - `require(nextId < SPARK_BASE)` in minter public mint path is stronger than only checking auction state.
   - If coupling task `EVM-002` lands, align guard with the final public ID source (`expectedId`/`nextId`).
2. Explicit fail mode at cap:
   - define behavior once public IDs reach `SPARK_BASE - 1` (revert reason, ops runbook, monitoring).
3. Migration compatibility:
   - existing deployments with already-minted high sparker IDs cannot be remapped.
   - treat as new deployment/versioned rollout unless no reserved mints exist yet.
4. Off-chain assumptions:
   - indexers/analytics that assumed max-range sparker IDs must be updated.

### Why this matters

- Makes sparker IDs human-sized and easier to reason about.
- Maintains deterministic domain separation between public and reserved IDs.
- Enables simple type checks (`tokenId >= SPARK_BASE`) for downstream tooling.

### Acceptance criteria

- `mintSparker` mints `SPARK_BASE + serial` in ascending order.
- Public mint path reverts before reaching `SPARK_BASE`.
- No public/reserved ID overlap is possible on-chain.
- Tests cover boundary cases (`SPARK_BASE - 1`, `SPARK_BASE`, first/last reserved serial).
- Docs and scripts reflect `SPARK_BASE` semantics and `isSpark` rule.

### Implementation summary

1. Added `SPARK_BASE = 1_000_000_000_000_000` in `PathMinter`.
2. Changed `mintSparker` to mint `SPARK_BASE + mintedSoFar` (ascending serial).
3. Added public-domain guard in mint paths: revert `PUBLIC_ID_DOMAIN_EXHAUSTED` when `nextId >= SPARK_BASE`.
4. Extended minter tests to cover:
   - `SPARK_BASE` boundary (`SPARK_BASE - 1` succeeds, `SPARK_BASE` reverts),
   - first/next/last reserved serial behavior,
   - domain separation invariants.
5. Updated rehearsal/testing docs for new reserved/public ID semantics.

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
