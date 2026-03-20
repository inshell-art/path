#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
export ROOT

NETWORK=${NETWORK:-}
LANE=${LANE:-deploy}
CHECK_GH_AUTH=${CHECK_GH_AUTH:-0}
GH_REPO=${GH_REPO:-inshell-art/path}
OPSEC_ROOT=${OPSEC_ROOT:-~/.opsec}
ENV_FILE=${ENV_FILE:-}
SIGNER_ALIAS=${SIGNER_ALIAS:-}
KEYSTORE_JSON=${KEYSTORE_JSON:-}
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD:-}
KEYSTORE_PASSWORD_FILE=${KEYSTORE_PASSWORD_FILE:-}
export NETWORK LANE SIGNER_ALIAS

expand_user_path() {
  local value="${1:-}"
  if [[ "$value" == "~/"* ]]; then
    printf '%s\n' "$HOME/${value#~/}"
  else
    printf '%s\n' "$value"
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required tool: $cmd" >&2
    exit 2
  fi
}

check_git_clean() {
  local label="$1"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Tracked git tree is dirty ($label)." >&2
    exit 1
  fi
}

if [[ -z "$NETWORK" ]]; then
  echo "Usage: NETWORK=<sepolia|mainnet> [LANE=<lane>] [CHECK_GH_AUTH=1] $0" >&2
  exit 2
fi

case "$NETWORK" in
  sepolia|mainnet) ;;
  *)
    echo "Invalid NETWORK: $NETWORK" >&2
    exit 2
    ;;
esac

for cmd in node npm git jq python3 make gh cast; do
  require_cmd "$cmd"
done

ENV_FILE=$(expand_user_path "${ENV_FILE:-$OPSEC_ROOT/path/env/${NETWORK}.env}")

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing Signing OS env file: $ENV_FILE" >&2
  exit 1
fi
if [[ ! -r "$ENV_FILE" ]]; then
  echo "Signing OS env file is not readable: $ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

NETWORK_UPPER=$(printf '%s' "$NETWORK" | tr '[:lower:]' '[:upper:]')
RAW_KEY_VAR="${NETWORK_UPPER}_PRIVATE_KEY"
if [[ -n "${!RAW_KEY_VAR:-}" ]]; then
  echo "Refusing raw key env ${RAW_KEY_VAR}; Signing OS preflight expects keystore mode only." >&2
  exit 1
fi

check_git_clean "before preflight"

NETWORK="$NETWORK" npm run ops:policy:init:check

if [[ "$CHECK_GH_AUTH" == "1" ]]; then
  gh auth status >/dev/null
  gh repo view "$GH_REPO" >/dev/null
  echo "[signingos] gh auth ok for $GH_REPO"
else
  echo "[signingos] gh auth check skipped (set CHECK_GH_AUTH=1 to enable)"
fi

MARKER_PATH=$(expand_user_path "${SIGNING_OS_MARKER_FILE:-}")
if [[ -z "$MARKER_PATH" ]]; then
  echo "Missing SIGNING_OS_MARKER_FILE in $ENV_FILE" >&2
  exit 1
fi
if [[ ! -f "$MARKER_PATH" ]]; then
  echo "Signing OS marker file not found: $MARKER_PATH" >&2
  exit 1
fi
if [[ ! -r "$MARKER_PATH" ]]; then
  echo "Signing OS marker file is not readable: $MARKER_PATH" >&2
  exit 1
fi

POLICY_META=$(python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["ROOT"])
network = os.environ["NETWORK"]
lane = os.environ["LANE"]
requested = os.environ.get("SIGNER_ALIAS", "").strip()
policy_path = root / "ops" / "policy" / f"lane.{network}.json"

if not policy_path.exists():
    print(f"Missing policy file: {policy_path}", file=sys.stderr)
    sys.exit(1)

policy = json.loads(policy_path.read_text())
lanes = policy.get("lanes")
if not isinstance(lanes, dict) or lane not in lanes or not isinstance(lanes[lane], dict):
    print(f"Lane {lane!r} not found in {policy_path.relative_to(root)}", file=sys.stderr)
    sys.exit(1)

lane_cfg = lanes[lane]
allowed = [str(item).strip() for item in lane_cfg.get("allowed_signers") or [] if str(item).strip()]
if not allowed:
    print(f"Lane {lane} does not declare allowed_signers in {policy_path.relative_to(root)}", file=sys.stderr)
    sys.exit(1)

if requested:
    if requested not in allowed:
        print(f"SIGNER_ALIAS {requested!r} is not allowed for {network}/{lane}: {', '.join(allowed)}", file=sys.stderr)
        sys.exit(1)
    alias = requested
elif len(allowed) == 1:
    alias = allowed[0]
