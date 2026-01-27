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
./scripts/ops/10_build.sh
./scripts/ops/20_declare.sh
./scripts/ops/30_deploy.sh
./scripts/ops/40_wire.sh
./scripts/ops/50_prepare_handoff_intents.sh
```

## C) Multisig handoff procedure
- locate `workbook/artifacts/mainnet/intents/handoff.json`
- open multisig UI
- submit each action in order
- collect approvals (Signer A + Ledger)
- execute each action
- record tx hashes per action

## D) Verification steps
```bash
./scripts/ops/60_verify.sh
```
- manual explorer checks (owner/admin addresses)

## E) Logging
- append to `workbook/mainnet-run-YYYYMMDD.md`
- include: class hashes, addresses, tx hashes, final owner/admin values

## F) Failure handling
- declare ok but deploy failed → retry deploy only
- wiring failed → revert config if possible, retry
- handoff partially executed → stop and finish; never leave deployer privileged longer than needed
