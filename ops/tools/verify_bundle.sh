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

export BUNDLE_DIR ROOT NETWORK

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import subprocess


def type_ok(value, expected):
    mapping = {
        "string": str,
        "number": (int, float),
        "integer": int,
        "boolean": bool,
        "object": dict,
        "array": list,
    }
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    py_type = mapping.get(expected)
    return isinstance(value, py_type) if py_type else True


def validate_schema(schema, value, path="$"):
    if "oneOf" in schema:
        errs = []
        for branch in schema["oneOf"]:
            try:
                validate_schema(branch, value, path)
                return
            except ValueError as exc:
                errs.append(str(exc))
        raise ValueError(f"{path}: oneOf validation failed ({'; '.join(errs)})")

    expected_type = schema.get("type")
    if isinstance(expected_type, list):
        if not any(type_ok(value, t) for t in expected_type):
            raise ValueError(f"{path}: expected one of {expected_type}, got {type(value).__name__}")
    elif isinstance(expected_type, str):
        if not type_ok(value, expected_type):
            raise ValueError(f"{path}: expected {expected_type}, got {type(value).__name__}")

    if "const" in schema and value != schema["const"]:
        raise ValueError(f"{path}: const mismatch")

    enum = schema.get("enum")
    if enum is not None and value not in enum:
        raise ValueError(f"{path}: value not in enum")

    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                raise ValueError(f"{path}: missing required key '{key}'")
        props = schema.get("properties", {})
        for key, child in props.items():
            if key in value:
                validate_schema(child, value[key], f"{path}.{key}")
        if schema.get("additionalProperties") is False:
            unknown = set(value.keys()) - set(props.keys())
            if unknown:
                raise ValueError(f"{path}: unknown keys not allowed: {sorted(unknown)}")

    if isinstance(value, list):
        item_schema = schema.get("items")
        if item_schema:
            for idx, item in enumerate(value):
                validate_schema(item_schema, item, f"{path}[{idx}]")


bundle_dir = Path(os.environ["BUNDLE_DIR"])
root = Path(os.environ["ROOT"])
network_env = os.environ.get("NETWORK", "")
manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())

items = manifest.get("immutable_files", [])
if not items:
    raise SystemExit("manifest has no immutable_files")

required_files = {"run.json", "intent.json", "checks.json"}
paths = {item.get("path") for item in items if isinstance(item, dict)}
missing = required_files - paths
if missing:
    raise SystemExit(f"manifest missing required files: {', '.join(sorted(missing))}")

forbidden = {"txs.json", "approval.json", "postconditions.json"}
for bad in forbidden:
    if bad in paths:
        raise SystemExit(f"manifest must not include mutable/apply artifact: {bad}")

recomputed = []
for item in items:
    if not isinstance(item, dict):
        raise SystemExit("manifest immutable_files must contain objects")
    path = item.get("path")
    if not path:
        raise SystemExit("manifest entry missing path")
    file_path = bundle_dir / path
    if not file_path.exists():
        raise SystemExit(f"missing immutable file listed in manifest: {path}")
    data = file_path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != item.get("sha256"):
        raise SystemExit(f"hash mismatch for {path}")
    recomputed.append({"path": path, "sha256": digest})

bundle_hash_input = "\n".join([f"{i['path']}={i['sha256']}" for i in recomputed]).encode()
expected_bundle_hash = hashlib.sha256(bundle_hash_input).hexdigest()
if expected_bundle_hash != manifest.get("bundle_hash"):
    raise SystemExit("bundle_hash mismatch")

run = json.loads((bundle_dir / "run.json").read_text())
intent = json.loads((bundle_dir / "intent.json").read_text())
checks = json.loads((bundle_dir / "checks.json").read_text())

run_commit = run.get("git_commit", "")
if not run_commit:
    raise SystemExit("run.json missing git_commit")

current_commit = os.popen("git rev-parse HEAD").read().strip()
if current_commit != run_commit:
    raise SystemExit(f"Commit mismatch: run.json={run_commit} current={current_commit}")

run_network = run.get("network", "")
run_lane = run.get("lane", "")
run_id = run.get("run_id", "")
if not run_network or not run_lane or not run_id:
    raise SystemExit("run.json missing network, lane, or run_id")

if network_env and network_env != run_network:
    raise SystemExit(f"Network mismatch: {network_env} vs {run_network}")

policy_path = None
for candidate in [
    root / "ops/policy" / f"lane.{run_network}.json",
    root / "ops/policy" / f"{run_network}.policy.json",
    root / "ops/policy" / f"lane.{run_network}.example.json",
    root / "ops/policy" / f"{run_network}.policy.example.json",
    root / "policy" / f"{run_network}.policy.example.json",
]:
    if candidate.exists():
        policy_path = candidate
        break
if policy_path is None:
    raise SystemExit(f"Missing policy file for network: {run_network}")

policy = json.loads(policy_path.read_text())
lanes = policy.get("lanes", {})
if run_lane not in lanes:
    raise SystemExit(f"Lane '{run_lane}' not found in policy: {policy_path}")

lane_cfg = lanes.get(run_lane, {})
required_inputs = lane_cfg.get("required_inputs", [])
if required_inputs is None:
    required_inputs = []
if not isinstance(required_inputs, list):
    raise SystemExit("policy lanes.<lane>.required_inputs must be a list when set")

required_kinds = []
for item in required_inputs:
    if isinstance(item, dict) and isinstance(item.get("kind"), str) and item.get("kind").strip():
        required_kinds.append(item["kind"].strip())

inputs_path = bundle_dir / "inputs.json"
has_inputs = inputs_path.exists()
if has_inputs and "inputs.json" not in paths:
    raise SystemExit("inputs.json exists but is not listed in immutable manifest")

