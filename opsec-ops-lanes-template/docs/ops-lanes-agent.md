# Ops Lanes (Agent) — operator rules for intent‑gated onchain ops (EVM, Keystore + Ledger)

This document defines **Ops Lanes** and the responsibilities split between:

- an **agent** (automation / deterministic scripts)
- **you** (human approver + physical signer)

It is designed to work with the OPSEC compartments in **OPSEC × Ops-lanes Signer Map**.

> **Principle:** Humans approve **meaning**. Machines verify **reality**.

---

## 0) Vocabulary

- **Lane**: a permission + process boundary defined by:
  - **Allowed signer set** (which EOA/Safe signer may be used)
  - **Allowed operations** (what actions are permitted)
  - **Required checks** (what must be proven true before execution)
  - **Approval rules** (how/when a human can authorize execution)

- **Intent**: canonical machine-readable description of an operation (usually one tx).
- **Checks**: machine proof that an intent is safe/consistent (identity, preconditions, simulation).
- **Approval**: a human “go” tied to a specific intent/bundle hash (approves meaning, not hex).
- **Apply**: execution that must use only the approved intent (no manual args).

- **Bundle**: a folder containing intent + checks + approval + state (txs/snapshots).

---

## 1) Golden rules (Sepolia/Mainnet)

1) **No manual args at apply time.**  
   `apply` must read everything from `intent.json` (and bundle artifacts).  
   If you find yourself pasting tx ids, nonces, calldata, proposal ids: stop and fix the tooling.

2) **No “paste into execution commands.”**
   If you must paste an address/tx hash, paste only into a dedicated `inputs/*` step that:
   - validates format
   - verifies on-chain identity
   - persists into a file (so future steps read files, not clipboard)

3) **Network-scoped bundles only.**  
   Bundles live under `bundles/<network>/<run_id>/` (and archives). Never mix networks.

4) **Identity checks are mandatory for every write.**  
   Every write must verify:
   - chain id matches lane config
   - signer matches lane allowlist
   - target code identity matches expected (bytecode hash / proxy implementation / ABI selector policy)
   - preconditions match expected (owner/roles/config)

5) **Plan + Check + Approve + Apply are logically distinct** (even if scripted).  
   Apply refuses unless the exact intent (or bundle hash) is:
   - checked (`checks.json: pass`)
   - approved (`approval.json` matches intent/bundle hash)

6) **Postconditions are proof.**  
   “Tx succeeded” isn’t enough. Every write produces:
   - `snapshots/post_*.json`
   - postcondition checks (expected state matches)

7) **Shared files are untrusted (AIRLOCK rule).**  
   If bundles move across OSes via a shared volume/folder:
   - treat the shared location as **untrusted input**
   - verify a **bundle_manifest.json** (hashes of immutable files)
   - freeze immutables after approval
   - trust on-chain truth over `txs.json`

---

## 2) Standard bundle files (minimum set)

Required:

- `run.json` — run id, git commit/tag, network, timestamps
- `intent.json` — one intent (or bundle intent list) in canonical form
- `checks.json` — machine proof: identity + preconditions + simulation
- `approval.json` — human “go” tied to intent/bundle hash
- `txs.json` — tx hashes and Safe step ids produced during apply
- `snapshots/*.json` — baseline + post-* readbacks
- `postconditions.json` — pass/fail + evidence pointers

Recommended:

- `policy.json` — lane policy snapshot used for the run
- `bundle_manifest.json` — hashes of immutable files (see AIRLOCK rule)

---

## 3) Agent vs Human (who does what)

### Agent responsibilities (automation)
The agent must be able to truthfully say:

> “All required checks passed for this exact intent, under this policy, on this network.”

**Must do**
- Resolve labels → addresses from bundle files (never from memory).
- Generate `intent.json` deterministically (ABI + args -> calldata, or canonical Safe payloads).
- Run required checks and write `checks.json`.
- Enforce lane policy: refuse operations outside allowed list.
- Ask the human for **semantic approval** (not hex review).
- On apply:
  - re-load intent from disk
  - re-check critical invariants just-in-time (chain id, signer, identity)
  - execute the tx
  - persist `txs.json` + snapshots + postconditions
- Produce a short, human-readable approval statement (labels, not raw addresses).

**Must not**
- Store, print, or request secrets.
- “Guess” inputs interactively at apply time.
- Proceed on partial checks.
- Accept raw addresses as apply args (unless read-only).

### Human responsibilities (you)
Your job is to approve **meaning**, pick the correct lane/network, and physically sign when prompted.

**Must do**
- Confirm the **lane** you are authorizing.
- Confirm the **network** (Sepolia vs Mainnet).
- Confirm the agent’s **semantic statement** matches your intent.
- Confirm you are using the correct signer for the lane (GOV vs TREASURY vs DEPLOY).
- Provide approval and sign (Ledger / keystore unlock).

