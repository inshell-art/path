# PATH ops runbooks

- Devnet runbook: `devnet-runbook.md`
- [Sepolia runbook](sepolia-runbook.md)
- [Mainnet runbook](mainnet-runbook.md)
- [Signing OS runbook](signing-os-runbook.md)
  - operator-first
  - target process is runbook-only on Signing OS
  - includes the rehearsal ladder:
    - stage 1: separate signer workspace, procedure rehearsal
    - stage 2: separate local macOS account, authority-shape rehearsal
    - stage 3: real Signing OS machine, production-shape rehearsal
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
