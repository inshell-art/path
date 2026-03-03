# PATH Protocol – EVM Internal Security Review (Pre-Audit)

> Superseded by `docs/reviews/PATH_internal_review_v2.md` for current status (resolved vs open findings).

**Reviewed repo:** `inshell-art/path`  
**Reviewed commit:** `b1c89cfef3747ec545550f47aa05bd09ede8c9df` (GitHub commit page)  
**Review date:** 2026-03-01  
**Reviewer:** GPT-5.2 Pro (AI-assisted internal review)

> This is an internal review intended to surface obvious risks, misconfiguration footguns, and integration assumptions.
> It is **not** a substitute for an independent third‑party audit or a formal verification effort.

---

## 1) Executive summary

### Overall risk
**Medium** (mainly *operational / configuration* risk, not “classic exploits”).

The codebase is relatively small and uses OpenZeppelin primitives; the main risks come from:
- **Irreversible “freeze” behaviors** (sales caller freeze, movement config freeze) that can brick the system if the *first* successful call happens from the wrong address or with the wrong config.
- **Upgradeable/owner-controlled wiring** in the adapter (owner can swap auction/minter).
- **`tx.origin` gating** in `consumeUnit` (intentional anti-relay/anti-contract restriction) that will block some wallet patterns and can surprise integrators.

### Contracts in scope (EVM)
| Contract | Purpose |
|---|---|
| `PathNFT.sol` | ERC‑721 permission token with staged progression (THOUGHT → WILL → AWA → COMPLETE) and on-chain `tokenURI` JSON+SVG. |
| `PathMinter.sol` | Shared mint proxy with two mint streams: public sequential IDs and reserved “sparker” IDs. |
| `PathMinterAdapter.sol` | Pulse adapter that enforces epoch→tokenId coupling and mints PATH via `PathMinter`. |

### External dependency (not pinned in this doc)
- `PulseAuction` is pulled via git submodule `vendors/pulse` (`inshell-art/pulse`). The exact submodule commit should be recorded and reviewed as part of the release bundle.

---

## 2) System overview (how it fits together)

### Minting and settlement flow (public auction path)
1. **PulseAuction** collects payment and calls `adapter.settle(buyer, nextEpochIndex, data)`.
2. **PathMinterAdapter**:
   - checks caller is the configured `auction`
   - checks `epochIndex` matches `auction.getEpochIndex() + 1`
   - derives expected token id: `tokenBase + (epoch - epochBase)`
   - checks `PathMinter.nextId() == expectedId`
   - calls `PathMinter.mintPublic(buyer, data)`
3. **PathMinter** mints the PATH NFT by calling `PathNFT.safeMint(...)`.

### Movement consumption (progression)
- Movement minter contracts (one per stage) call `PathNFT.consumeUnit(pathId, movement, claimer)` to advance counts and stage.
- `consumeUnit` is guarded by:
  - only the configured authorized minter for that movement
  - `claimer == tx.origin`
  - `claimer` is approved/owner for the PATH token
  - movement order is correct and quota not exceeded

---

## 3) Roles, permissions, and “freeze” points

### `PathNFT` roles and config
- `DEFAULT_ADMIN_ROLE` (constructor `initialAdmin`)
  - can call `setMovementConfig(...)`
  - can grant `MINTER_ROLE`
- `MINTER_ROLE`
  - can call `safeMint` / `safe_mint`
- **Movement config freeze**
  - First successful `consumeUnit` for a movement sets `_movementFrozen[movement] = true`.
  - After that, `setMovementConfig` for that movement reverts (`MOVEMENT_FROZEN`).

### `PathMinter` roles and the sales caller freeze
- `DEFAULT_ADMIN_ROLE` (constructor `admin`)
  - can grant `SALES_ROLE` and `RESERVED_ROLE` **until freeze**
- `SALES_ROLE`
  - can call `mintPublic` **only until the first successful public mint**
- `RESERVED_ROLE`
  - can call `mintSparker`

**Sales caller freeze behavior**
- First successful `mintPublic`:
  - records `salesCaller = msg.sender`
  - sets `salesCallerFrozen = true`
  - changes admin of `SALES_ROLE` to `FROZEN_SALES_ADMIN_ROLE`
  - `FROZEN_SALES_ADMIN_ROLE` is self-admin and no one is granted it in constructor → `SALES_ROLE` becomes effectively immutable after the first success.

