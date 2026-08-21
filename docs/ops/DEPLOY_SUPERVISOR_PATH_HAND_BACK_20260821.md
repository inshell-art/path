# DEPLOY-SUPERVISOR PATH handback

Date: 2026-08-21

Status: repository-owned OPS interop v1 implementation complete and locally
verified. Trust tier: `VERIFIED`; not `PINNED` or `ON_CHAIN`.

Base repository pin: `085cfc084b0e568740e0da639e968eb535f7e5c8`.
At the time of this verification handback, the campaign work remained
uncommitted in a dirty worktree. Its later selective release cleanup is recorded
in `docs/ops/DEPLOY_SUPERVISOR_PATH_RELEASE_CLEAN_HAND_BACK_20260821.md`.

## Delivered contract

- PATH Phase A keeps the existing `path_campaign_phase_a_receipt` owner payload
  and `schemas/path.campaign.phase_a_receipt.schema.json` as the canonical PATH
  payload surface.
- Every phase uses the strict generic receipt envelope from OPS. The PATH mirror
  is byte-identical to the frozen OPS schema.
- `protocol_payload.sha256` is RFC 8785 JCS over the exact payload, restricted to
  JSON integers in the IEEE-754 safe range. Floating-point, non-finite, unsafe
  integers, duplicate object keys, unpaired Unicode surrogates, and non-JSON
  values fail closed. Larger EVM quantities remain decimal strings. The same
  strict parser is used by production receipt readers and the test harness.
- Embedded receipts preserve the exact raw envelope bytes, exact raw-file
  SHA-256, parsed envelope object, JCS payload SHA-256, campaign identity,
  environment, numeric chain, phase identity, and prior-envelope link.
- PATH Phase B consumes the exact THOUGHT-owned
  `inshell.thought.deployment.receipt.v1` current-V2 payload. The former reduced
  PATH-authored THOUGHT receipt shape and its stale examples were removed.
- THOUGHT must link the exact PATH-A envelope and payload digests and declare
  `pathMutationPerformed=false` and `pathMutationOwner=PATH_PHASE_B`.
- The PATH-B final owner payload links both PATH-A and THOUGHT envelope-file
  digests and both protocol payload digests. Existing checkpoint parameter
  hashing continues to bind the complete exact inputs and canonical action
  prefix.
- Protocol-owned `CAMPAIGN-PHASE.json` descriptors and executable
  preflight/execute/postcondition/checkpoint/resume entrypoints exist for
  `path-a` and `path-b`. The descriptor generator creates environment- and
  chain-bound variants.
- The test-only harness supports both a self-contained unit chain and a true
  staged cross-repository chain. Staged mode emits PATH-A separately, requires
  the exact THOUGHT harness output file for PATH-B, and never constructs or
  rewrites the THOUGHT envelope. No production descriptor refers to either test
  mode.

## Changed campaign files

Pre-existing modified tracked files with campaign-specific hunks that must be
separated carefully from the rest of the dirty worktree:

- `AGENTS.md`
- `docs/repo-boundary.md`
- `evm/package.json`
- `ops/policy/lane.devnet.example.json`
- `ops/policy/lane.devnet.json`
- `ops/policy/lane.mainnet.example.json`
- `ops/policy/lane.mainnet.json`
- `ops/policy/lane.sepolia.example.json`
- `ops/policy/lane.sepolia.json`
- `ops/tools/apply_bundle.sh`
- `ops/tools/bundle.sh`
- `ops/tools/generate_path_checks.sh`
- `ops/tools/lock_inputs.sh`
- `ops/tools/postconditions.sh`
- `ops/tools/README.md`
- `package.json`

Pre-existing untracked campaign files that were necessarily edited:

