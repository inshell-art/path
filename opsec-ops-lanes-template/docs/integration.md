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

2) Define your signer aliases (EOA + Safe addresses) in `artifacts/<net>/current/addresses.json`.

3) Keep runbooks in `ops/runbooks/`, but reference the lane rules in:
- `ops-template/docs/ops-lanes-agent.md`
- `ops-template/docs/opsec-ops-lanes-signer-map.md`
