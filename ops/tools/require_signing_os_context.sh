#!/usr/bin/env bash
set -euo pipefail

BUNDLE_DIR=${BUNDLE_DIR:-}
SCRIPT_NAME=${SCRIPT_NAME:-$(basename "${BASH_SOURCE[0]}")}
SIGNING_OS_MARKER_FILE=${SIGNING_OS_MARKER_FILE:-}

expand_user_path() {
  local value="${1:-}"
  if [[ "$value" == "~/"* ]]; then
    printf '%s\n' "$HOME/${value#~/}"
  else
    printf '%s\n' "$value"
  fi
}

if [[ -z "$BUNDLE_DIR" || ! -d "$BUNDLE_DIR" ]]; then
  echo "BUNDLE_DIR must point to an existing bundle directory." >&2
  exit 2
fi

if [[ ! -f "$BUNDLE_DIR/run.json" ]]; then
  echo "Missing run.json in $BUNDLE_DIR" >&2
  exit 2
fi

IFS=$'\t' read -r RUN_NETWORK RUN_LANE <<EOF_META
$(BUNDLE_DIR="$BUNDLE_DIR" python3 - <<'PY'
import json
import os
from pathlib import Path

run = json.loads((Path(os.environ["BUNDLE_DIR"]) / "run.json").read_text())
print(f"{run.get('network', '')}\t{run.get('lane', '')}")
PY
)
EOF_META

if [[ "$RUN_LANE" != "deploy" ]]; then
  exit 0
fi

case "$RUN_NETWORK" in
  sepolia|mainnet) ;;
  *) exit 0 ;;
esac

if [[ "${SIGNING_OS:-}" != "1" ]]; then
  echo "Refusing to run: SIGNING_OS=1 is required for $RUN_NETWORK deploy on Signing OS." >&2
  exit 2
fi

MARKER_PATH="$(expand_user_path "$SIGNING_OS_MARKER_FILE")"
if [[ -z "$MARKER_PATH" ]]; then
  echo "Refusing to run: SIGNING_OS_MARKER_FILE is required for $RUN_NETWORK deploy on Signing OS." >&2
  exit 2
fi

if [[ ! -f "$MARKER_PATH" ]]; then
  echo "Refusing to run: Signing OS marker file not found: $MARKER_PATH" >&2
  exit 2
fi

if [[ ! -r "$MARKER_PATH" ]]; then
  echo "Refusing to run: Signing OS marker file is not readable: $MARKER_PATH" >&2
  exit 2
fi
