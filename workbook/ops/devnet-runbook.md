# Devnet runbook

## A) Preflight checklist
- correct network selected (devnet)
- correct RPC reachable
- deployer funded (minimal STRK)
- multisig funded (minimal STRK)
- signers available (Mac A, Ledger, Mac B)
- “no browsing” rule confirmed for signer environments

## B) Execute scripts (exact commands)
```bash
source scripts/devnet/00_env.sh
scripts/devnet/01_preflight.sh
scripts/devnet/10_group_A_utils.sh
scripts/devnet/20_group_C_path_core.sh
scripts/devnet/30_group_B_renderer.sh
scripts/devnet/40_group_D_pulse.sh
scripts/devnet/50_group_E_movements.sh
```

All‑in‑one:
```bash
scripts/devnet/rehearse_all.sh
```

## C) Verification steps
```bash
scripts/devnet/05_smoke_e2e.sh
```

## D) Logging
- append to `workbook/runs/run-YYYYMMDD.md`
- include: class hashes, addresses, tx hashes, and any anomalies

## E) Failure handling
- declare ok but deploy failed → rerun the failed group only
- renderer failed → rerun Group B after confirming token id
- pulse failed → rerun Group D after verifying adapter wiring