### `PathMinterAdapter` ownership
- `Ownable` owner can change:
  - `auction` address (`setAuction`)
  - `minter` address (`setMinter`)
- `settle` is only callable by `auction`.

---

## 4) Threat model (practical)

### Assets to protect
- Buyer funds paid to PulseAuction.
- Correct delivery of PATH NFTs for each epoch.
- Integrity of the stage progression system (no unauthorized progression).
- Integrity of reserved (“sparker”) supply allocation.

### Primary attacker profiles
- Malicious buyer contract (reentrancy / revert behavior).
- Misconfigured deployment (wrong role grants, wrong adapter wiring).
- Compromised admin/owner keys (centralization risk).

---

## 5) Findings and recommendations

Severity legend: **Critical / High / Medium / Low / Info**

---

### F-01: Adapter wiring is owner-upgradable (auction/minter can be swapped)
**Severity:** Medium  
**Where:** `PathMinterAdapter.setAuction`, `PathMinterAdapter.setMinter`

**Why it matters**
- Whoever controls the adapter owner key can redirect settlements to a different auction or minter.
- In the worst case, this can break epoch→tokenId assumptions or route mints in unexpected ways.

**Recommendation**
- If you want trust-minimized behavior:
  - Make `auction`/`minter` **immutable**, or
  - Add a **one-way freeze** function that permanently locks these addresses after deployment, or
  - Put the adapter owner behind a **timelock + multisig** and document it as a trust assumption.

---

### F-02: Irreversible sales caller freeze can brick public minting if first call is wrong
**Severity:** High (operational footgun)  
**Where:** `PathMinter.mintPublic`

**Why it matters**
- The first **successful** public mint permanently sets `salesCaller`.
- After that, `SALES_ROLE` administration becomes effectively unreachable (admin = `FROZEN_SALES_ADMIN_ROLE`, which has no members).
- If the first successful caller is not your intended sales engine (the Pulse adapter), your public mint route is permanently stuck.

**Recommendation**
- Strongly consider one of:
  1. **Constructor-set** `salesCaller` + `salesCallerFrozen = true` (no “first caller wins”).
  2. Add an explicit `freezeSalesCaller(address expected)` callable by admin **once** (and only once).
  3. Operationally: ensure **only** the adapter has `SALES_ROLE` before any mint can succeed, and run a “dry-run mint” on a testnet with the exact ops steps you will execute on mainnet.

---

### F-03: Movement config freezes globally on first consumption (hard to recover from misconfiguration)
**Severity:** Medium (operational footgun)  
**Where:** `PathNFT.consumeUnit` + `PathNFT.setMovementConfig`

**Why it matters**
- `_movementFrozen[movement]` is global per movement.
- As soon as any token consumes `THOUGHT` once, you can no longer update THOUGHT minter/quota.
- If you misconfigure the movement minter address or quota and a single user consumes, it becomes permanent.

**Recommendation**
- Add an explicit “admin freeze” step *before* launch (or “freeze only after admin confirms”).
- Consider adding a deployment-time “staging” flag:
  - Allow config edits while `staging=true`
  - Require admin to call `finalizeConfig()` once to lock configuration
  - Only allow `consumeUnit` after finalization

If you keep the current design: document this clearly in runbooks and enforce “no consumption until config verified.”

---

### F-04: `consumeUnit` uses `tx.origin` (blocks smart wallets / relayers; can complicate UX)
**Severity:** Medium (UX/integration risk)  
**Where:** `PathNFT.consumeUnit`

**Why it matters**
- `require(claimer == tx.origin, "BAD_CLAIMER")` prevents:
  - account abstraction (ERC‑4337 style)
  - relayers / meta-tx patterns
  - some contract-wallet flows where the owner is a contract address (unless owner pre-approves an EOA as `claimer`)

This is likely intentional, but it is a strong constraint.

**Recommendation**
- If the goal is “user must explicitly authorize consumption,” consider alternatives:
  - EIP‑712 signatures from the owner/approved address
  - ERC‑1271 support for contract wallets
  - Permit-style `consumeWithSig(...)`

If you keep `tx.origin`, document supported wallet types and the “approve an EOA claimer” workaround for Safe-like custody.

