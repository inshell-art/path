# Changelog

## 2026-03-04

### breaking: replace deploy-params gate with first-class `inputs.json`

- Switched Sepolia/Mainnet deploy lane examples to policy-driven inputs requirements:
  - `lanes.deploy.required_inputs: [{"kind": "constructor_params"}]`
- Added first-class inputs wrapper schema:
  - `schemas/inputs.schema.json`
- Added lock helper:
  - `examples/scaffold/ops/tools/lock_inputs.sh`
- Updated scaffold pipeline scripts:
  - `bundle.sh` now accepts `INPUTS_TEMPLATE` and pins `intent.json.inputs_sha256`
  - `verify_bundle.sh` validates `inputs.json` schema + coherence + hash binding
  - `approve_bundle.sh` binds `approval.json.inputs_sha256`
  - `apply_bundle.sh` enforces bundled `inputs.json` for lanes with `required_inputs` and rejects mismatched external `INPUTS_FILE`
- Updated CI and tests:
  - workflow input moved to `inputs_json`
  - added `examples/scaffold/tests/inputs_gate.sh`
- Updated audit control evidence for `AUD-011` to inputs-wrapper artifacts.
- Removed old deploy-params-only schema:
  - `schemas/deploy_params.schema.json`

### migration notes (downstream repos)

- Replace deploy-params policy blocks with lane-level `required_inputs`.
- Replace `DEPLOY_PARAMS_FILE` flow with:
  - `ops/tools/lock_inputs.sh` (source params -> locked wrapper)
  - `INPUTS_TEMPLATE=<locked_wrapper_path>` for `ops/tools/bundle.sh`
- Update downstream artifact bindings:
  - `intent.json.inputs_sha256`
  - `approval.json.inputs_sha256`
  - apply evidence `txs.json.inputs_file` + `txs.json.inputs_sha256`

### feat: deploy params integrity gate (Sepolia/Mainnet deploy lanes)

- Added deploy params policy contract to Sepolia/Mainnet lane examples:
  - `deploy_params.required_networks`, `deploy_params.required_lanes`
  - `deploy_params.bundle_filename`, `deploy_params.apply_env_var`
  - `deploy_params.canonicalization`, `deploy_params.allow_external_override`
  - `deploy_params.schema_file`, `deploy_params.semantic_validator_cmd`
- Added `deploy_params_pinned` to `lanes.deploy.required_checks` in Sepolia/Mainnet policy examples.
- Added new schema:
  - `schemas/deploy_params.schema.json`
- Updated scaffold bundle flow:
  - `bundle.sh` now requires/canonicalizes deploy params for required lanes and pins hash in `intent.json.deploy_params_sha256`
  - `bundle_manifest.json` includes bundled deploy params as immutable when present
- Updated verifier:
  - `verify_bundle.sh` enforces deploy params presence/hash/manifest binding/schema validation and optional semantic validator command
- Updated approval/apply binding:
  - `approve_bundle.sh` now includes `deploy_params_sha256` in `approval.json`
  - approval phrase includes deploy params hash suffix when present
  - `apply_bundle.sh` enforces bundled deploy params path/hash binding and records params path/hash in `txs.json` and `snapshots/post_state.json`
- Added audit control:
  - `AUD-011` Deploy params pinned and enforced at apply
  - wired into `docs/audit-controls-catalog.md`, `audit.policy.example.json`, and scaffold `audit_verify.sh` / `audit_report.sh`
- Added scaffold test:
  - `examples/scaffold/tests/deploy_params_gate.sh`

## 2026-03-03

### feat: audit module v1.1 (contract hardening)

- Hardened audit module contract and defaults:
  - required audit outputs now explicitly include:
    - `audit_plan.json`
    - `audit_evidence_index.json`
    - `audit_verification.json`
    - `audit_report.json`
    - `findings.json`
  - `signoff.json` remains optional but recommended
- Extended audit policy template with:
  - `required_artifacts`
  - `claims.require_tier_labels`
  - `release_gate.fail_on_status`
- Updated audit schemas:
  - `audit_plan.schema.json` requires `generated_at`
  - `audit_report.schema.json` now requires `network` and `inferred_claims`
  - `audit_finding.schema.json` now requires `tier`
- Updated scaffold audit scripts:
  - `audit_plan.sh` enforces schema-required keys
  - `audit_report.sh` now requires plan/index/verification inputs, validates claim-tier outputs, and enforces required artifact presence before finalize
  - `audit_gate.sh` enforces release-gate policy status checks
