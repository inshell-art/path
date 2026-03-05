#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
AUDIT_ID=${AUDIT_ID:-}
AUDIT_PATH=${AUDIT_PATH:-}

ROOT=$(git rev-parse --show-toplevel)

if [[ -n "$AUDIT_PATH" ]]; then
  AUDIT_DIR="$AUDIT_PATH"
else
  if [[ -z "$NETWORK" || -z "$AUDIT_ID" ]]; then
    echo "Usage: NETWORK=<devnet|sepolia|mainnet> AUDIT_ID=<id> $0" >&2
    echo "   or: AUDIT_PATH=<path> $0" >&2
    exit 2
  fi
  AUDIT_DIR="$ROOT/audits/$NETWORK/$AUDIT_ID"
fi

PLAN_PATH="$AUDIT_DIR/audit_plan.json"
INDEX_PATH="$AUDIT_DIR/audit_evidence_index.json"
if [[ ! -f "$PLAN_PATH" || ! -f "$INDEX_PATH" ]]; then
  echo "Missing audit_plan.json or audit_evidence_index.json in $AUDIT_DIR" >&2
  exit 2
fi

export ROOT AUDIT_DIR PLAN_PATH INDEX_PATH

python3 - <<'PY'
import hashlib
import json
import os
import re
from pathlib import Path
from datetime import datetime, timezone

root = Path(os.environ["ROOT"])
audit_dir = Path(os.environ["AUDIT_DIR"])
plan = json.loads(Path(os.environ["PLAN_PATH"]).read_text())
index = json.loads(Path(os.environ["INDEX_PATH"]).read_text())
network = plan.get("network", "")
run_ids = plan.get("run_ids", [])
controls = plan.get("controls", [])
repo_commit = os.popen("git rev-parse HEAD").read().strip()

policy_candidates = [
    root / "ops/policy" / f"lane.{network}.json",
    root / "ops/policy" / f"{network}.policy.json",
    root / "ops/policy" / f"lane.{network}.example.json",
    root / "ops/policy" / f"{network}.policy.example.json",
]
policy_path = next((p for p in policy_candidates if p.exists()), None)
policy = json.loads(policy_path.read_text()) if policy_path else {}

results = []

def make_result(control_id, status, tier, details, evidence_refs=None, repro_commands=None):
    return {
        "control_id": control_id,
        "status": status,
        "tier": tier,
        "details": details,
        "evidence_refs": evidence_refs or [],
        "repro_commands": repro_commands or []
    }

def load_json(path: Path):
    return json.loads(path.read_text()) if path.exists() else None

def verify_manifest(bundle_dir: Path):
    manifest_path = bundle_dir / "bundle_manifest.json"
    if not manifest_path.exists():
        return False, "missing bundle_manifest.json"
    manifest = load_json(manifest_path)
    items = manifest.get("immutable_files", [])
    if not items:
        return False, "manifest missing immutable_files"
    recomputed = []
    for item in items:
        rel = item.get("path")
        expected = item.get("sha256")
        if not rel or not expected:
            return False, "manifest entry missing path or sha256"
        fpath = bundle_dir / rel
        if not fpath.exists():
            return False, f"missing immutable file: {rel}"
        digest = hashlib.sha256(fpath.read_bytes()).hexdigest()
        if digest != expected:
            return False, f"hash mismatch for {rel}"
        recomputed.append({"path": rel, "sha256": digest})
    calc = hashlib.sha256("\n".join([f"{x['path']}={x['sha256']}" for x in recomputed]).encode()).hexdigest()
    if calc != manifest.get("bundle_hash"):
        return False, "bundle_hash mismatch"
    return True, "manifest hashes verified"

run_context = []
for run_id in run_ids:
    bdir = root / "bundles" / network / run_id
    ctx = {
        "run_id": run_id,
        "bundle_dir": bdir,
        "exists": bdir.exists(),
        "run": load_json(bdir / "run.json") if bdir.exists() else None,
        "intent": load_json(bdir / "intent.json") if bdir.exists() else None,
        "checks": load_json(bdir / "checks.json") if bdir.exists() else None,
        "manifest": load_json(bdir / "bundle_manifest.json") if bdir.exists() else None,
        "approval": load_json(bdir / "approval.json") if bdir.exists() else None,
        "postconditions": load_json(bdir / "postconditions.json") if bdir.exists() else None,
        "txs": load_json(bdir / "txs.json") if bdir.exists() else None,
    }
    run_context.append(ctx)

