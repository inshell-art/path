# Ops tools (stubs)

These scripts are placeholders. Replace them with your repo's real commands.

Expected behavior by script:
- `bundle.sh` creates `run.json`, `intent.json`, `checks.json`, optional `checks.path.json` (devnet PATH rehearsal), and `bundle_manifest.json`.
- `verify_bundle.sh` verifies manifest hashes, git commit, and policy compatibility.
- `approve_bundle.sh` records human approval tied to the bundle hash.
- `apply_bundle.sh` executes the approved bundle in signing context only.
- `postconditions.sh` records post-apply verification and writes `postconditions.json`.
- `generate_path_checks.sh` probes PATH readiness (devnet/sepolia/mainnet) and writes `checks.path.json` with `required_checks` and `path_invariants`.
- `audit_plan.sh` creates `audit_plan.json`.
- `audit_collect.sh` indexes evidence files and writes `audit_evidence_index.json`.
- `audit_verify.sh` runs control checks and writes `audit_verification.json`.
- `audit_report.sh` generates `audit_report.json` and `findings.json`.
- `audit_signoff.sh` writes `signoff.json` linked to the report hash.

All write operations must use keystore mode only. Do not use accounts-file signing.

Optional bundle tooling (reference implementations):
- `bundle.sh`, `verify_bundle.sh`, `approve_bundle.sh`, `apply_bundle.sh`

Optional audit tooling (reference implementations):
- `audit_plan.sh`, `audit_collect.sh`, `audit_verify.sh`, `audit_report.sh`, `audit_signoff.sh`

Review and adapt these scripts before use.
