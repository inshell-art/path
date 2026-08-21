# PATH + THOUGHT Deployment Campaign Refactor Report

Date: 2026-08-21

Status: PATH-owned implementation complete and verified on local devnet.

Interop supersession: the receipt model described below was the pre-interop
implementation. It is superseded by the frozen OPS interop v1 alignment and
handback in `docs/ops/DEPLOY_SUPERVISOR_PATH_HAND_BACK_20260821.md`. In
particular, PATH no longer consumes the reduced `thought_deployment_receipt`
shape described below; it consumes the exact THOUGHT-owned current-V2 payload
inside the generic protocol receipt envelope.

Trust tier: `VERIFIED`, not `PINNED` or `ON_CHAIN`.

Repository base pin: `085cfc084b0e568740e0da639e968eb535f7e5c8` (`v0.5.0`).
The refactor remained uncommitted at the time of this report. Its later
selective release cleanup is recorded in
`docs/ops/DEPLOY_SUPERVISOR_PATH_RELEASE_CLEAN_HAND_BACK_20260821.md`.

## Executive Summary

The standalone PATH deployment flow could not safely integrate with the
standalone THOUGHT deployment flow. PATH expected every movement minter before
deployment and froze the configuration, while THOUGHT required a deployed
PathNFT before ThoughtNFT could be constructed. A placeholder ThoughtNFT address
was unacceptable because PATH movement freezes are irreversible.

The deployment process is now split into two PATH-owned phases around a
THOUGHT-owned deployment phase:

```text
PATH Phase A
  deploy PathNFT only
  keep THOUGHT, WILL, and AWA unset and unfrozen
  keep public mint disabled
        |
        v
THOUGHT phase
  consume the exact Phase A receipt
  deploy ThoughtNFT against that PathNFT
  emit compatibility and deployment evidence
  do not mutate PathNFT
        |
        v
PATH Phase B
  consume the exact Phase A and THOUGHT receipts
  configure and freeze THOUGHT=1, WILL=10, AWA=1
  deploy and freeze adapter/auction wiring
  use an explicitly authorized future openTime
  freeze public mint authority
  complete final role and ownership handoff
  emit a final receipt only after combined postconditions pass
```

No Solidity bytecode change was required for this campaign refactor. The work is
in deployment scripts, semantic validators, schemas, ops bundle integration,
postconditions, tests, policies, and documentation.

## Before the Refactor

The original deployment assumptions conflicted:

- PATH required the THOUGHT minter before completing canonical deployment.
- THOUGHT required the actual deployed PathNFT address in its constructor.
- PATH movement configuration is one-way frozen.
- A predicted or placeholder ThoughtNFT address could permanently freeze the
  wrong dependency.
- The existing flow had no typed cross-repo receipt contract.
- Partial deployment state was not represented as a resumable declared
  checkpoint.
- A partial stack could not be reliably distinguished from a complete campaign
  using one integrated final acceptance artifact.

## Refactored Ownership Boundary

PATH owns all permanent mutations to `PathNFT`.

THOUGHT is expected to:

- consume the exact PATH Phase A receipt;
- deploy ThoughtNFT against the receipt's PathNFT address;
- verify its release, registries, immutable dependencies, and `pathNft()`
  readback;
- emit a typed `thought_deployment_receipt`;
- declare `pathMutationOwner=PATH_PHASE_B`;
- declare `pathMutationPerformed=false`.

Signing OS remains protocol-agnostic. It should order immutable bundles and
link typed receipts by digest without encoding movement names, PATH/THOUGHT
addresses, ABIs, or auction semantics in its core.

## Phase A

Phase A accepts a typed `path_campaign_phase_a` input and deploys only
`PathNFT`.

Required post-deployment state:

- THOUGHT minter is zero, quota is zero, and frozen is false.
- WILL minter is zero, quota is zero, and frozen is false.
- AWA minter is zero, quota is zero, and frozen is false.
- `publicMinter` is zero.
- `publicMinterFrozen` is false.
- No adapter exists in the receipt.
- No auction exists in the receipt.
- No `openTime` exists in the input or receipt.
- The deployment signer retains `DEFAULT_ADMIN_ROLE` only for the bounded Phase
  B completion interval.

