# PATH Devnet Hand-Check Workbook

This workbook is a hands-on guide for verifying the PATH contracts on a local devnet. It is organized in groups (A–E), from utilities to auction/movements. Each group has:

- deploy steps
- view calls
- one state-changing invoke
- re-checks to confirm changes
- artifacts saved to `workbook/artifacts/devnet/`

## Quick start

1) Ensure devnet is alive:
```bash
curl -sSf http://127.0.0.1:5050/is_alive && echo
```

2) Load env helpers:
```bash
source scripts/devnet/00_env.sh
```

3) Verify toolchain:
```bash
scarb --version
snforge --version
sncast --version
```

## Layout

- `workbook/A-utils.md` — pprf + step-curve
- `workbook/B-renderer.md` — path-look
- `workbook/C-path-core.md` — path_nft + minter + adapter
- `workbook/D-pulse.md` — pulse auction
- `workbook/E-movements.md` — movement stages

Note: operational order is A → C → B → D → E (renderer needs a minted token).

## Artifacts

Artifacts are written by scripts and manual commands:

- `workbook/artifacts/devnet/addresses.json`
- `workbook/artifacts/devnet/txs.json`
- `workbook/artifacts/devnet/svg/`
- `workbook/artifacts/devnet/metadata/`

## Helper scripts

- `scripts/devnet/01_deploy_utils.sh`
- `scripts/devnet/02_deploy_renderer.sh`
- `scripts/devnet/03_deploy_path_core.sh`
- `scripts/devnet/04_deploy_pulse.sh`
- `scripts/devnet/05_smoke_e2e.sh`

## Logging template

Use `workbook/runs/run-YYYYMMDD.md` to log each hand-check run.
