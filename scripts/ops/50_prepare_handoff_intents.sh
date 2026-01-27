#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_env OPS_NETWORK MULTISIG_ADDRESS
require_cmd python3

intents_dir="$(artifact_dir intents)"
output_path="$intents_dir/handoff.json"

export _OPS_HANDOFF_OUTPUT_PATH="$output_path"

python3 - <<'PY'
import json
import os
from datetime import datetime, timezone

network = os.environ.get("OPS_NETWORK")
multisig = os.environ.get("MULTISIG_ADDRESS")
actions_file = os.environ.get("OPS_HANDOFF_ACTIONS_FILE")

if not network or not multisig:
    raise SystemExit("Missing OPS_NETWORK or MULTISIG_ADDRESS")

if actions_file:
    with open(actions_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, dict) and "actions" in data:
        actions = data["actions"]
    else:
        actions = data
else:
    required = [
        "PATH_NFT_ADDRESS",
        "PATH_MINTER_ADDRESS",
        "ADMIN_ROLE",
        "DEPLOYER_ADDRESS",
    ]
    missing = [key for key in required if not os.environ.get(key)]
    if missing:
        raise SystemExit("Missing env vars for default handoff: " + ", ".join(missing))

    path_nft = os.environ["PATH_NFT_ADDRESS"]
    path_minter = os.environ["PATH_MINTER_ADDRESS"]
    admin_role = os.environ["ADMIN_ROLE"]
    deployer = os.environ["DEPLOYER_ADDRESS"]

    actions = [
        {
            "name": "Transfer PathNFT ownership",
            "target": path_nft,
            "entrypoint": "transfer_ownership",
            "calldata": [multisig],
            "notes": "After this, deployer must no longer be owner.",
        },
        {
            "name": "Grant ADMIN_ROLE on PathMinter to multisig",
            "target": path_minter,
            "entrypoint": "grant_role",
            "calldata": [admin_role, multisig],
            "notes": "Then revoke deployer role.",
        },
        {
            "name": "Revoke ADMIN_ROLE on PathMinter from deployer",
            "target": path_minter,
            "entrypoint": "revoke_role",
            "calldata": [admin_role, deployer],
            "notes": "Deployer should not retain admin after handoff.",
        },
    ]

payload = {
    "network": network,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "multisig_address": multisig,
    "actions": actions,
}

output_path = os.environ.get("OPS_HANDOFF_OUTPUT")
if not output_path:
    # fallback to env provided by shell wrapper
    output_path = os.environ.get("_OPS_HANDOFF_OUTPUT_PATH")

if not output_path:
    raise SystemExit("Missing output path")

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
PY

log "Handoff intent bundle written: $output_path"
