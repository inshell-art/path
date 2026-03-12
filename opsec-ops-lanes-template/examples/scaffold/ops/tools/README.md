# Ops tools (reference implementations)

These scripts are runnable reference implementations for the template contracts.
Downstream repos can adapt them, but should preserve the same inputs/outputs and refusal behavior.

Expected behavior by script:
- `lock_inputs.sh` locks high-entropy params into a run-scoped wrapper (`inputs.<run_id>.json`) and can enforce strict schema usage (`STRICT_PARAMS_SCHEMA=1`).
- `bundle.sh` creates `run.json`, `intent.json`, `checks.json`, and `bundle_manifest.json` (plus `inputs.json` when provided/required).
- `verify_bundle.sh` verifies manifest hashes, git commit, policy compatibility, and inputs coherence/pinning for lanes with `required_inputs`.
- `approve_bundle.sh` records human approval tied to the bundle hash (and `inputs_sha256` when present).
- `apply_bundle.sh` executes the approved bundle in signing context only and enforces bundled `inputs.json` on required lanes.
- `postconditions.sh` records post-apply verification and writes `postconditions.json` (`POSTCONDITIONS_MODE=auto` by default, optional `manual` compatibility mode).
- `audit_plan.sh` creates `audit_plan.json`.
- `audit_collect.sh` indexes evidence files and writes `audit_evidence_index.json`.
- `audit_verify.sh` runs control checks and writes `audit_verification.json`.
- `audit_report.sh` generates `audit_report.json` and `findings.json`.
- `audit_signoff.sh` writes `signoff.json` linked to the report hash.
- `audit_gate.sh` enforces release-gate policy on `audit_report.json`.

Audit output contract:
- required: `audit_plan.json`, `audit_evidence_index.json`, `audit_verification.json`, `audit_report.json`, `findings.json`
- optional but recommended: `signoff.json`

All write operations must use keystore mode only. Do not use accounts-file signing.

Release gate behavior:
- periodic audit runs can publish artifacts without blocking releases
- release-gate runs should fail when `audit_report.json.status` is listed under `release_gate.fail_on_status`

Inputs behavior:
- deploy lanes can require first-class inputs via `required_inputs` (for example `[{\"kind\":\"constructor_params\"}]`)
- lock params with `lock_inputs.sh` and pass to `bundle.sh` via `INPUTS_TEMPLATE`
- for Sepolia/Mainnet production flows, use a downstream strict `PARAMS_SCHEMA` with `STRICT_PARAMS_SCHEMA=1`
- template `examples/inputs/*.example.json` schemas are minimal; they are refused on Sepolia/Mainnet unless `ALLOW_EXAMPLE_PARAMS_SCHEMA=1`
- when schema validation is used, `inputs.json.source` includes `params_schema_path_hint` and `params_schema_sha256`
- `apply_bundle.sh` sets/uses bundled `inputs.json` only and rejects mismatched external `INPUTS_FILE`
- `postconditions.sh` auto mode computes deterministic `pass|fail` from bundle predicates (`txs_present`, `bundle_verified`, optional `checks.path.json`, deploy snapshot presence)
- manual compatibility: `POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pending|pass|fail`

Reference tests:
- `examples/scaffold/tests/audit_smoke.sh`
- `examples/scaffold/tests/audit_negative.sh`
- `examples/scaffold/tests/inputs_gate.sh`

Review and adapt these scripts before production use.
