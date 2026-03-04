# Codex guide — adopting the template inside a downstream repo

This file is intended for use inside a downstream repo that wants to adhere to the template rules.

## Add template as submodule
```bash
git submodule add <REMOTE_URL_OF_TEMPLATE> ops-template
git commit -m "Add ops-template submodule"
```

## Create instance directories
```bash
mkdir -p ops/policy ops/runbooks artifacts/devnet/current artifacts/sepolia/current artifacts/mainnet/current audits/devnet
```

## Copy example policies (edit placeholders)
```bash
cp ops-template/policy/devnet.policy.example.json ops/policy/lane.devnet.json
cp ops-template/policy/sepolia.policy.example.json ops/policy/lane.sepolia.json
cp ops-template/policy/mainnet.policy.example.json ops/policy/lane.mainnet.json
cp ops-template/policy/audit.policy.example.json ops/policy/audit.policy.json
```

For Sepolia/Mainnet deploy lanes:
- keep `required_inputs: [{\"kind\":\"constructor_params\"}]` in lane policy
- run `ops/tools/lock_inputs.sh` before bundle generation
- pass `INPUTS_TEMPLATE=<locked_inputs_path>` to `ops/tools/bundle.sh`
- use `PARAMS_SCHEMA` in `lock_inputs.sh` for downstream-specific strict validation

## Add audit module scripts
Use scaffold scripts as a baseline:
- `ops-template/examples/scaffold/ops/tools/audit_plan.sh`
- `ops-template/examples/scaffold/ops/tools/audit_collect.sh`
- `ops-template/examples/scaffold/ops/tools/audit_verify.sh`
- `ops-template/examples/scaffold/ops/tools/audit_report.sh`
- `ops-template/examples/scaffold/ops/tools/audit_signoff.sh`

Wire make targets in `ops/Makefile`:
- `audit-plan`, `audit-collect`, `audit-verify`, `audit-report`, `audit-signoff`, `audit-gate`

Paste response-contract snippets into downstream root `AGENTS.md`:
- `ops-template/docs/snippets/root-AGENTS-ops-agent-contract.md`
- `ops-template/docs/snippets/root-AGENTS-audit-response-contract.md`

## Keep secrets out-of-repo
Store keystore files and signer metadata outside the repo and reference them via env vars (gitignored).
