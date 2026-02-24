# OPSEC × Ops-lanes Signer Map (Inshell)

This document merges:

- **OPSEC compartments** (where actions happen, what never mixes)
- **Ops Lanes** (who is allowed to do what, with what checks/approvals)
- **Signer map** (which keys/accounts exist, what they are used for, and where they live)

It is written so you can keep it in a **public template repo** without leaking secrets. No private keys, no seeds, no real RPC URLs.

---

## 0) Core mental model

**Compartmentation beats cleverness.**

- Keep **eyes** (monitoring/browsing) separate from **hands** (signing).
- Prefer **intent → checks → approval → apply** over ad‑hoc clicking.
- Treat any “shared” medium as **untrusted input** unless you verify it.

---

## 1) Roles (compartments)

- **PUBLIC**: open identity + browsing + OSS presence.
- **OPS**: infra/billing consoles (Cloudflare/registrar/DNS). No wallets.
- **HOT**: low-stakes “normal user” wallet (tiny funds, disposable).
- **DEPLOYER**: deploy/initialize only; must end with **zero privilege**.
- **GOV (ADMIN)**: protocol authority (ownership/roles/wiring).
- **TREASURY**: custody of value; rare outflows.
- **WATCH**: monitoring only.

---

## 2) Phase split

### Phase A — Devnet rehearsal (low stakes)
Goal: learning + speed.

- You may run multiple signers on one machine user, but still keep role separation.
- Use keystore mode for CLI signers; Ledger is recommended as 2nd factor.
- Sepolia remains optional for public-testnet parity, but Devnet is the default rehearsal network.

### Phase B — Mainnet (high stakes)
Goal: reduce attack surface and correlated mistakes.

- Privileged signing happens only inside dedicated signing environments.
- Daily OS is not used for privileged signing (no GOV/TREASURY/DEPLOYER signing).

---

## 3) Recommended OS layout (simple and strong)

You described:

- **OS1**: general-purpose macOS on internal disk (dev/browse/ops)
- **OS2**: dedicated signing OS (Admin/GOV domain)
- **OS3**: dedicated signing OS (Treasury domain)
- OS2 + OS3 live on the same external SSD (two bootable volumes)

This layout is good **if** you also add a controlled sharing mechanism for non-secret ops files.

---

## 4) “Airlock” for shared ops files (not an enclave)

You *can* call it an “enclave” informally, but in security terminology an **enclave** usually means hardware-enforced isolated execution (e.g., Secure Enclave / SGX).  
What you want here is a **transfer zone**. Call it an **AIRLOCK**.

### What AIRLOCK is
A shared folder/volume used to move **non-secret** ops bundles between OSes without copy/paste.

- Contains: `intent.json`, `checks.json`, `approval.json`, `txs.json`, snapshots, logs.
- Does **not** contain: keystores, account JSON with secrets, passwords, seeds, `.env`.

### How to implement AIRLOCK (macOS-friendly)
On the external SSD, create a third APFS volume (or partition) called:

- `AIRLOCK`

Then use a fixed directory structure such as:

```
AIRLOCK/
  bundles/
    devnet/<run_id>/
    sepolia/<run_id>/
    mainnet/<run_id>/
  inbox/
    from-os1/
    from-os2/
    from-os3/
  outbox/
    to-os2/
    to-os3/
  archive/
```

The only thing that needs to be shared is the **bundle folder** for a given run.

### Critical extra rule (integrity): shared files are untrusted
Treat anything read from AIRLOCK as **untrusted input**, even if you wrote it yourself earlier.

On the signing OS (OS2/OS3), before any signature:

1) Copy the run bundle from AIRLOCK into a local working directory (example):
   - `~/ops/bundles/<run_id>/`

2) Generate and verify a **bundle manifest**:

- `bundle_manifest.json` contains SHA256 hashes of immutable files.
- Minimum immutable set (at least): `run.json`, `intent.json`, `checks.json`.

**Manifest format (example):**
```json
{
  "manifest_version": 1,
  "bundle_hash": "<sha256>",
  "immutable_files": [
    { "path": "run.json", "sha256": "<sha256>" },
    { "path": "intent.json", "sha256": "<sha256>" },
    { "path": "checks.json", "sha256": "<sha256>" }
  ]
}
```

3) Freeze immutables:
- After approval, these files must never change:
  - `intent.json`
  - `checks.json`
  - `approval.json`
  - `policy.json` (if present)
  - `addresses.json` (if present)

4) Allow only these outputs to change:
- `txs.json`
- `snapshots/*`
- `receipts/*`
- `logs/*`

5) Verify on-chain reality:
- Do not trust `txs.json` alone.
- Derive / confirm the target Safe operation from chain state/events and match it back to the approved intent hash.

This rule is how you get “shared bundles” without re-introducing “clipboard ops”.

---

## 5) Signer alias scheme (lane-agnostic)

Avoid lane numbers inside signer names. Lanes are enforced by policy.

Format:

`<NET>_<DOMAIN>_<TYPE>_<A/B>`

- `NET`: `DEVNET` / `SEPOLIA` / `MAINNET`
- `DOMAIN`: `DEPLOY` / `GOV` / `TREASURY`
- `TYPE`: `SW` (software keystore) / `HW` (Ledger)
- `A/B`: signer index for 2-of-2

Example set (per network):

- `DEVNET_DEPLOY_SW_A`
- `DEVNET_GOV_SW_A`
- `DEVNET_GOV_HW_B`
- `DEVNET_TREASURY_SW_A`
- `DEVNET_TREASURY_HW_B`

---

## 6) Phase B signer placement (Mainnet recommended)

### GOV / ADMIN Safe (2-of-2)
- `MAINNET_GOV_SW_A` → keystore signer on **OS2**
- `MAINNET_GOV_HW_B` → Ledger signer used on **OS2**
- Safe address: `MAINNET_GOV_SAFE`

### TREASURY Safe (2-of-2)
- `MAINNET_TREASURY_SW_A` → keystore signer on **OS3**
- `MAINNET_TREASURY_HW_B` → Ledger signer used on **OS3**
- Safe address: `MAINNET_TREASURY_SAFE`

### HOT user wallet
- `MAINNET_HOT_USER` → MetaMask/Rabby on OS1 (separate browser profile)
- Never admin. Never treasury.

### WATCH
- Can run anywhere (OS1 included). Watch-only only.

---

## 7) LLM / agent policy (the “big pivot” rules)

**Use LLMs to write. Do not use LLMs to run.**

### Allowed
- Use Codex/LLMs to **author and refactor** scripts/runbooks (Lane 0/1).
- Use LLMs to explain errors, format runbooks, and improve documentation.

### Not allowed in “apply”
- No LLM calls (online or local) during Lane 2+ apply on Mainnet.
- No “agent decides what to execute” at apply time.
- Apply must run deterministic code from disk.

### Pinning (required)
- Any script that can produce a chain write must be pinned:
  - git commit hash or tag recorded in `run.json`
- Apply refuses if the working tree is dirty or the commit hash is not recorded.

### Review (required)
- Treat all LLM output as **untrusted** until reviewed and committed.
- Never paste secrets into an LLM (keys, seeds, passwords, tokens).

---

## 8) Never list (non-negotiable)

- Never do privileged signing from PUBLIC or OPS contexts.
- Never store admin/treasury secrets in the repo, chat logs, screenshots, CI logs.
- Never let HOT considered “safe enough” for privileged roles.
- Never sign (Ledger or keystore) unless:
  - chain id matches,
  - signer matches policy,
  - target identity matches expected,
  - approved intent hash matches the operation being confirmed.