**Must not**
- Try to validate calldata/addresses by eyeballing (that’s what checks are for).
- Approve on Mainnet if rehearsal proof is missing (when your policy requires it).

---

## 4) LLM usage policy (critical)

**LLMs may help write the tools. LLMs must not run the tools.**

### Allowed
- Use Codex/LLMs to author/refactor scripts, runbooks, and documentation.
- Use LLMs for explanation, formatting, and review assistance.

### Required safety rules
- Treat LLM output as **untrusted** until reviewed.
- Only execute deterministic scripts committed to git.
- Pin the execution version:
  - record git commit hash/tag in `run.json`
  - apply refuses if the repo is dirty or the commit differs
- Use `docs/agent-trust-model.md` for trust tiers and Evidence Pack response shape.

### Disallowed (especially on Mainnet)
- No LLM calls inside `apply` (no “agent decides what to do” at runtime).
- No secrets ever pasted into LLMs (keys, seeds, passwords, tokens).

---

## 5) Ops Lanes (tight definition)

Each lane is defined by: **Signer(s), Allowed ops, Required checks, Approval rule**.

### Lane `observe` — read-only
- **Signer:** none
- **Ops:** reads, snapshots, diffs, simulate/estimate (no state changes)
- **Checks:** chain id and identity checks recommended
- **Approval:** none

### Lane `plan` — build and checks (no chain writes)
- **Signer:** none
- **Ops:** compile/build, derive tx payloads, produce intent/check bundles (no writes)
- **Checks:** determinism + hashing
- **Approval:** none

### Lane `deploy` — create primitives
- **Signer:** deployer only
- **Ops:** deploy contracts/proxies, then initialize bootstrap config
- **Checks (required):**
  - chain id / rpc allowlist
  - bytecode hash / implementation hash policy
  - expected address derivation (if used)
  - post-deploy snapshot
- **Approval:** required

### Lane `handoff` — handoff and lockdown
- **Signer:** deployer (initial) then governance (final)
- **Ops:** set roles, transfer ownership to GOV Safe, revoke deployer privileges
- **Checks (required):**
  - current ownership/roles match expected
  - postconditions: deployer cannot mutate protected state
- **Approval:** required (high safety)

### Lane `govern` — high-power changes
- **Signer:** governance Safe signers only
- **Ops:** upgrades, sensitive config, authority changes
- **Checks (required):**
  - strict identity checks + simulation
  - pre/post state proofs
  - Safe threshold enforcement
- **Approval:** via Safe confirmations + bundle approval artifact

### Lane `treasury` — custody actions
- **Signer:** treasury Safe signers only
- **Ops:** outflows, custody moves, allowlist changes
- **Checks (required):**
  - destination allowlist and limits
  - simulation + postconditions
  - Safe threshold enforcement
- **Approval:** required, usually dual-control

### Lane `operate` — bounded routine actions
- **Signer:** operator role accounts (not deployer; not treasury unless needed)
- **Ops:** routine actions within strict bounds
- **Checks (required):**
  - role membership proof
  - bounds/rate limits
  - postconditions
- **Approval:** required (often per-intent)

### Lane `emergency` — break-glass
- **Signer:** emergency Safe/key (separate from routine)
- **Ops:** pause/freeze, stop-the-bleed actions
- **Checks (required):**
  - tight allowlist of actions
  - mandatory postcondition snapshot
- **Approval:** required, with extra friction

---

## 6) Remote CI + Local CD (recommended shape)

### Deterministic pipeline (no LLM at apply)
- Rehearsal output is a **pinned pipeline** (CI + local scripts), not an LLM workflow.
- **Agent = deterministic scripts**; LLMs are for authoring tools/docs only.

### Remote CI (no secrets)
- Build/test
- Produce release bundle (compiled artifacts + hashes + policies)
- Generate intents + checks (read/sim only)
- Publish bundle as an artifact (or PR)

### Local CD (signing stays local)
- On Signing OS, pull/download bundle
- Re-run critical checks (defense-in-depth)
- Create approval on the signing side (or verify approval integrity)
- Apply intents with keystore + Ledger
- Archive bundle + tx hashes + snapshots

---

## 7) Stop conditions (agent must refuse)

Refuse if any of these occur:
- chain id mismatch
- rpc not allowlisted
- signer not allowed for lane
- target identity mismatch (bytecode hash / proxy implementation / ABI selectors)
- preconditions fail (ownership/roles/config not as expected)
- simulation fails / revert predicted
- fee above threshold (unless elevated approval exists)
- intent/bundle hash mismatch across files
- AIRLOCK integrity check fails (manifest mismatch / immutable changed)
- postconditions fail after tx
