#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
export ROOT
export NETWORK=${NETWORK:-}

python3 - <<'PY'
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

root = Path(os.environ["ROOT"])
network_env = os.environ.get("NETWORK", "").strip()
targets = [network_env] if network_env else ["sepolia", "mainnet"]

valid = {"sepolia", "mainnet"}
for target in targets:
    if target not in valid:
        print(f"Invalid NETWORK: {target}", file=sys.stderr)
        sys.exit(2)

had_problem = False

for network in targets:
    path = root / "ops" / "policy" / f"lane.{network}.json"
    if not path.exists():
        print(f"[{network}] missing policy file: {path}", file=sys.stderr)
        had_problem = True
        continue

    policy = json.loads(path.read_text())
    lanes = policy.get("lanes") if isinstance(policy.get("lanes"), dict) else {}
    signer_map = policy.get("signer_alias_map") if isinstance(policy.get("signer_alias_map"), dict) else {}
    rpc_hosts = policy.get("rpc_host_allowlist") if isinstance(policy.get("rpc_host_allowlist"), list) else []

    aliases = sorted({
        str(alias).strip()
        for lane_cfg in lanes.values()
        if isinstance(lane_cfg, dict)
        for alias in (lane_cfg.get("allowed_signers") or [])
        if str(alias).strip()
    })
    missing_aliases = [alias for alias in aliases if not str(signer_map.get(alias, "")).strip()]

    fee_placeholders = []
    for lane_name, lane_cfg in lanes.items():
        if not isinstance(lane_cfg, dict):
            continue
        fee_policy = lane_cfg.get("fee_policy")
        if not isinstance(fee_policy, dict):
            continue
        for key, value in fee_policy.items():
            if isinstance(value, str) and "<SET_ME>" in value:
                fee_placeholders.append(f"{lane_name}.{key}")

    print(f"[{network}]")
    print(f"  policy: {path.relative_to(root)}")
    print(f"  signer aliases referenced: {', '.join(aliases) if aliases else '(none)'}")
    print(f"  rpc host allowlist: {', '.join(rpc_hosts) if rpc_hosts else '(none)'}")

    if missing_aliases:
        had_problem = True
        print(f"  missing signer_alias_map entries: {', '.join(missing_aliases)}")
    else:
        print("  missing signer_alias_map entries: (none)")

    if fee_placeholders:
        had_problem = True
        print(f"  unresolved fee_policy placeholders: {', '.join(fee_placeholders)}")
    else:
        print("  unresolved fee_policy placeholders: (none)")

    rpc_var = f"{network.upper()}_RPC_URL"
    rpc_url = os.environ.get(rpc_var, "").strip()
    if rpc_url:
        host = urlparse(rpc_url).hostname or ""
        if host and rpc_hosts and host not in rpc_hosts:
            had_problem = True
            print(f"  configured {rpc_var} host not allowlisted: {host}")
        elif host:
            print(f"  configured {rpc_var} host allowlisted: {host}")
    print()

if had_problem:
    sys.exit(1)
PY
