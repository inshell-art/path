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
- `docs/audit-framework.md` — process-audit model for lane evidence.
- `docs/audit-runbook.md` — deterministic audit operator flow.
- `docs/audit-controls-catalog.md` — v1 control IDs and evidence mapping.
- `docs/snippets/root-AGENTS-audit-response-contract.md` — root-ready audit response contract snippet.
- `schemas/bundle_manifest.schema.json` — schema for bundle manifests (AIRLOCK integrity).
- `schemas/audit_*.schema.json` — audit plan/report/findings schema set.
- `schemas/inputs.schema.json` — schema for first-class high-entropy inputs wrapper.
- `examples/inputs/params.constructor_params.minimal.schema.example.json` — minimal schema example (not production strict).
- `examples/inputs/params.constructor_params.strict.schema.template.json` — copy/edit template for downstream strict schemas.
- `policy/audit.policy.example.json` — audit policy template (coverage and finding thresholds).
- `examples/scaffold/.github/workflows/ops_audit.yml` — scheduled audit + release-gate CI example.
- `examples/scaffold/.github/workflows/ops_tests.yml` — scaffold regression tests for ops helper scripts.

## What this template is (and is not)

**It is:**
- A disciplined process for *how* to deploy, handoff, and govern using deterministic intents + checks + approvals.
- A way to make agent-assisted ops safer by forcing “meaning approval” and “reality verification”.
- A first-class audit module for periodic/release process assurance over lane artifacts.

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
- Sepolia/Mainnet deploy lanes require pinned `inputs.json` by default (`required_inputs` policy).
- Sepolia/Mainnet deploy lanes should use `STRICT_PARAMS_SCHEMA=1` with downstream `PARAMS_SCHEMA` in `lock_inputs.sh`.
- Do not use raw `*_PRIVATE_KEY` export flows; use keystore + address env vars.

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
For an audit fixture example, see:
`examples/scaffold/audits/devnet/audit-20260222-example/`.

Audit output contract (required):
- `audit_plan.json`
- `audit_evidence_index.json`
- `audit_verification.json`
- `audit_report.json`
- `findings.json`

Optional but recommended:
- `signoff.json`

## License

MIT (see `LICENSE`).

## Contributing

PRs that improve safety, clarity, and reproducibility are welcome. See `CONTRIBUTING.md`.
