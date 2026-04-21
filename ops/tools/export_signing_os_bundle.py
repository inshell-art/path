#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse


CHAIN_ID_BY_NETWORK = {
    "devnet": 31337,
    "sepolia": 11155111,
    "mainnet": 1,
}

SPARSE_PATHS = [
    "package.json",
    "ops",
    "evm",
    "schemas",
    "vendors",
]

PORTABLE_TOOL_OVERRIDES = [
    "ops/tools/approve_bundle.sh",
    "ops/tools/apply_bundle.sh",
    "ops/tools/postconditions.sh",
    "ops/tools/verify_bundle.sh",
    "ops/tools/generate_path_checks.sh",
    "ops/tools/require_signing_os_context.sh",
]

PORTABLE_FILE_OVERRIDES = [
    "schemas/path.protocol_release.schema.json",
    "ops/params.constructor.example.json",
    "ops/tools/export_fe_release.sh",
]

PORTABLE_DIR_OVERRIDES = [
    "ops/policy",
]

IMMUTABLE_BUNDLE_FILES = [
    "run.json",
    "intent.json",
    "checks.json",
    "bundle_manifest.json",
]

OPTIONAL_BUNDLE_FILES = [
    "inputs.json",
]

MUTABLE_BUNDLE_PATHS = [
    "approval.json",
    "txs.json",
    "postconditions.json",
    "inputs.params.json",
    "checks.path.verify.json",
    "checks.path.post.json",
    "deployments",
    "snapshots",
]


ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIR = Path(__file__).resolve().parent
DEFAULT_NODE_RUNTIME_ENV = "PATH_SIGNING_NODE_RUNTIME_ROOT"


