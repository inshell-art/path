# Deploy procedure template

Purpose: deploy contracts and capture addresses using the `deploy` lane rules.

Prereqs:
- Deploy lane policy is configured for this network.
- Deployer keystore is available in signing context.

Steps:
1. Run plan to generate intents.
2. Run checks and confirm required checks pass (chain id, signer, bytecode hash, proxy implementation).
3. Human approves the intent meaning.
4. Apply in signing context only.
5. Record tx hashes, post-deploy snapshots, and EIP-1559 fee evidence.
6. Run postconditions (auto mode default):
   - `NETWORK=<network> RUN_ID=<run_id> ops/tools/postconditions.sh`
   - manual compatibility (if needed): `POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pass NETWORK=<network> RUN_ID=<run_id> ops/tools/postconditions.sh`

Stop conditions:
- Any required check fails.
- Intent hash changes after approval.
- You are not in the correct OPSEC compartment.
