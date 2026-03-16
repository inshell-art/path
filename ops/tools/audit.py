#!/usr/bin/env python3
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

CONTROL_ORDER = [f"AUD-{i:03d}" for i in range(1, 12)]
DEFAULT_BASE_CONTROLS = {
    "devnet": ["AUD-001", "AUD-002", "AUD-003", "AUD-009", "AUD-010"],
    "sepolia": ["AUD-001", "AUD-002", "AUD-003", "AUD-009", "AUD-010"],
    "mainnet": ["AUD-001", "AUD-002", "AUD-003", "AUD-009", "AUD-010"],
}
DEFAULT_FEATURE_CONTROLS = {
    "write_lane": ["AUD-004", "AUD-005", "AUD-006"],
    "signer_allowlist": ["AUD-008"],
    "rehearsal_proof": ["AUD-007"],
    "required_inputs": ["AUD-011"],
}
SEVERITY_BY_CONTROL = {
    "AUD-001": "high",
    "AUD-002": "high",
    "AUD-003": "high",
    "AUD-004": "high",
    "AUD-005": "high",
    "AUD-006": "high",
    "AUD-007": "high",
    "AUD-008": "high",
    "AUD-009": "high",
    "AUD-010": "critical",
    "AUD-011": "high",
}
SECRET_PATTERNS = [
    re.compile(pattern)
    for pattern in [
        r"(^|/|\\)\.env($|\.)",
        r"(^|/|\\).*keystore.*\.json$",
        r"(^|/|\\).*password.*(\.txt|\.json)?$",
        r"(^|/|\\).*mnemonic.*$",
        r"(^|/|\\).*seed.*$",
        r"(^|/|\\).*recovery.*$",
        r"(^|/|\\).*private[-_]?key.*$",
        r"(^|/|\\).*vault.*$",
        r"(^|/|\\).*\.pem$",
        r"(^|/|\\).*\.key$",
    ]
]


class AuditError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def repo_root() -> Path:
    return Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())


def git_head(root: Path) -> str:
    return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()


def git_remote_slug(root: Path) -> str:
    try:
        url = subprocess.check_output(["git", "-C", str(root), "config", "--get", "remote.origin.url"], text=True).strip()
    except subprocess.CalledProcessError:
        return root.name
    if url.endswith(".git"):
        url = url[:-4]
    if url.startswith("git@github.com:"):
        return url.split(":", 1)[1]
    if url.startswith("https://github.com/"):
        return url.split("https://github.com/", 1)[1]
    return url or root.name


def git_show(root: Path, commit: str, repo_relpath: str) -> bytes | None:
    try:
        return subprocess.check_output(["git", "-C", str(root), "show", f"{commit}:{repo_relpath}"], stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return None


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text())


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def csv_list(raw: str) -> list[str]:
    seen = set()
    values = []
    for item in (raw or "").split(","):
        value = item.strip()
        if value and value not in seen:
            values.append(value)
            seen.add(value)
    return values


def sorted_unique(items: list[str]) -> list[str]:
    return sorted({item for item in items if item})


def canonicalize_controls(items: list[str]) -> list[str]:
    seen = set()
    ordered = []
    for cid in CONTROL_ORDER:
        if cid in items and cid not in seen:
            ordered.append(cid)
            seen.add(cid)
    extras = sorted(set(items) - set(CONTROL_ORDER))
    ordered.extend(extras)
    return ordered


def secret_like(relpath: str) -> bool:
    lowered = relpath.lower()
    return any(pattern.search(lowered) for pattern in SECRET_PATTERNS)


def audit_policy_path(root: Path) -> Path:
    for candidate in [
        root / "ops/policy/audit.policy.json",
        root / "ops/policy/audit.policy.example.json",
    ]:
        if candidate.exists():
            return candidate
    raise AuditError("Missing ops/policy/audit.policy.json")


def live_lane_policy_path(root: Path, network: str) -> Path:
    for candidate in [
        root / "ops/policy" / f"lane.{network}.json",
        root / "ops/policy" / f"lane.{network}.example.json",
    ]:
        if candidate.exists():
            return candidate
    raise AuditError(f"Missing lane policy for network {network}")


def load_policy_snapshot(root: Path, commit: str, network: str) -> tuple[dict | None, bytes | None, str]:
    repo_relpath = f"ops/policy/lane.{network}.json"
    raw = git_show(root, commit, repo_relpath)
    if raw is None:
        repo_relpath = f"ops/policy/lane.{network}.example.json"
        raw = git_show(root, commit, repo_relpath)
    if raw is None:
        return None, None, ""
    return json.loads(raw.decode()), raw, repo_relpath


def determine_audit_dir(root: Path, command: str) -> tuple[Path, str, str]:
    audit_path = os.environ.get("AUDIT_PATH", "").strip()
    network = os.environ.get("NETWORK", "").strip()
    audit_id = os.environ.get("AUDIT_ID", "").strip()
    if command == "plan":
        if not network or not audit_id:
            raise AuditError("Usage: NETWORK=<devnet|sepolia|mainnet> AUDIT_ID=<id> [RUN_IDS=r1,r2] ops/tools/audit_plan.sh")
        target = Path(audit_path) if audit_path else root / "audits" / network / audit_id
        return target, network, audit_id
    if audit_path:
        target = Path(audit_path)
        plan_path = target / "audit_plan.json"
        if not plan_path.exists():
            raise AuditError(f"Missing audit_plan.json in {target}")
        plan = load_json(plan_path)
        return target, str(plan.get("network", "")), str(plan.get("audit_id", ""))
    if not network or not audit_id:
        raise AuditError(f"Usage: NETWORK=<devnet|sepolia|mainnet> AUDIT_ID=<id> ops/tools/audit_{command}.sh")
    return root / "audits" / network / audit_id, network, audit_id


