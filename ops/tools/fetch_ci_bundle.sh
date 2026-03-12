#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
RUN_ID=${RUN_ID:-}
RUN_DB_ID=${RUN_DB_ID:-}
GH_REPO=${GH_REPO:-}
ARTIFACT_NAME=${ARTIFACT_NAME:-}
ROOT=$(git rev-parse --show-toplevel)
DEST_PARENT=${DEST_PARENT:-"$ROOT/bundles/$NETWORK"}
TARGET_DIR=${TARGET_DIR:-"$DEST_PARENT/$RUN_ID"}
FORCE=${FORCE:-0}

if [[ -z "$NETWORK" || -z "$RUN_ID" || -z "$RUN_DB_ID" ]]; then
  echo "Usage: NETWORK=<devnet|sepolia|mainnet> RUN_ID=<id> RUN_DB_ID=<gh-run-id> $0" >&2
  echo "   optional: GH_REPO=<owner/repo> DEST_PARENT=<dir> TARGET_DIR=<dir> FORCE=1" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Missing GitHub CLI 'gh' in PATH" >&2
  exit 2
fi

if [[ -z "$GH_REPO" ]]; then
  GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi

if [[ -z "$GH_REPO" ]]; then
  echo "Unable to determine GitHub repository. Set GH_REPO=<owner/repo>." >&2
  exit 2
fi

if [[ -z "$ARTIFACT_NAME" ]]; then
  ARTIFACT_NAME="ops-bundle-${NETWORK}-${RUN_ID}"
fi

if [[ -e "$TARGET_DIR" ]]; then
  if [[ "$FORCE" != "1" ]]; then
    echo "Target bundle already exists: $TARGET_DIR" >&2
    echo "Set FORCE=1 to replace it." >&2
    exit 2
  fi
  rm -rf "$TARGET_DIR"
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/path-bundle-download.XXXXXX")
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$DEST_PARENT"

gh run download "$RUN_DB_ID" -R "$GH_REPO" -D "$TMP_DIR"

DOWNLOADED_DIR="$TMP_DIR/$ARTIFACT_NAME"
if [[ ! -d "$DOWNLOADED_DIR" ]]; then
  echo "Expected artifact directory not found after download: $DOWNLOADED_DIR" >&2
  echo "Downloaded entries:" >&2
  find "$TMP_DIR" -maxdepth 2 -mindepth 1 -print | sort >&2
  exit 2
fi

mv "$DOWNLOADED_DIR" "$TARGET_DIR"

for required in bundle_manifest.json checks.json intent.json run.json; do
  if [[ ! -f "$TARGET_DIR/$required" ]]; then
    echo "Missing required bundle file: $TARGET_DIR/$required" >&2
    exit 2
  fi
done

python3 - "$TARGET_DIR" "$NETWORK" "$RUN_ID" <<'PY'
import json
import sys
from pathlib import Path

bundle_dir = Path(sys.argv[1])
expected_network = sys.argv[2]
expected_run_id = sys.argv[3]

run = json.loads((bundle_dir / "run.json").read_text())

run_network = run.get("network")
run_id = run.get("run_id")
lane = run.get("lane")

if run_network != expected_network:
    raise SystemExit(
        f"Bundle network mismatch: expected {expected_network}, got {run_network}"
    )
if run_id != expected_run_id:
    raise SystemExit(f"Bundle run_id mismatch: expected {expected_run_id}, got {run_id}")

print(f"bundle_dir={bundle_dir}")
print(f"run_id={run_id}")
print(f"network={run_network}")
print(f"lane={lane}")
PY

echo "files:"
find "$TARGET_DIR" -maxdepth 1 -type f -exec basename {} \; | sort
