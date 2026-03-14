#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
RUN_ID=${RUN_ID:-}
BUNDLE_PATH=${BUNDLE_PATH:-}
POSTCONDITIONS_MODE=${POSTCONDITIONS_MODE:-auto}
POSTCONDITIONS_STATUS=${POSTCONDITIONS_STATUS:-pending}
POSTCONDITIONS_NOTE=${POSTCONDITIONS_NOTE:-}

ROOT=$(git rev-parse --show-toplevel)

if [[ -n "$BUNDLE_PATH" ]]; then
  BUNDLE_DIR="$BUNDLE_PATH"
else
  if [[ -z "$NETWORK" || -z "$RUN_ID" ]]; then
    echo "Usage: NETWORK=<devnet|sepolia|mainnet> RUN_ID=<id> $0" >&2
    echo "   or: BUNDLE_PATH=<path> $0" >&2
    echo "Modes: POSTCONDITIONS_MODE=auto (default) | manual (requires POSTCONDITIONS_STATUS=pending|pass|fail)" >&2
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

SCRIPT_NAME=$(basename "$0") BUNDLE_DIR="$BUNDLE_DIR" "$ROOT/ops/tools/require_signing_os_context.sh"

TXS_PRESENT="false"
if [[ -f "$BUNDLE_DIR/txs.json" ]]; then
  TXS_PRESENT="true"
fi

if [[ "$POSTCONDITIONS_MODE" != "auto" && "$POSTCONDITIONS_MODE" != "manual" ]]; then
  echo "Invalid POSTCONDITIONS_MODE: $POSTCONDITIONS_MODE" >&2
  exit 2
fi

VERIFY_OK="true"
VERIFY_EXIT="0"
VERIFY_LOG=""
PATH_POSTCHECK_OK="skip"
PATH_POSTCHECK_EXIT="0"
PATH_POSTCHECK_LOG=""
PATH_POSTCHECK_FILE=""

if [[ "$POSTCONDITIONS_MODE" == "manual" ]]; then
  if [[ "$POSTCONDITIONS_STATUS" != "pending" && "$POSTCONDITIONS_STATUS" != "pass" && "$POSTCONDITIONS_STATUS" != "fail" ]]; then
    echo "Invalid POSTCONDITIONS_STATUS: $POSTCONDITIONS_STATUS" >&2
    exit 2
  fi

  if [[ "$POSTCONDITIONS_STATUS" == "pass" && "$TXS_PRESENT" != "true" ]]; then
    echo "Cannot mark pass without txs.json present" >&2
    exit 2
  fi
else
  VERIFY_LOG="$BUNDLE_DIR/postconditions.verify.log"
  if BUNDLE_PATH="$BUNDLE_DIR" "$ROOT/ops/tools/verify_bundle.sh" >"$VERIFY_LOG" 2>&1; then
    VERIFY_OK="true"
    VERIFY_EXIT="0"
  else
    verify_rc=$?
    VERIFY_OK="false"
    VERIFY_EXIT="$verify_rc"
  fi

  RUN_JSON="$BUNDLE_DIR/run.json"
  RUN_LANE=""
  if [[ -f "$RUN_JSON" ]]; then
    RUN_LANE=$(RUN_JSON="$RUN_JSON" python3 - <<'PY'
import json
import os
from pathlib import Path

run = json.loads(Path(os.environ["RUN_JSON"]).read_text())
print(run.get("lane", ""))
PY
)
  fi

  if [[ "$RUN_LANE" == "deploy" ]]; then
    PATH_POSTCHECK_FILE="$BUNDLE_DIR/checks.path.post.json"
    PATH_POSTCHECK_LOG="$BUNDLE_DIR/postconditions.pathcheck.log"
    if NETWORK="$NETWORK" LANE="$RUN_LANE" OUT_FILE="$PATH_POSTCHECK_FILE" "$ROOT/ops/tools/generate_path_checks.sh" >"$PATH_POSTCHECK_LOG" 2>&1; then
      PATH_POSTCHECK_OK="true"
      PATH_POSTCHECK_EXIT="0"
    else
      path_postcheck_rc=$?
      PATH_POSTCHECK_OK="false"
      PATH_POSTCHECK_EXIT="$path_postcheck_rc"
    fi
  fi
fi

VERIFIED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export BUNDLE_DIR NETWORK RUN_ID TXS_PRESENT POSTCONDITIONS_MODE POSTCONDITIONS_STATUS POSTCONDITIONS_NOTE VERIFIED_AT VERIFY_OK VERIFY_EXIT VERIFY_LOG ROOT PATH_POSTCHECK_OK PATH_POSTCHECK_EXIT PATH_POSTCHECK_LOG PATH_POSTCHECK_FILE

python3 - <<'PY'
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
mode = os.environ["POSTCONDITIONS_MODE"]
status_input = os.environ["POSTCONDITIONS_STATUS"]
verified_at = os.environ["VERIFIED_AT"]
notes = os.environ.get("POSTCONDITIONS_NOTE", "")

txs_present = os.environ["TXS_PRESENT"] == "true"
verify_ok = os.environ.get("VERIFY_OK", "true") == "true"
verify_exit = int(os.environ.get("VERIFY_EXIT", "0"))
verify_log = os.environ.get("VERIFY_LOG", "")
path_postcheck_ok = os.environ.get("PATH_POSTCHECK_OK", "skip")
path_postcheck_exit = int(os.environ.get("PATH_POSTCHECK_EXIT", "0"))
path_postcheck_log = os.environ.get("PATH_POSTCHECK_LOG", "")
path_postcheck_file = os.environ.get("PATH_POSTCHECK_FILE", "")
root = Path(os.environ["ROOT"])

