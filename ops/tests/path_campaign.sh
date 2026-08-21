#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

TMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

EXAMPLES="$ROOT/ops/campaign/examples"
TOOL=(node "$ROOT/ops/tools/path_campaign.mjs")

for file in "$ROOT"/schemas/path.campaign.*.schema.json \
  "$ROOT/schemas/protocol-receipt-envelope.v1.schema.json" "$EXAMPLES"/*.json; do
  jq -e . "$file" >/dev/null
done

cmp "$ROOT/schemas/protocol-receipt-envelope.v1.schema.json" \
  /Users/bigu/Projects/inshell-feed-ops/deployment-campaign/schemas/protocol-receipt-envelope.v1.schema.json
cmp "$ROOT/schemas/path.campaign.thought_receipt.schema.json" \
  /Users/bigu/Projects/THOUGHT/ops/integrated-campaign/schemas/thought-deployment-receipt.v1.schema.json

"${TOOL[@]}" verify-phase-a-params --params "$EXAMPLES/path-phase-a-params.example.json" >/dev/null
"${TOOL[@]}" verify-phase-a-checkpoint \
  --checkpoint "$EXAMPLES/path-phase-a-checkpoint.example.json" \
  --params "$EXAMPLES/path-phase-a-params.example.json" \
  --source-bundle-digest bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb >/dev/null
"${TOOL[@]}" verify-phase-a --receipt "$EXAMPLES/path-phase-a-receipt.example.json" >/dev/null
"${TOOL[@]}" verify-final --receipt "$EXAMPLES/path-phase-b-final-receipt.example.json" >/dev/null

PATH_CAMPAIGN_TEST_ONLY=1 node "$ROOT/ops/tests/synthetic_path_campaign_receipts.mjs" \
  emit-chain --out-dir "$TMP_DIR/synthetic" >/dev/null
"${TOOL[@]}" verify-envelope --receipt "$TMP_DIR/synthetic/path-a-envelope.json" --phase path-a >/dev/null
"${TOOL[@]}" verify-envelope --receipt "$TMP_DIR/synthetic/thought-envelope.json" --phase thought >/dev/null
"${TOOL[@]}" verify-envelope --receipt "$TMP_DIR/synthetic/path-b-envelope.json" --phase path-b >/dev/null
"${TOOL[@]}" verify-phase-b-input --params "$TMP_DIR/synthetic/path-b-params.json" \
  --latest-block-timestamp 1900000000 >/dev/null

"${TOOL[@]}" prepare-phase-b \
  --config "$TMP_DIR/synthetic/path-b-params.json" \
  --phase-a "$TMP_DIR/synthetic/path-a-envelope.json" \
  --thought "$TMP_DIR/synthetic/thought-envelope.json" \
  --out "$TMP_DIR/prepared-phase-b.json" >/dev/null
"${TOOL[@]}" verify-phase-b-input --params "$TMP_DIR/prepared-phase-b.json" >/dev/null

NETWORK=devnet LANE=deploy RUN_ID=campaign-phase-b-schema-test \
  INPUT_FILE="$TMP_DIR/synthetic/path-b-params.json" \
  INPUT_KIND=path_campaign_phase_b \
  PARAMS_SCHEMA=schemas/path.campaign.phase_b_params.schema.json \
  OUT_DIR="$TMP_DIR/locked-b" \
  "$ROOT/ops/tools/lock_inputs.sh" >/dev/null

INPUT="$TMP_DIR/synthetic/path-b-params.json" OUT="$TMP_DIR/tampered-receipt.json" python3 - <<'PY'
import json
import os
from pathlib import Path

payload = json.loads(Path(os.environ["INPUT"]).read_text())
payload["pathPhaseA"]["receipt"]["protocol_payload"]["payload"]["observedAtBlock"] = "999999"
Path(os.environ["OUT"]).write_text(json.dumps(payload, indent=2) + "\n")
PY
if "${TOOL[@]}" verify-phase-b-input --params "$TMP_DIR/tampered-receipt.json" >/dev/null 2>&1; then
  echo "expected exact-raw Phase A envelope tamper to fail" >&2
  exit 1
fi

INPUT="$TMP_DIR/synthetic/path-b-params.json" OUT="$TMP_DIR/wrong-chain.json" python3 - <<'PY'
import json
import os
from pathlib import Path

payload = json.loads(Path(os.environ["INPUT"]).read_text())
payload["expectedChainId"] = "1"
Path(os.environ["OUT"]).write_text(json.dumps(payload, indent=2) + "\n")
PY
if "${TOOL[@]}" verify-phase-b-input --params "$TMP_DIR/wrong-chain.json" >/dev/null 2>&1; then
  echo "expected wrong-chain Phase B input to fail" >&2
  exit 1
fi

node --test "$ROOT/ops/tests/path_campaign_interop.mjs" >/dev/null

echo "PATH campaign envelope, exact-owner-payload, descriptor, and negative tests passed"
