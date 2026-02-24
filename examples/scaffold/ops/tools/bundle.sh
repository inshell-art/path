#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
LANE=${LANE:-}
RUN_ID=${RUN_ID:-}
FORCE=${FORCE:-0}

if [[ -z "$NETWORK" || -z "$LANE" || -z "$RUN_ID" ]]; then
  echo "Usage: NETWORK=<devnet|sepolia|mainnet> LANE=<observe|plan|deploy|handoff|govern|treasury|operate|emergency> RUN_ID=<id> $0" >&2
  exit 2
fi

case "$NETWORK" in
  devnet|sepolia|mainnet) ;;
  *) echo "Invalid NETWORK: $NETWORK" >&2; exit 2 ;;
esac

case "$LANE" in
  observe|plan|deploy|handoff|govern|treasury|operate|emergency) ;;
  *) echo "Invalid LANE: $LANE" >&2; exit 2 ;;
esac

ROOT=$(git rev-parse --show-toplevel)
BUNDLE_DIR="$ROOT/bundles/$NETWORK/$RUN_ID"

if [[ -d "$BUNDLE_DIR" ]] && [[ -n "$(ls -A "$BUNDLE_DIR" 2>/dev/null)" ]] && [[ "$FORCE" != "1" ]]; then
  echo "Bundle dir already exists and is not empty: $BUNDLE_DIR" >&2
  echo "Set FORCE=1 to overwrite." >&2
  exit 2
fi

mkdir -p "$BUNDLE_DIR"

GIT_COMMIT=$(git rev-parse HEAD)
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export BUNDLE_DIR NETWORK LANE RUN_ID GIT_COMMIT CREATED_AT

python3 - <<'PY'
import json
import hashlib
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
network = os.environ["NETWORK"]
lane = os.environ["LANE"]
run_id = os.environ["RUN_ID"]
git_commit = os.environ["GIT_COMMIT"]
created_at = os.environ["CREATED_AT"]

run = {
    "run_id": run_id,
    "network": network,
    "lane": lane,
    "git_commit": git_commit,
    "created_at": created_at
}
intent = {
    "intent_version": 1,
    "network": network,
    "lane": lane,
    "ops": ["stub"],
    "notes": "Scaffold stub. Replace with real intent generation."
}
checks = {
    "checks_version": 1,
    "network": network,
    "lane": lane,
    "pass": True,
    "stub": True,
    "notes": "Scaffold stub. Replace with real checks/simulations."
}

(bundle_dir / "run.json").write_text(json.dumps(run, indent=2, sort_keys=True) + "\n")
(bundle_dir / "intent.json").write_text(json.dumps(intent, indent=2, sort_keys=True) + "\n")
(bundle_dir / "checks.json").write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n")

immutable_files = ["run.json", "intent.json", "checks.json"]
items = []
for name in immutable_files:
    data = (bundle_dir / name).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    items.append({"path": name, "sha256": digest})

bundle_hash_input = "\n".join([f"{i['path']}={i['sha256']}" for i in items]).encode()
bundle_hash = hashlib.sha256(bundle_hash_input).hexdigest()

manifest = {
    "manifest_version": 1,
    "bundle_hash": bundle_hash,
    "network": network,
    "lane": lane,
    "run_id": run_id,
    "git_commit": git_commit,
    "generated_at": created_at,
    "immutable_files": items
}

(bundle_dir / "bundle_manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
print(f"Bundle created at {bundle_dir}")
PY
