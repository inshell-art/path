# Scaffold example (downstream repo)

Purpose: provide a minimal, safe layout to integrate this template and run **bundle rehearsals** in CI while keeping **apply** on a Signing OS.
Default rehearsal network is **devnet** (Sepolia remains optional).

This scaffold is a runnable reference baseline. Adapt `ops/tools/` for your repo while keeping the same artifact contracts.

## Layout
- `ops/` — policy, runbooks, and tooling wrappers
- `ops/tests/` — regression tests for ops helper scripts
- `artifacts/` — generated intents, checks, approvals, and snapshots
- `bundles/` — immutable bundles produced by CI and consumed by Signing OS
- `audits/` — generated audit plans, evidence indexes, reports, findings, and signoffs
- `.github/workflows/ops_bundle.yml` — example CI workflow (copy into downstream repo)
- `.github/workflows/ops_tests.yml` — scaffold regression test workflow
- `.env.example` — local-only environment variables (no secrets)

## How to use
1. Copy this scaffold into your downstream repo root, or copy the pieces you want.
2. Implement `ops/tools/bundle.sh`, `verify_bundle.sh`, `approve_bundle.sh`, `apply_bundle.sh`, and `postconditions.sh` for your toolchain.
3. Implement or adapt audit scripts under `ops/tools/audit_*.sh`.
4. Copy and edit the example policies in `ops/policy/`.
5. Keep secrets out of git.

## CI and rehearsal guidance
- CI builds **bundles** (run/intent/checks + manifest) and uploads artifacts.
- The scaffold `ops_bundle.yml` example is bundle-only: no signer secrets, no keystore, no passwords.
- For lanes with `required_inputs`, CI accepts `inputs_json` as the locked wrapper output of `ops/tools/lock_inputs.sh`, writes it to `artifacts/<network>/current/inputs/inputs.<run_id>.json`, and bundles from there.
- Apply happens only on a Signing OS with keystore mode (no raw `*_PRIVATE_KEY` exports).
- After apply, run postconditions to record chain verification (`POSTCONDITIONS_MODE=auto` default).
- Run periodic `audit-all` to validate process controls over lane artifacts.
- Use `audit-gate` for release branches/tags.
- Sepolia/Mainnet deploy lanes require pinned `inputs.json` by default (`required_inputs`, generated via `ops/tools/lock_inputs.sh` and passed as `INPUTS_TEMPLATE`).
- Raw constructor params stay outside CI; CI should receive only the locked wrapper JSON.
- For Sepolia/Mainnet deploy lanes, use downstream strict `PARAMS_SCHEMA` with `STRICT_PARAMS_SCHEMA=1`.
- No LLM calls are allowed at apply time.
- HOT wallets are not ops-lane signers.

## References
- `docs/ops-lanes-agent.md`
- `docs/opsec-ops-lanes-signer-map.md`
- `docs/downstream-ops-contract.md`
- `docs/pipeline-reference.md`
