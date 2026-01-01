# Path + Pulse + Inshell.art Overview

## What this doc covers

- The Path contracts and their roles
- Pulse auction contract behavior
- How Path and Pulse wire together
- How inshell.art reads and renders the system

## Contracts and responsibilities

### Path core

- `PathNFT`
  - ERC-721 collection for PATH tokens.
  - Stores per-token progression state: `stage`, `stage_minted`.
  - Stores global movement configuration: `movement_quota`, `movement_frozen`, `authorized_minter`.
  - `safe_mint` is gated by `MINTER_ROLE` and initializes stage state for new tokens.
  - `token_uri` delegates rendering to PathLook and returns a JSON data URI.

- `PathMinter`
  - Shared minting proxy for `PathNFT`.
  - Public mint entrypoint `mint_public` is gated by `SALES_ROLE`.
  - Reserved mint entrypoint `mint_sparker` is gated by `RESERVED_ROLE`.
  - Tracks the next sequential token id (and a separate reserved pool).

- `PathMinterAdapter`
  - Ownable adapter that connects a sales engine to `PathMinter`.
  - Holds the registered `auction` and `minter` addresses.
  - `settle` is callable only by the registered auction; it calls `PathMinter.mint_public`.

### Path look + glyph deps

- `PathLook`
  - Stateless renderer that builds SVGs and metadata on demand.
  - Reads PATH state from `PathNFT` (`stage`, `stage_minted`, movement quotas).
  - Uses two glyph contracts for visuals:
    - `PPRF` for deterministic randomness (seeded by token id).
    - `StepCurve` for generating curve path data via `IGlyph` interface.
  - Exposes `generate_svg`, `generate_svg_data_uri`, and `get_token_metadata`.

- `PPRF` and `StepCurve`
  - Deployed alongside PathLook as its dependencies.
  - StepCurve is called through the `IGlyph` interface.

### Pulse auction

- `PulseAuction` (vendor contract)
  - Hyperbolic pricing curve auction.
  - `get_current_price`, `get_config`, and `get_state` are view helpers for the UI.
  - `bid(max_price)` executes the sale if the ask is within the caller's max.
  - Enforces one bid per block and a genesis bid that activates the curve.
  - Emits `Sale` events with buyer, token id, price, timestamps, and curve state.

## Access control summary

- `PathNFT`
  - `DEFAULT_ADMIN_ROLE` can set `path_look` and configure movement rules.
  - `MINTER_ROLE` can call `safe_mint`.
  - Movement minters are stored per movement via `set_movement_config` and enforced by `consume_unit`.

- `PathMinter`
  - `DEFAULT_ADMIN_ROLE` manages roles.
  - `SALES_ROLE` can call `mint_public` (normally the adapter).
  - `RESERVED_ROLE` can call `mint_sparker`.

- `PathMinterAdapter`
  - `Ownable` for admin updates (set auction, set minter).
  - Only the registered auction can call `settle`.

## How the contracts work together

### A. Bid -> Mint

1. A bidder calls `PulseAuction.bid(max_price)`.
2. The auction checks `open_time`, one-bid-per-block guard, and computes the ask.
3. Funds are transferred and the auction calls `PathMinterAdapter.settle(buyer, data)`.
4. The adapter validates the caller (must be the auction) and calls `PathMinter.mint_public`.
5. `PathMinter` calls `PathNFT.safe_mint`, which mints the token and initializes stage state.

### B. token_uri -> PathLook

1. The UI calls `PathNFT.token_uri(token_id)`.
2. `PathNFT` calls `PathLook.get_token_metadata(path_nft, token_id)`.
3. `PathLook` reads stage/quota data from `PathNFT`, then generates SVGs and metadata.
4. `PathNFT` returns a `data:application/json,...` response.

### C. Movement consumption

1. A movement minter calls `PathNFT.consume_unit(path_id, movement, claimer)`.
2. `PathNFT` validates:
   - Caller is the configured minter for the movement.
   - `claimer` matches the tx sender.
   - Movement order matches current stage.
   - Quota is available.
3. On success, `stage` and `stage_minted` are updated and events are emitted.

## inshell.art implementation

inshell.art uses Starknet RPC to read the system and render three views:

- Bids tab
  - Reads `PulseAuction` events (Sale) via `getEvents`.
  - Renders bid dots and a popover for amount, bidder, time, plus a small SVG preview.

- Curve tab
  - Reads `PulseAuction.get_config` and `get_state` to compute the hyperbolic curve.
  - Displays the ask line, floor, and timing annotations in a hover popover.

- Look tab
  - Calls `PathNFT.token_uri(token_id)` and decodes the JSON data URI.
  - Displays the SVG and a hover popover of attributes.
  - Bottom bar shows token id and movement progress (THOUGHT, WILL, AWA).

Addresses are loaded from the devnet outputs in `output/addresses.env`, and the look
renderer assumes `PathLook`, `PPRF`, and `StepCurve` are deployed and wired via `PathNFT`.

## Related files

- Path contracts: `contracts/path_nft`, `contracts/path_minter`, `contracts/path_minter_adapter`
- Path look and deps: `contracts/path_look`, `vendors/pprf`, `vendors/step-curve`
- Pulse auction (vendor): `vendors/pulse`
- Frontend: `../inshell.art/src/components/AuctionCanvas.tsx`
