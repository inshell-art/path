# AGENTS

## Overview
- PATH smart contracts (Cairo) plus deployment tooling and vendor dependencies.
- Primary workflows: Scarb builds/tests and Sepolia deploy scripts.

## Project layout
- `contracts/`: PathNFT, PathMinter, PathMinterAdapter, PathLook (gallery under PathLook).
- `interfaces/`: shared Cairo interfaces.
- `crates/`: test support and e2e helpers.
- `vendors/`: vendored dependencies (pulse, pprf, step-curve).
- `scripts/`: deployment scripts (Sepolia) and devnet ops helpers.
- `workbook/`: runbooks + devnet/sepolia workbooks.

## Install
- `pnpm install` (optional; for husky hooks only).
- Required tools: `scarb`, `sncast`, `starknet-devnet`, `jq`, `python3`.

## Build / Lint / Format / Test
- Build: `scarb build` (root) or `scarb build -p path_nft` (per package).
- Format: `scarb fmt` (per package or root).
- Lint: `scarb lint` (per package or root).
- Unit tests: `./scripts/test-unit.sh`.
- Full tests (includes vendor pulse): `./scripts/test-full.sh`.

## Devnet entrypoints
- Devnet runtime is managed in `../localnet` (see `../localnet/README.md`).
- Devnet scripts live under `scripts/devnet/`.
- Devnet workbook lives under `workbook/`.

## Sepolia local deploy (no CI/CD)
- Create `scripts/.env.sepolia.local` with `RPC_URL`, `SNCAST_ACCOUNTS_FILE`, `SNCAST_ACCOUNTS_NAMESPACE`, and `DECLARE_PROFILE/DEPLOY_PROFILE`.
- Create `scripts/params.sepolia.local` with `PAYTOKEN`, `TREASURY`, and any constructor overrides.
- Optional: set `PPRF_ADDR` and `STEP_CURVE_ADDR` in `scripts/params.sepolia.local` to reuse existing glyph deployments.
- Declare: `./scripts/declare-sepolia.sh` (build + declare).
- Deploy: `./scripts/deploy-sepolia.sh`.
- Configure roles: `./scripts/config-sepolia.sh`.
- Verify wiring: `./scripts/verify-sepolia.sh`.
- If using v0_10 RPC, the scripts use `scripts/sepolia_declare_v3.py` and `scripts/sepolia_invoke_v3.py` helpers for v3 transactions.
- Artifacts live under `output/sepolia/` (`classes.sepolia.json`, `addresses.sepolia.json`, `addresses.sepolia.env`, `deploy.params.sepolia.json`, and per-contract declare/deploy JSON logs).

## Definition of done
- Relevant builds/tests pass.
- `scarb fmt` and `scarb lint` run for touched packages.
- No unintended changes in `vendors/`, `output/`, or `workbook/` artifacts.
- Docs updated when interfaces or behavior change.

## Coding conventions
- Follow existing Cairo style; prefer `snake_case` names.
- Keep movement labels (`THOUGHT`, `WILL`, `AWA`) and constants consistent.
- Use `ByteArray` for string outputs and keep edits ASCII by default.

## Boundaries (do not touch unless asked)
- `vendors/` vendored code or submodules.
- `workbook/artifacts/*`, `output/*`, or `.accounts` secrets.
- Network credentials, keys, or deployment state.

## Security and leak-prevention rules
- Never introduce secrets into the repo.
- Do not add or modify code that includes any: private keys, seed phrases, mnemonics, service account JSON, API keys/tokens (RPC keys included), `.env` files, or `.pem`/`.key` files.
- Treat any `VITE_*` env vars as public (baked into client JS). Never store secrets in them.
- Always run a leak scan before committing:
  - `git diff --staged` and manually inspect for secrets.
  - `gitleaks detect --no-git --redact` (or repo’s chosen scanner).
- If any potential secret is detected, stop and remove it; do not “mask” it.
- Do not print sensitive values in CI logs (avoid `echo $TOKEN`, `printenv`, verbose debug logs with headers/keys).
- Avoid logging full RPC URLs if they include keys.
- No new third-party telemetry by default (no analytics, session replay, fingerprinting, or new error trackers unless explicitly requested).
- If error tracking exists, ensure it does not capture wallet addresses, RPC payloads, or user identifiers.
- Protect deployment and workflow integrity: do not weaken branch protections in docs/instructions; pin GitHub Action versions where possible; prefer least-privilege tokens; avoid long-lived credentials.
- Remove debug artifacts before committing (no debug-only endpoints, “test wallets”, or localhost RPC defaults in production configs).
- Security PR checklist (must pass):
  - No secrets in diff.
  - No new telemetry.
  - No new external endpoints without clear reason.
  - Build succeeds with clean env.
  - Any new config is documented and safe to be public.