def audit_inputs(root: Path, command: str) -> tuple[Path, Path, dict, dict]:
    audit_dir, _, _ = determine_audit_dir(root, command)
    plan_path = audit_dir / "audit_plan.json"
    manifest_path = audit_dir / "audit_manifest.json"
    plan = load_json(plan_path)
    manifest = load_json(manifest_path) if manifest_path.exists() else {}
    return audit_dir, plan_path, plan, manifest


def validate_plan(plan: dict) -> None:
    required = ["audit_id", "network", "run_ids", "allowed_lanes", "controls", "created_at", "purpose", "runs", "project"]
    for key in required:
        if key not in plan:
            raise AuditError(f"audit_plan missing required key: {key}")
    if not isinstance(plan["run_ids"], list) or not plan["run_ids"]:
        raise AuditError("audit_plan.run_ids must be a non-empty list")


def validate_manifest(manifest: dict) -> None:
    required = ["audit_id", "network", "run_ids", "runs", "plan_sha256", "evidence_set_sha256", "collected_at"]
    for key in required:
        if key not in manifest:
            raise AuditError(f"audit_manifest missing required key: {key}")


def validate_verify(verification: dict) -> None:
    required = ["audit_id", "network", "status", "verified_at", "run_ids", "control_results", "plan_sha256", "manifest_sha256", "frozen_input_sha256"]
    for key in required:
        if key not in verification:
            raise AuditError(f"audit_verify missing required key: {key}")
    if verification["status"] not in {"pass", "fail", "incomplete"}:
        raise AuditError("audit_verify status enum violation")


def validate_report(report: dict) -> None:
    required = ["audit_id", "network", "status", "generated_at", "run_ids", "coverage", "summary", "controls", "missing_evidence", "bundle_hashes", "git_commits"]
    for key in required:
        if key not in report:
            raise AuditError(f"audit_report missing required key: {key}")
    if report["status"] not in {"pass", "fail", "incomplete"}:
        raise AuditError("audit_report status enum violation")


def validate_signoff(signoff: dict) -> None:
    required = ["audit_id", "network", "run_ids", "plan_sha256", "manifest_sha256", "verify_sha256", "report_sha256", "approver", "signed_off_at", "decision"]
    for key in required:
        if key not in signoff:
            raise AuditError(f"audit_signoff missing required key: {key}")


def derive_controls(policy: dict, runs: list[dict], lane_policies: dict[str, dict]) -> list[str]:
    base_controls = (policy.get("required_controls") or {}).get(runs[0]["network"], DEFAULT_BASE_CONTROLS.get(runs[0]["network"], []))
    feature_controls = policy.get("lane_feature_controls") or DEFAULT_FEATURE_CONTROLS
    controls = list(base_controls)
    for run in runs:
        lane_cfg = lane_policies[run["run_id"]]
        if lane_cfg.get("writes"):
            controls.extend(feature_controls.get("write_lane", []))
        if lane_cfg.get("allowed_signers"):
            controls.extend(feature_controls.get("signer_allowlist", []))
        gates = lane_cfg.get("gates") if isinstance(lane_cfg.get("gates"), dict) else {}
        if bool(gates.get("require_rehearsal_proof", False)):
            controls.extend(feature_controls.get("rehearsal_proof", []))
        required_inputs = lane_cfg.get("required_inputs")
        if isinstance(required_inputs, list) and required_inputs:
            controls.extend(feature_controls.get("required_inputs", []))
    return canonicalize_controls(controls)


def run_expected_files(lane_cfg: dict) -> dict[str, bool]:
    expected = {
        "run.json": True,
        "bundle_manifest.json": True,
        "intent.json": True,
        "checks.json": True,
        "policy.json": True,
    }
    if lane_cfg.get("writes"):
        expected["approval.json"] = True
        expected["txs.json"] = True
        expected["postconditions.json"] = True
    required_inputs = lane_cfg.get("required_inputs") if isinstance(lane_cfg.get("required_inputs"), list) else []
    if required_inputs:
        expected["inputs.json"] = True
    return expected


def bundle_manifest_check(run_dir: Path) -> tuple[str, str, list[str]]:
    manifest_path = run_dir / "bundle_manifest.json"
    if not manifest_path.exists():
        return "incomplete", "missing bundle_manifest.json", []
    manifest = load_json(manifest_path)
    immutable = manifest.get("immutable_files") or []
    if not immutable:
        return "incomplete", "bundle_manifest.json missing immutable_files", ["bundle_manifest.json"]
    for item in immutable:
        rel = item.get("path")
        expected = item.get("sha256")
        if not rel or not expected:
            return "incomplete", "bundle manifest entry missing path or sha256", ["bundle_manifest.json"]
        target = run_dir / rel
        if not target.exists():
            return "incomplete", f"missing immutable file {rel}", [rel]
        actual = sha256_file(target)
        if actual != expected:
            return "fail", f"hash mismatch for immutable file {rel}", [rel, "bundle_manifest.json"]
    digest_lines = []
    for item in immutable:
        rel = item["path"]
        digest_lines.append(f"{rel}={sha256_file(run_dir / rel)}")
    bundle_hash = sha256_bytes("\n".join(digest_lines).encode())
    if bundle_hash != manifest.get("bundle_hash"):
        return "fail", "bundle_manifest.json bundle_hash mismatch", ["bundle_manifest.json"]
    return "pass", "bundle manifest hashes verified", ["bundle_manifest.json"]


def compute_frozen_input_sha256(audit_dir: Path) -> str:
    tracked = []
    for rel in [Path("audit_plan.json"), Path("audit_manifest.json")]:
        target = audit_dir / rel
        if not target.exists():
            raise AuditError(f"Missing frozen input file: {target}")
        tracked.append((rel.as_posix(), sha256_file(target)))
    runs_dir = audit_dir / "runs"
    if runs_dir.exists():
        for file_path in sorted([path for path in runs_dir.rglob("*") if path.is_file()]):
            tracked.append((file_path.relative_to(audit_dir).as_posix(), sha256_file(file_path)))
    payload = "\n".join(f"{path}={digest}" for path, digest in tracked)
    return sha256_bytes(payload.encode())


