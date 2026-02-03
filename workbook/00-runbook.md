# PATH Devnet Runbook Index

This runbook is the operator-facing index for the devnet rehearsal. It is the
single entry point to the A–E workbook sections and the stepwise scripts.

## Order of operations (why this order)

1) **Preflight** — ensure devnet + tooling + artifacts are healthy.
2) **Group A (Utilities)** — deploy pprf + step_curve used by PathLook.
3) **Group C (Path core)** — deploy PathNFT + minter + adapter, mint a known token id.
4) **Group B (Renderer)** — generate SVG/metadata for the minted token.
5) **Group D (Pulse)** — deploy auction, wire adapter, place a bid, snapshot state.
6) **Group E (Movements)** — consume THOUGHT → WILL → AWA and verify metadata/stage.

Notes:
- PathNFT’s constructor requires a PathLook address. The Group C script will
  deploy PathLook automatically if missing.
- Renderer (Group B) requires a minted token id from Group C.

## Source of env vars

- `scripts/devnet/00_env.sh` (single source of truth)
  - sets `RPC`, `ACCOUNT`, `ACCOUNTS_FILE`, artifact paths, and `PATH_REPO`.

## Artifacts

All scripts write to:
- `workbook/artifacts/devnet/addresses.json`
- `workbook/artifacts/devnet/txs.json`
- `workbook/artifacts/devnet/svg/`
- `workbook/artifacts/devnet/metadata/`

## Workbook sections

- Group A — `workbook/A-utils.md`
- Group B — `workbook/B-renderer.md`
- Group C — `workbook/C-path-core.md`
- Group D — `workbook/D-pulse.md`
- Group E — `workbook/E-movements.md`

## Script entrypoints

Stepwise scripts (recommended):
- `scripts/devnet/01_preflight.sh`
- `scripts/devnet/10_group_A_utils.sh`
- `scripts/devnet/20_group_C_path_core.sh`
- `scripts/devnet/30_group_B_renderer.sh`
- `scripts/devnet/40_group_D_pulse.sh`
- `scripts/devnet/50_group_E_movements.sh`

All-in-one:
- `scripts/devnet/rehearse_all.sh`

## Run log

Use `workbook/runs/run-YYYYMMDD.md` to capture:
- date/time
- repo commit hash
- RPC
- class hashes, addresses, txs
- results + anomalies
