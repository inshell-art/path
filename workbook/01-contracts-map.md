# PATH contracts map (devnet rehearsal)

Short, practical reference for responsibilities, entrypoints, and access control.

## PathNFT (core NFT + movement state)

**Responsibility**
- ERC721 token ownership + metadata.
- Movement progression (THOUGHT → WILL → AWA).
- Stores path_look address for metadata rendering.

**Key entrypoints**
- `safe_mint(to, token_id, data)` — mint token, initializes stage state.
- `burn(token_id)` — owner/badge burn.
- `set_path_look(addr)` — update renderer contract.
- `set_movement_config(movement, minter, quota)` — authorize a movement minter.
- `consume_unit(path_id, movement, claimer)` — consume a movement unit (advances stage).
- `get_stage(token_id)` / `get_stage_minted(token_id)` / `get_movement_quota(movement)`.
- `token_uri(token_id)` — returns `data:application/json,...` using PathLook.

**Access control**
- **Admin actions** (DEFAULT_ADMIN_ROLE): `set_path_look`, `set_movement_config`.
- **Minter actions** (MINTER_ROLE): `safe_mint`.
- **System actions**: `consume_unit` only by the **authorized movement minter** for the movement;
  also checks `claimer == tx.account_contract_address` and ownership approval.
- **User actions**: `burn`, `token_uri`, `get_*` view methods.

---

## PathMinter (mint proxy)

**Responsibility**
- Sequential public minting into PathNFT.
- Reserved mint pool for sparkers.

**Key entrypoints**
- `mint_public(to, data)` — mints next sequential id (returns token id).
- `mint_sparker(to, data)` — mints from reserved pool (descending ids).
- `get_reserved_cap()` / `get_reserved_remaining()`.

**Access control**
- **Admin actions** (DEFAULT_ADMIN_ROLE): role management via AccessControl.
- **Sales actions** (SALES_ROLE): `mint_public`.
- **Reserved actions** (RESERVED_ROLE): `mint_sparker`.

---

## PathMinterAdapter (Pulse → Path bridge)

**Responsibility**
- Bridges PulseAuction settlement to PathMinter.

**Key entrypoints**
- `set_auction(addr)` / `set_minter(addr)` / `get_config()`.
- `settle(buyer, data)` — called by PulseAuction; forwards to PathMinter.mint_public.
- `target()` — returns auction address.

**Access control**
- **Owner actions** (Ownable): `set_auction`, `set_minter`.
- **System actions**: `settle` only callable by the configured auction.

---

## PathLook (renderer)

**Responsibility**
- Derives SVG + metadata from PathNFT state.
- Uses pprf + step_curve glyph contracts.

**Key entrypoints**
- `generate_svg(path_nft, token_id)`
- `generate_svg_data_uri(path_nft, token_id)`
- `get_token_metadata(path_nft, token_id)`

**Access control**
- No admin methods; pure read/compute.

---

## PulseAuction (auction core)

**Responsibility**
- Computes ask via DAA curve.
- Accepts bids, collects payment, calls adapter for delivery.

**Key entrypoints**
- `get_current_price()`
- `get_state()`
- `get_config()`
- `curve_active()`
- `bid(max_price)`

**Access control**
- No admin entrypoints after deploy (config is constructor-only).
- **User action**: `bid`.
- **System action**: calls adapter `settle` internally during bid.

---

## Movement minters (external)

**Responsibility**
- Execute `consume_unit` for one movement when authorized.

**Access control**
- Authorized per movement via `PathNFT.set_movement_config`.
- Must pass: `caller == authorized_minter` and `claimer == tx.account_contract_address`.