if required_kinds and not has_inputs:
    raise SystemExit(f"inputs.json required for lane '{run_lane}' (expected kind in {required_kinds})")

if has_inputs:
    schema_path = root / "schemas/inputs.schema.json"
    if not schema_path.exists():
        raise SystemExit(f"Missing inputs wrapper schema: {schema_path}")

    inputs_schema = json.loads(schema_path.read_text())
    inputs = json.loads(inputs_path.read_text())
    try:
        validate_schema(inputs_schema, inputs)
    except ValueError as exc:
        raise SystemExit(f"inputs schema validation failed: {exc}")

    if inputs.get("network") != run_network:
        raise SystemExit("inputs.network does not match run.json.network")
    if inputs.get("lane") != run_lane:
        raise SystemExit("inputs.lane does not match run.json.lane")
    if inputs.get("run_id") != run_id:
        raise SystemExit("inputs.run_id does not match run.json.run_id")

    if required_kinds:
        kind = str(inputs.get("kind", ""))
        if kind not in required_kinds:
            raise SystemExit(f"inputs.kind '{kind}' not allowed; expected one of {required_kinds}")

    actual_inputs_hash = hashlib.sha256(inputs_path.read_bytes()).hexdigest()
    intent_inputs_hash = intent.get("inputs_sha256", "")
    if not intent_inputs_hash:
        raise SystemExit("inputs.json present but intent.json.inputs_sha256 is missing")
    if intent_inputs_hash != actual_inputs_hash:
        raise SystemExit("inputs hash mismatch: intent.json.inputs_sha256 vs inputs.json")

    if checks.get("inputs_pinned") is not True:
        raise SystemExit("inputs.json present but checks.json.inputs_pinned is not true")

required_checks = lane_cfg.get("required_checks", [])
if required_checks is None:
    required_checks = []
if not isinstance(required_checks, list):
    raise SystemExit("policy lanes.<lane>.required_checks must be a list when set")

path_invariants_required = "path_invariants" in required_checks
if path_invariants_required:
    checks_path = bundle_dir / "checks.path.json"
    checks_generated_locally = False
    if checks_path.exists():
        if "checks.path.json" not in paths:
            raise SystemExit("bundle_manifest.json is missing checks.path.json in immutable_files")
    elif run_lane == "deploy":
        checks_path = bundle_dir / "checks.path.verify.json"
        env = os.environ.copy()
        env.update({
            "NETWORK": run_network,
            "LANE": run_lane,
            "OUT_FILE": str(checks_path),
            "POLICY_FILE": str(policy_path),
        })
        result = subprocess.run(
            [str(root / "ops/tools/generate_path_checks.sh")],
            env=env,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            onchain_log = checks_path.with_suffix(".onchain.log")
            signed_log = checks_path.with_suffix(".signed-consume.log")
            details = result.stderr.strip() or result.stdout.strip() or f"exit={result.returncode}"
            raise SystemExit(
                f"local predeploy path checks failed: {details} "
                f"(logs: {onchain_log}, {signed_log})"
            )
        checks_generated_locally = True
    else:
        raise SystemExit(f"Lane '{run_lane}' requires path_invariants but checks.path.json is missing")

    path_checks = json.loads(checks_path.read_text())
    required_checks_map = path_checks.get("required_checks", {})
    path_invariants = path_checks.get("path_invariants", {})
    checks_phase = str(path_checks.get("phase", ""))
    deployment_present = path_checks.get("deployment_present") is True

    required_path_invariants = [
        "adapter_wiring_frozen",
        "sales_caller_frozen_to_adapter",
        "epoch_token_coupling_holds",
        "role_owner_hygiene_ok",
        "auction_config_matches",
        "sale_handshake_ok",
        "movement_config_policy_ok",
        "signed_consume_path_ok",
    ]

    if run_lane == "deploy" and not deployment_present and checks_phase == "predeploy":
        predeploy_required_checks = ["chain_id", "rpc_allowlist", "signer_allowlist"]
        failed_predeploy_checks = [
            name for name in predeploy_required_checks if required_checks_map.get(name) is not True
        ]
        if failed_predeploy_checks:
            raise SystemExit(f"required checks failed: {', '.join(sorted(set(failed_predeploy_checks)))}")
        if path_checks.get("pass") is not True:
            raise SystemExit("checks.path.json has pass=false")
        print("Manifest hashes verified")
        if has_inputs:
            print("Inputs wrapper verified")
        if checks_generated_locally:
            print("Required checks verified (predeploy/local)")
        else:
            print("Required checks verified (predeploy)")
        print(f"Bundle verified: {bundle_dir}")
        raise SystemExit(0)

    failed_required_checks = []
    for check_name in required_checks:
        if check_name == "path_invariants":
            continue
        if required_checks_map.get(check_name) is not True:
            failed_required_checks.append(check_name)

    failed_path_invariants = [name for name in required_path_invariants if path_invariants.get(name) is not True]
    if failed_path_invariants:
        failed_required_checks.append("path_invariants")

    if failed_required_checks:
        raise SystemExit(f"required checks failed: {', '.join(sorted(set(failed_required_checks)))}")
    if failed_path_invariants:
        raise SystemExit(f"path invariants failed: {', '.join(failed_path_invariants)}")
    if path_checks.get("pass") is not True:
        raise SystemExit("checks.path.json has pass=false")

print("Manifest hashes verified")
if has_inputs:
    print("Inputs wrapper verified")
if path_invariants_required:
    print("Required checks verified")
    print("Path invariants verified")
print(f"Bundle verified: {bundle_dir}")
PY
