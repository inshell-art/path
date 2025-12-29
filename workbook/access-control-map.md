# Access Control Map (PulseAuction + Path)

This is the control/authority map across PulseAuction, PathMinterAdapter, PathMinter, and PathNFT.
It focuses on who can call what, and which roles/owners gate those calls.

## Quick diagram (roles + calls)

```
             [Admin / Owner]
                 |   \
                 |    \ (Ownable)
                 |     -> PathMinterAdapter.set_auction / set_minter
                 |
                 | (AccessControl)
                 +-> PathNFT grants MINTER_ROLE to PathMinter
                 +-> PathMinter grants SALES_ROLE to PathMinterAdapter

User
  |
  v
PulseAuction.bid(...)
  |
  v
PathMinterAdapter.settle(...)   [require msg.sender == auction]
  |
  v
PathMinter.mint_public(...)     [require SALES_ROLE]
  |
  v
PathNFT.safe_mint(...)          [require MINTER_ROLE]
  |
  v
PathNFT token minted + stage=0

MovementMinter (authorized via PathNFT admin)
  |
  v
PathNFT.consume_movement_unit(...)   [caller == authorized minter, claimer is tx sender + owner/approved]
  |
  v
PathNFT stage advanced

Sparker (reserved mint)
  |
  v
PathMinter.mint_sparker(...)    [requires RESERVED_ROLE]
  |
  v
PathNFT.safe_mint(...)          [requires MINTER_ROLE]
```

## Control primitives used

- AccessControl (OpenZeppelin): role-based. `DEFAULT_ADMIN_ROLE` is granted in constructor to the
  provided admin address. That admin can grant/revoke roles unless role admins are customized
  (not used here).
- Ownable (OpenZeppelin): single `owner` set in constructor. Only owner can call `only_owner`-gated
  functions.

## Per-contract control model

### PulseAuction
- No AccessControl, no Ownable.
- Anyone can `bid(...)` when the auction is open and rules are satisfied.
- Uses immutable constructor config, including `mint_adapter` (PathMinterAdapter address).
- Calls `mint_adapter.settle(buyer, data)` during `bid`.

### PathMinterAdapter (Ownable)
- Ownable: `owner` set in constructor.
- Admin functions (owner-only):
  - `set_auction(auction)`
  - `set_minter(minter)`
- Runtime gate:
  - `settle(...)` asserts `msg.sender == auction`.
- Forwards `settle` to `PathMinter.mint_public(...)`.

### PathMinter (AccessControl)
- `DEFAULT_ADMIN_ROLE` set in constructor via `admin` parameter.
- Roles:
  - `SALES_ROLE`: required for `mint_public`.
  - `RESERVED_ROLE`: required for `mint_sparker`.
- Calls `PathNFT.safe_mint(...)`.
- Must hold `MINTER_ROLE` on PathNFT for `safe_mint` to succeed.

### PathNFT (AccessControl + movement minter map)
- `DEFAULT_ADMIN_ROLE` set in constructor via `initial_admin` parameter.
- Roles:
  - `MINTER_ROLE`: required for `safe_mint`.
- Admin-only setters (DEFAULT_ADMIN_ROLE):
  - `set_path_look(path_look)`
  - `set_authorized_minter(movement, minter)`
- Movement gating (not AccessControl):
  - `consume_movement_unit(...)` requires caller == `authorized_minter[movement]`,
    `claimer == tx sender`, and `claimer` must be owner/approved for the PathNFT token.
- Stage is advanced inside PathNFT when `consume_movement_unit` succeeds.

## Orchestration path (typical sale)

1) Deploy contracts with chosen admin/owner addresses:
   - PulseAuction(mint_adapter = PathMinterAdapter)
   - PathMinterAdapter(owner = admin)
   - PathMinter(admin = admin)
   - PathNFT(initial_admin = admin)

2) Wire roles/config:
   - PathNFT admin grants `MINTER_ROLE` to PathMinter.
   - PathMinter admin grants `SALES_ROLE` to PathMinterAdapter.
   - PathMinterAdapter owner sets `auction = PulseAuction` and `minter = PathMinter`.

3) Sale flow:
   - User calls `PulseAuction.bid(max_price)`.
   - PulseAuction calls `PathMinterAdapter.settle(buyer, data)`.
   - Adapter checks `msg.sender == auction` then calls `PathMinter.mint_public`.
   - PathMinter checks `SALES_ROLE` and calls `PathNFT.safe_mint`.
   - PathNFT checks `MINTER_ROLE`, mints token, sets stage = 0 (THOUGHT active).

## Notes
- There is no PathNFT adapter in this repo.
- Movement minters are registered in PathNFT via `set_authorized_minter`; they are distinct from
  the minting flow and are used to advance stage through `consume_movement_unit`.
