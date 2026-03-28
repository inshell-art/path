# PATH ADMIN / TREASURY custody OPSEC upgrade — v1

## Status
Aligned to the chosen `two-ledgers-passphrase-custody-spec.md` design.

## Scope
This upgrade applies to **ADMIN / TREASURY Safe custody**.
It replaces the old Safe-owner assumption:

- one Ledger hardware owner
- one keystore/software owner on Signing OS

with:

- **two Ledger Nano S Plus devices only**
- **no software keystore Safe owner**
- **active Safe owners only on passphrase-derived Ledger wallets**
- **base / no-passphrase wallets intentionally unused**

This is a custody upgrade, not a blanket rewrite of every deploy detail in the repo.
If a deploy lane still uses a temporary software deployer outside Safe custody, treat that as a separate design question.

---

## 1) Executive design shift

### Old assumption to retire for Safe custody
For ADMIN / TREASURY Safe ownership, retire:

- `Ledger + keystore on Signing OS`
- keystore backup media
- keystore password path
- Signing OS as a key-holding software signer

### New chosen custody model
For each physical Ledger:

- **ADMIN path** = attached passphrase unlocked by a secondary PIN
- **TREASURY path** = temporary passphrase entered for the current session only
- **base wallet** = unused / never a Safe owner

### Final Safe owner sets

- **ADMIN Safe (2-of-2)** = `Ledger A / ADMIN path` + `Ledger B / ADMIN path`
- **TREASURY Safe (2-of-2)** = `Ledger A / TREASURY path` + `Ledger B / TREASURY path`

### Why the new model wins for this case
The new model removes the whole software-key path from active Safe custody:

- no encrypted keystore file for Safe ownership
- no keystore backup media for Safe ownership
- no keystore password path for Safe ownership
- less host burden on Signing OS
- one active signer model everywhere: Ledger only

What it accepts in exchange:

- common-mode Ledger / vendor risk
- passphrase restore complexity
- need for a non-secret owner-address map
- full passphrase-restore drills, because base Recovery Check is not enough for passphrase wallets

---

## 2) What changes in the operating model

### A. Signing OS still exists, but its role changes
Keep the Signing OS.
Do **not** delete it from the architecture.

But change its custody role:

- **old role**: coordinator + verifier + executor + software Safe owner
- **new role**: coordinator + verifier + executor only

The Signing OS still:

- fetches the pinned repo/bundle
- verifies run material and chain state
- hosts the Safe interaction / execution environment
- keeps local `.opsec` storage for non-repo local material

The Signing OS no longer needs to hold an active ADMIN/TREASURY software signer for Safe custody.

### B. Safe custody becomes hardware-only
ADMIN / TREASURY Safe ownership should live only on:

- `A-admin`
- `B-admin`
- `A-treasury`
- `B-treasury`

where each is a Ledger passphrase path.

### C. Base wallets become intentionally dead for authority
The no-passphrase base wallets are not owners.
Do not fund them as authority paths.
Do not enroll them as Safe owners.
Do not treat them as fallback signers.

---

## 3) New custody principles

### 3.1 Count factors, not objects
- two copies of the same passphrase are still one factor
- two Ledgers restored from the same 24 words are still one recovery factor
- 24 words in one place and the passphrase in another place are two factors

### 3.2 Use memory only as an index
Acceptable in memory:
- which box is where
- which path is ADMIN vs TREASURY
- the normal sequence of use

Not acceptable as memory-only secrets:
- 24-word recovery phrases
- passphrases
- exact owner-address mapping

### 3.3 Separate operations from recovery
Keep four places:

- **OM** = Operations / Materials
- **OS** = Operations / Secrets
- **RM** = Recovery / Materials
- **RP** = Recovery / Secrets

### 3.4 No single box must complete an active signer path
These must remain true:

- `OM` alone cannot operate or recover an owner
- `OS` alone cannot operate or recover an owner
- `RM` alone cannot recover an active owner
- `RP` alone cannot recover an active owner

---

## 4) Box layout to adopt

## 4.1 Boxes

| Box | Meaning | Contents | Rule |
|---|---|---|---|
| `OM` | Operations / Materials | `A-LEDGER`, `B-LEDGER`, coordinator machine/SSD, cable/adapter, working copy of `MAP-MAIN`, non-secret checklist | never co-store with recovery metals or master passphrase copy |
| `OS` | Operations / Secrets | `ADMIN-PIN-A`, `ADMIN-PIN-B`, coordinator OS login/disk password, optional working copy of `TREASURY-PP` | never co-store with `OM` |
| `RM` | Recovery / Materials | `A-M24`, `B-M24` | never co-store with `RP` |
| `RP` | Recovery / Secrets | `ADMIN-PP`, `TREASURY-PP`, master copy of `MAP-MAIN` | never co-store with `RM` |

