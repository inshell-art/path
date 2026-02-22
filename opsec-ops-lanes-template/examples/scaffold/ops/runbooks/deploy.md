# Deploy runbook (template)

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

Stop conditions:
- Any required check fails.
- Intent hash changes after approval.
- You are not in the correct OPSEC compartment.
