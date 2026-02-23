# Mainnet runbook

## A) Preflight checklist
- correct network selected (mainnet)
- correct RPC reachable
- deployer funded (minimal STRK)
- multisig funded (minimal STRK)
- signers available (Mac A, Ledger, Mac B)
- “no browsing” rule confirmed for signer environments

## B) Execute scripts (exact commands)
```bash
source ~/.config/inshell/path/env/mainnet.env
# Until mainnet-specific scripts exist, run the sepolia scripts with mainnet env:
./scripts/declare-sepolia.sh
./scripts/deploy-sepolia.sh
./scripts/config-sepolia.sh
./scripts/verify-sepolia.sh
```

## C) Capture deploy metadata (for FE)
- After deploy, record the **deploy block** from the deploy tx receipt.
- Update:
  - `output/addresses.mainnet.json`
  - `output/deploy.mainnet.json`

## D) Verification steps
- `./scripts/verify-sepolia.sh`
- manual explorer checks (owner/admin addresses)

## E) Logging
- append to `workbook/runs/run-YYYYMMDD.md`
- include: class hashes, addresses, tx hashes, deploy block, final owner/admin values

## F) Failure handling
- declare ok but deploy failed → rerun deploy only
- config failed → rerun config/verify after fixing roles
