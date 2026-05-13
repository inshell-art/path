#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN_ID="safe-treasury-fixture-$STAMP"
RUN_ID_MISSING="safe-treasury-missing-$STAMP"
BUNDLE_DIR="$ROOT/bundles/sepolia/$RUN_ID"
BUNDLE_DIR_MISSING="$ROOT/bundles/sepolia/$RUN_ID_MISSING"
TMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TMP_DIR" "$BUNDLE_DIR" "$BUNDLE_DIR_MISSING"
}
trap cleanup EXIT

PARAMS="$TMP_DIR/params.json"
SAFE="$TMP_DIR/treasury_safe.json"
INPUTS_DIR="$TMP_DIR/inputs"

cat > "$PARAMS" <<'JSON'
{
  "name": "PATH",
  "symbol": "PATH",
  "baseUri": "",
  "startDelaySec": "600",
  "admin": "0xa31Fe4bC2A9A4EeA01275A6c4b4be2Aa994A0981",
  "adminSignerRef": "SEPOLIA_ADMIN_HW_A",
  "k": "100000000000000000000",
  "genesisPrice": "1000000000000000000",
  "genesisFloor": "100000000000000000",
  "pts": "100000000000000",
  "firstPublicId": "1",
  "epochBase": "1",
  "paymentToken": "0x0000000000000000000000000000000000000000",
  "treasury": "0xE524EDf82c2D0d8243eE4fF21FB020Bd8b45D47F",
  "treasurySignerRef": "SEPOLIA_TREASURY_SAFE_1OF1"
}
JSON

cat > "$SAFE" <<'JSON'
{
  "chainId": 11155111,
  "createdAtUtc": "2026-05-12T11:21:07Z",
  "custodySignerRef": "SEPOLIA_TREASURY_SAFE_1OF1",
  "deploymentTx": "0x2cca6b14ba86f6881f60dadfcc6fb49e8d5bb8aea3e3bbfc0a087b0755c040a6",
  "network": "sepolia",
  "owners": [
    {
      "address": "0xFC309d64Ff133d69bE2B690931BE2E923ef05E90",
      "custodyPlace": "OM+OS",
      "role": "initial-owner",
      "signerRef": "SEPOLIA_TREASURY_HW_A"
    }
  ],
  "rehearsalOnly": true,
  "role": "treasury",
  "safeAddress": "0xE524EDf82c2D0d8243eE4fF21FB020Bd8b45D47F",
  "safeVersion": "verified-by-cast-readback",
  "source": "cast-readback",
  "threshold": 1,
  "treasurySignerRef": "SEPOLIA_TREASURY_SAFE_1OF1",
  "verification": {
    "codeIsContract": true,
    "expectedOwner": "0xFC309d64Ff133d69bE2B690931BE2E923ef05E90",
    "expectedThreshold": 1,
    "mode": "onchain-readback",
    "ownersReadbackMatch": true,
    "thresholdMatches": true,
    "thresholdReadback": 1
  }
}
JSON

NETWORK=sepolia LANE=deploy RUN_ID="$RUN_ID" INPUT_FILE="$PARAMS" \
  OUT_DIR="$INPUTS_DIR" PARAMS_SCHEMA=schemas/path.constructor_params.schema.json \
  ./ops/tools/lock_inputs.sh >/dev/null

NETWORK=sepolia LANE=deploy RUN_ID="$RUN_ID" \
  LOCKED_INPUTS_FILE="$INPUTS_DIR/inputs.$RUN_ID.json" TREASURY_SAFE_FILE="$SAFE" \
  ./ops/tools/bundle.sh >/dev/null

jq -e '.immutable_files[] | select(.path == "treasury_safe.json")' "$BUNDLE_DIR/bundle_manifest.json" >/dev/null
jq -e '.treasury_safe_verified == true' "$BUNDLE_DIR/checks.json" >/dev/null
jq -e '.treasury_safe_sha256 | type == "string" and length == 64' "$BUNDLE_DIR/intent.json" >/dev/null
test -f "$BUNDLE_DIR/RUNBOOK.md"

NETWORK=sepolia LANE=deploy RUN_ID="$RUN_ID_MISSING" INPUT_FILE="$PARAMS" \
  OUT_DIR="$INPUTS_DIR" PARAMS_SCHEMA=schemas/path.constructor_params.schema.json \
  ./ops/tools/lock_inputs.sh >/dev/null

if NETWORK=sepolia LANE=deploy RUN_ID="$RUN_ID_MISSING" \
  LOCKED_INPUTS_FILE="$INPUTS_DIR/inputs.$RUN_ID_MISSING.json" \
  ./ops/tools/bundle.sh >/dev/null 2>"$TMP_DIR/missing-safe.err"; then
  echo "expected bundle without TREASURY_SAFE_FILE to fail" >&2
  exit 1
fi

grep -q "provide TREASURY_SAFE_FILE" "$TMP_DIR/missing-safe.err"
