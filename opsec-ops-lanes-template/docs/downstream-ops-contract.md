# Downstream Ops Contract

This document defines the **non-negotiable rules** for any downstream repo that adopts the template.

## Required directory conventions
Downstream repos must follow these (or compatible) paths:

```
ops/
  policy/
  runbooks/
  tools/
artifacts/
  <network>/current/
bundles/
  <network>/<run_id>/
```

- `ops/` contains policies, runbooks, and scripts.
- `artifacts/` contains generated evidence (intents, checks, approvals, snapshots).
- `bundles/` contains immutable bundle directories used across CI/CD and Signing OS.

## Required pipeline shape

### Remote CI (no secrets, no signing)
- Build/test (read-only)
- Generate bundle:
  - `run.json`
  - `intent.json` (EVM call or Safe transaction payload)
  - `checks.json` (must include policy-required identity checks for write lanes)
  - for lanes with `required_inputs`, accept only a locked wrapper JSON input produced outside CI by `ops/tools/lock_inputs.sh`
  - in the scaffold workflow example, write that wrapper to `artifacts/<network>/current/inputs/inputs.<run_id>.json`
  - pass `INPUTS_TEMPLATE=<locked_wrapper_path>` to `ops/tools/bundle.sh`
  - do not accept raw constructor params or signer secrets in CI
  - `inputs.json` for lanes that declare `required_inputs` (Sepolia/Mainnet deploy default)
  - `bundle_manifest.json`
- Upload bundle as CI artifact

### Local CD (Signing OS only)
- Download bundle from AIRLOCK (untrusted input)
- Verify manifest hashes + policy compatibility
- Verify inputs pinning/coherence (`inputs.json` + `intent.json.inputs_sha256`) when required
- Human approval recorded **before apply**
- Apply with keystore + Ledger only (Safe signers for govern/treasury lanes)
- Produce post-apply evidence (`txs.json`, `snapshots/*`), then run postconditions to generate `postconditions.json`
- The scaffold default is `POSTCONDITIONS_MODE=auto`; manual mode remains available for compatibility

### Audit lane-process assurance (periodic or release-gated)
- Build an audit plan (`audit_plan.json`) over selected run ids
- Collect evidence index from bundle artifacts (`audit_evidence_index.json`)
- Verify controls (`audit_verification.json`) and produce findings/report
- Record signoff tied to report hash (`signoff.json`, optional but recommended)

Audit output contract (required every run):
- `audit_plan.json`
- `audit_evidence_index.json`
- `audit_verification.json`
- `audit_report.json`
- `findings.json`

## No manual args at apply time
Apply **must not** accept manual calldata, addresses, or tx hashes. It must read from the bundle artifacts.
For lanes with required inputs, apply must set inputs path from the bundle internally and reject mismatched external overrides.

## No LLM in apply
LLMs may be used to author scripts and docs, but **must never** be invoked at runtime for apply.
Agent responses MUST follow this order whenever discussing ops-step/tool execution or results (see trigger rules):
- Minimal Evidence Pack
- Common Answer
See `docs/agent-trust-model.md`.

Downstream repos should paste the root-ready contract snippet into their repo root `AGENTS.md` so agent runners auto-load it:
- `docs/snippets/root-AGENTS-ops-agent-contract.md`
- `docs/snippets/root-AGENTS-audit-response-contract.md`

Audit claims must explicitly separate `VERIFIED` from `INFERRED`.

## AIRLOCK integrity rules
- AIRLOCK is **untrusted input**.
- Bundles are immutable once approved.
- Apply **refuses** on manifest mismatch or dirty repo.
- Chain truth is preferred over local `txs.json` when verifying.

## Rehearsal → Mainnet gating (Devnet-first)
If policy requires a rehearsal proof:
- Mainnet apply **refuses** unless a rehearsal bundle exists on the configured proof network with:
  - `txs.json`
  - `postconditions.json`
  - manifest hash match

Canonical gate keys (per lane):
- `gates.require_rehearsal_proof` (boolean)
- `gates.rehearsal_proof_network` (`devnet` | `sepolia`)

Canonical proof env var:
- `REHEARSAL_PROOF_RUN_ID`

Backward-compatible fallback support in scaffold apply script:
- `DEVNET_PROOF_RUN_ID`
- `SEPOLIA_PROOF_RUN_ID`

Backward-compatible legacy policy keys are temporarily supported for migration:
- `requires_devnet_rehearsal_proof` / `gates.require_devnet_rehearsal_proof`
- `requires_sepolia_rehearsal_proof` / `gates.require_sepolia_rehearsal_proof`

At minimum, proof means a successful rehearsal run bundle archived and referenced by run id.
