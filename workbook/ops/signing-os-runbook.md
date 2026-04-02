# Signing OS runbook

This file is the Signing OS overview and selector only.
It is not the step-by-step handbook for execution.

If you are actually running the Signing OS half, choose exactly one stage runbook and follow that stage runbook alone.

## A) Select the stage runbook

- [Signing OS Stage 1 runbook](signing-os-stage1-runbook.md)
  - same macOS account
  - separate signer workspace and separate secrets root
  - procedure rehearsal
- [Signing OS Stage 2 runbook](signing-os-stage2-runbook.md)
  - separate local macOS account on the same machine
  - authority-shape rehearsal
- [Signing OS Stage 3 runbook](signing-os-stage3-runbook.md)
  - real separate Signing OS machine
  - production-shape rehearsal

## B) Core rules

- operate the Signing OS from the selected stage runbook alone
- PATH `ops/` and `workbook/ops/` are canonical for this repo
- do not depend on an agent on the Signing OS
- if the Signing OS run blocks, stop there
- bring the failure back to Dev OS
- fix repo code, policy, or docs on Dev OS
- commit and push the fix
- start a fresh run only after the fix is published

## C) Sequencing rule

Before any serious Dev OS preflight or bundle creation that depends on deploy signer binding:
1. complete the selected stage runbook setup first
2. if the deploy signer is new or rotated, complete signer enrollment/rotation first
3. only then start the serious Dev OS flow from the network runbook

## D) Trust boundary

Dev OS does:
- code and policy edits
- `npm run evm:compile`
- `npm run evm:test`
- `npm run ops:lock-inputs`
- `npm run ops:dispatch-bundle`

Remote CI does:
- checkout pinned commit
- build bundle artifact only
- no signing
- no keystore
- no password material

Signing OS does:
- maintain local-only deploy keystore/password material for deploy-only lanes
- coordinate Ledger-backed ADMIN actions on the dedicated host
- keep final ADMIN / TREASURY custody off the host itself
- keep the daily ops secret layer narrow: host password/disk unlock plus Ledger PIN path only
- keep passphrase master copies out of the host and in the recovery layer
- fetch bundle artifact
- checkout the exact commit pinned in `run.json`
- `ops:verify`
- `ops:approve`
- `ops:apply`
- `ops:postconditions`
- post-run audit

Never do serious Sepolia/Mainnet `apply` from the Dev OS.
Never patch repo code, policy, or runbook content on the Signing OS during an active run.

Signing OS network rule:
- Wi-Fi off by default
- turn Wi-Fi on only for a bounded maintenance session or a bounded serious-run session
- during a serious run, online use is limited to exact repo/bundle fetch, RPC checks, Ledger/RPC execution, and postconditions
- no browsing, chat, search, cloud storage, package installs, or cloud agents during the run

## E) Which other runbooks still matter

- [Sepolia runbook](sepolia-runbook.md)
  - Dev OS half for Sepolia
- [Mainnet runbook](mainnet-runbook.md)
  - Dev OS half for Mainnet
- [Audit runbook](audit-runbook.md)
  - detailed audit explanation
- [Signer Enrollment runbook](signer-enrollment-runbook.md)
  - dedicated one-time background/reference for signer enrollment and rotation
- [Signing OS Wi-Fi handbook](signing-os-wifi-handbook.md)
  - canonical online/offline rule for Signing OS
- [No-Safe two-Ledger custody doc](../../docs/custody-no-safe-two-ledgers.md)
  - canonical final-custody rule for PATH
- [PATH custody migration note](path-admin-treasury-custody-opsec-upgrade-v1.md)
  - what changed and what stayed intentionally unchanged

## F) Passing rule

Do not move to the next stage until the previous stage completes:
- a full Sepolia deploy run
- `postconditions.json` with `pass`
- `audit_verify.json` with `pass`
- `audit_report.json` with `pass`
- `audit_signoff.json` written
- no ad hoc fixes during execution

The selected stage runbook defines the stage-specific acceptance criteria.