## 4.2 Operational warning about `OS`
A working Treasury passphrase copy in `OS` is allowed only as a deliberate convenience trade.
It weakens separation and should be treated as such.

---

## 5) `MAP-MAIN` becomes mandatory

`MAP-MAIN` is a **non-secret** map.
It should exist in:

- one working copy in `OM`
- one master copy in `RP`

It must contain:

- ADMIN Safe address
- TREASURY Safe address
- chain IDs
- threshold = 2/2
- exact owner addresses for `A-admin`, `B-admin`, `A-treasury`, `B-treasury`
- path map: `ADMIN = attached passphrase`, `TREASURY = temporary passphrase`, `base = unused`
- item map: which IDs live in which box
- drill log and incident map

It must **not** contain:

- raw 24 words
- raw passphrase text
- raw PINs

---

## 6) What to deprecate in PATH docs / runbooks

### Deprecate for ADMIN / TREASURY Safe custody
Anything that assumes these as final Safe owners:

- `*_GOV_SW_*`
- `*_TREASURY_SW_*`
- keystore-backed final ADMIN / TREASURY owner path

### Keep, but reinterpret
The Signing OS runbook still provides useful discipline for:

- separate machine/account
- repo fetch discipline
- bundle verification
- no local patching during active runs
- audit after postconditions

Keep those behaviors.
But stop treating the Signing OS as an active software Safe owner in the final custody shape.

### Public-safe repo boundary remains in force
Do not put into public git:

- passphrases
- seeds / mnemonic phrases
- exact private operator identity mapping
- raw keyed RPC URLs
- real recovery materials

If exact signer-to-device mapping is sensitive, keep the live mapping in local/private overlay only.
The public repo should keep aliases/placeholders/examples only.

---

## 7) Migration plan from old Safe custody

### Phase 0 — inventory
Record in `MAP-MAIN`:

- current ADMIN Safe address, owners, threshold
- current TREASURY Safe address, owners, threshold
- which owners are Ledger-backed vs keystore-backed

### Phase 1 — prepare both Ledgers
For each Ledger:

1. confirm authenticity with Genuine Check
2. confirm it is initialized from the intended 24-word phrase
3. set up ADMIN as attached-passphrase / secondary-PIN path
4. set up TREASURY as temporary-passphrase path
5. derive and record:
   - `A-admin`
   - `A-treasury`
   - `B-admin`
   - `B-treasury`
6. confirm base wallets are not owners

### Phase 2 — migrate Safe owners
For each Safe:

1. add or swap in the new Ledger owner addresses using the still-valid current authority path
2. verify owner list and threshold after each change
3. remove the old keystore owner after the new Ledger owner is live and verified
4. confirm final owner set matches the chosen design

### Phase 3 — build boxes and cards
Prepare `OM`, `OS`, `RM`, `RP`, `MAP-MAIN`, and local box cards.
Label boxes with neutral codes only.

### Phase 4 — drills
Run:

- base-phrase Recovery Check
- passphrase restore drill for all four owner paths
- harmless Safe signing drill with the correct owner paths

---

## 8) Drill ladder under the new model

### Drill 1 — Ledger fundamentals
Goal:
- understand base seed, PIN, reset, restore, Ethereum app, and on-device verification

### Drill 2 — Passphrase fundamentals
Goal:
- understand attached-passphrase vs temporary-passphrase
- prove that base / admin / treasury paths resolve to different addresses
- prove that wrong passphrase can silently open a different wallet

### Drill 3 — Safe fundamentals
Goal:
- understand owners, threshold, nonce, `safeTxHash`, confirmation vs execution
- this can be done with temporary Sepolia software owners as a pure concept drill if desired

### Drill 4 — Two-Ledger Safe drill
Goal:
- create harmless Sepolia Safe flows using the final topology shape
- ADMIN drill: `A-admin + B-admin`
- TREASURY drill: `A-treasury + B-treasury`

### Drill 5 — Restore drill
Because Recovery Check does not prove passphrase wallets, do a full restore/address-check drill for all four active owner paths.

---

## 9) What this changes in the old Ledger drill

The old drill assumed:

- one Ledger owner
- one software owner on Signing OS
- 2-of-2 = Ledger + keystore

That is no longer the target design.

The revised drill must instead teach:

- Ledger as a hardware signer only
- passphrase path control
- base-wallet non-use
- two-Ledger 2-of-2 Safe ownership
- restore discipline for passphrase wallets

---

## 10) Final judgment

For this case, the chosen design is:

- **better than Ledger + keystore for ADMIN/TREASURY Safe custody**
- **not simpler in recovery**, but simpler in active signer classes
- **worth adopting** because it removes the software-key path from final Safe authority

The main cost is that restore discipline now matters more than before.
That cost is real and should not be minimized.
