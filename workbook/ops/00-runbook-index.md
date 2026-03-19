# PATH ops runbooks

- Devnet runbook: `devnet-runbook.md`
- [Sepolia runbook](sepolia-runbook.md)
- [Mainnet runbook](mainnet-runbook.md)
- [Signing OS runbook](signing-os-runbook.md)
  - root/common Signing OS flow after stage-specific setup
  - operator-first
  - target process is runbook-only on Signing OS
- [Signing OS Stage 1 runbook](signing-os-stage1-runbook.md)
  - separate signer workspace on the same macOS account
  - procedure rehearsal
- [Signing OS Stage 2 runbook](signing-os-stage2-runbook.md)
  - separate local macOS account on the same machine
  - authority-shape rehearsal
- [Signing OS Stage 3 runbook](signing-os-stage3-runbook.md)
  - real separate Signing OS machine
  - production-shape rehearsal
- [Signer Enrollment runbook](signer-enrollment-runbook.md)
  - one-time signer enrollment and rotation
  - Signing OS derives public addresses; Dev OS updates policy
- [Audit runbook](audit-runbook.md)
  - run after `postconditions`
  - required for accepting serious Sepolia rehearsals and mainnet release evidence

All runbooks assume:
- env files live outside the repo (e.g., `~/.opsec/path/env/<network>.env`)
- params files live outside the repo (e.g., `~/.opsec/path/params/params.<network>.deploy.json`)
- scripts are run from the repo root
  - use ops-lane commands (`npm run ops:*`)
- EVM deploy/test entrypoints are in `npm run evm:*`
- lane artifacts are written to `bundles/<network>/<run_id>/`
- audit artifacts are written to `audits/<network>/<audit_id>/`
