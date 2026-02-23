# PATH ops runbooks

- Devnet runbook: `devnet-runbook.md`
- [Sepolia runbook](sepolia-runbook.md)
- [Mainnet runbook](mainnet-runbook.md)

All runbooks assume:
- env files live outside the repo (e.g., `~/.config/inshell/path/env/<network>.env`)
- scripts are run from the repo root
  - devnet uses `scripts/devnet/*`
  - sepolia uses `scripts/*-sepolia.sh`
  - mainnet mirrors sepolia (when mainnet scripts are added)
- artifacts are written to `workbook/artifacts/<network>/...`
