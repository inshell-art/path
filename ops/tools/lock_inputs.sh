#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
LANE=${LANE:-}
RUN_ID=${RUN_ID:-}
INPUT_FILE=${INPUT_FILE:-}
INPUT_KIND=${INPUT_KIND:-constructor_params}
PARAMS_SCHEMA=${PARAMS_SCHEMA:-}
ORIGIN=${ORIGIN:-}
OUT_DIR=${OUT_DIR:-}
FORCE=${FORCE:-0}

if [[ -z "$NETWORK" || -z "$LANE" || -z "$RUN_ID" || -z "$INPUT_FILE" ]]; then
  echo "Usage: NETWORK=<devnet|sepolia|mainnet> LANE=<lane> RUN_ID=<id> INPUT_FILE=<path> $0" >&2
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
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$ROOT/artifacts/$NETWORK/current/inputs"
fi

INPUT_PATH=$(cd "$(dirname "$INPUT_FILE")" && pwd)/$(basename "$INPUT_FILE")
if [[ ! -f "$INPUT_PATH" ]]; then
  echo "INPUT_FILE not found: $INPUT_PATH" >&2
  exit 2
fi

if [[ -n "$PARAMS_SCHEMA" ]]; then
  if [[ "$PARAMS_SCHEMA" = /* ]]; then
    PARAMS_SCHEMA_PATH="$PARAMS_SCHEMA"
  else
    PARAMS_SCHEMA_PATH="$ROOT/$PARAMS_SCHEMA"
  fi
  if [[ ! -f "$PARAMS_SCHEMA_PATH" ]]; then
    echo "PARAMS_SCHEMA not found: $PARAMS_SCHEMA_PATH" >&2
    exit 2
  fi
else
  PARAMS_SCHEMA_PATH=""
fi

if [[ -z "$ORIGIN" ]]; then
  if [[ "$INPUT_PATH" == "$ROOT"/* ]]; then
    ORIGIN="repo_file"
  else
    ORIGIN="local_secure_path"
  fi
fi

mkdir -p "$OUT_DIR"
OUTPUT_PATH="$OUT_DIR/inputs.$RUN_ID.json"
if [[ -e "$OUTPUT_PATH" && "$FORCE" != "1" ]]; then
  echo "Refusing to overwrite existing locked inputs: $OUTPUT_PATH (set FORCE=1 to overwrite)" >&2
  exit 2
fi

export ROOT NETWORK LANE RUN_ID INPUT_PATH INPUT_KIND PARAMS_SCHEMA_PATH ORIGIN OUTPUT_PATH

python3 - <<'PY'
import hashlib
import json
import os
import re
from datetime import datetime, timezone
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


def normalize(value):
    if isinstance(value, dict):
        return {k: normalize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(v) for v in value]
    if isinstance(value, str):
        if re.fullmatch(r"0x[0-9a-fA-F]{40}", value):
            return value.lower()
        return value
    return value


def ensure_invariants(params):
    bad_tokens = ["0xYour", "<TODO>", "REPLACE_ME"]

    def walk(value, path="$"):
        if isinstance(value, dict):
            for k, v in value.items():
                walk(v, f"{path}.{k}")
        elif isinstance(value, list):
            for i, v in enumerate(value):
                walk(v, f"{path}[{i}]")
        elif isinstance(value, str):
            for tok in bad_tokens:
                if tok in value:
                    raise ValueError(f"placeholder token '{tok}' found at {path}")
            if re.fullmatch(r"[0-9]+", value):
                int(value)
            elif re.fullmatch(r"[0-9]+\.[0-9]+", value):
                float(value)

    walk(params)
    for key in ("name", "symbol"):
        if key in params and isinstance(params[key], str) and params[key].strip() == "":
            raise ValueError(f"{key} cannot be empty when present")


root = Path(os.environ["ROOT"])
network = os.environ["NETWORK"]
lane = os.environ["LANE"]
run_id = os.environ["RUN_ID"]
input_path = Path(os.environ["INPUT_PATH"])
input_kind = os.environ["INPUT_KIND"]
origin = os.environ["ORIGIN"]
params_schema_path = os.environ.get("PARAMS_SCHEMA_PATH", "")
output_path = Path(os.environ["OUTPUT_PATH"])

raw = input_path.read_bytes()
source_sha256 = hashlib.sha256(raw).hexdigest()

try:
    params = json.loads(raw.decode())
except Exception as exc:
    raise SystemExit(f"Invalid JSON in INPUT_FILE: {exc}")

if not isinstance(params, dict):
    raise SystemExit("INPUT_FILE JSON must be an object")

params = normalize(params)
try:
    ensure_invariants(params)
except ValueError as exc:
    raise SystemExit(f"Invalid params invariants: {exc}")

if params_schema_path:
    schema = json.loads(Path(params_schema_path).read_text())
    try:
        validate_schema(schema, params, "$params")
    except ValueError as exc:
        raise SystemExit(f"PARAMS_SCHEMA validation failed: {exc}")

wrapper = {
    "inputs_version": "1",
    "network": network,
    "lane": lane,
    "run_id": run_id,
    "kind": input_kind,
    "created_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "source": {
        "origin": origin,
        "path_hint": str(input_path),
        "sha256": source_sha256,
    },
    "params": params,
}

canonical = json.dumps(wrapper, indent=2, sort_keys=True) + "\n"
output_path.write_text(canonical)
os.chmod(output_path, 0o600)

locked_sha256 = hashlib.sha256(canonical.encode()).hexdigest()
print(f"locked_inputs_path={output_path}")
print(f"inputs_sha256={locked_sha256}")
print(f"inputs_hash_suffix={locked_sha256[-8:]}")
PY
