#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
LANE=${LANE:-}
RUN_ID=${RUN_ID:-}
FORCE=${FORCE:-0}
INPUTS_TEMPLATE=${INPUTS_TEMPLATE:-}

if [[ -z "$NETWORK" || -z "$LANE" || -z "$RUN_ID" ]]; then
  echo "Usage: NETWORK=<devnet|sepolia|mainnet> LANE=<observe|plan|deploy|handoff|govern|treasury|operate|emergency> RUN_ID=<id> [INPUTS_TEMPLATE=<path>] $0" >&2
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

if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "Invalid RUN_ID (allowed: A-Za-z0-9._:-): $RUN_ID" >&2
  exit 2
fi

ROOT=$(git rev-parse --show-toplevel)
BUNDLE_DIR="$ROOT/bundles/$NETWORK/$RUN_ID"

if [[ -d "$BUNDLE_DIR" ]] && [[ -n "$(ls -A "$BUNDLE_DIR" 2>/dev/null)" ]] && [[ "$FORCE" != "1" ]]; then
  echo "Bundle dir already exists and is not empty: $BUNDLE_DIR" >&2
  echo "Set FORCE=1 to overwrite." >&2
  exit 2
fi

POLICY_FILE=""
for candidate in \
  "$ROOT/ops/policy/lane.${NETWORK}.json" \
  "$ROOT/ops/policy/${NETWORK}.policy.json" \
  "$ROOT/ops/policy/lane.${NETWORK}.example.json" \
  "$ROOT/ops/policy/${NETWORK}.policy.example.json" \
  "$ROOT/policy/${NETWORK}.policy.example.json"
do
  if [[ -f "$candidate" ]]; then
    POLICY_FILE="$candidate"
    break
  fi
done

if [[ -z "$POLICY_FILE" ]]; then
  echo "Missing policy file for network: $NETWORK" >&2
  exit 2
fi

if [[ -n "$INPUTS_TEMPLATE" ]]; then
  INPUTS_TEMPLATE_ABS=$(cd "$(dirname "$INPUTS_TEMPLATE")" && pwd)/$(basename "$INPUTS_TEMPLATE")
  if [[ ! -f "$INPUTS_TEMPLATE_ABS" ]]; then
    echo "INPUTS_TEMPLATE not found: $INPUTS_TEMPLATE_ABS" >&2
    exit 2
  fi
else
  INPUTS_TEMPLATE_ABS=""
fi

mkdir -p "$BUNDLE_DIR"

GIT_COMMIT=$(git rev-parse HEAD)
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export ROOT BUNDLE_DIR NETWORK LANE RUN_ID GIT_COMMIT CREATED_AT POLICY_FILE INPUTS_TEMPLATE_ABS

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path


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
network = os.environ["NETWORK"]
lane = os.environ["LANE"]
run_id = os.environ["RUN_ID"]
git_commit = os.environ["GIT_COMMIT"]
created_at = os.environ["CREATED_AT"]
policy_file = Path(os.environ["POLICY_FILE"])
inputs_template = os.environ.get("INPUTS_TEMPLATE_ABS", "")

policy = json.loads(policy_file.read_text())
lane_cfg = ((policy.get("lanes") or {}).get(lane) or {})
required_inputs = lane_cfg.get("required_inputs", [])
if required_inputs is None:
    required_inputs = []
if not isinstance(required_inputs, list):
    raise SystemExit("policy lanes.<lane>.required_inputs must be a list when set")

required_kinds = []
for item in required_inputs:
    if isinstance(item, dict) and isinstance(item.get("kind"), str) and item.get("kind").strip():
        required_kinds.append(item["kind"].strip())

inputs_payload = None
inputs_sha256 = ""
if inputs_template:
    src = Path(inputs_template)
    if not src.exists():
        raise SystemExit(f"INPUTS_TEMPLATE not found: {src}")
    try:
        inputs_payload = json.loads(src.read_text())
    except Exception as exc:
        raise SystemExit(f"Invalid JSON in INPUTS_TEMPLATE: {exc}")

    schema_path = root / "schemas/inputs.schema.json"
    if not schema_path.exists():
        raise SystemExit(f"Missing inputs wrapper schema: {schema_path}")
    schema = json.loads(schema_path.read_text())
    try:
        validate_schema(schema, inputs_payload)
    except ValueError as exc:
        raise SystemExit(f"inputs schema validation failed: {exc}")

    if inputs_payload.get("network") != network:
        raise SystemExit("inputs.network does not match bundle NETWORK")
    if inputs_payload.get("lane") != lane:
        raise SystemExit("inputs.lane does not match bundle LANE")
    if inputs_payload.get("run_id") != run_id:
        raise SystemExit("inputs.run_id does not match bundle RUN_ID")

    if required_kinds:
        kind = str(inputs_payload.get("kind", ""))
        if kind not in required_kinds:
            raise SystemExit(f"inputs.kind '{kind}' not allowed for lane; expected one of {required_kinds}")

    canonical_inputs = json.dumps(inputs_payload, indent=2, sort_keys=True) + "\n"
    (bundle_dir / "inputs.json").write_text(canonical_inputs)
    inputs_sha256 = hashlib.sha256(canonical_inputs.encode()).hexdigest()
else:
    if required_kinds:
        raise SystemExit(f"Missing INPUTS_TEMPLATE for lane requiring inputs kinds: {required_kinds}")

run = {
    "run_id": run_id,
    "network": network,
    "lane": lane,
    "git_commit": git_commit,
    "created_at": created_at,
}
intent = {
    "intent_version": 1,
    "network": network,
    "lane": lane,
    "ops": ["stub"],
    "notes": "Scaffold stub. Replace with real intent generation.",
}
if inputs_sha256:
    intent["inputs_sha256"] = inputs_sha256

checks = {
    "checks_version": 1,
    "network": network,
    "lane": lane,
    "pass": True,
    "stub": True,
    "notes": "Scaffold stub. Replace with real checks/simulations.",
}
if inputs_sha256:
    checks["inputs_pinned"] = True

(bundle_dir / "run.json").write_text(json.dumps(run, indent=2, sort_keys=True) + "\n")
(bundle_dir / "intent.json").write_text(json.dumps(intent, indent=2, sort_keys=True) + "\n")
(bundle_dir / "checks.json").write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n")

immutable_files = ["run.json", "intent.json", "checks.json"]
if inputs_sha256:
    immutable_files.append("inputs.json")

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
    "immutable_files": items,
}

(bundle_dir / "bundle_manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

if inputs_sha256:
    print(f"Bundle created at {bundle_dir} (inputs_sha256={inputs_sha256})")
else:
    print(f"Bundle created at {bundle_dir}")
PY