def collect_index_from_manifest(manifest: dict) -> dict:
    files_indexed = []
    missing = []
    for run in manifest.get("runs", []):
        files_indexed.extend(run.get("files", []))
        for item in run.get("missing_files", []):
            missing.append({
                "run_id": run.get("run_id"),
                **item,
            })
    return {
        "audit_id": manifest.get("audit_id"),
        "network": manifest.get("network"),
        "run_ids": manifest.get("run_ids", []),
        "files_indexed": files_indexed,
        "missing_files": missing,
        "evidence_set_sha256": manifest.get("evidence_set_sha256"),
        "collect_time": manifest.get("collected_at"),
    }


def markdown_report(report: dict) -> str:
    lines = []
    lines.append(f"# Audit Report: {report['audit_id']}")
    lines.append("")
    lines.append(f"- Network: `{report['network']}`")
    lines.append(f"- Status: `{report['status']}`")
    lines.append(f"- Run IDs: `{', '.join(report['run_ids'])}`")
    lines.append(f"- Generated at: `{report['generated_at']}`")
    lines.append(f"- Coverage: `{report['coverage']['covered']}/{report['coverage']['total']} ({report['coverage']['percent']}%)`")
    lines.append("")
    lines.append("## Commits")
    for item in report.get("git_commits", []):
        lines.append(f"- `{item['run_id']}` -> `{item['git_commit']}`")
    lines.append("")
    lines.append("## Bundle Hashes")
    for item in report.get("bundle_hashes", []):
        lines.append(f"- `{item['run_id']}` -> `{item['bundle_hash']}`")
    lines.append("")
    lines.append("## Controls")
    for result in report.get("controls", []):
        lines.append(f"- `{result['control_id']}` `{result['status']}`: {result['details']}")
    if report.get("missing_evidence"):
        lines.append("")
        lines.append("## Missing Evidence")
        for item in report["missing_evidence"]:
            lines.append(f"- `{item['run_id']}` `{item['path']}`: {item['reason']}")
    return "\n".join(lines) + "\n"


def plan_command(root: Path) -> int:
    audit_dir, network, audit_id = determine_audit_dir(root, "plan")
    run_ids = csv_list(os.environ.get("RUN_IDS", ""))
    if not run_ids:
        raise AuditError("RUN_IDS must be provided and non-empty for audit planning")

    allowed_lanes = csv_list(os.environ.get("ALLOWED_LANES", ""))
    purpose = os.environ.get("AUDIT_PURPOSE", "release evidence review").strip() or "release evidence review"
    auditor = os.environ.get("AUDITOR", os.environ.get("USER", "unknown")).strip() or "unknown"
    policy = load_json(audit_policy_path(root))

    run_rows = []
    lane_policies = {}
    observed_lanes = []
    for run_id in run_ids:
        run_path = root / "bundles" / network / run_id / "run.json"
        if not run_path.exists():
            raise AuditError(f"Missing run.json for run_id {run_id}: {run_path}")
        run_payload = load_json(run_path)
        if run_payload.get("network") != network:
            raise AuditError(f"Run {run_id} declared network {run_payload.get('network')} != {network}")
        if run_payload.get("run_id") != run_id:
            raise AuditError(f"Run {run_id} has mismatched run.json run_id {run_payload.get('run_id')}")
        lane = str(run_payload.get("lane", "")).strip()
        commit = str(run_payload.get("git_commit", "")).strip()
        if not lane or not commit:
            raise AuditError(f"Run {run_id} is missing lane or git_commit in run.json")
        snapshot, raw, snapshot_path = load_policy_snapshot(root, commit, network)
        if snapshot is None or raw is None:
            raise AuditError(f"Unable to load lane policy snapshot for run {run_id} at commit {commit}")
        lane_cfg = ((snapshot or {}).get("lanes") or {}).get(lane)
        if not isinstance(lane_cfg, dict):
            raise AuditError(f"Run {run_id} lane '{lane}' not present in policy snapshot {snapshot_path}")
        lane_policies[run_id] = lane_cfg
        observed_lanes.append(lane)
        run_rows.append({
            "run_id": run_id,
            "lane": lane,
            "git_commit": commit,
            "bundle_path": f"bundles/{network}/{run_id}",
            "policy_snapshot_path": snapshot_path,
            "policy_snapshot_sha256": sha256_bytes(raw),
        })

    unique_lanes = sorted_unique(observed_lanes)
    if len(unique_lanes) > 1 and not allowed_lanes:
        raise AuditError("Multiple lanes in scope require explicit ALLOWED_LANES=<lane1,lane2>")
    if not allowed_lanes:
        allowed_lanes = unique_lanes
    missing_allowed = [lane for lane in unique_lanes if lane not in allowed_lanes]
    if missing_allowed:
        raise AuditError(f"Observed lanes not covered by ALLOWED_LANES: {', '.join(missing_allowed)}")

    controls = derive_controls(policy, [{"network": network, **row} for row in run_rows], lane_policies)
    plan = {
        "audit_id": audit_id,
        "network": network,
        "run_ids": run_ids,
        "allowed_lanes": allowed_lanes,
        "purpose": purpose,
        "auditor": auditor,
        "created_at": utc_now(),
        "controls": controls,
        "project": {
            "repo_name": root.name,
            "repo_remote": git_remote_slug(root),
        },
        "repo_commit_at_plan": git_head(root),
        "runs": run_rows,
    }
    validate_plan(plan)
    audit_dir.mkdir(parents=True, exist_ok=True)
    write_json(audit_dir / "audit_plan.json", plan)
    print(f"Audit plan written: {audit_dir / 'audit_plan.json'}")
    return 0


