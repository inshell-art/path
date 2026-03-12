#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
RUN_ID=${RUN_ID:-}
BUNDLE_PATH=${BUNDLE_PATH:-}
POSTCONDITIONS_MODE=${POSTCONDITIONS_MODE:-auto}
POSTCONDITIONS_STATUS=${POSTCONDITIONS_STATUS:-}
POSTCONDITIONS_NOTE=${POSTCONDITIONS_NOTE:-}
RECEIPT_RPC_URL=${RECEIPT_RPC_URL:-${ETH_RPC_URL:-${RPC_URL:-}}}

ROOT=$(git rev-parse --show-toplevel)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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

if [[ "$POSTCONDITIONS_MODE" != "auto" && "$POSTCONDITIONS_MODE" != "manual" ]]; then
  echo "Invalid POSTCONDITIONS_MODE: $POSTCONDITIONS_MODE (expected: auto|manual)" >&2
  exit 2
fi

if [[ "$POSTCONDITIONS_MODE" == "manual" ]]; then
  if [[ -z "$POSTCONDITIONS_STATUS" ]]; then
    echo "POSTCONDITIONS_MODE=manual requires POSTCONDITIONS_STATUS (pending|pass|fail)" >&2
    exit 2
  fi
  if [[ "$POSTCONDITIONS_STATUS" != "pending" && "$POSTCONDITIONS_STATUS" != "pass" && "$POSTCONDITIONS_STATUS" != "fail" ]]; then
    echo "Invalid POSTCONDITIONS_STATUS: $POSTCONDITIONS_STATUS" >&2
    exit 2
  fi
fi

VERIFIED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VERIFY_BUNDLE_PASS="false"
VERIFY_LOG_PATH=""
cleanup() {
  if [[ -n "$VERIFY_LOG_PATH" && -f "$VERIFY_LOG_PATH" ]]; then
    rm -f "$VERIFY_LOG_PATH"
  fi
}
trap cleanup EXIT

if [[ "$POSTCONDITIONS_MODE" == "auto" ]]; then
  VERIFY_LOG_PATH=$(mktemp)
  if BUNDLE_PATH="$BUNDLE_DIR" "$SCRIPT_DIR/verify_bundle.sh" >"$VERIFY_LOG_PATH" 2>&1; then
    VERIFY_BUNDLE_PASS="true"
  else
    VERIFY_BUNDLE_PASS="false"
  fi
fi

export BUNDLE_DIR NETWORK RUN_ID POSTCONDITIONS_MODE POSTCONDITIONS_STATUS POSTCONDITIONS_NOTE VERIFIED_AT RECEIPT_RPC_URL VERIFY_BUNDLE_PASS VERIFY_LOG_PATH

python3 - <<'PY'
import json
import os
import urllib.error
import urllib.request
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
mode = os.environ["POSTCONDITIONS_MODE"]
status_manual = os.environ.get("POSTCONDITIONS_STATUS", "")
verified_at = os.environ["VERIFIED_AT"]
notes = os.environ.get("POSTCONDITIONS_NOTE", "")
rpc_url = os.environ.get("RECEIPT_RPC_URL", "").strip()
verify_bundle_pass = os.environ.get("VERIFY_BUNDLE_PASS", "false") == "true"
verify_log_path = os.environ.get("VERIFY_LOG_PATH", "")

run = {}
run_path = bundle_dir / "run.json"
if run_path.exists():
    run = json.loads(run_path.read_text())

network = (os.environ.get("NETWORK", "").strip() or str(run.get("network", "")).strip())
run_id = (os.environ.get("RUN_ID", "").strip() or str(run.get("run_id", "")).strip() or bundle_dir.name)
lane = str(run.get("lane", "")).strip()

checks = []
failure_reasons = []


def add_check(name, status, required, details):
    checks.append({
        "name": name,
        "status": status,
        "required": required,
        "details": details,
    })
    if required and status != "pass":
        failure_reasons.append(f"{name}: {details}")


def read_tail(path, max_lines=20):
    p = Path(path)
    if not p.exists():
        return ""
    lines = p.read_text(errors="replace").splitlines()
    return " | ".join(lines[-max_lines:]).strip()


