# PATH + Pulse (EVM) Cascade Testing Spec

## Goal

Validate that the Solidity PATH stack preserves the same critical behavior as Cairo:

- Auction timing and cascade curve mechanics.
- Auction-to-adapter-to-minter-to-NFT settlement chain.
- PATH movement progression constraints.

## Scope

1. `PathNFT` invariants

- Role gates (`MINTER_ROLE`, admin-only config).
- Mint/burn/approval behavior.
- Movement consumption rules:
  - authorized minter only
  - claimer checks
  - owner/approval checks
  - movement order (`THOUGHT -> WILL -> AWA`)
  - quota progression and stage transitions
  - movement freeze behavior
- `tokenURI` returns `baseUri + tokenId`.

2. `PathMinter` invariants

- `SALES_ROLE` and `RESERVED_ROLE` enforcement.
- Public IDs increment sequentially.
- Reserved IDs count down from `2^256 - 2`.
- Reserved pool exhaustion reverts.
- Downstream NFT mint revert rolls back `nextId`.

3. `PathMinterAdapter` invariants

- Owner-only config updates.
- Non-zero config validation.
- `settle` callable only by registered auction.
- `settle` forwards buyer/data and returns minted ID.

4. Integrated ETH cascade (`PulseAuction`)

- Cannot bid before open time.
- Genesis bid activates curve and mints token 0.
- Subsequent bids mint sequential token IDs.
- Ask price follows hyperbolic model over time.
- One-bid-per-block guard works.
- Stress test with 20 sequential bids remains stable.

## Test Files

- `evm/test/pathNft.behavior.test.js`
- `evm/test/pathMinter.behavior.test.js`
- `evm/test/pathMinterAdapter.behavior.test.js`
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
