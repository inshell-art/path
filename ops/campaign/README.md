# PATH + THOUGHT Deployment Campaign

This directory contains public-safe examples for the PATH-owned portions of the
integrated deployment campaign. The examples are synthetic and are not deployment
authorization, release approval, signer approval, or an `openTime` approval.

## Frozen interop v1 identities

- Phase A input kind: `path_campaign_phase_a`
- Phase B input kind: `path_campaign_phase_b`
- Phase A owner payload kind: `path_campaign_phase_a_receipt`
- Phase A checkpoint kind: `path_campaign_phase_a_checkpoint`
- Phase A envelope type: `inshell.path.phase-a.receipt.v1`
- THOUGHT owner payload and envelope type: `inshell.thought.deployment.receipt.v1`
- Phase B checkpoint kind: `path_campaign_phase_b_checkpoint`
- Final owner payload kind: `path_campaign_phase_b_final_receipt`
- Final envelope type: `inshell.path.phase-b.final-receipt.v1`

Envelope and owner schemas live under `schemas/`. Semantic checks that
cannot be expressed safely in JSON Schema live in
`evm/scripts/lib/path-campaign.mjs`.

## Receipt Linking

Do not type a deployed address into Phase B params. Build Phase B params from the
two exact generic envelope files:

```bash
node ops/tools/path_campaign.mjs prepare-phase-b \
  --config ops/campaign/examples/path-phase-b-config.example.json \
  --phase-a /secure/campaign/path-a-envelope.json \
  --thought /secure/campaign/thought-envelope.json \
  --out /secure/campaign/path-phase-b-params.json
```

The command preserves the exact raw envelope bytes and objects, verifies each
payload's RFC 8785 JCS SHA-256, and binds the exact envelope-file SHA-256 values.
Protocol payload JSON numbers are restricted to safe-range integers; larger EVM
quantities remain decimal strings and floating-point values are rejected.

PATH consumes the THOUGHT-owned current-V2 payload without translating it into
a PATH-specific reduced shape. The local mirror
`schemas/path.campaign.thought_receipt.schema.json` must remain byte-identical to
THOUGHT's owner schema.

## Generic Signing OS phase bundles

The protocol-owned descriptors are:

- `ops/campaign/path-a/CAMPAIGN-PHASE.json`
- `ops/campaign/path-b/CAMPAIGN-PHASE.json`

Each declares generic `preflight`, `execute`, `postconditions`, checkpoint
verification, and resume entrypoints. Generate another environment/chain binding
with:

```bash
node ops/tools/generate_path_campaign_phase_descriptor.mjs \
  --phase path-a \
  --environment internal-sepolia \
  --chain-id 11155111 \
  --bundle-id <immutable-bundle-id> \
  --out <bundle>/CAMPAIGN-PHASE.json
```

Production entrypoints consume cross-phase receipts only through
`SIGNING_OS_CAMPAIGN_INPUT_RECEIPT` and emit only through
`SIGNING_OS_CAMPAIGN_OUTPUT_RECEIPT`. `PATH_CAMPAIGN_PARAMS_FILE` is the single
descriptor-declared owner input.

## Bundle Inputs

Lock each phase independently:

```bash
NETWORK=sepolia LANE=deploy RUN_ID=<phase-a-run-id> \
  INPUT_FILE=/secure/campaign/path-phase-a-params.json \
  INPUT_KIND=path_campaign_phase_a \
  PARAMS_SCHEMA=schemas/path.campaign.phase_a_params.schema.json \
  npm run ops:lock-inputs

NETWORK=sepolia LANE=deploy RUN_ID=<phase-b-run-id> \
  INPUT_FILE=/secure/campaign/path-phase-b-params.json \
  INPUT_KIND=path_campaign_phase_b \
  PARAMS_SCHEMA=schemas/path.campaign.phase_b_params.schema.json \
  npm run ops:lock-inputs
```

Continue through the normal immutable bundle and Signing OS entrypoints. Phase A
writes `deployments/path-phase-a-checkpoint.json` before its final
`deployments/path-phase-a-receipt.json`. Phase B atomically advances
`deployments/path-phase-b-checkpoint.json` after each mined write and writes
`deployments/path-phase-b-final-receipt.json` only after combined postconditions
pass.

## Resume Rules

Checkpoint files are mutable execution evidence and are deliberately excluded
from the immutable bundle manifest. Each checkpoint is bound to the exact
campaign, environment, chain, params SHA-256, immutable bundle digest, and prior
receipt digests. Phase B accepts only the canonical action prefix and requires
transaction evidence plus exact on-chain state for every recorded action.

Never delete a checkpoint to force a retry. A mismatched checkpoint or an
unrecorded on-chain mutation is an abandon/incident condition outside disposable
devnet rehearsal.

## Static Verification

```bash
node ops/tools/path_campaign.mjs verify-phase-a --receipt <phase-a-receipt>
node ops/tools/path_campaign.mjs verify-phase-a-checkpoint --checkpoint <phase-a-checkpoint> --params <phase-a-params> --source-bundle-digest <sha256>
node ops/tools/path_campaign.mjs verify-envelope --receipt <envelope> --phase <path-a|thought|path-b>
node ops/tools/path_campaign.mjs verify-phase-b-input --params <phase-b-params>
node ops/tools/path_campaign.mjs verify-phase-b-checkpoint --checkpoint <phase-b-checkpoint> --params <phase-b-params> --source-bundle-digest <sha256>
node ops/tools/path_campaign.mjs verify-final --receipt <final-receipt>
npm run ops:campaign:test
npm run ops:campaign:test:e2e
```

The no-RPC, no-deployment synthetic interop harness is test-only:

```bash
PATH_CAMPAIGN_TEST_ONLY=1 node ops/tests/synthetic_path_campaign_receipts.mjs \
  emit-chain --out-dir <temporary-directory>
```

No production `CAMPAIGN-PHASE.json` execute path references that harness.

For a true staged cross-repository rehearsal, run `emit-path-a`, pass that exact
file to THOUGHT's `synthetic-thought-campaign-harness.mjs`, then pass the exact
THOUGHT output file to PATH `emit-path-b`. Staged PATH-B validates and embeds the
unaltered raw THOUGHT bytes; it has no THOUGHT-envelope constructor on that code
path. Exact commands are recorded in
`docs/ops/DEPLOY_SUPERVISOR_PATH_HAND_BACK_20260821.md`.

Static verification does not replace the predeploy and postdeploy on-chain checks
run by the bundle workflow.