---

### F-05: On-chain `tokenURI` JSON+SVG is not standardized for every indexer/wallet
**Severity:** Low (compatibility risk)  
**Where:** `PathNFT.tokenURI` returns `data:application/json;utf8,...`

**Why it matters**
- Many clients support `data:application/json;utf8,` and inline SVG.
- Some expect `data:application/json;base64,` or strongly prefer off-chain HTTP(S) token URIs.
- Some marketplaces cache metadata and may not refresh automatically as progression changes.

**Recommendation**
- Consider adding:
  - `description` and `attributes` fields (marketplace friendliness)
  - EIP‑4906 events (`MetadataUpdate`) on `consumeUnit` so indexers know metadata changed
  - Optional switch to base64 JSON if you see compatibility issues

---

### F-06: EVM README is outdated relative to current `tokenURI` behavior
**Severity:** Info  
**Where:** `evm/README.md` (“tokenURI returns baseUri + tokenId”)

**Recommendation**
- Update docs to match implementation: `tokenURI` is fully on-chain JSON+SVG; `_baseTokenUri` is not used by `tokenURI` in current code.

---

### F-07: Pulse interface drift risk (adapter interface mismatch vs upstream)
**Severity:** Info → can become High if you update submodule  
**Where:** `IPulseAdapter` in this repo vs `inshell-art/pulse` main

**Why it matters**
- Upstream Pulse `IPulseAdapter` currently includes `target()` (at least on `pulse/main` as observed at review time).
- Your adapter does not implement `target()` and your local interface does not declare it.
- If your `vendors/pulse` submodule updates to a commit that expects `target()`, your build will break or require adapter changes.

**Recommendation**
- Avoid duplicating Pulse interfaces in your repo; import the interface from the submodule and implement it exactly.
- Pin the submodule commit in release artifacts and include it in audit scope.

---

## 6) Invariants and quick test checklist

### Invariants worth asserting (fuzz/invariant tests)
- `PathMinter.nextId` increases by exactly 1 per successful `mintPublic`.
- `mintPublic` cannot succeed if `nextId >= SPARK_BASE`.
- `mintSparker` cannot exceed `reservedCap`.
- `consumeUnit` can only be called by the configured movement minter.
- `consumeUnit` cannot exceed quota and advances stage only when quota hits exactly.
- `PathMinterAdapter.settle` mints exactly `tokenBase + (epoch - epochBase)` and reverts otherwise.

### Manual rehearsal checklist (testnet)
- Deploy `PathNFT` (admin = multisig).
- Deploy `PathMinter` (admin = multisig), verify:
  - `nextId == firstPublicId`
  - `reservedCap`/`reservedRemaining` set
- Deploy `PathMinterAdapter` (owner = multisig), set:
  - `tokenBase == firstPublicId`
  - `epochBase == 1` (or chosen base)
- Deploy `PulseAuction` (treasury is correct, payment token correct).
- Wire:
  - grant `PathNFT.MINTER_ROLE` to `PathMinter`
  - grant `PathMinter.SALES_ROLE` to `PathMinterAdapter` **and do not grant it to anyone else**
  - set adapter’s `auction` to the deployed `PulseAuction`
- Configure movements in `PathNFT`:
  - set THOUGHT/WILL/AWA minter addresses and quotas
  - double-check before any user can call consumption
- Perform the **first** auction mint (this freezes `salesCaller`):
  - confirm `SalesCallerFrozen(adapter)` emitted
- Perform a movement consume flow and confirm:
  - first consume emits `MovementFrozen(movement)`
  - subsequent config edits for that movement revert as expected

---

## 7) Suggested hardening changes (if you want stricter trust minimization)

- **Freeze adapter wiring** after deployment (or make immutable).
- Replace “first caller wins” sales freeze with explicit admin-set sales caller.
- Replace `tx.origin` with signature-based authorization.
- Emit EIP‑4906 metadata update events on progression.
- Add explicit docs/runbooks around irreversible freeze points.

---

## Appendix A: Key references (files)
- `evm/src/PathNFT.sol`
- `evm/src/PathMinter.sol`
- `evm/src/PathMinterAdapter.sol`
- `evm/src/interfaces/*`
- `evm/test/*.behavior.test.js`
