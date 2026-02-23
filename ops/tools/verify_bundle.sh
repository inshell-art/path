#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
RUN_ID=${RUN_ID:-}
BUNDLE_PATH=${BUNDLE_PATH:-}

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

if [[ ! -f "$BUNDLE_DIR/bundle_manifest.json" ]]; then
  echo "Missing bundle_manifest.json in $BUNDLE_DIR" >&2
  exit 2
fi

export BUNDLE_DIR

python3 - <<'PY'
import json
import hashlib
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
manifest_path = bundle_dir / "bundle_manifest.json"
manifest = json.loads(manifest_path.read_text())

items = manifest.get("immutable_files", [])
if not items:
    raise SystemExit("manifest has no immutable_files")

required = {"run.json", "intent.json", "checks.json"}
paths = {item.get("path") for item in items}
missing = required - paths
if missing:
    raise SystemExit(f"manifest missing required files: {', '.join(sorted(missing))}")

recomputed = []
for item in items:
    path = item.get("path")
    if not path:
        raise SystemExit("manifest entry missing path")
    data = (bundle_dir / path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != item.get("sha256"):
        raise SystemExit(f"hash mismatch for {path}")
    recomputed.append({"path": path, "sha256": digest})

bundle_hash_input = "\n".join([f"{i['path']}={i['sha256']}" for i in recomputed]).encode()
expected_bundle_hash = hashlib.sha256(bundle_hash_input).hexdigest()
if expected_bundle_hash != manifest.get("bundle_hash"):
    raise SystemExit("bundle_hash mismatch")

print("Manifest hashes verified")
PY

if [[ ! -f "$BUNDLE_DIR/run.json" ]]; then
  echo "Missing run.json" >&2
  exit 2
fi

RUN_COMMIT=$(python3 - <<'PY'
import json
import os
from pathlib import Path
bundle_dir = Path(os.environ["BUNDLE_DIR"])
run = json.loads((bundle_dir / "run.json").read_text())
print(run.get("git_commit", ""))
PY
)

if [[ -z "$RUN_COMMIT" ]]; then
  echo "run.json missing git_commit" >&2
  exit 2
fi

CURRENT_COMMIT=$(git rev-parse HEAD)
if [[ "$CURRENT_COMMIT" != "$RUN_COMMIT" ]]; then
  echo "Commit mismatch: run.json=$RUN_COMMIT current=$CURRENT_COMMIT" >&2
  exit 2
fi

NETWORK_FROM_RUN=$(python3 - <<'PY'
import json
import os
from pathlib import Path
bundle_dir = Path(os.environ["BUNDLE_DIR"])
run = json.loads((bundle_dir / "run.json").read_text())
print(run.get("network", ""))
PY
)

LANE_FROM_RUN=$(python3 - <<'PY'
import json
import os
from pathlib import Path
bundle_dir = Path(os.environ["BUNDLE_DIR"])
run = json.loads((bundle_dir / "run.json").read_text())
print(run.get("lane", ""))
PY
)

if [[ -z "$NETWORK_FROM_RUN" || -z "$LANE_FROM_RUN" ]]; then
  echo "run.json missing network or lane" >&2
  exit 2
fi

if [[ -n "$NETWORK" && "$NETWORK" != "$NETWORK_FROM_RUN" ]]; then
  echo "Network mismatch: $NETWORK vs $NETWORK_FROM_RUN" >&2
  exit 2
fi

POLICY_FILE=""
for candidate in \
  "$ROOT/ops/policy/lane.${NETWORK_FROM_RUN}.json" \
  "$ROOT/ops/policy/${NETWORK_FROM_RUN}.policy.json" \
  "$ROOT/ops/policy/lane.${NETWORK_FROM_RUN}.example.json" \
  "$ROOT/ops/policy/${NETWORK_FROM_RUN}.policy.example.json"
do
  if [[ -f "$candidate" ]]; then
    POLICY_FILE="$candidate"
    break
  fi
done

if [[ -z "$POLICY_FILE" ]]; then
  echo "Missing policy file for network: $NETWORK_FROM_RUN" >&2
  echo "Expected one of: lane.${NETWORK_FROM_RUN}.json, ${NETWORK_FROM_RUN}.policy.json, lane.${NETWORK_FROM_RUN}.example.json, ${NETWORK_FROM_RUN}.policy.example.json" >&2
  exit 2
fi

LANE_OK=$(POLICY_FILE="$POLICY_FILE" RUN_LANE="$LANE_FROM_RUN" python3 - <<'PY'
import json
import os
from pathlib import Path
policy_path = Path(os.environ["POLICY_FILE"])
run_lane = os.environ["RUN_LANE"]
policy = json.loads(policy_path.read_text())
lanes = policy.get("lanes", {})
print("ok" if run_lane in lanes else "missing")
PY
  )

if [[ "$LANE_OK" != "ok" ]]; then
  echo "Lane '$LANE_FROM_RUN' not found in policy: $POLICY_FILE" >&2
  exit 2
fi

echo "Bundle verified: $BUNDLE_DIR"