else:
    print(f"Multiple allowed_signers for {network}/{lane}; set SIGNER_ALIAS explicitly: {', '.join(allowed)}", file=sys.stderr)
    sys.exit(1)

signer_map = policy.get("signer_alias_map")
if not isinstance(signer_map, dict):
    print(f"signer_alias_map missing in {policy_path.relative_to(root)}", file=sys.stderr)
    sys.exit(1)

address = str(signer_map.get(alias, "")).strip()
if not address:
    print(f"signer_alias_map entry missing for {alias} in {policy_path.relative_to(root)}", file=sys.stderr)
    sys.exit(1)

print(f"{alias}\t{address}")
PY
)

IFS=$'\t' read -r SELECTED_SIGNER_ALIAS EXPECTED_SIGNER_ADDRESS <<<"$POLICY_META"

if [[ -z "$KEYSTORE_JSON" ]]; then
  if [[ "$LANE" == "deploy" ]]; then
    KEYSTORE_JSON_VAR="${NETWORK_UPPER}_DEPLOY_KEYSTORE_JSON"
    KEYSTORE_JSON="${!KEYSTORE_JSON_VAR:-}"
  fi
fi
if [[ -z "$KEYSTORE_PASSWORD" && -z "$KEYSTORE_PASSWORD_FILE" ]]; then
  if [[ "$LANE" == "deploy" ]]; then
    KEYSTORE_PASSWORD_VAR="${NETWORK_UPPER}_DEPLOY_KEYSTORE_PASSWORD"
    KEYSTORE_PASSWORD_FILE_VAR="${NETWORK_UPPER}_DEPLOY_KEYSTORE_PASSWORD_FILE"
    KEYSTORE_PASSWORD="${!KEYSTORE_PASSWORD_VAR:-}"
    KEYSTORE_PASSWORD_FILE="${!KEYSTORE_PASSWORD_FILE_VAR:-}"
  fi
fi

KEYSTORE_JSON=$(expand_user_path "$KEYSTORE_JSON")
KEYSTORE_PASSWORD_FILE=$(expand_user_path "$KEYSTORE_PASSWORD_FILE")

if [[ -z "$KEYSTORE_JSON" ]]; then
  echo "Missing keystore path. Set KEYSTORE_JSON or ${NETWORK_UPPER}_DEPLOY_KEYSTORE_JSON." >&2
  exit 1
fi
if [[ ! -f "$KEYSTORE_JSON" ]]; then
  echo "Keystore file not found: $KEYSTORE_JSON" >&2
  exit 1
fi
if [[ ! -r "$KEYSTORE_JSON" ]]; then
  echo "Keystore file is not readable: $KEYSTORE_JSON" >&2
  exit 1
fi

if [[ -n "$KEYSTORE_PASSWORD" && -n "$KEYSTORE_PASSWORD_FILE" ]]; then
  echo "Set only one of KEYSTORE_PASSWORD or KEYSTORE_PASSWORD_FILE." >&2
  exit 1
fi

CAST_ARGS=(wallet address --keystore "$KEYSTORE_JSON")
if [[ -n "$KEYSTORE_PASSWORD_FILE" ]]; then
  if [[ ! -f "$KEYSTORE_PASSWORD_FILE" ]]; then
    echo "Keystore password file not found: $KEYSTORE_PASSWORD_FILE" >&2
    exit 1
  fi
  if [[ ! -r "$KEYSTORE_PASSWORD_FILE" ]]; then
    echo "Keystore password file is not readable: $KEYSTORE_PASSWORD_FILE" >&2
    exit 1
  fi
  CAST_ARGS+=(--password-file "$KEYSTORE_PASSWORD_FILE")
elif [[ -n "$KEYSTORE_PASSWORD" ]]; then
  CAST_ARGS+=(--password "$KEYSTORE_PASSWORD")
else
  echo "Missing keystore password input. Set KEYSTORE_PASSWORD_FILE, KEYSTORE_PASSWORD, or the network deploy password env." >&2
  exit 1
fi

ACTUAL_SIGNER_ADDRESS=$(cast "${CAST_ARGS[@]}")

if [[ "${ACTUAL_SIGNER_ADDRESS,,}" != "${EXPECTED_SIGNER_ADDRESS,,}" ]]; then
  echo "Signer binding mismatch for $NETWORK/$LANE." >&2
  echo "  alias:    $SELECTED_SIGNER_ALIAS" >&2
  echo "  expected: $EXPECTED_SIGNER_ADDRESS" >&2
  echo "  actual:   $ACTUAL_SIGNER_ADDRESS" >&2
  exit 1
fi

echo "[signingos] signer binding ok: $SELECTED_SIGNER_ALIAS -> $ACTUAL_SIGNER_ADDRESS"
echo "[signingos] marker ok: $MARKER_PATH"

check_git_clean "after preflight"

echo "[signingos] preflight passed for $NETWORK/$LANE"
