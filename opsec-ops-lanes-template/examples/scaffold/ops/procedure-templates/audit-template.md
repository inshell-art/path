# Audit procedure template

Purpose: run process controls over lane evidence and produce signoff artifacts.

Prereqs:
- Audit policy is configured (`ops/policy/audit.policy.json` or `.example.json`).
- Target run ids are available under `bundles/<network>/`.

Steps:
1. `NETWORK=<net> AUDIT_ID=<id> RUN_IDS=<r1,r2> ops/tools/audit_plan.sh`
2. `NETWORK=<net> AUDIT_ID=<id> ops/tools/audit_collect.sh`
3. `NETWORK=<net> AUDIT_ID=<id> ops/tools/audit_verify.sh`
4. `NETWORK=<net> AUDIT_ID=<id> ops/tools/audit_report.sh`
5. `make -C ops audit-gate NETWORK=<net> AUDIT_ID=<id>` (release branches/tags)
6. `NETWORK=<net> AUDIT_ID=<id> AUDIT_APPROVER=<name> ops/tools/audit_signoff.sh` (optional)

Stop conditions:
- required artifacts missing
- schema validation failure
- policy thresholds exceeded for release gating