def run(cmd: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=env,
        check=True,
        text=True,
        capture_output=True,
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def git_head_commit(repo_root: Path) -> str:
    return run(["git", "-C", str(repo_root), "rev-parse", "HEAD"]).stdout.strip()


def resolve_rpc_url(network: str, explicit_rpc_url: str, policy: dict) -> tuple[str, str]:
    if explicit_rpc_url:
        parsed = urlparse(explicit_rpc_url)
        host = parsed.hostname or parsed.netloc
        if not host:
            raise SystemExit(f"Unable to derive rpc host from --rpc-url: {explicit_rpc_url}")
        return explicit_rpc_url, host.lower()

    env_key = f"{network.upper()}_RPC_URL"
    env_value = os.environ.get(env_key, "").strip()
    if env_value:
        parsed = urlparse(env_value)
        host = parsed.hostname or parsed.netloc
        if not host:
            raise SystemExit(f"Unable to derive rpc host from ${env_key}: {env_value}")
        return env_value, host.lower()

    allowlist = policy.get("rpc_host_allowlist")
    if isinstance(allowlist, list) and len(allowlist) == 1 and isinstance(allowlist[0], str):
        return "", allowlist[0].strip().lower()

    raise SystemExit(
        f"Exact RPC host is ambiguous for {network}. Pass --rpc-url or set {env_key}."
    )


def resolve_policy(network: str) -> Path:
    candidates = [
        ROOT / "ops" / "policy" / f"lane.{network}.json",
        ROOT / "ops" / "policy" / f"{network}.policy.json",
        ROOT / "ops" / "policy" / f"lane.{network}.example.json",
        ROOT / "ops" / "policy" / f"{network}.policy.example.json",
        ROOT / "policy" / f"{network}.policy.example.json",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise SystemExit(f"Missing policy file for network: {network}")


def resolve_signer(policy: dict, lane: str, explicit_alias: str) -> tuple[str, str]:
    lanes = policy.get("lanes") or {}
    lane_cfg = lanes.get(lane) or {}
    allowed = [str(item).strip() for item in lane_cfg.get("allowed_signers") or [] if str(item).strip()]
    if explicit_alias:
        if explicit_alias not in allowed:
            raise SystemExit(f"--signer-alias {explicit_alias!r} is not allowed for lane {lane}: {allowed}")
        alias = explicit_alias
    elif len(allowed) == 1:
        alias = allowed[0]
    else:
        raise SystemExit(f"Lane {lane} needs an explicit --signer-alias. Allowed: {allowed}")

    signer_map = policy.get("signer_alias_map") or {}
    address = str(signer_map.get(alias, "")).strip()
    if not address:
        raise SystemExit(f"signer_alias_map entry missing for {alias}")
    return alias, address


def copytree(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst, symlinks=True)


def resolve_node_runtime_root() -> Path:
    explicit = os.environ.get(DEFAULT_NODE_RUNTIME_ENV, "").strip()
    if explicit:
        root = Path(explicit).expanduser().resolve()
    else:
        node_path = run(["node", "-p", "process.execPath"]).stdout.strip()
        if not node_path:
            raise SystemExit("Unable to resolve node runtime path from node -p process.execPath")
        root = Path(node_path).resolve().parents[1]

    node_bin = root / "bin" / "node"
    npm_bin = root / "bin" / "npm"
    npm_lib = root / "lib" / "node_modules" / "npm"
    if not node_bin.is_file():
        raise SystemExit(f"Node runtime is missing bin/node: {node_bin}")
    if not npm_bin.exists():
        raise SystemExit(f"Node runtime is missing bin/npm: {npm_bin}")
    if not npm_lib.is_dir():
        raise SystemExit(f"Node runtime is missing lib/node_modules/npm: {npm_lib}")
    return root


def build_sparse_workspace(repo_root: Path, commit: str, workspace_root: Path) -> None:
    run(["git", "clone", "--no-checkout", str(repo_root), str(workspace_root)])
    run(["git", "-C", str(workspace_root), "sparse-checkout", "init", "--cone"])
    run(["git", "-C", str(workspace_root), "sparse-checkout", "set", *SPARSE_PATHS])
    run(["git", "-C", str(workspace_root), "checkout", "--detach", commit])
    subprocess.run(
        ["git", "-C", str(workspace_root), "submodule", "update", "--init", "--checkout", "--recursive"],
        check=True,
    )
    origin = run(["git", "-C", str(workspace_root), "remote"], cwd=workspace_root).stdout.split()
    if "origin" in origin:
        run(["git", "-C", str(workspace_root), "remote", "remove", "origin"])


def populate_evm_runtime(source_repo_root: Path, workspace_root: Path) -> None:
    source_node_modules = source_repo_root / "evm" / "node_modules"
    if not source_node_modules.is_dir():
        raise SystemExit(f"Missing local evm/node_modules at {source_node_modules}. Run npm --prefix evm install first.")
    copytree(source_node_modules, workspace_root / "evm" / "node_modules")

    env = os.environ.copy()
    env["PATH"] = os.environ.get("PATH", "")
    compile_cmd = ["npm", "exec", "--", "hardhat", "compile"]
    try:
        subprocess.run(compile_cmd, cwd=str(workspace_root / "evm"), env=env, check=True)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"Failed to compile exported workspace: {exc}") from exc


def overlay_portable_tool_overrides(source_repo_root: Path, workspace_root: Path) -> None:
    for rel in PORTABLE_TOOL_OVERRIDES:
        src = source_repo_root / rel
        dst = workspace_root / rel
        if not src.is_file():
            raise SystemExit(f"Missing portable tool override source: {src}")
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        dst.chmod(0o755)

    for rel in PORTABLE_FILE_OVERRIDES:
        src = source_repo_root / rel
        dst = workspace_root / rel
        if not src.is_file():
            raise SystemExit(f"Missing portable file override source: {src}")
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

    for rel in PORTABLE_DIR_OVERRIDES:
        src = source_repo_root / rel
        dst = workspace_root / rel
        if not src.is_dir():
            raise SystemExit(f"Missing portable dir override source: {src}")
        copytree(src, dst)


def validate_source_bundle(bundle_dir: Path) -> tuple[dict, dict]:
    if not bundle_dir.is_dir():
        raise SystemExit(f"Bundle directory not found: {bundle_dir}")

    missing = [name for name in IMMUTABLE_BUNDLE_FILES if not (bundle_dir / name).is_file()]
    if missing:
        raise SystemExit(f"Bundle missing required files: {', '.join(missing)}")

    mutable_present = [name for name in MUTABLE_BUNDLE_PATHS if (bundle_dir / name).exists()]
    if mutable_present:
        raise SystemExit(
            "Source bundle already contains mutable/apply artifacts. Use a pre-approval bundle: "
            + ", ".join(mutable_present)
        )

    run_payload = json.loads((bundle_dir / "run.json").read_text())
    intent_payload = json.loads((bundle_dir / "intent.json").read_text())
    return run_payload, intent_payload


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def manifest_entries(root: Path) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel == "SHA256SUMS.txt":
            continue
        entries.append({"path": rel, "sha256": sha256_file(path)})
    return entries


def write_checksums(root: Path, entries: list[dict[str, str]]) -> None:
    lines = [f"{entry['sha256']}  {entry['path']}" for entry in entries]
    write_text(root / "SHA256SUMS.txt", "\n".join(lines) + "\n")


def render_export_bundle_manifest(source_manifest: dict, internal_bundle_dir: Path) -> dict:
    immutable_entries: list[dict[str, str]] = []
    for item in source_manifest.get("immutable_files", []):
        if not isinstance(item, dict):
            raise SystemExit("bundle_manifest.json immutable_files must contain objects")
        rel = str(item.get("path", "")).strip()
        if not rel or rel == "checks.path.json":
            continue
        file_path = internal_bundle_dir / rel
        if not file_path.is_file():
            raise SystemExit(f"Missing immutable file while exporting Signing OS bundle: {rel}")
        immutable_entries.append({"path": rel, "sha256": sha256_file(file_path)})

    bundle_hash_input = "\n".join(
        f"{entry['path']}={entry['sha256']}" for entry in immutable_entries
    ).encode()
    exported = dict(source_manifest)
    exported["immutable_files"] = immutable_entries
    exported["bundle_hash"] = hashlib.sha256(bundle_hash_input).hexdigest()
    return exported


def wrapper_script(name: str) -> str:
    return f"""#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "$0")" && pwd)/_run_step.sh" {name}
"""


def run_all_script() -> str:
    return """#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
START_FROM="preflight-signingos"
STEPS=(preflight-signingos verify approve apply postconditions)

usage() {
  cat <<'EOF'
Usage:
  run-all
  run-all --from <preflight-signingos|verify|approve|apply|postconditions>

Runs the PATH Signing OS phase in order.

Each step auto-loads:
  ~/.opsec/path/env/<network>.env

Override the env path with:
  PATH_SIGNING_ENV_FILE=/path/to/<network>.env ./bin/run-all
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --from)
      START_FROM="${2:-}"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

found=0
for step in "${STEPS[@]}"; do
  if [[ "$step" == "$START_FROM" ]]; then
    found=1
    break
  fi
done

if [[ "$found" -ne 1 ]]; then
  echo "Invalid --from step: $START_FROM" >&2
  usage >&2
  exit 2
fi

started=0
for step in "${STEPS[@]}"; do
  if [[ "$started" -eq 0 ]]; then
    if [[ "$step" != "$START_FROM" ]]; then
      continue
    fi
    started=1
  fi

  echo
  echo "[operator] ===== running $step ====="
  if [[ "$step" == "approve" ]]; then
    echo "[operator] approve will ask for an exact approval phrase. Type it when shown."
  fi
  "$SCRIPT_DIR/$step"
done

echo
echo "[operator] PATH phase complete."
"""


PREFLIGHT_SIGNINGOS_SCRIPT = """#!/usr/bin/env bash
set -euo pipefail

ROOT=${PATH_WORKSPACE_ROOT:-}
if [[ -z "$ROOT" ]]; then
  echo "Missing PATH_WORKSPACE_ROOT for Signing OS preflight." >&2
  exit 2
fi
if [[ ! -d "$ROOT" ]]; then
  echo "PATH_WORKSPACE_ROOT is not a directory: $ROOT" >&2
  exit 2
fi

cd "$ROOT"
export ROOT

NETWORK=${NETWORK:-}
LANE=${LANE:-deploy}
CHECK_GH_AUTH=${CHECK_GH_AUTH:-0}
GH_REPO=${GH_REPO:-inshell-art/path}
OPSEC_ROOT=${OPSEC_ROOT:-~/.opsec}
PACK_MANIFEST_JSON=${PATH_PACK_MANIFEST_JSON:-}
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

for cmd in node npm git jq python3 make cast; do
  require_cmd "$cmd"
done
if [[ "$CHECK_GH_AUTH" == "1" ]]; then
  require_cmd gh
fi
if [[ -z "$PACK_MANIFEST_JSON" ]]; then
  echo "Missing PATH_PACK_MANIFEST_JSON for Signing OS preflight." >&2
  exit 2
fi
if [[ ! -f "$PACK_MANIFEST_JSON" ]]; then
  echo "Pack manifest not found: $PACK_MANIFEST_JSON" >&2
  exit 2
fi

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

if [[ -z "$PACK_MANIFEST_JSON" ]]; then
  check_git_clean "before preflight"
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

MANIFEST_META=$(python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

manifest_path = Path(os.environ["PATH_PACK_MANIFEST_JSON"])
network = os.environ["NETWORK"]
lane = os.environ["LANE"]
requested = os.environ.get("SIGNER_ALIAS", "").strip()
manifest = json.loads(manifest_path.read_text())

manifest_network = str(manifest.get("network", "")).strip()
manifest_lane = str(manifest.get("lane", "")).strip()
if manifest_network != network or manifest_lane != lane:
    print(
        f"Manifest network/lane mismatch: manifest has {manifest_network}/{manifest_lane}, "
        f"preflight received {network}/{lane}",
        file=sys.stderr,
    )
    sys.exit(1)

alias = str(manifest.get("signer_alias", "")).strip()
address = str(manifest.get("expected_address", "")).strip()
if not alias or not address:
    print("Pack manifest is missing signer_alias or expected_address", file=sys.stderr)
    sys.exit(1)
if requested and requested != alias:
    print(
        f"SIGNER_ALIAS {requested!r} does not match pack manifest signer_alias {alias!r}",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"{alias}\t{address}")
PY
)

IFS=$'\\t' read -r SELECTED_SIGNER_ALIAS EXPECTED_SIGNER_ADDRESS <<<"$MANIFEST_META"

if [[ -z "$KEYSTORE_JSON" && "$LANE" == "deploy" ]]; then
  KEYSTORE_JSON_VAR="${NETWORK_UPPER}_DEPLOY_KEYSTORE_JSON"
  KEYSTORE_JSON="${!KEYSTORE_JSON_VAR:-}"
fi
if [[ -z "$KEYSTORE_PASSWORD" && -z "$KEYSTORE_PASSWORD_FILE" && "$LANE" == "deploy" ]]; then
  KEYSTORE_PASSWORD_VAR="${NETWORK_UPPER}_DEPLOY_KEYSTORE_PASSWORD"
  KEYSTORE_PASSWORD_FILE_VAR="${NETWORK_UPPER}_DEPLOY_KEYSTORE_PASSWORD_FILE"
  KEYSTORE_PASSWORD="${!KEYSTORE_PASSWORD_VAR:-}"
  KEYSTORE_PASSWORD_FILE="${!KEYSTORE_PASSWORD_FILE_VAR:-}"
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
ACTUAL_SIGNER_ADDRESS_NORM=$(printf '%s' "$ACTUAL_SIGNER_ADDRESS" | tr '[:upper:]' '[:lower:]')
EXPECTED_SIGNER_ADDRESS_NORM=$(printf '%s' "$EXPECTED_SIGNER_ADDRESS" | tr '[:upper:]' '[:lower:]')

if [[ "$ACTUAL_SIGNER_ADDRESS_NORM" != "$EXPECTED_SIGNER_ADDRESS_NORM" ]]; then
  echo "Signer binding mismatch for $NETWORK/$LANE." >&2
  echo "  alias:    $SELECTED_SIGNER_ALIAS" >&2
  echo "  expected: $EXPECTED_SIGNER_ADDRESS" >&2
  echo "  actual:   $ACTUAL_SIGNER_ADDRESS" >&2
  exit 1
fi

if [[ "$CHECK_GH_AUTH" == "1" ]]; then
  gh auth status >/dev/null
  gh repo view "$GH_REPO" >/dev/null
  echo "[signingos] gh auth ok for $GH_REPO"
else
  echo "[signingos] gh auth check skipped (set CHECK_GH_AUTH=1 to enable)"
fi

echo "[signingos] signer binding ok: $SELECTED_SIGNER_ALIAS -> $ACTUAL_SIGNER_ADDRESS"
echo "[signingos] marker ok: $MARKER_PATH"

if [[ -z "$PACK_MANIFEST_JSON" ]]; then
  check_git_clean "after preflight"
fi

echo "[signingos] preflight passed for $NETWORK/$LANE"
"""


RUN_STEP_SCRIPT = """#!/usr/bin/env bash
set -euo pipefail

STEP_NAME=${1:-}
if [[ -z "$STEP_NAME" ]]; then
  echo "Usage: _run_step.sh <preflight-signingos|verify|approve|apply|postconditions>" >&2
  exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACK_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
WORKSPACE_ROOT="$PACK_ROOT/WORKSPACE"
RESULTS_ROOT="$PACK_ROOT/results"
MANIFEST_JSON="$PACK_ROOT/MANIFEST.json"

IFS=$'\\t' read -r NETWORK RUN_ID LANE <<EOF_META
$(MANIFEST_JSON="$MANIFEST_JSON" python3 - <<'PY'
import json
import os
from pathlib import Path

manifest = json.loads(Path(os.environ["MANIFEST_JSON"]).read_text())
print("\\t".join([
    str(manifest.get("network", "")),
    str(manifest.get("run_id", "")),
    str(manifest.get("lane", "")),
]))
PY
)
EOF_META

if [[ -z "$NETWORK" || -z "$RUN_ID" || -z "$LANE" ]]; then
  echo "Invalid PATH-RUN-BUNDLE manifest metadata." >&2
  exit 2
fi

BUNDLE_DIR="$WORKSPACE_ROOT/bundles/$NETWORK/$RUN_ID"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Missing internal bundle dir: $BUNDLE_DIR" >&2
  exit 2
fi

DEFAULT_ENV_FILE="$HOME/.opsec/path/env/$NETWORK.env"
ENV_FILE="${PATH_SIGNING_ENV_FILE:-$DEFAULT_ENV_FILE}"
export PATH="$HOME/.foundry/bin:$HOME/.local/bin:$HOME/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
BUNDLED_NODE_ROOT="$PACK_ROOT/runtime/nodejs"
if [[ -x "$BUNDLED_NODE_ROOT/bin/node" ]]; then
  export PATH="$BUNDLED_NODE_ROOT/bin:$PATH"
  echo "[operator] bundled node runtime: $BUNDLED_NODE_ROOT"
fi
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  echo "[operator] env loaded: $ENV_FILE"
elif [[ -n "${SIGNING_OS_MARKER_FILE:-}" ]]; then
  echo "[operator] env file not found; using already-loaded shell env"
else
  echo "Missing Signing OS env file: $ENV_FILE" >&2
  echo "Install the Signing OS secret bootstrap or set PATH_SIGNING_ENV_FILE." >&2
  exit 2
fi
export SIGNING_OS=1

STAMP=$(date -u +"%Y%m%dT%H%M%SZ")
RUN_DIR="$RESULTS_ROOT/${STAMP}-${STEP_NAME}"
LOG_FILE="$RUN_DIR/${STEP_NAME}.log"
mkdir -p "$RUN_DIR"

SCRIPT_PATH=""
declare -a CMD_ENV
CMD_ENV=("PATH_WORKSPACE_ROOT=$WORKSPACE_ROOT" "PATH_PACK_MANIFEST_JSON=$MANIFEST_JSON" "ENV_FILE=$ENV_FILE")

case "$STEP_NAME" in
  preflight-signingos)
    SCRIPT_PATH="$PACK_ROOT/bin/_preflight_signingos.sh"
    CMD_ENV+=("NETWORK=$NETWORK" "LANE=$LANE")
    ;;
  verify)
    SCRIPT_PATH="$WORKSPACE_ROOT/ops/tools/verify_bundle.sh"
    CMD_ENV+=("NETWORK=$NETWORK" "RUN_ID=$RUN_ID" "BUNDLE_PATH=$BUNDLE_DIR")
    ;;
  approve)
    SCRIPT_PATH="$WORKSPACE_ROOT/ops/tools/approve_bundle.sh"
    CMD_ENV+=("NETWORK=$NETWORK" "RUN_ID=$RUN_ID" "BUNDLE_PATH=$BUNDLE_DIR")
    ;;
  apply)
    SCRIPT_PATH="$WORKSPACE_ROOT/ops/tools/apply_bundle.sh"
    CMD_ENV+=("NETWORK=$NETWORK" "RUN_ID=$RUN_ID" "BUNDLE_PATH=$BUNDLE_DIR")
    ;;
  postconditions)
    SCRIPT_PATH="$WORKSPACE_ROOT/ops/tools/postconditions.sh"
    CMD_ENV+=("NETWORK=$NETWORK" "RUN_ID=$RUN_ID" "BUNDLE_PATH=$BUNDLE_DIR")
    ;;
  *)
    echo "Unsupported step: $STEP_NAME" >&2
    exit 2
    ;;
esac

echo "[operator] step: $STEP_NAME"
echo "[operator] run dir: $RUN_DIR"
echo "[operator] log: $LOG_FILE"

set +e
(
  cd "$WORKSPACE_ROOT"
  set -o pipefail
  env "${CMD_ENV[@]}" "$SCRIPT_PATH" 2>&1 | tee "$LOG_FILE"
)
STEP_EXIT=$?
set -e

copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    if [[ -d "$src" ]]; then
      rm -rf "$dst"
      cp -R "$src" "$dst"
    else
      cp "$src" "$dst"
    fi
  fi
}

ARTIFACT_ROOT="$RUN_DIR/artifacts"
case "$STEP_NAME" in
  verify)
    copy_if_exists "$BUNDLE_DIR/checks.path.verify.json" "$ARTIFACT_ROOT/checks.path.verify.json"
    copy_if_exists "$BUNDLE_DIR/checks.path.verify.onchain.log" "$ARTIFACT_ROOT/checks.path.verify.onchain.log"
    copy_if_exists "$BUNDLE_DIR/checks.path.verify.signed-consume.log" "$ARTIFACT_ROOT/checks.path.verify.signed-consume.log"
    ;;
  approve)
    copy_if_exists "$BUNDLE_DIR/approval.json" "$ARTIFACT_ROOT/approval.json"
    ;;
  apply)
    copy_if_exists "$BUNDLE_DIR/txs.json" "$ARTIFACT_ROOT/txs.json"
    copy_if_exists "$BUNDLE_DIR/apply.plan.json" "$ARTIFACT_ROOT/apply.plan.json"
    copy_if_exists "$BUNDLE_DIR/deploy.deploy.log" "$ARTIFACT_ROOT/deploy.deploy.log"
    copy_if_exists "$BUNDLE_DIR/deployments" "$ARTIFACT_ROOT/deployments"
    copy_if_exists "$BUNDLE_DIR/snapshots" "$ARTIFACT_ROOT/snapshots"
    copy_if_exists "$BUNDLE_DIR/inputs.params.json" "$ARTIFACT_ROOT/inputs.params.json"
    ;;
  postconditions)
    copy_if_exists "$BUNDLE_DIR/postconditions.json" "$ARTIFACT_ROOT/postconditions.json"
    copy_if_exists "$BUNDLE_DIR/postconditions.verify.log" "$ARTIFACT_ROOT/postconditions.verify.log"
    copy_if_exists "$BUNDLE_DIR/postconditions.pathcheck.log" "$ARTIFACT_ROOT/postconditions.pathcheck.log"
    copy_if_exists "$BUNDLE_DIR/checks.path.post.json" "$ARTIFACT_ROOT/checks.path.post.json"
    copy_if_exists "$BUNDLE_DIR/checks.path.post.onchain.log" "$ARTIFACT_ROOT/checks.path.post.onchain.log"
    copy_if_exists "$BUNDLE_DIR/checks.path.post.signed-consume.log" "$ARTIFACT_ROOT/checks.path.post.signed-consume.log"
    ;;
esac

DATE_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ "$STEP_EXIT" -eq 0 ]]; then
  STATUS=PASS
else
  STATUS=FAIL
fi

cat >"$RUN_DIR/SUMMARY.txt" <<EOF_SUMMARY
DATE_UTC=$DATE_UTC
OUTPUT_DIR=$RUN_DIR
STEP=$STEP_NAME
NETWORK=$NETWORK
LANE=$LANE
RUN_ID=$RUN_ID
INTERNAL_BUNDLE_DIR=$BUNDLE_DIR
LOG_FILE=$LOG_FILE
EXIT_CODE=$STEP_EXIT
OVERALL_STATUS=$STATUS
EOF_SUMMARY

echo
echo "========== PATH STEP RESULT =========="
cat "$RUN_DIR/SUMMARY.txt"
echo "SUMMARY_FILE=$RUN_DIR/SUMMARY.txt"
echo "LOG_FILE=$LOG_FILE"
if [[ -d "$ARTIFACT_ROOT" ]]; then
  echo "ARTIFACTS_DIR=$ARTIFACT_ROOT"
fi
if [[ "$STEP_EXIT" -eq 0 ]]; then
  echo "NEXT=continue to the next PATH step"
else
  echo "NEXT=stop and push this run dir back from the pack root"
fi
echo "======================================"

echo "$RUN_DIR"
exit "$STEP_EXIT"
"""


def runbook_text(manifest: dict) -> str:
    rpc_display = manifest.get("rpc_url") or manifest.get("rpc_host", "")
    env_file = f"~/.opsec/path/env/{manifest['network']}.env"
    return f"""# PATH Signing Runbook

This bundle is meant to run after the Signing OS host baseline is already green.

Read `ENVIRONMENT.txt` first. That file defines the local secret/bootstrap
contract for this bundle.

Before using this bundle:
- finish the host checks from `Signing-OS-Transfer-Pack/`
- confirm the serious-run baseline is green
- confirm the intended signer alias is `{manifest['signer_alias']}`
- confirm the expected signer address is `{manifest['expected_address']}`
- confirm the intended RPC is `{rpc_display}`
- confirm the local Signing OS env file exists at `{env_file}`

Simplest path from `PATH-RUN-BUNDLE/`:

```bash
./bin/run-all
```

To resume from a later step:

```bash
./bin/run-all --from approve
```

Individual entrypoints also work and auto-load `{env_file}`:
- `./bin/preflight-signingos`
- `./bin/verify`
- `./bin/approve`
- `./bin/apply`
- `./bin/postconditions`

Required local env for serious deploy lanes:
- `SIGNING_OS_MARKER_FILE`
- `{manifest['network'].upper()}_DEPLOY_KEYSTORE_JSON`
- either `{manifest['network'].upper()}_DEPLOY_KEYSTORE_PASSWORD` or `{manifest['network'].upper()}_DEPLOY_KEYSTORE_PASSWORD_FILE`

Each entrypoint writes one result directory under `./results/`.
Every step now prints its own PASS/FAIL summary and the exact `SUMMARY.txt` path.
This bundle carries its own `node`/`npm` runtime under `./runtime/nodejs/`, so Signing OS does not need host-installed `node` or `npm`.

After every step:
1. if `OVERALL_STATUS=FAIL`, stop immediately
2. keep that whole result directory intact
3. push that whole result directory back to Dev OS from the combined pack root

Push-back helper from the combined `pack/` root:

```bash
./tools/push-latest-result.sh
```

or explicitly:

```bash
../tools/push-result.sh --run-dir "$(ls -dt ./results/* | head -n1)"
```

After final success:
- push the latest result directory back once more
- bring back the whole `PATH-RUN-BUNDLE/results/<timestamp-step>/` directory, not just logs

Do not:
- `git pull`
- edit files inside `WORKSPACE/`
- change signer alias mid-run
- continue after any fail summary
"""


def environment_contract_text(manifest: dict) -> str:
    network = manifest["network"]
    env_file = f"~/.opsec/path/env/{network}.env"
    upper = network.upper()
    rpc_display = manifest.get("rpc_url") or manifest.get("rpc_host", "")
    return f"""# PATH Signing Environment Contract

This file explains the local secret/bootstrap state required by this
`PATH-RUN-BUNDLE/`.

## What The Pack Owns

The pack owns:
- protocol bundle contents
- operator-facing PATH commands
- expected signer alias/address
- expected rpc host/url
- PATH policy and verify/apply/postconditions semantics

The pack does **not** carry secret-bearing local material.

## What The Signing OS Host Must Own

Local Signing OS secret/bootstrap state must exist at:
- `{env_file}`

That env file must point at local readable files on the Signing OS host for:
- `SIGNING_OS_MARKER_FILE`
- `{upper}_DEPLOY_KEYSTORE_JSON`
- either `{upper}_DEPLOY_KEYSTORE_PASSWORD_FILE` or `{upper}_DEPLOY_KEYSTORE_PASSWORD`

Required non-secret value:
- `{upper}_RPC_URL={rpc_display}`

Forbidden for serious deploy lanes:
- `{upper}_PRIVATE_KEY`

Expected signer binding for this pack:
- alias: `{manifest['signer_alias']}`
- address: `{manifest['expected_address']}`

## Operational Meaning

The env file is not a generic shell convenience file. It is the local secret
bootstrap contract between:
- `path/` as protocol owner
- `signing-os-ops/` as operator-kit owner
- the actual Signing OS host as secret-bearing execution environment

If this file is missing or points at the wrong signer material, PATH preflight
or verify/apply will fail even when the generic Signing OS baseline is green.

## References

- `env/{network}.env.example`
- `RUNBOOK.txt`
"""


def environment_example_text(manifest: dict) -> str:
    network = manifest["network"]
    upper = network.upper()
    rpc_display = manifest.get("rpc_url") or manifest.get("rpc_host", "")
    return f"""# Example only. Replace the paths with real local Signing OS paths.
export {upper}_RPC_URL="{rpc_display}"
export SIGNING_OS_MARKER_FILE="$HOME/.opsec/path/signing_os.marker"
export {upper}_DEPLOY_KEYSTORE_JSON="$HOME/.opsec/{network}/signers/deploy_sw_a/keystore.json"
export {upper}_DEPLOY_KEYSTORE_PASSWORD_FILE="$HOME/.opsec/{network}/password-files/deploy_sw_a.password.txt"

# Forbidden for serious deploy lanes:
# export {upper}_PRIVATE_KEY=...
"""


def render_context(run_payload: dict, intent_payload: dict, chain_id: int, rpc_url: str, rpc_host: str) -> dict:
    inputs_payload = {}
    bundle_dir = Path(run_payload["_bundle_dir"])
    inputs_path = bundle_dir / "inputs.json"
    if inputs_path.exists():
        inputs_payload = json.loads(inputs_path.read_text())

    params = inputs_payload.get("params", {}) if isinstance(inputs_payload, dict) else {}
    if not isinstance(params, dict):
        params = {}

    return {
        "action": run_payload.get("lane", ""),
        "description": f"PATH {run_payload.get('network', '')}/{run_payload.get('lane', '')} run {run_payload.get('run_id', '')}",
        "chain_id": chain_id,
        "rpc_host": rpc_host,
        "rpc_url": rpc_url,
        "contracts": {},
        "params": params,
        "expected_outputs": {
            "verify": ["results/<timestamp>-verify/SUMMARY.txt"],
            "approve": ["results/<timestamp>-approve/SUMMARY.txt", "approval.json"],
            "apply": ["results/<timestamp>-apply/SUMMARY.txt", "txs.json", "snapshots/post_state.json"],
            "postconditions": ["results/<timestamp>-postconditions/SUMMARY.txt", "postconditions.json"],
        },
        "source_intent": intent_payload,
    }


def render_expected(manifest: dict, run_payload: dict, intent_payload: dict) -> dict:
    forbidden = [
        "live git pull on Signing OS",
        "editing WORKSPACE during the run",
        "changing signer alias after verify",
        "continuing after a failed SUMMARY.txt",
        "using raw private key env for serious deploy lanes",
    ]
    if intent_payload.get("inputs_sha256"):
        forbidden.append("using constructor params that do not match inputs.json")

    return {
        "preconditions": [
            "Signing-OS-Transfer-Pack baseline passed",
            f"signer alias is {manifest['signer_alias']}",
            f"signer address matches {manifest['expected_address']}",
            f"bundle source commit is {manifest['source_commit']}",
        ],
        "postconditions": [
            "postconditions.json status=pass",
            "the latest result directory has OVERALL_STATUS=PASS",
            "result directory was pushed back intact to Dev OS",
        ],
        "must_match": {
            "bundle_id": manifest["bundle_id"],
            "source_commit": manifest["source_commit"],
            "signer_alias": manifest["signer_alias"],
            "expected_address": manifest["expected_address"],
            "rpc_host": manifest["rpc_host"],
            "inputs_sha256": intent_payload.get("inputs_sha256", ""),
        },
        "forbidden": forbidden,
    }


def export_bundle(bundle_dir: Path, output_dir: Path, signer_alias: str, rpc_url: str, rpc_host: str) -> None:
    run_payload, intent_payload = validate_source_bundle(bundle_dir)
    source_bundle_manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())
    run_payload["_bundle_dir"] = str(bundle_dir)
    network = str(run_payload.get("network", "")).strip()
    lane = str(run_payload.get("lane", "")).strip()
    run_id = str(run_payload.get("run_id", "")).strip()
    source_commit = str(run_payload.get("git_commit", "")).strip()
    if not network or not lane or not run_id or not source_commit:
        raise SystemExit("run.json is missing network, lane, run_id, or git_commit")

    policy_path = resolve_policy(network)
    policy = json.loads(policy_path.read_text())
    resolved_alias, expected_address = resolve_signer(policy, lane, signer_alias)
    node_runtime_root = resolve_node_runtime_root()
    node_runtime_version = run([str(node_runtime_root / "bin" / "node"), "--version"]).stdout.strip()

    chain_id = CHAIN_ID_BY_NETWORK.get(network)
    if chain_id is None:
        raise SystemExit(f"Unsupported network in run.json: {network}")

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    with tempfile.TemporaryDirectory(prefix="path-signing-workspace-") as tmpdir:
        tmp_workspace = Path(tmpdir) / "workspace"
        build_sparse_workspace(ROOT, source_commit, tmp_workspace)
        populate_evm_runtime(ROOT, tmp_workspace)
        overlay_portable_tool_overrides(ROOT, tmp_workspace)

        internal_bundle_dir = tmp_workspace / "bundles" / network / run_id
        internal_bundle_dir.mkdir(parents=True, exist_ok=True)
        for name in IMMUTABLE_BUNDLE_FILES + OPTIONAL_BUNDLE_FILES:
            if name == "bundle_manifest.json":
                continue
            src = bundle_dir / name
            if src.exists():
                shutil.copy2(src, internal_bundle_dir / name)

        exported_bundle_manifest = render_export_bundle_manifest(source_bundle_manifest, internal_bundle_dir)
        write_text(
            internal_bundle_dir / "bundle_manifest.json",
            json.dumps(exported_bundle_manifest, indent=2, sort_keys=True) + "\n",
        )

        copytree(tmp_workspace, output_dir / "WORKSPACE")

    copytree(node_runtime_root, output_dir / "runtime" / "nodejs")

    manifest = {
        "bundle_id": f"path-{network}-{lane}-{run_id}",
        "built_at_utc": utc_now(),
        "source_repo": str(ROOT),
        "source_commit": source_commit,
        "source_commit_dirty": False,
        "protocol": "path",
        "network": network,
        "lane": lane,
        "run_id": run_id,
        "chain_id": chain_id,
        "rpc_host": rpc_host,
        "rpc_url": rpc_url,
        "signer_alias": resolved_alias,
        "expected_address": expected_address,
        "bundled_runtime": {
            "node_root": "runtime/nodejs",
            "node_version": node_runtime_version,
        },
        "entrypoints": {
            "run_all": "bin/run-all",
            "preflight_signingos": "bin/preflight-signingos",
            "verify": "bin/verify",
            "approve": "bin/approve",
            "apply": "bin/apply",
            "postconditions": "bin/postconditions",
        },
    }

    context = render_context(run_payload, intent_payload, chain_id, rpc_url, rpc_host)
    expected = render_expected(manifest, run_payload, intent_payload)
    signer = {
        "signer_alias": resolved_alias,
        "expected_address": expected_address,
        "hd_path": "see local signer enrollment records",
        "ledger_label": "see MAP-MAIN / signer enrollment records",
        "role_description": f"{network}/{lane} operator signer",
    }

    write_text(output_dir / "RUNBOOK.txt", runbook_text(manifest))
    write_text(output_dir / "ENVIRONMENT.txt", environment_contract_text(manifest))
    write_text(output_dir / "env" / f"{network}.env.example", environment_example_text(manifest))
    write_text(output_dir / "MANIFEST.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    write_text(output_dir / "CONTEXT.json", json.dumps(context, indent=2, sort_keys=True) + "\n")
    write_text(output_dir / "SIGNER.json", json.dumps(signer, indent=2, sort_keys=True) + "\n")
    write_text(output_dir / "EXPECTED.json", json.dumps(expected, indent=2, sort_keys=True) + "\n")

    bin_dir = output_dir / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    write_text(bin_dir / "_preflight_signingos.sh", PREFLIGHT_SIGNINGOS_SCRIPT)
    (bin_dir / "_preflight_signingos.sh").chmod(0o755)
    write_text(bin_dir / "_run_step.sh", RUN_STEP_SCRIPT)
    (bin_dir / "_run_step.sh").chmod(0o755)
    write_text(bin_dir / "run-all", run_all_script())
    (bin_dir / "run-all").chmod(0o755)
    for name in ["preflight-signingos", "verify", "approve", "apply", "postconditions"]:
        write_text(bin_dir / name, wrapper_script(name))
        (bin_dir / name).chmod(0o755)

    entries = manifest_entries(output_dir)
    write_checksums(output_dir, entries)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export a portable PATH-RUN-BUNDLE for Signing OS")
    parser.add_argument("--bundle-dir", required=True, help="Existing immutable PATH bundle directory")
    parser.add_argument(
        "--output-dir",
        help="Output PATH-RUN-BUNDLE directory",
    )
    parser.add_argument(
        "--rpc-url",
        default="",
        help="Exact RPC URL for the intended Signing OS run. If omitted, uses $<NETWORK>_RPC_URL or a single-host allowlist.",
    )
    parser.add_argument(
        "--signer-alias",
        default="",
        help="Explicit signer alias when the lane policy allows more than one signer.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    bundle_dir = Path(args.bundle_dir).expanduser().resolve()

    run_payload, _ = validate_source_bundle(bundle_dir)
    network = str(run_payload.get("network", "")).strip()
    if not network:
        raise SystemExit("run.json missing network")
    output_dir = Path(args.output_dir or (ROOT / "dist" / "PATH-RUN-BUNDLE" / str(run_payload.get("run_id", "run")))).expanduser().resolve()

    policy_path = resolve_policy(network)
    policy = json.loads(policy_path.read_text())
    rpc_url, rpc_host = resolve_rpc_url(network, args.rpc_url, policy)
    export_bundle(bundle_dir, output_dir, args.signer_alias, rpc_url, rpc_host)
    print(f"PATH_RUN_BUNDLE={output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
