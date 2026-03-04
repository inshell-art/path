# Audit Runbook

Purpose: run deterministic process audits over lane evidence.

## Prereqs
- bundle artifacts exist under `bundles/<network>/<run_id>/`
- audit policy exists (`ops/policy/audit.policy.json` or `.example.json`)
- repo checkout is pinned to intended commit

## Steps
1. Plan
```bash
NETWORK=devnet AUDIT_ID=<audit_id> RUN_IDS=<run1,run2> ops/tools/audit_plan.sh
```

2. Collect
```bash
NETWORK=devnet AUDIT_ID=<audit_id> ops/tools/audit_collect.sh
```

3. Verify controls
```bash
NETWORK=devnet AUDIT_ID=<audit_id> ops/tools/audit_verify.sh
```

4. Build report
```bash
NETWORK=devnet AUDIT_ID=<audit_id> ops/tools/audit_report.sh
```

5. Release gate check (recommended for release branches/tags)
```bash
make -C ops audit-gate NETWORK=devnet AUDIT_ID=<audit_id>
```

6. Signoff (optional but recommended)
```bash
NETWORK=devnet AUDIT_ID=<audit_id> AUDIT_APPROVER=<name> ops/tools/audit_signoff.sh
```

## Outputs (contract)
Required:
- `audits/<network>/<audit_id>/audit_plan.json`
- `audits/<network>/<audit_id>/audit_evidence_index.json`
- `audits/<network>/<audit_id>/audit_verification.json`
- `audits/<network>/<audit_id>/audit_report.json`
- `audits/<network>/<audit_id>/findings.json`

Optional but recommended:
- `audits/<network>/<audit_id>/signoff.json`

## Stop Conditions
- missing required audit inputs
- control execution errors
- schema validation failure in report stage

## Notes
- findings are sorted critical to low in report output
- `VERIFIED` claims are only for checks that were actually executed
- `INFERRED` claims are explicitly labeled and never presented as `VERIFIED`