def collect_command(root: Path) -> int:
    audit_dir, plan_path, plan, _ = audit_inputs(root, "collect")
    validate_plan(plan)
    runs_dir = audit_dir / "runs"
    if runs_dir.exists():
        shutil.rmtree(runs_dir)
    for stale in [
        audit_dir / "audit_manifest.json",
        audit_dir / "audit_evidence_index.json",
        audit_dir / "audit_verify.json",
        audit_dir / "audit_verification.json",
        audit_dir / "audit_report.json",
        audit_dir / "audit_report.md",
        audit_dir / "findings.json",
        audit_dir / "audit_signoff.json",
        audit_dir / "signoff.json",
    ]:
        if stale.exists():
            stale.unlink()

    manifest_runs = []
    for run_info in plan.get("runs", []):
        run_id = run_info["run_id"]
        lane = run_info["lane"]
        commit = run_info["git_commit"]
        bundle_dir = root / "bundles" / plan["network"] / run_id
        target_dir = runs_dir / run_id
        target_dir.mkdir(parents=True, exist_ok=True)

        snapshot, raw, snapshot_path = load_policy_snapshot(root, commit, plan["network"])
        lane_cfg = None
        if snapshot is not None:
            lane_cfg = ((snapshot.get("lanes") or {}).get(lane))
        if not isinstance(lane_cfg, dict):
            lane_cfg = {}
        required_files = run_expected_files(lane_cfg)
        files = []
        missing_files = []

        if not bundle_dir.is_dir():
            for relpath in sorted(required_files):
                missing_files.append({
                    "path": f"runs/{run_id}/{relpath}",
                    "required": True,
                    "reason": f"source bundle missing: {bundle_dir}",
                })
            if raw is not None:
                policy_dest = target_dir / "policy.json"
                policy_dest.write_bytes(raw)
                os.chmod(policy_dest, 0o444)
                files.append({
                    "path": policy_dest.relative_to(audit_dir).as_posix(),
                    "sha256": sha256_file(policy_dest),
                    "required": True,
                    "source": snapshot_path,
                })
            manifest_runs.append({
                "run_id": run_id,
                "lane": lane,
                "git_commit": commit,
                "bundle_hash": "",
                "files": files,
                "missing_files": missing_files,
            })
            continue

        source_files = sorted([path for path in bundle_dir.rglob("*") if path.is_file()])
        for source_path in source_files:
            rel = source_path.relative_to(bundle_dir).as_posix()
            if source_path.is_symlink():
                raise AuditError(f"Audit collect refuses symlinked evidence: {source_path}")
            if secret_like(rel):
                raise AuditError(f"Audit collect refuses secret-bearing evidence file: {source_path}")
        for source_path in source_files:
            rel = source_path.relative_to(bundle_dir)
            dest = target_dir / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, dest)
            os.chmod(dest, 0o444)

        if raw is not None:
            policy_dest = target_dir / "policy.json"
            policy_dest.write_bytes(raw)
            os.chmod(policy_dest, 0o444)

        for copied in sorted([path for path in target_dir.rglob("*") if path.is_file()]):
            rel_to_audit = copied.relative_to(audit_dir).as_posix()
            files.append({
                "path": rel_to_audit,
                "sha256": sha256_file(copied),
                "required": required_files.get(copied.relative_to(target_dir).as_posix(), False),
                "source": f"bundles/{plan['network']}/{run_id}/{copied.relative_to(target_dir).as_posix()}" if copied.name != "policy.json" else snapshot_path,
            })

        existing_rels = {Path(item["path"]).relative_to(f"runs/{run_id}").as_posix() for item in files}
        for relpath, required in required_files.items():
            if required and relpath not in existing_rels:
                missing_files.append({
                    "path": f"runs/{run_id}/{relpath}",
                    "required": True,
                    "reason": "required by lane policy but not collected",
                })

        bundle_hash = ""
        manifest_path = target_dir / "bundle_manifest.json"
        if manifest_path.exists():
            bundle_hash = str(load_json(manifest_path).get("bundle_hash", ""))
        manifest_runs.append({
            "run_id": run_id,
            "lane": lane,
            "git_commit": commit,
            "bundle_hash": bundle_hash,
            "files": files,
            "missing_files": missing_files,
        })

    manifest = {
        "audit_id": plan["audit_id"],
        "network": plan["network"],
        "run_ids": plan["run_ids"],
        "allowed_lanes": plan["allowed_lanes"],
        "plan_sha256": sha256_file(plan_path),
        "collected_at": utc_now(),
        "runs": manifest_runs,
    }
    write_json(audit_dir / "audit_manifest.json", manifest)
    manifest["evidence_set_sha256"] = compute_frozen_input_sha256(audit_dir)
    write_json(audit_dir / "audit_manifest.json", manifest)
    write_json(audit_dir / "audit_evidence_index.json", collect_index_from_manifest(manifest))
    validate_manifest(manifest)
    print(f"Audit manifest written: {audit_dir / 'audit_manifest.json'}")
    return 0


def load_run_context(audit_dir: Path, manifest: dict) -> list[dict]:
    contexts = []
    for run_info in manifest.get("runs", []):
        run_dir = audit_dir / "runs" / run_info["run_id"]
        ctx = {
            "run_id": run_info["run_id"],
            "lane": run_info.get("lane", ""),
            "git_commit": run_info.get("git_commit", ""),
            "run_dir": run_dir,
            "manifest_entry": run_info,
        }
        for name in ["run.json", "bundle_manifest.json", "intent.json", "checks.json", "approval.json", "txs.json", "postconditions.json", "policy.json", "inputs.json"]:
            path = run_dir / name
            ctx[name.replace(".json", "").replace("bundle_manifest", "bundle_manifest")] = load_json(path) if path.exists() else None
        contexts.append(ctx)
    return contexts