- `evm/scripts/lib/path-campaign.mjs`
- `evm/scripts/deploy-campaign-phase-a.js`
- `evm/scripts/deploy-campaign-phase-b.js`
- `evm/scripts/check-path-campaign-state.js`
- `evm/scripts/prepare-path-campaign-devnet-dependencies.js`
- `evm/test/pathCampaign.behavior.test.js`
- `ops/tools/path_campaign.mjs`
- `ops/tests/path_campaign.sh`
- `ops/tests/path_campaign_e2e.sh`
- `ops/campaign/README.md`
- `ops/campaign/examples/path-phase-b-config.example.json`
- `ops/campaign/examples/path-phase-b-final-receipt.example.json`
- `schemas/path.campaign.phase_b_params.schema.json`
- `schemas/path.campaign.phase_b_final_receipt.schema.json`
- `schemas/path.campaign.thought_receipt.schema.json`
- `docs/ops/path-thought-deployment-campaign-refactor-report-2026-08-21.md`

Stale pre-interop reduced-receipt examples removed:

- `ops/campaign/examples/thought-deployment-receipt.example.json`
- `ops/campaign/examples/path-phase-b-params.example.json`

New files:

- `schemas/protocol-receipt-envelope.v1.schema.json`
- `ops/tools/path_campaign_protocol.mjs`
- `ops/tools/generate_path_campaign_phase_descriptor.mjs`
- `ops/campaign/path-a/CAMPAIGN-PHASE.json`
- `ops/campaign/path-a/bin/{preflight,execute,postconditions,verify-checkpoint,resume}`
- `ops/campaign/path-b/CAMPAIGN-PHASE.json`
- `ops/campaign/path-b/bin/{preflight,execute,postconditions,verify-checkpoint,resume}`
- `ops/tests/synthetic_path_campaign_receipts.mjs`
- `ops/tests/path_campaign_interop.mjs`
- `docs/ops/DEPLOY_SUPERVISOR_PATH_HAND_BACK_20260821.md`

No unrelated tracked bytecode, renderer, frontend, policy, workbook, output, or
marketplace-preview modifications were reverted, staged, or committed.

## Verification performed

All commands below exited `0` unless explicitly noted.

```bash
npm run evm:compile
npm run evm:test
npm run ops:campaign:test
npm run ops:campaign:test:e2e
```

The Hardhat compile, full tests, focused campaign unit tests, and ephemeral E2E
were completed before the supervisor's final authority clarification. After
that clarification, the E2E was not rerun. All final validation was static or
test-only synthetic, with no signing, transaction construction, broadcast,
deployment entrypoint, RPC, or local chain.

Observed:

- Hardhat compile: no contracts needed recompilation; glyph check passed.
- Full EVM test suite: 104 passing.
- Focused campaign unit suite: 7 passing.
- Synthetic interop suite: 6 passing, including a true THOUGHT-harness to
  PATH-B raw-byte handoff.
- Campaign static/schema/negative suite: passed.
- Ephemeral local bundle rehearsal: Phase A forced interruption/resume, Phase B
  forced interruption at the canonical prefix, complete postconditions,
  idempotent re-entry, and no additional block on complete re-entry all passed.
- The e2e rehearsal used only an ephemeral localhost Hardhat chain. No external
  RPC or persistent chain was contacted. This is earlier supporting evidence,
  not the final supervisor rehearsal.

Schema mirror verification:

```text
c74f493ba55326efcaca4be3ede6b33da319e2e6ae636817e1cb91aec550cccc  protocol-receipt-envelope.v1.schema.json
4db5fae69c93432b43b340ecf24078efdb5933c85094a23b70550789e49701d1  thought-deployment-receipt.v1.schema.json
```

The checked-in PATH mirrors matched the OPS and THOUGHT owner files byte for
byte at verification time. Both descriptors also passed the actual generic
Signing OS `validate_descriptor` implementation, and both production preflight
entrypoints passed against the synthetic exact receipts.

Leak review:

- `git diff --staged` was empty; nothing was staged.
- Scoped `gitleaks detect --no-git --redact` scans of `ops`, `schemas`,
  `evm/scripts`, and the campaign behavior test found no leaks.
