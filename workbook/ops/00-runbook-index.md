# PATH ops runbooks

- Devnet runbook (moved): `../localnet/workbook/ops/devnet-runbook.md`
- [Sepolia runbook](sepolia-runbook.md)
- [Mainnet runbook](mainnet-runbook.md)

All runbooks assume:
- env files live outside the repo (e.g., `~/.config/inshell/path/env/<network>.env`)
- scripts are run from the repo root (`./scripts/ops/...`) except devnet, which uses `../localnet`
- artifacts are written to `workbook/artifacts/<network>/...` (devnet artifacts live under `../localnet/workbook/artifacts/devnet`)