Phase A writes `path-phase-a-checkpoint.json` immediately after the PathNFT
deployment transaction. A restart verifies:

- campaign, environment, chain, params SHA-256, and bundle digest;
- deployment transaction, block, signer, and created address;
- exact constructor calldata, including string and Spark parameters;
- runtime bytecode and constructor readbacks;
- retained admin authority;
- all movement and public-mint invariants.

Only then may it emit `path-phase-a-receipt.json`. It never redeploys under the
same exact checkpoint.

## THOUGHT Receipt Contract

PATH Phase B requires the complete THOUGHT receipt to include:

- campaign, environment, and chain identity;
- THOUGHT repository, release tag, commit, and artifact manifest SHA-256;
- THOUGHT source bundle digest;
- exact consumed Phase A receipt SHA-256 and PathNFT address;
- ThoughtNFT address, deployment transaction, block, and runtime bytecode hash;
- on-chain `pathNft()` compatibility readback;
- release, registry, and immutable dependency verification flags;
- the agreed PATH mutation ownership declarations.

Phase B embeds the complete Phase A and THOUGHT receipt objects and their
canonical SHA-256 values. There is no independent address override that can
silently diverge from those receipts.

## Phase B

Phase B validates both embedded receipts before any state-changing transaction.
It then executes 16 canonical writes:

1. Set THOUGHT movement to the exact ThoughtNFT with quota 1.
2. Freeze THOUGHT movement.
3. Set WILL movement to the pinned minter with quota 10.
4. Freeze WILL movement.
5. Set AWA movement to the pinned minter with quota 1.
6. Freeze AWA movement.
7. Deploy PathPulseAdapter.
8. Deploy PulseAuction with the authorized future `openTime`.
9. Set the auction on the adapter.
10. Freeze adapter wiring.
11. Grant `MINTER_ROLE` to the adapter.
12. Freeze PATH public mint to the adapter.
13. Grant `RESERVED_ROLE` to the Spark issuer.
14. Grant `DEFAULT_ADMIN_ROLE` to the final admin.
15. Transfer adapter ownership to the final admin.
16. Renounce the deployment signer's `DEFAULT_ADMIN_ROLE`.

Read-only verification occurs before and after irreversible writes. A complete
receipt includes the larger 25-step action order, including preflight and
postcondition checks.

## Checkpoint and Resume Model

Phase B writes `path-phase-b-checkpoint.json` atomically after every mined
state-changing transaction.

A valid checkpoint must:

- match the exact campaign, environment, chain, params digest, bundle digest,
  Phase A receipt digest, and THOUGHT receipt digest;
- contain a prefix of the canonical 16-write sequence;
- contain transaction and block evidence for every recorded action;
- match the exact current on-chain movement, wiring, role, owner, and authority
  state;
- contain no unexplained on-chain mutation.

Every recorded transaction is resolved from the chain and checked for:

- successful mined status;
- exact block;
- expected signer;
- expected target or created contract address;
- decoded contract method;
- exact ABI arguments;
- strict canonical transaction order after the THOUGHT deployment.

A mismatch is rejected. The process does not infer that an unexplained state
change was probably intended and does not silently repeat a transaction.

## openTime Policy

`openTime` exists only in Phase B.

The input requires a separate authorization object containing:

- campaign and environment;
- exact authorized `openTime`;
- minimum lead time;
- authorization and expiry timestamps;
- authorizer reference and authorization ID;
- canonical authorization SHA-256.

Phase B rejects a forged digest, expired authorization, elapsed `openTime`, or
insufficient remaining lead time. The final receipt cannot be emitted at or
after `openTime`.

## Final Acceptance

`path-phase-b-final-receipt.json` is emitted only after the complete on-chain
state passes.

Final verification covers:

- exact PATH and THOUGHT releases and receipt links;
- PathNFT, ThoughtNFT, adapter, and auction deployment evidence;
- runtime bytecode hashes;
- ThoughtNFT to PathNFT binding;
- movement minters, quotas, and freezes;
- adapter PathNFT, auction, token base, epoch base, owner, and frozen wiring;
- auction adapter, treasury, payment token, pricing parameters, deployer, and
  authorized `openTime`;
- frozen PATH public minter and adapter `MINTER_ROLE`;
- final PATH admin and Spark issuer roles;
- removed deployment admin, minter, and reserved privileges;
- all canonical transaction hashes, methods, arguments, blocks, and ordering;
- completion before public exposure.

Phase A and THOUGHT receipts are not frontend deployment manifests. Only the
passing final Phase B receipt is eligible for downstream OPS and FE evaluation.

## Ops Bundle Integration

The deploy lane now accepts:

- `constructor_params` for the legacy standalone path;
- `path_campaign_phase_a`;
- `path_campaign_phase_b`.

Campaign bundles use the existing immutable bundle, approval, apply, and
postconditions workflow. The apply tool dispatches campaign inputs to their
dedicated Hardhat scripts and records campaign transaction hashes and snapshots.

Typed campaign params are preserved by the input locker. The generic address
normalizer is intentionally skipped for Phase A and Phase B campaign inputs,
because changing only the case of an address inside an embedded receipt changes
that receipt while leaving its declared SHA-256 stale.

Mutable checkpoint and deployment artifacts remain outside the immutable bundle
manifest. They are exact execution evidence, not editable inputs.

## Defects Found During the Refactor

### 1. Phase B restart preflight rejected legitimate partial state

The initial checker assumed every Phase B preflight started from untouched Phase
A state. After a valid THOUGHT freeze, a restart would fail before reaching the
resume logic.

Resolution: preflight now detects the exact Phase B checkpoint and validates its
declared partial state rather than requiring all movements to remain unset.

### 2. Phase B was not transaction-by-transaction resumable

The initial implementation could complete Phase B but did not persist every
irreversible write as an atomic checkpoint.

Resolution: each of the 16 writes now persists transaction evidence immediately,
and restart is allowed only from the canonical prefix.

### 3. Campaign receipt digests were broken by generic input normalization

The generic input locker lowercased addresses inside embedded receipt objects.
This modified the embedded receipt without recomputing its canonical digest.

Resolution: typed campaign inputs preserve their embedded data exactly. A
regression test verifies that locked Phase B params retain valid receipt links.

### 4. Devnet campaign input kinds were attached to the wrong lane

The initial policy edit placed campaign input kinds under the read-only plan or
observe surface instead of the deploy lane.

Resolution: both campaign kinds are accepted only by the intended deploy policy
surface in all checked devnet, Sepolia, and mainnet policy files.

### 5. Final transaction evidence was initially structural only

The first final checker required transaction-shaped fields but did not prove that
each hash represented the declared action.

Resolution: final postconditions now resolve every transaction on-chain and
verify its signer, target, block, method, arguments, and execution order.

### 6. Final auction checks were incomplete

The initial postcondition check covered the high-level auction wiring but not all
constructor pricing and adapter parameters.

Resolution: final verification now includes payment token, treasury, mint
adapter, `openTime`, `curveK`, genesis price, genesis floor, PTS, token base,
epoch base, and deployer.

## Main Delivered Files

Campaign implementation:

- `evm/scripts/lib/path-campaign.mjs`
- `evm/scripts/deploy-campaign-phase-a.js`
- `evm/scripts/deploy-campaign-phase-b.js`
- `evm/scripts/check-path-campaign-state.js`
- `evm/scripts/prepare-path-campaign-devnet-dependencies.js`
- `ops/tools/path_campaign.mjs`

Schemas:

- `schemas/path.campaign.phase_a_params.schema.json`
- `schemas/path.campaign.phase_a_checkpoint.schema.json`
- `schemas/path.campaign.phase_a_receipt.schema.json`
- `schemas/path.campaign.thought_receipt.schema.json`
- `schemas/path.campaign.phase_b_params.schema.json`
- `schemas/path.campaign.phase_b_checkpoint.schema.json`
- `schemas/path.campaign.phase_b_final_receipt.schema.json`

Ops integration:

- `ops/tools/lock_inputs.sh`
- `ops/tools/bundle.sh`
- `ops/tools/apply_bundle.sh`
- `ops/tools/generate_path_checks.sh`
- `ops/tools/postconditions.sh`
- `ops/policy/lane.*.json`
- `ops/policy/lane.*.example.json`

Tests and examples:

- `evm/test/pathCampaign.behavior.test.js`
- `ops/tests/path_campaign.sh`
- `ops/tests/path_campaign_e2e.sh`
- `ops/campaign/examples/*.json`

Documentation:

- `ops/campaign/README.md`
- `docs/ops/path-thought-integrated-deployment-campaign-handback-2026-08-21.md`
- `docs/repo-boundary.md`

## Verification Results

Executed against the final refactor state:

```bash
npm run evm:compile
npm run evm:test
./ops/tests/path_campaign.sh
npm run ops:campaign:test:e2e
npm run ops:test:safe-treasury
npm run ops:check:public-safe
```

Observed results:

- EVM compile passed.
- Full EVM suite passed: 104 tests.
- Focused campaign suite passed: 7 tests.
- Schema, receipt-link, checkpoint-order, lock-input, and negative mismatch tests
  passed.
- Immutable Phase A and Phase B devnet bundles built and verified.
- Phase A was deliberately interrupted after PathNFT deployment and resumed
  through bundle `approve/apply` without redeployment.
- Phase B was deliberately interrupted after THOUGHT freeze and resumed through
  bundle `approve/apply` from the exact next action.
- Automatic Phase A and Phase B postconditions passed.
- Repeating the complete Phase B script mined no additional block.
- Safe-backed bundle regression passed.
- Public-safe ops boundary check passed.
- `git diff --check` passed.
- No campaign-introduced gitleaks finding was detected. The full dirty tree has
  two pre-existing generated findings under `marketplace-preview/dist`.

## What This Does Not Prove

- No internal Sepolia, public-beta Sepolia, or mainnet deployment was executed.
- No real signer, hardware wallet, Safe, or production treasury was used.
- No production `openTime` was selected or authorized.
- Synthetic THOUGHT and movement dependencies were used for the local rehearsal.
- The THOUGHT repository has not yet implemented its receipt-producing phase.
- Signing OS has not yet implemented the generic cross-bundle campaign
  coordinator requested by the original handoff.
- No frontend, indexer, feed, monitor, or announcement was updated.
- The current implementation has not been committed, tagged, or released.

## Required Downstream Work

THOUGHT owner:

1. Consume the exact Phase A receipt rather than a manually supplied PathNFT
   address.
2. Emit the version 1 THOUGHT deployment receipt expected by PATH.
3. Keep permanent PathNFT mutation out of the THOUGHT phase.
4. Run a real cross-repo internal-Sepolia rehearsal.

Signing OS owner:

1. Implement generic ordered bundle campaigns and typed receipt propagation.
2. Preserve append-only phase receipts and explicit blocked/abandoned states.
3. Require human approval and refuse silent signing retries.
4. Keep PATH and THOUGHT semantics outside Signing OS core.

OPS:

1. Freeze real PATH and THOUGHT artifact manifest hashes.
2. Accept owner handbacks and authorize an internal-Sepolia campaign separately.
3. Qualify public-beta Sepolia before mainnet.
4. Supply FE only with a verified final deployment manifest and launch state.

## Final Verdict

The PATH-owned deployment flow is now structurally compatible with a coordinated
PATH -> THOUGHT -> PATH campaign. It is receipt-linked, resumable, strict about
irreversible actions, and verified through the existing PATH bundle workflow on
local devnet.

It is ready for cross-repo integration work, but it is not yet a pinned release
and does not authorize any public-network deployment or launch.