# AUD-001
if "AUD-001" in controls:
    if not run_context:
        results.append(make_result("AUD-001", "skip", "INFERRED", "No run_ids in scope."))
    else:
        fails = []
        for ctx in run_context:
            if not ctx["exists"]:
                fails.append(f"{ctx['run_id']}: bundle missing")
                continue
            ok, detail = verify_manifest(ctx["bundle_dir"])
            if not ok:
                fails.append(f"{ctx['run_id']}: {detail}")
        if fails:
            results.append(make_result("AUD-001", "fail", "VERIFIED", "; ".join(fails)))
        else:
            results.append(make_result("AUD-001", "pass", "VERIFIED", "All bundle manifests verified."))

# AUD-002
if "AUD-002" in controls:
    if not run_context:
        results.append(make_result("AUD-002", "skip", "INFERRED", "No run_ids in scope."))
    else:
        mismatches = []
        for ctx in run_context:
            run = ctx.get("run") or {}
            commit = run.get("git_commit")
            if not commit:
                mismatches.append(f"{ctx['run_id']}: run.json missing git_commit")
            elif commit != repo_commit:
                mismatches.append(f"{ctx['run_id']}: run commit {commit} != {repo_commit}")
        if mismatches:
            results.append(make_result("AUD-002", "fail", "VERIFIED", "; ".join(mismatches)))
        else:
            results.append(make_result("AUD-002", "pass", "VERIFIED", "run.json commit pins match checkout."))

# AUD-003
if "AUD-003" in controls:
    if not policy_path:
        results.append(make_result("AUD-003", "fail", "VERIFIED", f"Missing lane policy for network {network}."))
    elif not run_context:
        results.append(make_result("AUD-003", "skip", "INFERRED", "No run_ids in scope."))
    else:
        lanes = (policy or {}).get("lanes", {})
        invalid = []
        for ctx in run_context:
            lane = ((ctx.get("run") or {}).get("lane"))
            if not lane or lane not in lanes:
                invalid.append(f"{ctx['run_id']}: lane '{lane}' not in policy")
        if invalid:
            results.append(make_result("AUD-003", "fail", "VERIFIED", "; ".join(invalid), [str(policy_path.relative_to(root))]))
        else:
            results.append(make_result("AUD-003", "pass", "VERIFIED", "Policy file exists and lanes are valid.", [str(policy_path.relative_to(root))]))

# AUD-004
if "AUD-004" in controls:
    checked = 0
    fails = []
    for ctx in run_context:
        if not ctx.get("approval"):
            continue
        checked += 1
        approval_hash = (ctx["approval"] or {}).get("bundle_hash")
        manifest_hash = (ctx.get("manifest") or {}).get("bundle_hash")
        if not approval_hash or not manifest_hash or approval_hash != manifest_hash:
            fails.append(f"{ctx['run_id']}: approval hash mismatch")
    if checked == 0:
        results.append(make_result("AUD-004", "skip", "INFERRED", "No approval.json in scope."))
    elif fails:
        results.append(make_result("AUD-004", "fail", "VERIFIED", "; ".join(fails)))
    else:
        results.append(make_result("AUD-004", "pass", "VERIFIED", "Approval hash matches bundle hash."))

# AUD-005
if "AUD-005" in controls:
    applicable = []
    fails = []
    for ctx in run_context:
        run = ctx.get("run") or {}
        lane = run.get("lane")
        lane_policy = ((policy or {}).get("lanes", {}).get(lane, {}))
        writes = bool(lane_policy.get("writes", False))
        if not writes:
            continue
        applicable.append(ctx["run_id"])
        if not ctx.get("approval") or not ctx.get("txs"):
            fails.append(f"{ctx['run_id']}: missing approval.json or txs.json")
    if not applicable:
        results.append(make_result("AUD-005", "skip", "INFERRED", "No write-lane runs in scope."))
    elif fails:
        results.append(make_result("AUD-005", "fail", "INFERRED", "; ".join(fails)))
    else:
        results.append(make_result("AUD-005", "pass", "INFERRED", "Write-lane runs show approval and apply artifacts."))

