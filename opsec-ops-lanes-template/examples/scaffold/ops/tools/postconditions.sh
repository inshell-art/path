#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
RUN_ID=${RUN_ID:-}
BUNDLE_PATH=${BUNDLE_PATH:-}
POSTCONDITIONS_STATUS=${POSTCONDITIONS_STATUS:-pending}
POSTCONDITIONS_NOTE=${POSTCONDITIONS_NOTE:-}

ROOT=$(git rev-parse --show-toplevel)

if [[ -n "$BUNDLE_PATH" ]]; then
  BUNDLE_DIR="$BUNDLE_PATH"
else
  if [[ -z "$NETWORK" || -z "$RUN_ID" ]]; then
    echo "Usage: NETWORK=<devnet|sepolia|mainnet> RUN_ID=<id> $0" >&2
    echo "   or: BUNDLE_PATH=<path> $0" >&2
    exit 2
  fi
  BUNDLE_DIR="$ROOT/bundles/$NETWORK/$RUN_ID"
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Bundle directory not found: $BUNDLE_DIR" >&2
  exit 2
fi

if [[ ! -f "$BUNDLE_DIR/intent.json" ]]; then
  echo "Missing intent.json in $BUNDLE_DIR" >&2
  exit 2
fi

TXS_PRESENT="false"
if [[ -f "$BUNDLE_DIR/txs.json" ]]; then
  TXS_PRESENT="true"
fi

if [[ "$POSTCONDITIONS_STATUS" != "pending" && "$POSTCONDITIONS_STATUS" != "pass" && "$POSTCONDITIONS_STATUS" != "fail" ]]; then
  echo "Invalid POSTCONDITIONS_STATUS: $POSTCONDITIONS_STATUS" >&2
  exit 2
fi

if [[ "$POSTCONDITIONS_STATUS" == "pass" && "$TXS_PRESENT" != "true" ]]; then
  echo "Cannot mark pass without txs.json present" >&2
  exit 2
fi

VERIFIED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export BUNDLE_DIR NETWORK RUN_ID TXS_PRESENT POSTCONDITIONS_STATUS POSTCONDITIONS_NOTE VERIFIED_AT

python3 - <<'PY'
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
network = os.environ["NETWORK"] or ""
run_id = os.environ["RUN_ID"] or ""
status = os.environ["POSTCONDITIONS_STATUS"]
verified_at = os.environ["VERIFIED_AT"]
notes = os.environ.get("POSTCONDITIONS_NOTE", "")

txs_present = os.environ["TXS_PRESENT"] == "true"

checks = [
    {
        "name": "txs_present",
        "status": "pass" if txs_present else "fail",
        "details": "txs.json exists" if txs_present else "txs.json missing"
    },
    {
        "name": "state_verified",
        "status": "pass" if status == "pass" else "pending",
        "details": "fill in chain verification"
    }
]

payload = {
    "postconditions_version": "1",
    "network": network,
    "run_id": run_id,
    "verified_at": verified_at,
    "checks": checks,
    "status": status,
}

if notes:
    payload["notes"] = notes

(bundle_dir / "postconditions.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
print(f"Postconditions written to {bundle_dir / 'postconditions.json'}")
PY