- A whole-tree scan reported two pre-existing findings only in unrelated
  `marketplace-preview/dist/server/**/vinext-server.json` generated artifacts.
  No campaign file was implicated.

## Exact OPS verification commands

From `/Users/bigu/Projects/path`:

```bash
cmp schemas/protocol-receipt-envelope.v1.schema.json \
  /Users/bigu/Projects/inshell-feed-ops/deployment-campaign/schemas/protocol-receipt-envelope.v1.schema.json

cmp schemas/path.campaign.thought_receipt.schema.json \
  /Users/bigu/Projects/THOUGHT/ops/integrated-campaign/schemas/thought-deployment-receipt.v1.schema.json

node --check evm/scripts/lib/path-campaign.mjs
node --check evm/scripts/deploy-campaign-phase-a.js
node --check evm/scripts/deploy-campaign-phase-b.js
node --check evm/scripts/check-path-campaign-state.js
node --check evm/scripts/prepare-path-campaign-devnet-dependencies.js
node --check ops/tools/path_campaign.mjs
node --check ops/tools/path_campaign_protocol.mjs
node --check ops/tests/synthetic_path_campaign_receipts.mjs
node --test ops/tests/path_campaign_interop.mjs
./ops/tests/path_campaign.sh
```

These are the final-authority verification commands. They are pure static or
test-only synthetic checks and must replace, not precede, an E2E deployment
rehearsal for supervisor integration.

Generate exact synthetic receipts without deployment or RPC:

```bash
TMP_PATH_INTEROP=$(mktemp -d)
PATH_CAMPAIGN_TEST_ONLY=1 \
  node ops/tests/synthetic_path_campaign_receipts.mjs \
  emit-chain --out-dir "$TMP_PATH_INTEROP"

node ops/tools/path_campaign.mjs verify-envelope \
  --receipt "$TMP_PATH_INTEROP/path-a-envelope.json" --phase path-a
node ops/tools/path_campaign.mjs verify-envelope \
  --receipt "$TMP_PATH_INTEROP/thought-envelope.json" --phase thought
node ops/tools/path_campaign.mjs verify-envelope \
  --receipt "$TMP_PATH_INTEROP/path-b-envelope.json" --phase path-b
node ops/tools/path_campaign.mjs verify-phase-b-input \
  --params "$TMP_PATH_INTEROP/path-b-params.json"
```

True staged cross-repository, no-sign/no-broadcast/no-RPC rehearsal:

