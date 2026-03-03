# Audit Framework

This module adds process-audit capability to the ops-lanes template.

Intent:
- keep lane execution controls deterministic (`bundle -> verify -> approve -> apply -> postconditions`)
- add periodic, independent process assurance over produced evidence

This is operational/process auditability. It is not smart-contract security auditing.

## Scope
In scope:
- audit artifacts and schemas
- scaffold audit scripts and runbook
- control catalog mapped to lane artifacts
- agent response contract for audit prompts
- CI entrypoints for periodic audit checks

Out of scope:
- formal external security-audit workflow
- legal attestation workflows
- vendor-specific compliance wording

## Relationship To Lanes
- Lanes produce evidence per run.
- Audit consumes that evidence and verifies controls.
- Lane checks are change-scoped; audit is periodic or release-gated.

## Audit Lifecycle
1. `audit_plan.sh`
2. `audit_collect.sh`
3. `audit_verify.sh`
4. `audit_report.sh`
5. `audit_signoff.sh`

Default location:
- `audits/<network>/<audit_id>/`

Expected files:
- `audit_plan.json`
- `audit_evidence_index.json`
- `audit_verification.json`
- `audit_report.json`
- `findings.json`
- `signoff.json`

## Data Contracts
Schemas:
- `schemas/audit_plan.schema.json`
- `schemas/audit_report.schema.json`
- `schemas/audit_finding.schema.json`

## Controls
Control IDs and intent are defined in:
- `docs/audit-controls-catalog.md`

## Policy
Audit policy template:
- `policy/audit.policy.example.json`

Downstream copy target:
- `ops/policy/audit.policy.json`

## CI Hooks
Recommended:
- schedule periodic `audit-all` runs for non-prod branches
- run pre-release audit gate and fail on policy threshold breach
- upload `audits/<network>/<audit_id>/` as immutable artifact

## Downstream Adoption Sequence
1. Pull template update.
2. Copy `policy/audit.policy.example.json` to `ops/policy/audit.policy.json`.
3. Add/adapt audit scripts and `Makefile` targets.
4. Run first Devnet audit over recent run ids.
5. Tune thresholds and control strictness.
6. Enable release gate for Sepolia/Mainnet branches.

## Compatibility
- audit module is opt-in for the first release cycle
- existing lane scripts/flow stay unchanged
