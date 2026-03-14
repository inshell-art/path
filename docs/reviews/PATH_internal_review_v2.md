# PATH Protocol - EVM Internal Review v2 (Status Refresh)

**Reviewed repo:** `inshell-art/path`  
**Review baseline commit:** `b1c89cfef3747ec545550f47aa05bd09ede8c9df`  
**Review date:** 2026-03-01  
**Reviewer:** GPT-5 (AI-assisted internal review refresh)

This v2 document updates `PATH_internal_review.md` by separating:
- findings that are still open
- findings that are already resolved in the current workspace code

It is an internal pre-audit artifact, not a third-party audit.

---

## 1) Executive delta

### Risk posture
**Medium** remains appropriate, with risk concentrated in:
- irreversible freeze behavior (operational footguns)
- owner-controlled adapter rewiring
- `tx.origin` integration constraints
- interface drift risk against upstream Pulse

### What changed vs v1
- Metadata concerns were largely resolved:
  - `tokenURI` is base64 JSON with base64 SVG image
  - conventional metadata fields are present (`description`, `attributes`, `image`)
  - ERC-4906 support is implemented and emitted on progression
- README tokenURI note is aligned with current behavior

---

## 2) Findings status matrix

| ID | v1 theme | v2 status | v2 severity |
|---|---|---|---|
| F-01 | Adapter owner can rewire `auction` / `minter` | **Open** | Medium |
| F-02 | First successful `mintPublic` freezes sales caller forever | **Open** | High (operational) |
| F-03 | Movement config freezes on first consume | **Open** | Medium (operational) |
| F-04 | `tx.origin` claimer restriction | **Open** | Medium (integration/UX) |
| F-05 | tokenURI compatibility concerns | **Resolved** | N/A |
| F-06 | EVM README tokenURI mismatch | **Resolved** | N/A |
| F-07 | Pulse interface drift (`target()`) risk | **Open** | Medium (integration) |

---

## 3) Open findings (current)

### F-01: Adapter wiring remains owner-updatable
**Evidence**
- `setAuction`: [PathMinterAdapter.sol](~/Projects/path/evm/src/PathMinterAdapter.sol:35)  
- `setMinter`: [PathMinterAdapter.sol](~/Projects/path/evm/src/PathMinterAdapter.sol:42)

**Impact**
- Adapter owner can redirect settlement source/target if key governance is weak.

**Recommendation**
- Add one-way wiring freeze, or enforce multisig/timelock owner and document trust assumptions.

### F-02: Sales caller freeze is still first-success-wins
**Evidence**
- Freeze logic in [PathMinter.sol](~/Projects/path/evm/src/PathMinter.sol:48)

**Impact**
- Wrong first successful caller can permanently lock the sales route.

**Recommendation**
- Keep strict runbook control: adapter must be sole sales caller before first public mint.
- Optional code hardening: explicit admin freeze to expected caller.

### F-03: Movement config freeze still irreversible at first consume
**Evidence**
- movement frozen in [PathNFT.sol](~/Projects/path/evm/src/PathNFT.sol:120)
- config rejects frozen movement in [PathNFT.sol](~/Projects/path/evm/src/PathNFT.sol:71)

**Impact**
- Misconfigured movement minter/quota becomes permanent after first consume.

**Recommendation**
- Operationally require config verification checkpoint before enabling any consume flow.

### F-04: `tx.origin` restriction remains intentional but limiting
**Evidence**
- `claimer == tx.origin` in [PathNFT.sol](~/Projects/path/evm/src/PathNFT.sol:102)

**Impact**
- Blocks relayer and many smart-wallet/AA patterns unless workflows are adapted.

**Recommendation**
- Keep only if this restriction is a deliberate product decision; otherwise move to signature-based authorization.

### F-07: Pulse interface drift risk remains
**Evidence**
- Local adapter interface lacks `target()`: [IPulseAdapter.sol](~/Projects/path/evm/src/interfaces/IPulseAdapter.sol:4)
- Upstream vendor interface includes `target()`: [vendors pulse IPulseAdapter](~/Projects/path/vendors/pulse/evm/src/interfaces/IPulseAdapter.sol:17)

**Impact**
- Future submodule updates can break integration or force emergency adapter/interface changes.

**Recommendation**
- Use vendor interface directly (or keep local mirror continuously synchronized with pinned vendor commit).

---

## 4) Resolved items

### F-05 resolved: metadata and refresh signals
**Now present**
- base64 JSON tokenURI: [PathNFT.sol](~/Projects/path/evm/src/PathNFT.sol:165)
- `description` and `attributes`: [PathNFT.sol](~/Projects/path/evm/src/PathNFT.sol:182)
- ERC-4906 support and event emit: [PathNFT.sol](~/Projects/path/evm/src/PathNFT.sol:252), [PathNFT.sol](~/Projects/path/evm/src/PathNFT.sol:132)

### F-06 resolved: README matches tokenURI model
- README note reflects base64 metadata: [evm README](~/Projects/path/evm/README.md:68)

---

## 5) Test confidence snapshot

Current tests in workspace include coverage for:
- sales caller freeze and role lock behavior
- movement ordering/freeze and approvals
- metadata shape and ERC-4906 emission
- adapter epoch/token coupling and mismatch reverts
- pulse integration happy/failure paths

Recommended next testing increment:
- add invariant/fuzz tests for freeze and coupling assumptions under randomized sequences.

---

## 6) Pre-Sepolia operator checklist (focused)

1. Verify adapter is the only intended first successful `mintPublic` caller.
2. Verify movement minter/quota config before any user consumes.
3. Pin and record pulse submodule commit in release artifacts.
4. Execute devnet lane + audit rehearsal and archive bundle/audit artifacts.
5. Confirm owner/admin key governance model is documented (multisig/timelock if used).

---

## 7) Suggested next revision trigger

Generate v3 when any of these change:
- adapter ownership/freeze model
- `consumeUnit` authorization model (`tx.origin` replacement)
- pulse interface dependency strategy
- metadata format/event strategy