```bash
STAGED_INTEROP=$(mktemp -d)
PATH_A_DIR="$STAGED_INTEROP/path-a"
PATH_B_DIR="$STAGED_INTEROP/path-b"
THOUGHT_PAYLOAD="$STAGED_INTEROP/thought-payload.json"
THOUGHT_ENVELOPE="$STAGED_INTEROP/thought-envelope.json"

PATH_CAMPAIGN_TEST_ONLY=1 \
  node /Users/bigu/Projects/path/ops/tests/synthetic_path_campaign_receipts.mjs \
  emit-path-a --out-dir "$PATH_A_DIR"

PATH_A_ENVELOPE="$PATH_A_DIR/path-a-envelope.json"
PATH_A_SHA256=$(shasum -a 256 "$PATH_A_ENVELOPE" | awk '{print $1}')
PATH_A_PAYLOAD_SHA256=$(jq -er '.protocol_payload.sha256' "$PATH_A_ENVELOPE")
PATH_NFT=$(jq -er '.protocol_payload.payload.pathNft.address' "$PATH_A_ENVELOPE")
CAMPAIGN_ID=$(jq -er '.campaign_id' "$PATH_A_ENVELOPE")

jq \
  --arg campaign "$CAMPAIGN_ID" \
  --arg envelope_sha "$PATH_A_SHA256" \
  --arg payload_sha "$PATH_A_PAYLOAD_SHA256" \
  --arg path_nft "$PATH_NFT" \
  '.campaignId = $campaign
   | .consumedPathPhaseAReceiptSha256 = $envelope_sha
   | .consumedPathPhaseA = {
       envelopeSha256: $envelope_sha,
       payloadSha256: $payload_sha
     }
   | .pathNft = $path_nft
   | .compatibility.pathNftImmutable = $path_nft' \
  /Users/bigu/Projects/THOUGHT/ops/integrated-campaign/examples/thought-deployment-receipt.example.json \
  >"$THOUGHT_PAYLOAD"

node /Users/bigu/Projects/THOUGHT/scripts/synthetic-thought-campaign-harness.mjs \
  --path-envelope "$PATH_A_ENVELOPE" \
  --thought-payload "$THOUGHT_PAYLOAD" \
  --out "$THOUGHT_ENVELOPE" \
  --campaign-id "$CAMPAIGN_ID" \
  --environment internal-sepolia \
  --chain-id 11155111 \
  --path-bundle-digest bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  --path-retained-authority 0x2000000000000000000000000000000000000002 \
  --path-nft "$PATH_NFT" \
  --thought-bundle-digest 0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  --registry-owner 0x4444444444444444444444444444444444444444 \
  --attestation-authority 0x5555555555555555555555555555555555555555

PATH_CAMPAIGN_TEST_ONLY=1 \
  node /Users/bigu/Projects/path/ops/tests/synthetic_path_campaign_receipts.mjs \
  emit-path-b \
  --path-a-envelope "$PATH_A_ENVELOPE" \
  --thought-envelope "$THOUGHT_ENVELOPE" \
  --out-dir "$PATH_B_DIR"

cmp "$THOUGHT_ENVELOPE" \
  <(jq -j '.thoughtDeployment.receiptRaw' "$PATH_B_DIR/path-b-params.json")
test "$(shasum -a 256 "$THOUGHT_ENVELOPE" | awk '{print $1}')" = \
  "$(jq -er '.thoughtDeployment.receiptSha256' "$PATH_B_DIR/path-b-params.json")"
node /Users/bigu/Projects/path/ops/tools/path_campaign.mjs verify-envelope \
  --receipt "$PATH_B_DIR/path-b-envelope.json" --phase path-b
```

In the last stage, PATH reads `THOUGHT_ENVELOPE` as raw UTF-8, hashes it, parses
and validates it, and embeds the same raw string and digest. It does not call
`createProtocolReceiptEnvelope` for phase `thought` or synthesize selected
THOUGHT fields.

Generate an immutable descriptor variant:

```bash
node ops/tools/generate_path_campaign_phase_descriptor.mjs \
  --phase path-b \
  --environment internal-sepolia \
  --chain-id 11155111 \
  --bundle-id <reviewed-immutable-bundle-id> \
  --out <bundle-root>/CAMPAIGN-PHASE.json
```

OPS should then assemble the full `path-a -> thought -> path-b` generic Signing
OS campaign using the exact three owner bundles and run the Signing OS campaign
controller's plan/preflight/approve/execute/postconditions flow. That final
cross-repository orchestration is deliberately not simulated by a PATH-owned
substitute.

## Remaining blockers and stop conditions

- The PATH tree is dirty with unrelated work. Separate and review campaign
  changes before pinning or packaging a release bundle.
- OPS must re-check both schema hashes immediately before bundle freeze; the
  THOUGHT implementation is also currently uncommitted.
- Signing OS/OPS still owns full three-bundle manifest assembly, immutable
  bundle digests, ordered append-only receipt transport, and campaign evidence.
- No signer approval, release approval, `openTime` approval, credential, or
  deployment authorization is included here.
- No Sepolia/mainnet signing or broadcast was performed. A schema, digest,
  identity, authority, checkpoint, transaction-order, or final-postcondition
  mismatch remains a hard stop.