- Updated scaffold CI example (`examples/scaffold/.github/workflows/ops_audit.yml`):
  - supports both periodic audit mode and release-gate mode
  - includes tag-triggered release-gate example (`v*`)
- Added scaffold test fixtures/scripts:
  - `examples/scaffold/tests/audit_smoke.sh`
  - `examples/scaffold/tests/audit_negative.sh`
  - negative checks cover manifest mismatch, commit mismatch, missing approval/hash mismatch, and missing required rehearsal postconditions
- Added missing fixture artifact:
  - `examples/scaffold/audits/devnet/audit-20260222-example/audit_verification.json`

### migration notes (downstream repos)

- Update `ops/policy/audit.policy.json` from the v1.1 example.
- Wire audit targets in `ops/Makefile`:
  - `audit-plan`, `audit-collect`, `audit-verify`, `audit-report`, `audit-signoff`, `audit-gate`
- Paste/update root `AGENTS.md` snippets:
  - `docs/snippets/root-AGENTS-ops-agent-contract.md`
  - `docs/snippets/root-AGENTS-audit-response-contract.md`

## 2026-03-01

### feat: audit module v1 (opt-in)

- Added audit module docs:
  - `docs/audit-framework.md`
  - `docs/audit-runbook.md`
  - `docs/audit-controls-catalog.md`
  - `docs/snippets/root-AGENTS-audit-response-contract.md`
- Added audit schemas:
  - `schemas/audit_plan.schema.json`
  - `schemas/audit_report.schema.json`
  - `schemas/audit_finding.schema.json`
- Added audit policy templates:
  - `policy/audit.policy.example.json`
  - `examples/scaffold/ops/policy/audit.policy.example.json`
- Added scaffold audit tools and make targets:
  - `audit_plan.sh`, `audit_collect.sh`, `audit_verify.sh`, `audit_report.sh`, `audit_signoff.sh`
  - `audit-plan`, `audit-collect`, `audit-verify`, `audit-report`, `audit-signoff`, `audit-all`
- Added scaffold audit artifacts fixture:
  - `examples/scaffold/audits/devnet/audit-20260222-example/*`
- Added optional CI entrypoint:
  - `examples/scaffold/.github/workflows/ops_audit.yml`

Compatibility:
- Existing lane flow remains unchanged (`bundle -> verify -> approve -> apply -> postconditions`).
- Audit module is opt-in for the first release cycle.

## 2026-02-22

### breaking: devnet-first rehearsal and generic proof gating

- Added Devnet as a first-class rehearsal network across template scripts, examples, and CI workflow inputs.
- Mainnet example write lanes now use generic rehearsal gates:
  - `gates.require_rehearsal_proof`
  - `gates.rehearsal_proof_network`
- Mainnet example policies now default to Devnet proof (`rehearsal_proof_network: "devnet"`).
- Added new template/example files:
  - `policy/devnet.policy.example.json`
  - `examples/scaffold/ops/policy/lane.devnet.example.json`
  - `examples/scaffold/artifacts/devnet/current/addresses.example.json`
  - `examples/toy/artifacts/devnet/current/*`
- Updated apply gate logic to resolve proof bundles from `bundles/<rehearsal_network>/<run_id>/` instead of hardcoding Sepolia.

### migration notes

- New canonical proof env var:
  - `REHEARSAL_PROOF_RUN_ID`
- Backward-compatible proof env fallbacks are still supported for one migration cycle:
  - `DEVNET_PROOF_RUN_ID`
  - `SEPOLIA_PROOF_RUN_ID`
- Deprecated but temporarily supported legacy policy keys:
  - `requires_devnet_rehearsal_proof` / `gates.require_devnet_rehearsal_proof`
  - `requires_sepolia_rehearsal_proof` / `gates.require_sepolia_rehearsal_proof`

## 2026-02-11

### breaking: drop legacy lane aliases, enforce semantic lane IDs only

- Removed `lane_aliases` from:
  - `policy/sepolia.policy.example.json`
  - `policy/mainnet.policy.example.json`
- Semantic lane IDs are now the only supported machine-facing IDs:
  - `observe`, `plan`, `deploy`, `handoff`, `govern`, `treasury`, `operate`, `emergency`
- Updated example intent lane value to semantic form in:
  - `examples/toy/artifacts/sepolia/current/intents/deploy_gov_safe.intent.json`

### Migration required for downstream repos

- Use semantic lane names only in:
  - policy lane keys
  - workflow inputs (`LANE`)
  - intent artifacts (`"lane": "<semantic_id>"`)
- Remove alias-normalization logic and legacy `lane_aliases` blocks in downstream tooling and policy files.
