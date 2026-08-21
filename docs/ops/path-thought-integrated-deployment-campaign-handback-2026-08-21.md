# PATH Handback: PATH + THOUGHT Integrated Deployment Campaign

Date: 2026-08-21

Interop supersession: this is the durable pre-interop implementation handback.
The frozen OPS interop v1 contract and exact THOUGHT-owned payload integration
are documented in `docs/ops/DEPLOY_SUPERVISOR_PATH_HAND_BACK_20260821.md`.
Where receipt formats differ, that later handback and the checked-in schemas are
authoritative.

Status: implemented in the PATH working tree. This handback does not authorize a
deployment, signer use, an auction `openTime`, FE exposure, or a public rollout.

## Verdict

`PathNFT` supports the bounded Phase A interval without a bytecode change.
Immediately after construction, THOUGHT, WILL, and AWA each have a zero minter,
zero quota, and `frozen=false`. Public mint is disabled because `publicMinter` is
zero and `publicMinterFrozen=false`.

The retained Phase A `DEFAULT_ADMIN_ROLE` is bounded operationally to the exact
Phase B action set recorded in the receipt. The immutable bundle, exact signer
binding, preflight, receipt, and resume rules enforce that interval; no new
temporary on-chain role was added.

PATH accepts the recommended mutation boundary:

- THOUGHT deploys and verifies its contracts and emits a typed receipt.
- THOUGHT does not permanently mutate `PathNFT`.
- PATH Phase B configures and freezes all three movement contracts.

## Delivered Interfaces

Schemas:

- `schemas/path.campaign.phase_a_params.schema.json`
- `schemas/path.campaign.phase_a_checkpoint.schema.json`
- `schemas/path.campaign.phase_a_receipt.schema.json`
- `schemas/path.campaign.thought_receipt.schema.json`
- `schemas/path.campaign.phase_b_params.schema.json`
- `schemas/path.campaign.phase_b_checkpoint.schema.json`
- `schemas/path.campaign.phase_b_final_receipt.schema.json`

Reference examples:

- `ops/campaign/examples/path-phase-a-params.example.json`
- `ops/campaign/examples/path-phase-a-checkpoint.example.json`
- `ops/campaign/examples/path-phase-a-receipt.example.json`
- `ops/campaign/examples/thought-deployment-receipt.example.json`
- `ops/campaign/examples/path-phase-b-config.example.json`
- `ops/campaign/examples/path-phase-b-params.example.json`
- `ops/campaign/examples/path-phase-b-checkpoint.example.json`
- `ops/campaign/examples/path-phase-b-final-receipt.example.json`

Executable PATH surfaces:

- `evm/scripts/deploy-campaign-phase-a.js`
- `evm/scripts/deploy-campaign-phase-b.js`
- `evm/scripts/check-path-campaign-state.js`
- `evm/scripts/lib/path-campaign.mjs`
- `ops/tools/path_campaign.mjs`

The checked-in examples contain synthetic addresses and artifact hashes. A real
campaign must replace them with a frozen release matrix and verified receipts.

## Phase A Receipt

Phase A deploys only `PathNFT` and emits:

- campaign ID, environment, and chain ID;
- exact PATH repository, tag, commit, and artifact manifest SHA-256;
- executing bundle digest;
- PathNFT address, deployment transaction, block, and runtime bytecode hash;
- retained authority address, signer reference, role, and bounded actions;
- all three movement states proving zero minter, zero quota, and unfrozen state;
- public exposure proof showing no adapter, auction, or `openTime` and no enabled
  public mint.

Phase A params reject `openTime`, `startDelaySec`, adapter, and auction fields.

## Phase B Input

`prepare-phase-b` consumes the exact Phase A and THOUGHT receipt files. It embeds
both complete receipt objects and their canonical SHA-256 values into one Phase B
params file. The bundle hashes that complete file. There is no separate PathNFT
or ThoughtNFT address override.

The generic input locker preserves typed campaign params without normalizing
embedded addresses. This is required because even case-only receipt mutation
would invalidate the embedded canonical SHA-256.

Phase B rejects:

- altered or mismatched receipt digests;
- campaign, environment, chain, or release mismatch;
- a THOUGHT receipt that consumed another Phase A receipt;
- a ThoughtNFT runtime hash that differs from its receipt;
- a ThoughtNFT whose on-chain `pathNft()` readback differs from Phase A;
- changed Phase A movement or public-mint state;
- zero, placeholder, or code-less movement minters;
- wrong WILL/AWA quotas;
- forged, expired, elapsed, or insufficiently future `openTime` authorization;
- unexpected retained or final authority.

## Irreversible Action Order

1. Verify the Phase A receipt and on-chain checkpoint.
2. Verify the THOUGHT receipt, runtime bytecode, and `pathNft()` binding.
3. Set THOUGHT to the exact ThoughtNFT address with quota 1.
4. Verify THOUGHT before freezing it.
5. Freeze THOUGHT and verify the freeze.
6. Set WILL to its pinned contract with quota 10, verify, freeze, and verify again.
7. Set AWA to its pinned contract with quota 1, verify, freeze, and verify again.
8. Deploy `PathPulseAdapter` against the exact Phase A PathNFT.
9. Deploy `PulseAuction` with the exact authorized future `openTime`.
10. Set the auction on the adapter and freeze adapter wiring.
11. Grant `MINTER_ROLE` to the adapter and freeze PATH public mint to it.
12. Grant `RESERVED_ROLE` to the pinned Spark issuer.
13. Grant `DEFAULT_ADMIN_ROLE` to the final admin.
14. Transfer adapter ownership to the final admin.
15. Renounce the deployment signer's `DEFAULT_ADMIN_ROLE`.
16. Verify combined postconditions and only then emit `status=complete`.