txs_path = bundle_dir / "txs.json"
txs_present = txs_path.exists()
tx_hashes = []
if txs_present:
    try:
        txs_doc = json.loads(txs_path.read_text())
        txs_raw = txs_doc.get("txs", [])
        if isinstance(txs_raw, list):
            tx_hashes = [x for x in txs_raw if isinstance(x, str) and x.startswith("0x") and len(x) > 2]
    except Exception:
        tx_hashes = []

if mode == "manual":
    if status_manual == "pass" and not txs_present:
        raise SystemExit("Cannot mark pass without txs.json present in manual mode")

    add_check(
        "txs_present",
        "pass" if txs_present else "fail",
        False,
        "txs.json exists" if txs_present else "txs.json missing",
    )
    state_status = "pass" if status_manual == "pass" else ("fail" if status_manual == "fail" else "pending")
    add_check("state_verified", state_status, False, "manual operator assertion")
    status = status_manual
else:
    add_check(
        "txs_present",
        "pass" if txs_present else "fail",
        True,
        "txs.json exists" if txs_present else "txs.json missing",
    )

    verify_tail = read_tail(verify_log_path)
    add_check(
        "bundle_verified",
        "pass" if verify_bundle_pass else "fail",
        True,
        "verify_bundle.sh passed" if verify_bundle_pass else f"verify_bundle.sh failed ({verify_tail or 'see logs'})",
    )

    checks_path = bundle_dir / "checks.path.json"
    if checks_path.exists():
        try:
            checks_path_doc = json.loads(checks_path.read_text())
            path_ok = checks_path_doc.get("pass") is True
            add_check(
                "checks_path_pass",
                "pass" if path_ok else "fail",
                True,
                "checks.path.json has pass=true" if path_ok else "checks.path.json exists but pass is not true",
            )
        except Exception as exc:
            add_check("checks_path_pass", "fail", True, f"invalid checks.path.json: {exc}")
    else:
        add_check("checks_path_pass", "skip", False, "checks.path.json not present")

    if lane == "deploy":
        post_state = bundle_dir / "snapshots" / "post_state.json"
        has_post_state = post_state.exists()
        add_check(
            "deploy_post_state_present",
            "pass" if has_post_state else "fail",
            True,
            "snapshots/post_state.json exists" if has_post_state else "missing snapshots/post_state.json for deploy lane",
        )
    else:
        add_check("deploy_post_state_present", "skip", False, f"lane={lane or 'unknown'}")

    if tx_hashes and rpc_url:
        failed_receipts = []
        for tx_hash in tx_hashes:
            payload = json.dumps({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "eth_getTransactionReceipt",
                "params": [tx_hash],
            }).encode()
            req = urllib.request.Request(
                rpc_url,
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                with urllib.request.urlopen(req, timeout=10) as resp:
                    body = json.loads(resp.read().decode())
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
                failed_receipts.append(f"{tx_hash}: rpc_error={exc}")
                continue

            if "error" in body:
                failed_receipts.append(f"{tx_hash}: rpc_error={body['error']}")
                continue
            receipt = body.get("result")
            if not isinstance(receipt, dict):
                failed_receipts.append(f"{tx_hash}: missing receipt")
                continue
            status_hex = str(receipt.get("status", "")).lower()
            if status_hex not in {"0x1", "1"}:
                failed_receipts.append(f"{tx_hash}: receipt.status={status_hex or 'missing'}")

        add_check(
            "receipts_success",
            "pass" if not failed_receipts else "fail",
            False,
            "all receipt statuses are success" if not failed_receipts else "; ".join(failed_receipts),
        )
    elif tx_hashes:
        add_check("receipts_success", "skip", False, "tx hashes present but RECEIPT_RPC_URL/ETH_RPC_URL/RPC_URL is not set")
    else:
        add_check("receipts_success", "skip", False, "no tx hashes available")

    status = "pass" if not failure_reasons else "fail"

payload = {
    "postconditions_version": "1",
    "mode": mode,
    "network": network,
    "lane": lane,
    "run_id": run_id,
    "verified_at": verified_at,
    "checks": checks,
    "status": status,
}

if failure_reasons:
    payload["failure_reasons"] = failure_reasons
if notes:
    payload["notes"] = notes

(bundle_dir / "postconditions.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
print(f"Postconditions written to {bundle_dir / 'postconditions.json'}")
PY
