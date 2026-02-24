# opsec-ops-lanes-template

A public, repo-safe template for **deterministic** intent-gated Ethereum operations under a practical **OPSEC compartment model**.
**LLMs are for authoring tools; production apply is pinned scripts only.**

This repo contains:
- `docs/ops-lanes-agent.md` — the “Ops Lanes” contract between an agent and a human operator (keystore-mode signing, no accounts-file mode).
- `docs/opsec-ops-lanes-signer-map.md` — OPSEC compartments + signer aliases + phase split (Devnet rehearsal → Mainnet, Sepolia optional).
- `policy/*.example.json` — example lane policies (RPC allowlist, signer allowlists, EIP-1559 fee thresholds, required checks).
- `schemas/*` — starter JSON schemas for intent/check/approval artifacts (including EVM + Safe transaction shapes).
- `examples/*` — toy examples (no real addresses, no secrets).
- `examples/scaffold/*` — downstream repo scaffold for CI rehearsal + ops layout.
- `codex/BOOTSTRAP.md` — maintainer steps to create and publish the template repo.
- `codex/BUSINESS_REPO_ADOPTION.md` — quick checklist for adopting this template inside a downstream repo.
- `docs/downstream-ops-contract.md` — required rules for downstream repos (CI/CD + signing).
- `docs/pipeline-reference.md` — step-by-step pipeline reference (bundle → verify → approve → apply).
- `docs/agent-trust-model.md` — trust tiers + evidence-pack requirements for agent claims.
- `schemas/bundle_manifest.schema.json` — schema for bundle manifests (AIRLOCK integrity).

## What this template is (and is not)

**It is:**
- A disciplined process for *how* to deploy, handoff, and govern using deterministic intents + checks + approvals.
- A way to make agent-assisted ops safer by forcing “meaning approval” and “reality verification”.

**It is not:**
- A wallet tutorial.
- A full security guarantee.

## Secrets rule

This repo **must stay public-safe**:
- No seed phrases, private keys, keystore JSON, 2FA backups, RPC URLs with embedded credentials, or screenshots.
- Keystores and passwords live **outside the repo** (e.g., in a local encrypted directory or dedicated Signing OS).

## Mainnet contract (non-negotiable)

- Mainnet writes must be executed via **Local CD on Signing OS**.
- Remote CI may build/check bundles, but **may not sign**.
- **No LLM calls inside apply**; only pinned scripts run.
- If policy requires rehearsal proof, Mainnet apply **refuses** without it.
  - Default example policy is Devnet-first.
  - Canonical proof env var is `REHEARSAL_PROOF_RUN_ID` (legacy proof env vars remain temporarily supported).

See `docs/downstream-ops-contract.md`.
For agent claim verification discipline, see `docs/agent-trust-model.md`.

## How to use this template in a downstream repo

Note: Fork/copy/submodule this repo into your downstream repo and keep secrets out of git (keystore files, seed phrases, 2FA backups, RPC credentials). Commit only `*.example` templates.

Pick one approach:

### Option A — Git subtree (recommended)
Vendor the template into your repo (example: `opsec-ops-lanes-template/`) and pull updates periodically.

### Option B — Git submodule
Add this repo to your downstream repo at a stable path (example: `ops-template/`), then reference docs/policy from there.

### Option C — Copy the docs
Copy `docs/` and `policy/` and maintain your own fork.

## Suggested private repo layout (downstream repo)

Keep “rules” separate from “instance data”:

- `ops-template/` (this repo, read-only)
- `ops/` (your instance: runbooks, lane policy, artifacts)
- `artifacts/<network>/...` (generated, commit only what you want public)

See `docs/integration.md` for a full example, and `examples/scaffold/` for a runnable layout.

For a minimal CI/CD scaffold you can copy into a downstream repo, see:
`examples/scaffold/`.

## License

MIT (see `LICENSE`).

## Contributing

PRs that improve safety, clarity, and reproducibility are welcome. See `CONTRIBUTING.md`.
