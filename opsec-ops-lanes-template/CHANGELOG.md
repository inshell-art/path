# Changelog

## 2026-02-22

### breaking: devnet-first rehearsal and generic proof gating

- Added Devnet as a first-class rehearsal network across template scripts, examples, and CI workflow inputs.
- Mainnet example write lanes now use generic rehearsal gates:
  - `gates.require_rehearsal_proof`
  - `gates.rehearsal_proof_network`
- Mainnet example policies now default to Devnet proof (`rehearsal_proof_network: "devnet"`).
- Added new template/example files:
  - `policy/devnet.policy.example.json`
  - `examples/scaffold/ops/policy/lane.devnet.example.json`
  - `examples/scaffold/artifacts/devnet/current/addresses.example.json`
  - `examples/toy/artifacts/devnet/current/*`
- Updated apply gate logic to resolve proof bundles from `bundles/<rehearsal_network>/<run_id>/` instead of hardcoding Sepolia.

### migration notes

- New canonical proof env var:
  - `REHEARSAL_PROOF_RUN_ID`
- Backward-compatible proof env fallbacks are still supported for one migration cycle:
  - `DEVNET_PROOF_RUN_ID`
  - `SEPOLIA_PROOF_RUN_ID`
- Deprecated but temporarily supported legacy policy keys:
  - `requires_devnet_rehearsal_proof` / `gates.require_devnet_rehearsal_proof`
  - `requires_sepolia_rehearsal_proof` / `gates.require_sepolia_rehearsal_proof`

## 2026-02-11

### breaking: drop legacy lane aliases, enforce semantic lane IDs only

- Removed `lane_aliases` from:
  - `policy/sepolia.policy.example.json`
  - `policy/mainnet.policy.example.json`
- Semantic lane IDs are now the only supported machine-facing IDs:
  - `observe`, `plan`, `deploy`, `handoff`, `govern`, `treasury`, `operate`, `emergency`
- Updated example intent lane value to semantic form in:
  - `examples/toy/artifacts/sepolia/current/intents/deploy_gov_safe.intent.json`

### Migration required for downstream repos

- Use semantic lane names only in:
  - policy lane keys
  - workflow inputs (`LANE`)
  - intent artifacts (`"lane": "<semantic_id>"`)
- Remove alias-normalization logic and legacy `lane_aliases` blocks in downstream tooling and policy files.