run_payload = {}
run_path = bundle_dir / "run.json"
if run_path.exists():
    try:
        run_payload = json.loads(run_path.read_text())
    except Exception:
        run_payload = {}

network = (os.environ["NETWORK"] or run_payload.get("network") or "")
run_id = (os.environ["RUN_ID"] or run_payload.get("run_id") or "")
lane = (run_payload.get("lane") or "")

def resolve_policy_path(root_dir: Path, run_network: str):
    candidates = [
        root_dir / "ops/policy" / f"lane.{run_network}.json",
        root_dir / "ops/policy" / f"{run_network}.policy.json",
        root_dir / "ops/policy" / f"lane.{run_network}.example.json",
        root_dir / "ops/policy" / f"{run_network}.policy.example.json",
        root_dir / "policy" / f"{run_network}.policy.example.json",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None

lane_writes = True
policy_path = resolve_policy_path(root, network)
if policy_path and lane:
    try:
        policy = json.loads(policy_path.read_text())
        lane_cfg = (policy.get("lanes") or {}).get(lane) or {}
        if isinstance(lane_cfg, dict) and isinstance(lane_cfg.get("writes"), bool):
            lane_writes = lane_cfg["writes"]
    except Exception:
        lane_writes = True

checks = []

def push_check(name: str, status: str, details: str, required: bool = True):
    item = {
        "name": name,
        "status": status,
        "details": details
    }
    if not required:
        item["required"] = False
    checks.append(item)

if mode == "manual":
    status = status_input
    push_check(
        "txs_present",
        "pass" if txs_present else "fail",
        "txs.json exists" if txs_present else "txs.json missing"
    )
    push_check(
        "state_verified",
        "pass" if status == "pass" else ("fail" if status == "fail" else "pending"),
        "operator attestation (manual mode)"
    )
else:
    push_check(
        "bundle_verified",
        "pass" if verify_ok else "fail",
        "verify_bundle.sh passed" if verify_ok else f"verify_bundle.sh failed (exit={verify_exit})"
    )

    if txs_present:
        txs_path = bundle_dir / "txs.json"
        txs_payload = {}
        txs_parse_ok = True
        try:
            txs_payload = json.loads(txs_path.read_text())
        except Exception as exc:
            txs_parse_ok = False
            push_check("txs_json_parse", "fail", f"invalid txs.json: {exc}")

        if txs_parse_ok:
            txs = txs_payload.get("txs")
            tx_count = len(txs) if isinstance(txs, list) else 0
            push_check("txs_present", "pass", "txs.json exists")
            if lane_writes:
                push_check(
                    "txs_nonempty",
                    "pass" if tx_count > 0 else "fail",
                    f"tx count={tx_count}"
                )
            else:
                push_check(
                    "txs_nonempty",
                    "skip",
                    f"lane writes=false (tx count={tx_count})",
                    required=False
                )
    else:
        if lane_writes:
            push_check("txs_present", "fail", "txs.json missing")
        else:
            push_check("txs_present", "skip", "lane writes=false", required=False)

    snapshot_path = bundle_dir / "snapshots" / "post_state.json"
    if lane_writes:
        if snapshot_path.exists():
            try:
                json.loads(snapshot_path.read_text())
                push_check("post_state_snapshot", "pass", "snapshots/post_state.json exists")
            except Exception as exc:
                push_check("post_state_snapshot", "fail", f"invalid snapshots/post_state.json: {exc}")
        else:
            push_check("post_state_snapshot", "fail", "snapshots/post_state.json missing")
    else:
        push_check("post_state_snapshot", "skip", "lane writes=false", required=False)

    checks_path = Path(path_postcheck_file) if path_postcheck_file else (bundle_dir / "checks.path.json")
    if checks_path.exists():
        try:
            checks_path_payload = json.loads(checks_path.read_text())
            path_pass = checks_path_payload.get("pass") is True
            phase = str(checks_path_payload.get("phase", ""))
            deployment_present = checks_path_payload.get("deployment_present") is True
            details = f"{checks_path.name} pass=true"
            if phase:
                details += f" ({phase})"
            push_check(
                "checks_path_pass",
                "pass" if path_pass else "fail",
                details if path_pass else f"{checks_path.name} pass=false"
            )
            if path_postcheck_file:
                push_check(
                    "checks_path_postdeploy",
                    "pass" if (phase == "postdeploy" and deployment_present and path_postcheck_ok == "true") else "fail",
                    "postdeploy path checks generated" if (phase == "postdeploy" and deployment_present and path_postcheck_ok == "true") else f"postdeploy path checks failed (exit={path_postcheck_exit})"
                )
        except Exception as exc:
            push_check("checks_path_pass", "fail", f"invalid checks.path.json: {exc}")
    else:
        push_check("checks_path_pass", "skip", "checks.path.json not present", required=False)

    required_failures = [c for c in checks if c.get("required", True) and c.get("status") == "fail"]
    status = "pass" if len(required_failures) == 0 else "fail"

payload = {
    "postconditions_version": "2",
    "network": network,
    "run_id": run_id,
    "verified_at": verified_at,
    "checks": checks,
    "status": status,
    "mode": mode
}

if notes:
    payload["notes"] = notes
if mode == "auto":
    payload["auto"] = {
        "verify_log": verify_log or None
    }

(bundle_dir / "postconditions.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
print(f"Postconditions written to {bundle_dir / 'postconditions.json'}")
if mode == "auto" and status == "fail":
    raise SystemExit("Auto postconditions failed; see checks in postconditions.json")
PY