def append_result(results: list[dict], control_id: str, status: str, tier: str, details: str, evidence_refs: list[str] | None = None) -> None:
    results.append({
        "control_id": control_id,
        "status": status,
        "tier": tier,
        "details": details,
        "evidence_refs": evidence_refs or [],
    })


def verify_command(root: Path) -> int:
    audit_dir, plan_path, plan, manifest = audit_inputs(root, "verify")
    validate_plan(plan)
    validate_manifest(manifest)

    actual_plan_sha = sha256_file(plan_path)
    manifest_path = audit_dir / "audit_manifest.json"
    actual_manifest_sha = sha256_file(manifest_path)
    actual_frozen_sha = compute_frozen_input_sha256(audit_dir)

    results = []
    contexts = load_run_context(audit_dir, manifest)
    lane_scope = set(plan.get("allowed_lanes", []))
    current_repo_commit = git_head(root)

    # AUD-001 manifest hashes
    if "AUD-001" in plan["controls"]:
        statuses = []
        details = []
        refs = []
        for ctx in contexts:
            status, detail, evidence = bundle_manifest_check(ctx["run_dir"])
            statuses.append(status)
            details.append(f"{ctx['run_id']}: {detail}")
            refs.extend([f"runs/{ctx['run_id']}/{item}" for item in evidence])
        if any(status == "fail" for status in statuses):
            append_result(results, "AUD-001", "fail", "VERIFIED", "; ".join(details), refs)
        elif any(status == "incomplete" for status in statuses):
            append_result(results, "AUD-001", "incomplete", "VERIFIED", "; ".join(details), refs)
        else:
            append_result(results, "AUD-001", "pass", "VERIFIED", "All bundle manifests verified.", refs)

    # AUD-002 commit / policy provenance binding
    if "AUD-002" in plan["controls"]:
        problems = []
        incomplete = False
        refs = []
        for ctx in contexts:
            run = ctx.get("run") or {}
            manifest_json = ctx.get("bundle_manifest") or {}
            policy_json = ctx.get("policy") or {}
            refs.extend([f"runs/{ctx['run_id']}/run.json", f"runs/{ctx['run_id']}/bundle_manifest.json", f"runs/{ctx['run_id']}/policy.json"])
            run_commit = str(run.get("git_commit", "")).strip()
            manifest_commit = str(manifest_json.get("git_commit", "")).strip()
            if not run_commit or not manifest_commit:
                incomplete = True
                problems.append(f"{ctx['run_id']}: missing git_commit in run.json or bundle_manifest.json")
                continue
            if run_commit != manifest_commit or run_commit != ctx["git_commit"]:
                problems.append(f"{ctx['run_id']}: run/manifest/plan commit mismatch")
            if not policy_json:
                incomplete = True
                problems.append(f"{ctx['run_id']}: missing policy snapshot")
        if problems:
            append_result(results, "AUD-002", "incomplete" if incomplete and not any("mismatch" in item for item in problems) else "fail", "VERIFIED", "; ".join(problems), refs)
        else:
            append_result(results, "AUD-002", "pass", "VERIFIED", f"Bundle provenance binds to pinned commits. Current checkout is {current_repo_commit}.", refs)

    # AUD-003 scope / lane compatibility
    if "AUD-003" in plan["controls"]:
        problems = []
        incomplete = False
        refs = []
        if manifest.get("run_ids") != plan.get("run_ids"):
            problems.append("plan run_ids and manifest run_ids differ")
        for ctx in contexts:
            run = ctx.get("run") or {}
            policy_json = ctx.get("policy") or {}
            lane = str(run.get("lane", ctx["lane"]))
            refs.extend([f"runs/{ctx['run_id']}/run.json", f"runs/{ctx['run_id']}/policy.json"])
            if run.get("network") != plan["network"]:
                problems.append(f"{ctx['run_id']}: run network mismatch")
            if lane not in lane_scope:
                problems.append(f"{ctx['run_id']}: lane {lane} outside allowed_lanes")
            if not policy_json:
                incomplete = True
                problems.append(f"{ctx['run_id']}: missing policy snapshot")
            elif lane not in ((policy_json.get("lanes") or {}).keys()):
                problems.append(f"{ctx['run_id']}: lane {lane} not found in policy snapshot")
        if problems:
            append_result(results, "AUD-003", "incomplete" if incomplete and all("missing policy snapshot" in item for item in problems) else "fail", "VERIFIED", "; ".join(problems), refs)
        else:
            append_result(results, "AUD-003", "pass", "VERIFIED", "Audit scope matches network and lane policy.", refs)

    # AUD-004 approval binding
    if "AUD-004" in plan["controls"]:
        problems = []
        incomplete = False
        refs = []
        for ctx in contexts:
            policy_json = ctx.get("policy") or {}
            lane_cfg = ((policy_json.get("lanes") or {}).get(ctx["lane"], {})) if policy_json else {}
            if not lane_cfg.get("writes"):
                continue
            approval = ctx.get("approval")
            bundle_manifest = ctx.get("bundle_manifest") or {}
            refs.append(f"runs/{ctx['run_id']}/approval.json")
            if not approval:
                incomplete = True
                problems.append(f"{ctx['run_id']}: missing approval.json")
                continue
            if approval.get("bundle_hash") != bundle_manifest.get("bundle_hash"):
                problems.append(f"{ctx['run_id']}: approval bundle_hash mismatch")
            if approval.get("network") != plan["network"] or approval.get("run_id") != ctx["run_id"] or approval.get("lane") != ctx["lane"]:
                problems.append(f"{ctx['run_id']}: approval metadata mismatch")
        if problems:
            append_result(results, "AUD-004", "incomplete" if incomplete and all("missing approval.json" in item for item in problems) else "fail", "VERIFIED", "; ".join(problems), refs)
        else:
            append_result(results, "AUD-004", "pass", "VERIFIED", "Approval artifacts bind to bundle hashes.", refs)

    # AUD-005 apply evidence
    if "AUD-005" in plan["controls"]:
        problems = []
        incomplete = False
        refs = []
        for ctx in contexts:
            policy_json = ctx.get("policy") or {}
            lane_cfg = ((policy_json.get("lanes") or {}).get(ctx["lane"], {})) if policy_json else {}
            if not lane_cfg.get("writes"):
                continue
            txs = ctx.get("txs")
            refs.append(f"runs/{ctx['run_id']}/txs.json")
            if not txs:
                incomplete = True
                problems.append(f"{ctx['run_id']}: missing txs.json")
                continue
            if txs.get("network") != plan["network"] or txs.get("lane") != ctx["lane"]:
                problems.append(f"{ctx['run_id']}: txs metadata mismatch")
            tx_list = txs.get("txs") if isinstance(txs.get("txs"), list) else []
            if not tx_list:
                problems.append(f"{ctx['run_id']}: txs.json has empty tx list")
        if problems:
            append_result(results, "AUD-005", "incomplete" if incomplete and all("missing txs.json" in item for item in problems) else "fail", "VERIFIED", "; ".join(problems), refs)
        else:
            append_result(results, "AUD-005", "pass", "VERIFIED", "Write-lane execution evidence is present.", refs)

    # AUD-006 postconditions
    if "AUD-006" in plan["controls"]:
        problems = []
        incomplete = False
        refs = []
        for ctx in contexts:
            policy_json = ctx.get("policy") or {}
            lane_cfg = ((policy_json.get("lanes") or {}).get(ctx["lane"], {})) if policy_json else {}
            if not lane_cfg.get("writes"):
                continue
            post = ctx.get("postconditions")
            refs.append(f"runs/{ctx['run_id']}/postconditions.json")
            if not post:
                incomplete = True
                problems.append(f"{ctx['run_id']}: missing postconditions.json")
                continue
            if post.get("network") != plan["network"] or post.get("run_id") != ctx["run_id"]:
                problems.append(f"{ctx['run_id']}: postconditions metadata mismatch")
            if post.get("status") != "pass":
                problems.append(f"{ctx['run_id']}: postconditions status is {post.get('status')}")
        if problems:
            append_result(results, "AUD-006", "incomplete" if incomplete and all("missing postconditions.json" in item for item in problems) else "fail", "VERIFIED", "; ".join(problems), refs)
        else:
            append_result(results, "AUD-006", "pass", "VERIFIED", "Postconditions evidence exists and passed.", refs)

    # AUD-007 rehearsal proof binding
    if "AUD-007" in plan["controls"]:
        problems = []
        incomplete = False
        refs = []
        for ctx in contexts:
            policy_json = ctx.get("policy") or {}
            lane_cfg = ((policy_json.get("lanes") or {}).get(ctx["lane"], {})) if policy_json else {}
            gates = lane_cfg.get("gates") if isinstance(lane_cfg.get("gates"), dict) else {}
            if not bool(gates.get("require_rehearsal_proof", False)):
                continue
            txs = ctx.get("txs") or {}
            refs.append(f"runs/{ctx['run_id']}/txs.json")
            proof_run_id = str(txs.get("rehearsal_proof_run_id", "")).strip()
            proof_network = str(txs.get("rehearsal_proof_network", "")).strip()
            if not proof_run_id or not proof_network:
                incomplete = True
                problems.append(f"{ctx['run_id']}: missing rehearsal_proof_run_id or rehearsal_proof_network in txs.json")
                continue
            proof_dir = root / "bundles" / proof_network / proof_run_id
            if not (proof_dir / "txs.json").exists() or not (proof_dir / "postconditions.json").exists():
                problems.append(f"{ctx['run_id']}: referenced rehearsal proof bundle is incomplete: {proof_dir}")
        if problems:
            append_result(results, "AUD-007", "incomplete" if incomplete and all("missing rehearsal_proof" in item for item in problems) else "fail", "VERIFIED", "; ".join(problems), refs)
        else:
            append_result(results, "AUD-007", "pass", "VERIFIED", "Mainnet rehearsal proof binding is present.", refs)

    # AUD-008 signer allowlist
    if "AUD-008" in plan["controls"]:
        problems = []
        incomplete = False
        refs = []
        for ctx in contexts:
            policy_json = ctx.get("policy") or {}
            lane_cfg = ((policy_json.get("lanes") or {}).get(ctx["lane"], {})) if policy_json else {}
            allowed_aliases = lane_cfg.get("allowed_signers") if isinstance(lane_cfg.get("allowed_signers"), list) else []
            if not allowed_aliases:
                continue
            signer_map = policy_json.get("signer_alias_map") if isinstance(policy_json.get("signer_alias_map"), dict) else {}
            allowed_addresses = {str(signer_map.get(alias, "")).lower() for alias in allowed_aliases if str(signer_map.get(alias, "")).strip()}
            txs = ctx.get("txs") or {}
            refs.append(f"runs/{ctx['run_id']}/txs.json")
            signer_used = str(txs.get("signer_address_used", "")).lower().strip()
            if not allowed_addresses:
                incomplete = True
                problems.append(f"{ctx['run_id']}: signer_alias_map missing addresses for allowed_signers")
                continue
            if not signer_used:
                incomplete = True
                problems.append(f"{ctx['run_id']}: txs.json missing signer_address_used")
                continue
            if signer_used not in allowed_addresses:
                problems.append(f"{ctx['run_id']}: signer_address_used {signer_used} not in allowed signer addresses")
        if problems:
            append_result(results, "AUD-008", "incomplete" if incomplete and all("missing" in item or "signer_alias_map" in item for item in problems) else "fail", "VERIFIED", "; ".join(problems), refs)
        else:
            append_result(results, "AUD-008", "pass", "VERIFIED", "Observed signer addresses match lane allowlists.", refs)

    # AUD-009 network coherence
    if "AUD-009" in plan["controls"]:
        problems = []
        refs = []
        for ctx in contexts:
            for name in ["run", "intent", "checks", "bundle_manifest", "approval", "txs", "postconditions"]:
                payload = ctx.get(name)
                if not isinstance(payload, dict):
                    continue
                refs.append(f"runs/{ctx['run_id']}/{name.replace('bundle_manifest', 'bundle_manifest').replace('run', 'run').replace('postconditions', 'postconditions')}.json")
                net = payload.get("network")
                if isinstance(net, str) and net and net != plan["network"]:
                    problems.append(f"{ctx['run_id']}: {name}.json network mismatch ({net})")
        if problems:
            append_result(results, "AUD-009", "fail", "VERIFIED", "; ".join(problems), refs)
        else:
            append_result(results, "AUD-009", "pass", "VERIFIED", "Network coherence holds across collected evidence.", refs)

    # AUD-010 secret-safety
    if "AUD-010" in plan["controls"]:
        suspicious = []
        refs = []
        for run in manifest.get("runs", []):
            for item in run.get("files", []):
                refs.append(item["path"])
                rel = Path(item["path"]).relative_to(f"runs/{run['run_id']}").as_posix()
                if secret_like(rel):
                    suspicious.append(item["path"])
        if suspicious:
            append_result(results, "AUD-010", "fail", "VERIFIED", "Secret-like evidence filenames were collected.", suspicious)
        else:
            append_result(results, "AUD-010", "pass", "VERIFIED", "Collected evidence excludes secret-bearing filenames.", refs[:20])

    # AUD-011 pinned inputs
    if "AUD-011" in plan["controls"]:
        problems = []
        incomplete = False
        refs = []
        for ctx in contexts:
            policy_json = ctx.get("policy") or {}
            lane_cfg = ((policy_json.get("lanes") or {}).get(ctx["lane"], {})) if policy_json else {}
            required_inputs = lane_cfg.get("required_inputs") if isinstance(lane_cfg.get("required_inputs"), list) else []
            required_kinds = [item.get("kind") for item in required_inputs if isinstance(item, dict) and isinstance(item.get("kind"), str)]
            if not required_kinds:
                continue
            inputs = ctx.get("inputs")
            approval = ctx.get("approval") or {}
            intent = ctx.get("intent") or {}
            txs = ctx.get("txs") or {}
            refs.extend([f"runs/{ctx['run_id']}/inputs.json", f"runs/{ctx['run_id']}/approval.json", f"runs/{ctx['run_id']}/txs.json"])
            if not inputs:
                incomplete = True
                problems.append(f"{ctx['run_id']}: missing inputs.json")
                continue
            inputs_path = ctx["run_dir"] / "inputs.json"
            inputs_hash = sha256_file(inputs_path)
            if intent.get("inputs_sha256") != inputs_hash:
                problems.append(f"{ctx['run_id']}: intent inputs_sha256 mismatch")
            if approval.get("inputs_sha256") != inputs_hash:
                problems.append(f"{ctx['run_id']}: approval inputs_sha256 mismatch")
            if txs.get("inputs_sha256") != inputs_hash:
                problems.append(f"{ctx['run_id']}: txs inputs_sha256 mismatch")
            kind = str(inputs.get("kind", "")).strip()
            if kind not in required_kinds:
                problems.append(f"{ctx['run_id']}: inputs kind {kind} not in {required_kinds}")
            if inputs.get("network") != plan["network"] or inputs.get("lane") != ctx["lane"] or inputs.get("run_id") != ctx["run_id"]:
                problems.append(f"{ctx['run_id']}: inputs wrapper coherence mismatch")
        if problems:
            append_result(results, "AUD-011", "incomplete" if incomplete and all("missing inputs.json" in item for item in problems) else "fail", "VERIFIED", "; ".join(problems), refs)
        else:
            append_result(results, "AUD-011", "pass", "VERIFIED", "Pinned inputs remained coherent through apply evidence.", refs)

    missing_evidence = []
    for run in manifest.get("runs", []):
        for item in run.get("missing_files", []):
            missing_evidence.append({
                "run_id": run["run_id"],
                **item,
            })

    statuses = [result["status"] for result in results]
    if any(status == "fail" for status in statuses):
        overall_status = "fail"
    elif any(status == "incomplete" for status in statuses) or missing_evidence:
        overall_status = "incomplete"
    else:
        overall_status = "pass"

    verification = {
        "audit_id": plan["audit_id"],
        "network": plan["network"],
        "status": overall_status,
        "verified_at": utc_now(),
        "run_ids": plan["run_ids"],
        "current_repo_commit": current_repo_commit,
        "plan_sha256": actual_plan_sha,
        "manifest_sha256": actual_manifest_sha,
        "frozen_input_sha256": actual_frozen_sha,
        "control_results": results,
        "checks": [{"name": result["control_id"], "status": result["status"], "details": result["details"]} for result in results],
        "failures": [result for result in results if result["status"] == "fail"],
        "missing_evidence": missing_evidence,
    }
    validate_verify(verification)
    write_json(audit_dir / "audit_verify.json", verification)
    write_json(audit_dir / "audit_verification.json", verification)
    print(f"Audit verify written: {audit_dir / 'audit_verify.json'}")
    return 0


