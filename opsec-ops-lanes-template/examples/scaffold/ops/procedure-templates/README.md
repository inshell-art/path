# Procedure Templates

These are minimal procedure templates for downstream repos. Customize them with your project details.

Suggested files:
- `deploy-template.md`
- `handoff-template.md`
- `govern-template.md`
- `audit-template.md`

For release branches/tags, concrete audit runbooks should include:
- `make -C ops audit-gate NETWORK=<network> AUDIT_ID=<id>`

Each concrete runbook should reference:
- `docs/ops-lanes-agent.md`
- `docs/opsec-ops-lanes-signer-map.md`
