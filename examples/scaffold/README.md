# Scaffold example (downstream repo)

Purpose: provide a minimal, safe layout to integrate this template and run **bundle rehearsals** in CI while keeping **apply** on a Signing OS.
Default rehearsal network is **devnet** (Sepolia remains optional).

This scaffold is not a runnable system. The scripts in `ops/tools/` are stubs that you must replace for your repo.

## Layout
- `ops/` — policy, runbooks, and tooling wrappers
- `artifacts/` — generated intents, checks, approvals, and snapshots
- `bundles/` — immutable bundles produced by CI and consumed by Signing OS
- `.github/workflows/ops_bundle.yml` — example CI workflow (copy into downstream repo)
- `.env.example` — local-only environment variables (no secrets)

## How to use
1. Copy this scaffold into your downstream repo root, or copy the pieces you want.
2. Implement `ops/tools/bundle.sh`, `verify_bundle.sh`, `approve_bundle.sh`, and `apply_bundle.sh` for your toolchain.
3. Copy and edit the example policies in `ops/policy/`.
4. Keep secrets out of git.

## CI and rehearsal guidance
- CI builds **bundles** (run/intent/checks + manifest) and uploads artifacts.
- Apply happens only on a Signing OS with keystore mode.
- After apply, run postconditions to record chain verification.
- No LLM calls are allowed at apply time.
- HOT wallets are not ops-lane signers.

## References
- `docs/ops-lanes-agent.md`
- `docs/opsec-ops-lanes-signer-map.md`
- `docs/downstream-ops-contract.md`
- `docs/pipeline-reference.md`
