# Handoff and lockdown procedure template

Purpose: transfer authority away from a temporary deploy/admin path and revoke deployer privileges.
For new deploys, prefer deploy-integrated authority finalization; use this lane for older deploys or corrective changes.

Prereqs:
- The final ADMIN Ledger address is known and verified.
- Handoff lane policy is configured for this network.

Steps:
1. Run plan to generate handoff intents.
2. Run checks for current ownership, proxy implementation identity, and target admin identity.
3. Human approves the intent meaning.
4. Apply in signing context only.
5. Verify postconditions that deployer has zero privilege.

Stop conditions:
- Ownership or roles do not match expected preconditions.
- Any required check fails.
