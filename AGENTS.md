# AGENTS

## Overview
- PATH smart contracts (Cairo) plus devnet tooling and vendor dependencies.
- Primary workflows: Scarb builds/tests and devnet deployment scripts.

## Project layout
- `contracts/`: PathNFT, PathMinter, PathMinterAdapter, PathLook (gallery under PathLook).
- `interfaces/`: shared Cairo interfaces.
- `crates/`: test support and e2e helpers.
- `vendors/`: vendored dependencies (pulse, pprf, step-curve).
- `scripts/`: devnet and deployment scripts.
- `workbook/`: local artifacts, SVGs, and notes.

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
- `./scripts/devnet_watchdog.sh` (start/monitor devnet, load dump).
- `./scripts/deploy-devnet.sh` (end-to-end devnet deploy).
- `scripts/devnet/00_env.sh` (source env).
- `scripts/devnet/01_deploy_utils.sh`.
- `scripts/devnet/02_deploy_renderer.sh` (PathLook + deps).
- `scripts/devnet/03_deploy_path_core.sh`.
- `scripts/devnet/04_deploy_pulse.sh`.
- `scripts/devnet/05_smoke_e2e.sh`.

## Sepolia local deploy (no CI/CD)
- Create `scripts/.env.sepolia.local` with `RPC_URL`, `SNCAST_ACCOUNTS_FILE`, `SNCAST_ACCOUNTS_NAMESPACE`, and `DECLARE_PROFILE/DEPLOY_PROFILE`.
- Create `scripts/params.sepolia.local` with `PAYTOKEN`, `TREASURY`, and any constructor overrides.
- Optional: set `PPRF_ADDR` and `STEP_CURVE_ADDR` in `scripts/params.sepolia.local` to reuse existing glyph deployments.
- Declare: `./scripts/declare-sepolia.sh` (build + declare).
- Deploy: `./scripts/deploy-sepolia.sh`.
- Configure roles: `./scripts/config-sepolia.sh`.
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
- `workbook/artifacts/devnet/*`, `output/*`, or `.accounts` secrets.
- Network credentials, keys, or deployment state.