def report_command(root: Path) -> int:
    audit_dir, plan_path, plan, manifest = audit_inputs(root, "report")
    verify_path = audit_dir / "audit_verify.json"
    if not verify_path.exists():
        raise AuditError(f"Missing audit_verify.json in {audit_dir}")
    verification = load_json(verify_path)
    validate_plan(plan)
    validate_manifest(manifest)
    validate_verify(verification)

    policy = load_json(audit_policy_path(root))
    min_coverage = float(policy.get("min_coverage_percent", 100))

    results = verification.get("control_results", [])
    total = len(plan.get("controls", []))
    covered = len([result for result in results if result.get("status") in {"pass", "fail"}])
    coverage = round((covered / total) * 100.0, 2) if total else 100.0

    summary = {"critical": 0, "high": 0, "medium": 0, "low": 0}
    findings = []
    for result in results:
        if result.get("status") == "pass":
            continue
        severity = SEVERITY_BY_CONTROL.get(result["control_id"], "medium")
        summary[severity] += 1
        findings.append({
            "id": f"F-{result['control_id']}",
            "severity": severity,
            "control_id": result["control_id"],
            "status": "open",
            "result_status": result["status"],
            "title": result["details"],
            "evidence_refs": result.get("evidence_refs", []),
        })

    if verification["status"] == "fail":
        status = "fail"
    elif verification["status"] == "incomplete" or coverage < min_coverage:
        status = "incomplete"
    else:
        status = "pass"

    report = {
        "audit_id": plan["audit_id"],
        "network": plan["network"],
        "status": status,
        "generated_at": utc_now(),
        "run_ids": plan["run_ids"],
        "coverage": {"covered": covered, "total": total, "percent": coverage},
        "summary": summary,
        "controls": results,
        "missing_evidence": verification.get("missing_evidence", []),
        "bundle_hashes": [{"run_id": run["run_id"], "bundle_hash": run.get("bundle_hash", "")} for run in manifest.get("runs", [])],
        "git_commits": [{"run_id": run["run_id"], "git_commit": run.get("git_commit", "")} for run in manifest.get("runs", [])],
        "current_repo_commit": verification.get("current_repo_commit", ""),
        "complete_for_signoff": status == "pass",
        "plan_sha256": sha256_file(plan_path),
        "manifest_sha256": sha256_file(audit_dir / "audit_manifest.json"),
        "verify_sha256": sha256_file(verify_path),
        "frozen_input_sha256": verification.get("frozen_input_sha256", ""),
    }
    validate_report(report)
    findings_doc = {"audit_id": plan["audit_id"], "findings": findings}
    write_json(audit_dir / "audit_report.json", report)
    write_text(audit_dir / "audit_report.md", markdown_report(report))
    write_json(audit_dir / "findings.json", findings_doc)
    print(f"Audit report written: {audit_dir / 'audit_report.json'}")
    return 0


