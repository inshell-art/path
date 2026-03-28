# PATH ops runbooks

- Devnet runbook: `devnet-runbook.md`
- [Sepolia runbook](sepolia-runbook.md)
  - Dev OS and handoff for Sepolia
- [Mainnet runbook](mainnet-runbook.md)
  - Dev OS and handoff for Mainnet
- [Signing OS runbook](signing-os-runbook.md)
  - Signing OS selector and overview only
- [Signing OS Stage 1 runbook](signing-os-stage1-runbook.md)
  - self-contained Signing OS handbook for Stage 1
  - same macOS account, separate signer workspace, procedure rehearsal
- [Signing OS Stage 2 runbook](signing-os-stage2-runbook.md)
  - self-contained Signing OS handbook for Stage 2
  - separate local macOS account on the same machine, authority-shape rehearsal
- [Signing OS Stage 3 runbook](signing-os-stage3-runbook.md)
  - self-contained Signing OS handbook for Stage 3
  - real separate Signing OS machine, production-shape rehearsal
- [Signer Enrollment runbook](signer-enrollment-runbook.md)
  - one-time signer enrollment and rotation
  - Signing OS derives public addresses; Dev OS updates policy
- [Signing OS Wi-Fi handbook](signing-os-wifi-handbook.md)
  - canonical bounded-online rule for Signing OS maintenance and run sessions
- [PATH ADMIN / TREASURY custody OPSEC upgrade — v1](path-admin-treasury-custody-opsec-upgrade-v1.md)
  - canonical Safe custody rule: two Ledger owner paths only for ADMIN / TREASURY
- [cast verification discipline](cast-verification-discipline.md)
  - Signing OS bootstrap trust check for the local `cast` binary
- [Audit runbook](audit-runbook.md)
  - run after `postconditions`
  - required for accepting serious Sepolia rehearsals and mainnet release evidence

All runbooks assume:
- PATH `ops/` and `workbook/ops/` are canonical for this repo
- env files live outside the repo (e.g., `~/.opsec/path/env/<network>.env`)
- params files live outside the repo (e.g., `~/.opsec/path/params/params.<network>.deploy.json`)
- scripts are run from the repo root
  - use ops-lane commands (`npm run ops:*`)
- EVM deploy/test entrypoints are in `npm run evm:*`
- lane artifacts are written to `bundles/<network>/<run_id>/`
- audit artifacts are written to `audits/<network>/<audit_id>/`
