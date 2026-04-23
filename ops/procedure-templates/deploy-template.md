# Deploy procedure template

Purpose: deploy contracts and capture addresses using the `deploy` lane rules.

Prereqs:
- Deploy lane policy is configured for this network.
- Deployer keystore is available in signing context.
- Constructor params name the final ADMIN address; the deployer is only the deploy transaction signer.
- For Sepolia/Mainnet, never place raw private-key values in shell commands or runbook snippets.
- Working tree is committed (no tracked diffs), and `HEAD` will not change between `bundle` and `apply`.

Steps:
1. Run plan to generate intents.
2. Run checks and confirm required checks pass (chain id, signer, bytecode hash, proxy implementation).
3. Human approves the intent meaning.
4. Apply in signing context only.
5. Record deploy, wiring, and authority-finalization tx hashes, post-deploy snapshots, and EIP-1559 fee evidence.
6. Confirm postconditions prove final ADMIN owns contract authority and the deployer has no steady-state admin/owner role.
7. If `HEAD` changes after `bundle` (including new commits), create a new `RUN_ID` and re-run `bundle -> verify -> approve -> apply`.

Stop conditions:
- Any required check fails.
- Intent hash changes after approval.
- You are not in the correct OPSEC compartment.
- `run.json` commit pin does not match current `HEAD`.