def signoff_command(root: Path) -> int:
    audit_dir, plan_path, plan, manifest = audit_inputs(root, "signoff")
    verify_path = audit_dir / "audit_verify.json"
    report_path = audit_dir / "audit_report.json"
    if not verify_path.exists() or not report_path.exists():
        raise AuditError(f"Missing audit_verify.json or audit_report.json in {audit_dir}")
    verification = load_json(verify_path)
    report = load_json(report_path)
    validate_plan(plan)
    validate_manifest(manifest)
    validate_verify(verification)
    validate_report(report)
    if verification.get("status") != "pass":
        raise AuditError(f"Refusing signoff: audit_verify.status={verification.get('status')}")
    if report.get("status") != "pass":
        raise AuditError(f"Refusing signoff: audit_report.status={report.get('status')}")

    actual_plan_sha = sha256_file(plan_path)
    actual_manifest_sha = sha256_file(audit_dir / "audit_manifest.json")
    actual_verify_sha = sha256_file(verify_path)
    actual_report_sha = sha256_file(report_path)
    actual_frozen_sha = compute_frozen_input_sha256(audit_dir)

    if verification.get("plan_sha256") != actual_plan_sha:
        raise AuditError("Refusing signoff: audit_plan.json changed after verify")
    if verification.get("manifest_sha256") != actual_manifest_sha:
        raise AuditError("Refusing signoff: audit_manifest.json changed after verify")
    if verification.get("frozen_input_sha256") != actual_frozen_sha:
        raise AuditError("Refusing signoff: collected evidence changed after verify")
    if plan.get("run_ids") != manifest.get("run_ids") or plan.get("run_ids") != verification.get("run_ids") or plan.get("run_ids") != report.get("run_ids"):
        raise AuditError("Refusing signoff: ordered run_ids differ across plan/manifest/verify/report")

    signoff = {
        "audit_id": plan["audit_id"],
        "network": plan["network"],
        "run_ids": plan["run_ids"],
        "plan_sha256": actual_plan_sha,
        "manifest_sha256": actual_manifest_sha,
        "verify_sha256": actual_verify_sha,
        "report_sha256": actual_report_sha,
        "frozen_input_sha256": actual_frozen_sha,
        "approver": os.environ.get("AUDIT_APPROVER", os.environ.get("USER", "unknown")).strip() or "unknown",
        "signed_off_at": utc_now(),
        "decision": os.environ.get("AUDIT_DECISION", "approve").strip() or "approve",
        "notes": os.environ.get("AUDIT_SIGNOFF_NOTE", "").strip(),
    }
    validate_signoff(signoff)
    write_json(audit_dir / "audit_signoff.json", signoff)
    write_json(audit_dir / "signoff.json", signoff)
    print(f"Audit signoff written: {audit_dir / 'audit_signoff.json'}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in {"plan", "collect", "verify", "report", "signoff"}:
        print(f"Usage: {argv[0]} <plan|collect|verify|report|signoff>", file=sys.stderr)
        return 2
    root = repo_root()
    command = argv[1]
    try:
        if command == "plan":
            return plan_command(root)
        if command == "collect":
            return collect_command(root)
        if command == "verify":
            return verify_command(root)
        if command == "report":
            return report_command(root)
        return signoff_command(root)
    except AuditError as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