# AUD-006
if "AUD-006" in controls:
    applicable = []
    fails = []
    for ctx in run_context:
        if not ctx.get("txs"):
            continue
        applicable.append(ctx["run_id"])
        post = ctx.get("postconditions")
        if not post or not post.get("status"):
            fails.append(f"{ctx['run_id']}: missing postconditions status")
    if not applicable:
        results.append(make_result("AUD-006", "skip", "INFERRED", "No applied runs in scope."))
    elif fails:
        results.append(make_result("AUD-006", "fail", "VERIFIED", "; ".join(fails)))
    else:
        results.append(make_result("AUD-006", "pass", "VERIFIED", "Postconditions present with status."))

# AUD-007
if "AUD-007" in controls:
    if network != "mainnet":
        results.append(make_result("AUD-007", "skip", "INFERRED", "Rehearsal proof gate check is mainnet-only."))
    else:
        needed = []
        for ctx in run_context:
            run = ctx.get("run") or {}
            lane = run.get("lane")
            lane_cfg = ((policy or {}).get("lanes", {}).get(lane, {}))
            gates = lane_cfg.get("gates", {}) if isinstance(lane_cfg.get("gates", {}), dict) else {}
            require = False
            proof_network = ""
            if "require_rehearsal_proof" in gates or "rehearsal_proof_network" in gates:
                require = bool(gates.get("require_rehearsal_proof", False))
                proof_network = str(gates.get("rehearsal_proof_network", "devnet")).strip().lower() if require else ""
            else:
                dev = bool(lane_cfg.get("requires_devnet_rehearsal_proof", False) or gates.get("require_devnet_rehearsal_proof", False))
                sep = bool(lane_cfg.get("requires_sepolia_rehearsal_proof", False) or gates.get("require_sepolia_rehearsal_proof", False))
                require = dev or sep
                proof_network = "devnet" if dev else ("sepolia" if sep else "")
            if require:
                needed.append(proof_network)
        if not needed:
            results.append(make_result("AUD-007", "skip", "INFERRED", "No mainnet lanes requiring rehearsal proof in scope."))
        else:
            missing = []
            for pnet in sorted(set(needed)):
                pdir = root / "bundles" / pnet
                ok = False
                if pdir.exists():
                    for run_dir in pdir.iterdir():
                        if not run_dir.is_dir():
                            continue
                        if (run_dir / "txs.json").exists() and (run_dir / "postconditions.json").exists():
                            ok = True
                            break
                if not ok:
                    missing.append(pnet)
            if missing:
                results.append(make_result("AUD-007", "fail", "INFERRED", f"No proof bundle with txs/postconditions found for: {', '.join(missing)}"))
            else:
                results.append(make_result("AUD-007", "pass", "INFERRED", "Proof bundle artifacts found for required rehearsal networks."))

# AUD-008
if "AUD-008" in controls:
    applicable = []
    fails = []
    for ctx in run_context:
        run = ctx.get("run") or {}
        lane = run.get("lane")
        lane_cfg = ((policy or {}).get("lanes", {}).get(lane, {}))
        allow = lane_cfg.get("allowed_signers", [])
        if not isinstance(allow, list) or not allow:
            continue
        applicable.append(ctx["run_id"])
        signer = ((ctx.get("intent") or {}).get("signer_alias"))
        if not signer:
            fails.append(f"{ctx['run_id']}: intent missing signer_alias")
        elif signer not in allow:
            fails.append(f"{ctx['run_id']}: signer_alias '{signer}' not in allowlist")
    if not applicable:
        results.append(make_result("AUD-008", "skip", "INFERRED", "No signer-allowlist checks applicable."))
    elif fails:
        results.append(make_result("AUD-008", "fail", "VERIFIED", "; ".join(fails)))
    else:
        results.append(make_result("AUD-008", "pass", "VERIFIED", "Signer alias and lane allowlist are consistent."))

