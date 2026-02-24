# Handoff and lockdown runbook (template)

Purpose: transfer ownership and revoke deployer privileges.

Prereqs:
- Governance Safe is deployed and verified.
- Handoff lane policy is configured for this network.

Steps:
1. Run plan to generate handoff intents.
2. Run checks for current ownership, proxy implementation identity, and target Safe ownership.
3. Human approves the intent meaning.
4. Apply in signing context only.
5. Verify postconditions that deployer has zero privilege.

Stop conditions:
- Ownership or roles do not match expected preconditions.
- Any required check fails.
