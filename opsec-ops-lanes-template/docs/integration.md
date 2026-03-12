# Integration guide

This template is designed to be *imported* into one or more downstream repos without copying secrets.

See also:
- `codex/BUSINESS_REPO_ADOPTION.md` for a short adoption checklist.
- `docs/downstream-ops-contract.md` for the required CI/CD rules.
- `docs/pipeline-reference.md` for the step-by-step pipeline.

## Scaffold example

See `examples/scaffold/` for a minimal downstream repo layout and CI rehearsal stub (plan + check only, Devnet-first).
An optional bundle workflow example is included for teams that want deterministic bundles.

## Recommended structure

```
downstream-repo/
  ops-template/                 # this repo as a submodule (or subtree)
    docs/
    policy/
    schemas/
  ops/
    policy/
      lane.devnet.json          # your real policy (no secrets)
      lane.sepolia.json         # your real policy (no secrets)
      lane.mainnet.json
      audit.policy.json
    runbooks/
      deploy.md
      handoff.md
      govern.md
  artifacts/
    devnet/current/             # generated artifacts (safe to commit if redacted)
    devnet/runs/<run_id>/
    sepolia/current/            # generated artifacts (safe to commit if redacted)
    sepolia/runs/<run_id>/
    mainnet/current/
  audits/
    devnet/<audit_id>/
    sepolia/<audit_id>/
    mainnet/<audit_id>/
  .env.example                  # env vars with local paths (no secrets)
  .gitignore
```

## Keeping secrets out of the repo

Use *local-only* locations for keystores and signer metadata:

Example (operator machine):
```
~/.opsec/
  devnet/
    deploy_sw_a/{address.txt,keystore.json}
    gov_sw_a/{address.txt,keystore.json}
    treasury_sw_a/{address.txt,keystore.json}
  sepolia/
    deploy_sw_a/{address.txt,keystore.json}
    gov_sw_a/{address.txt,keystore.json}
    treasury_sw_a/{address.txt,keystore.json}
  mainnet/
    ...
```

Only reference these via local env vars or local config files that are gitignored.

## Keystore-first operator contract

- Never export raw private keys (for example `SEPOLIA_PRIVATE_KEY`).
- Use keystore env vars (for example `SEPOLIA_DEPLOY_KEYSTORE_JSON`) plus address env vars (for example `SEPOLIA_DEPLOY_ADDRESS`) as policy expects.
- Derive `*_DEPLOY_ADDRESS` from keystore metadata (`.address`) rather than private-key math.
- Keep keystore files and password handling outside git.

## Submodule commands (example)

```bash
git submodule add <REMOTE_URL> ops-template
git commit -m "Add ops-template"
```

To update later:
```bash
git submodule update --remote --merge
git commit -am "Update ops-template"
```

## What to customize

1) Copy an example policy and edit it:
- `ops-template/policy/devnet.policy.example.json` → `ops/policy/lane.devnet.json`
- `ops-template/policy/sepolia.policy.example.json` → `ops/policy/lane.sepolia.json`
- `ops-template/policy/mainnet.policy.example.json` → `ops/policy/lane.mainnet.json`
- `ops-template/policy/audit.policy.example.json` → `ops/policy/audit.policy.json`

For Sepolia/Mainnet deploy lanes, wire locked inputs:
- run `ops/tools/lock_inputs.sh` with `NETWORK`, `LANE`, `RUN_ID`, and `INPUT_FILE=<local_params_json>`
- set `PARAMS_SCHEMA=<downstream_schema_path>` (strict project-specific schema)
- pass `INPUTS_TEMPLATE=<artifacts/<network>/current/inputs/inputs.<run_id>.json>` to `ops/tools/bundle.sh`
- keep raw params outside git (or commit only if intentionally public/safe)

For the scaffold CI bundle workflow:
- local operator flow produces the locked wrapper outside CI via `ops/tools/lock_inputs.sh`
- GitHub Actions receives that wrapper as the `inputs_json` workflow input
- the workflow writes it to `artifacts/<network>/current/inputs/inputs.<run_id>.json` and runs `ops/tools/bundle.sh`
- do not pass raw constructor params, keystores, passwords, or signer secrets into CI

Schema discipline for required inputs:
- Sepolia/Mainnet deploy lanes with `required_inputs` should use `STRICT_PARAMS_SCHEMA=1` in `lock_inputs.sh`.
- Template example schemas under `examples/inputs/*.example.json` are minimal and are not production-safe validation.
- Recommended downstream naming: `schemas/params/<kind>.<contract>.<lane>.schema.json`.

2) Define your signer aliases (EOA + Safe addresses) in `artifacts/<net>/current/addresses.json`.

3) Keep runbooks in `ops/runbooks/`, but reference the lane rules in:
- `ops-template/docs/ops-lanes-agent.md`
- `ops-template/docs/opsec-ops-lanes-signer-map.md`

4) Wire audit targets in `ops/Makefile`:
- `audit-plan`, `audit-collect`, `audit-verify`, `audit-report`, `audit-signoff`, `audit-gate`

5) Paste response-contract snippets into downstream root `AGENTS.md`:
- `ops-template/docs/snippets/root-AGENTS-ops-agent-contract.md`
- `ops-template/docs/snippets/root-AGENTS-audit-response-contract.md`

Operational split:
- remote CI builds and uploads bundles only
- local Signing OS runs `verify`, `approve`, `apply`, and `postconditions`