# AUD-009
if "AUD-009" in controls:
    if not run_context:
        results.append(make_result("AUD-009", "skip", "INFERRED", "No run_ids in scope."))
    else:
        mismatches = []
        for ctx in run_context:
            run = ctx.get("run") or {}
            intent = ctx.get("intent") or {}
            checks = ctx.get("checks") or {}
            manifest = ctx.get("manifest") or {}
            values = [
                run.get("network"),
                intent.get("network"),
                checks.get("network"),
                manifest.get("network"),
                network,
            ]
            cleaned = [v for v in values if isinstance(v, str) and v]
            if any(v != network for v in cleaned):
                mismatches.append(f"{ctx['run_id']}: network mismatch in artifacts")
        if mismatches:
            results.append(make_result("AUD-009", "fail", "VERIFIED", "; ".join(mismatches)))
        else:
            results.append(make_result("AUD-009", "pass", "VERIFIED", "Network consistency holds across artifacts."))

# AUD-010
if "AUD-010" in controls:
    suspicious = []
    patterns = ["mnemonic", "seed", "private_key", "keystore", "account.json"]
    for item in index.get("files_indexed", []):
        p = (item.get("path") or "").lower()
        if any(tok in p for tok in patterns):
            suspicious.append(item.get("path"))
    if suspicious:
        results.append(make_result("AUD-010", "fail", "VERIFIED", "Suspicious secret-like filenames detected.", suspicious[:10]))
    else:
        results.append(make_result("AUD-010", "pass", "INFERRED", "No suspicious secret-like filenames in indexed artifacts."))

# AUD-011
if "AUD-011" in controls:
    if network not in {"sepolia", "mainnet"}:
        results.append(make_result("AUD-011", "skip", "INFERRED", "Secret-snippet strictness is enforced for sepolia/mainnet only."))
    else:
        scan_roots = [
            root / "README.md",
            root / "AGENTS.md",
            root / "ops/runbooks",
            root / "workbook/ops",
            root / "docs",
        ]
        md_files = []
        for entry in scan_roots:
            if not entry.exists():
                continue
            if entry.is_file() and entry.suffix == ".md":
                md_files.append(entry)
            elif entry.is_dir():
                md_files.extend(sorted(p for p in entry.rglob("*.md") if p.is_file()))

        patterns = [
            re.compile(r"export\s+SEPOLIA_PRIVATE_KEY\s*=", re.IGNORECASE),
            re.compile(r"export\s+MAINNET_PRIVATE_KEY\s*=", re.IGNORECASE),
            re.compile(r"SEPOLIA_PRIVATE_KEY\s*=\s*[\"']?0x[0-9a-fA-F]{64}", re.IGNORECASE),
            re.compile(r"MAINNET_PRIVATE_KEY\s*=\s*[\"']?0x[0-9a-fA-F]{64}", re.IGNORECASE),
            re.compile(r"--private-key(\s|=|$)", re.IGNORECASE),
        ]

        hits = []
        for path in md_files:
            try:
                lines = path.read_text().splitlines()
            except Exception:
                continue
            for idx, line in enumerate(lines, 1):
                if any(p.search(line) for p in patterns):
                    rel = str(path.relative_to(root))
                    hits.append(f"{rel}:{idx}")

        if hits:
            details = "Found forbidden raw secret snippets in docs/runbooks."
            results.append(
                make_result(
                    "AUD-011",
                    "fail",
                    "VERIFIED",
                    details,
                    hits[:20],
                    [f"NETWORK={network} ops/tools/lint_secret_snippets.sh"]
                )
            )
        else:
            results.append(
                make_result(
                    "AUD-011",
                    "pass",
                    "VERIFIED",
                    "No forbidden raw secret snippets in docs/runbooks for sepolia/mainnet scope.",
                    repro_commands=[f"NETWORK={network} ops/tools/lint_secret_snippets.sh"]
                )
            )

verification = {
    "audit_id": plan.get("audit_id"),
    "network": network,
    "verified_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "control_results": [r for r in results if r["control_id"] in controls],
    "execution_errors": []
}

(audit_dir / "audit_verification.json").write_text(json.dumps(verification, indent=2, sort_keys=True) + "\n")
print(f"Audit verification written: {audit_dir / 'audit_verification.json'}")
PY
