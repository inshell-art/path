# Audit runbook

Purpose: audit is the read-only evidence layer over completed runs. It is not part of the authority path for `bundle`, `verify`, `approve`, `apply`, or `postconditions`.

Prereqs:
- Audit policy is configured in `ops/policy/audit.policy.json`.
- Target run ids already exist under `bundles/<network>/`.
- Audit outputs are generated under `audits/<network>/<audit_id>/` and are local by default.
- Do not commit live audit outputs unless they are deliberately reviewed and redacted.

Outputs:
- `audit_plan.json`
- `audit_manifest.json`
- `audit_verify.json`
- `audit_report.md`
- `audit_report.json`
- `audit_signoff.json`
- compatibility aliases: `audit_evidence_index.json`, `audit_verification.json`, `signoff.json`

Steps:
1. `NETWORK=<net> AUDIT_ID=<id> RUN_IDS=<r1,r2> [ALLOWED_LANES=<lane1,lane2>] ops/tools/audit_plan.sh`
2. `NETWORK=<net> AUDIT_ID=<id> ops/tools/audit_collect.sh`
3. `NETWORK=<net> AUDIT_ID=<id> ops/tools/audit_verify.sh`
4. `NETWORK=<net> AUDIT_ID=<id> ops/tools/audit_report.sh`
5. `NETWORK=<net> AUDIT_ID=<id> AUDIT_APPROVER=<name> ops/tools/audit_signoff.sh`

Behavior:
- `plan` fails if `RUN_IDS` is empty.
- `plan` requires explicit `ALLOWED_LANES` when more than one lane is in scope.
- `collect` copies bundle evidence into `audits/<network>/<audit_id>/runs/<run_id>/` and refuses secret-bearing files.
- `collect` snapshots the lane policy at each run's pinned commit as `runs/<run_id>/policy.json`.
- `verify` is fail-closed and marks missing evidence as `incomplete`, not `pass`.
- `signoff` is only allowed when `audit_verify.json.status == "pass"` and `audit_report.json.status == "pass"`.
- `signoff` fails if `audit_plan.json`, `audit_manifest.json`, or any collected run evidence changes after verify.

Stop conditions:
- required bundle evidence missing
- secret-bearing file detected during collect
- policy snapshot unavailable for a pinned run commit
- verify status `fail` or `incomplete`
- signoff hash mismatch after verify freeze
