# Runbooks (templates)

These are minimal runbook templates for downstream repos. Customize them with your project details.

Suggested files:
- `deploy.md`
- `handoff.md`
- `govern.md`
- `audit.md`

For release branches/tags, audit runbooks should include:
- `make -C ops audit-gate NETWORK=<network> AUDIT_ID=<id>`

Each runbook should reference:
- `docs/ops-lanes-agent.md`
- `docs/opsec-ops-lanes-signer-map.md`