The complete machine-readable order is `PHASE_B_ACTION_ORDER` in
`evm/scripts/lib/path-campaign.mjs` and is copied into each final receipt.

## Resume and Abandon Rules

Phase A writes its deployment checkpoint atomically before it can emit a Phase A
receipt. A restart verifies the exact constructor calldata, deployment
transaction, runtime bytecode, constructor readbacks, retained admin, movement
state, and disabled public mint before reusing that PathNFT.

Phase B writes an atomic checkpoint after every mined state-changing transaction.
The checkpoint must be a prefix of the 16 canonical writes and must contain the
transaction/block evidence for every recorded action. Before another write, the
resume preflight verifies the input and bundle digests plus exact movement state,
contract bytecode and constructor values, adapter wiring, public minter, roles,
owners, and retained authority. Recorded transactions are resolved on-chain and
must match their signer, target or created address, block, decoded method,
arguments, and canonical execution order. An on-chain mutation without its
matching checkpoint is rejected rather than inferred.

| Checkpoint | Resume rule | Abandon rule |
| --- | --- | --- |
| Before Phase A transaction | Rebuild or reapprove the immutable Phase A bundle. | None; no on-chain state exists. |
| PathNFT deployed, Phase A receipt incomplete | Re-read the exact deployment transaction and state; emit the receipt only if all Phase A invariants pass. Never redeploy under the same run ID. | Wrong chain, bytecode, constructor values, or retained authority. |
| Phase A complete, before THOUGHT | Resume THOUGHT only from the exact Phase A receipt digest. | Any movement/public-mint mutation or loss of retained authority. |
| THOUGHT complete, before Phase B | Rebuild Phase B from the exact two receipts and obtain a fresh explicit `openTime` authorization. | Wrong PATH binding, release, registry state, bytecode, or chain. |
| Phase B before first freeze | Re-run preflight and continue only when current state exactly equals a declared checkpoint. | Unexpected mutation, signer, role, or elapsed authorization. |
| Any movement frozen | Resume from the next verified action only; never repeat or substitute a frozen address. | Wrong minter/quota/freeze, wrong chain/bytecode, or unknown transaction outcome. |
| Auction deployed or wiring frozen | Resume only when addresses, constructor values, `openTime`, and wiring match the receipts. | Wrong config, unsafe elapsed `openTime`, or freeze mismatch. |
| Authority handoff started | Resume from verified role/owner readbacks and the next missing handoff action. | Unexpected authority, lost admin path, or unintended deployer privilege. |
| Final receipt complete | No write resume. Run read-only combined postconditions and return the receipt to OPS. | Any failed acceptance check invalidates exposure of the stack. |

For public-beta Sepolia and mainnet, any wrong permanent freeze, dependency,
bytecode, chain, or authority abandons the complete stack. Preserve failed
receipts; never edit them into a passing state.

## Exposure Gate

Phase A and THOUGHT receipts are never FE deployment manifests. Only the final
Phase B receipt can satisfy contract deployment completion, and only after all ten
acceptance flags are true. OPS still owns the separate decision to move from
`studio-preview` to `onchain-countdown` or `onchain-open`.

## Cross-Repo Contract

THOUGHT must emit `thought_deployment_receipt` version 1 with:

- the exact consumed Phase A receipt SHA-256 and PathNFT address;
- ThoughtNFT deployment evidence and runtime bytecode hash;
- a verified on-chain `pathNft()` readback;
- `pathMutationOwner=PATH_PHASE_B` and `pathMutationPerformed=false`;
- release, registry, and immutable-dependency verification flags.

Signing OS should treat PATH and THOUGHT bundles as opaque protocol-owned phases
linked by receipt digests. No PATH address, THOUGHT address, movement name, ABI,
or `openTime` rule needs to move into Signing OS core.

## Immutable Release References

The examples identify PATH `v0.5.0` at
`085cfc084b0e568740e0da639e968eb535f7e5c8` and the inspected THOUGHT candidate at
`4fbbd708dce7b35fe6c219cb130be794162980d4`. Their artifact manifest hashes are
synthetic. OPS must freeze real artifact manifest hashes before approval.

## Verification

```bash
npm run evm:compile
npm --prefix evm test -- test/pathCampaign.behavior.test.js
./ops/tests/path_campaign.sh
npm run ops:campaign:test:e2e
npm run evm:test
npm run ops:test:safe-treasury
npm run ops:check:public-safe
```

Observed PATH results:

- compile passed;
- 7 focused campaign tests passed;
- campaign schema, canonical digest, lock-input, receipt-link, checkpoint-order,
  missing-evidence, and negative mismatch checks passed;
- the local devnet rehearsal built and verified immutable Phase A and Phase B
  bundles, interrupted Phase A after PathNFT deployment, interrupted Phase B
  after THOUGHT freeze, resumed both through `approve/apply`, passed automatic
  postconditions, and proved an idempotent final rerun mined no block;
- the full EVM suite passed with 104 tests;
- Safe-backed bundle regression and public-safe ops boundary checks passed.

No Sepolia/mainnet transaction, signer use, auction authorization, FE exposure,
or public rollout was performed by this implementation.
