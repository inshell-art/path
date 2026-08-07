# PATH + Pulse (EVM) Cascade Testing Spec

## Goal

Validate that the Solidity PATH stack preserves the critical PATH behavior:

- Auction timing and cascade curve mechanics.
- Auction-to-adapter-to-NFT settlement chain.
- PATH movement progression constraints.

## Scope

1. `PathNFT` invariants

- Role gates (`MINTER_ROLE`, admin-only config).
- Mint/approval behavior.
- Spark pass behavior:
  - deploy-time `reservedCap`
  - deploy-time `sparkClaimDurationSec`
  - `RESERVED_ROLE` gate
  - named invitation, expiry, revoke, and stale-name checks
  - reservation accounting with no overbooking or double release
  - recipient self-claim gas payment and exact-expiry semantics
  - `SPARK_BASE` token domain
  - `isSparker(tokenId)` classification
  - permanent ERC-5192 locking while regular PATH remains transferable
  - `Locked` / `Unlocked` mint signaling
  - immutable Spark metadata name and acknowledgment description with the stable four-trait schema
- Movement consumption rules:
  - authorized minter only
  - claimer checks
  - current-owner authorization and approved-operator consume denial
  - movement order (`THOUGHT -> WILL -> AWA`)
  - quota progression and stage transitions
  - movement freeze behavior
  - collection-wide `BatchMetadataUpdate` on movement configuration changes
- `tokenURI` returns on-chain JSON data URI metadata with the canonical
  Inshell Mono 76 native-path SVG image.
- The renderer contains exactly the nine pinned glyphs required by
  `THOUGHT WILL AWA`; each path and the generated Solidity source must match
  `evm/glyphs/inshell-mono-76-path-400.json`.
- Movement progress changes only the `#00ff35` consumed clip widths over the
  centered `THOUGHT WILL AWA` line; no browser font or off-chain renderer is
  required.

2. `PathPulseAdapter` invariants

- Owner-only config updates.
- Non-zero config validation.
- Explicit getters (`getAuthorizedAuction`, `getPathNftTarget`) mirror wiring.
- `settle` callable only by registered auction.
- `settle` derives `tokenId = tokenBase + (epoch - epochBase)`.
- `settle` calls `PathNFT.safeMint` directly and returns minted ID.

3. Integrated ETH cascade (`PulseAuction`)

- Cannot bid before open time.
- Genesis bid activates curve and mints token 1.
- Subsequent bids mint sequential token IDs.
- Auction remains token-id agnostic; settlement details are adapter responsibilities.
- Ask price follows hyperbolic model over time.
- One-bid-per-block guard works.
- Stress test with 20 sequential bids remains stable.

## Test Files

- `evm/test/pathNft.behavior.test.js`
- `evm/test/pathPulseAdapter.behavior.test.js`
- `evm/test/pathPulse.integration.test.js`

## Local Scenario Validation

Use scripts to validate realistic behavior outside unit tests:

1. `npm run deploy:local:eth`
2. `npm run smoke:local:eth`
3. `npm run scenario:local:eth`

The scenario report includes per-step checks for:

- quote/price match
- treasury payment deltas
- epoch monotonicity
- sale event/state consistency
- minted token owner and token ID sequencing
