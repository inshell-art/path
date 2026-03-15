#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

export ROOT
python3 - <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(os.environ["ROOT"])
allowlist_file = root / "ops" / "public-safe-allowlist.txt"

allowlist = []
if allowlist_file.exists():
    for line in allowlist_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        allowlist.append(re.compile(line))

special_prefixes = ("artifacts/", "bundles/", "output/", "audits/")
forbidden_exact = {
    "keystore",
    "keystore.json",
    "password.txt",
}
forbidden_suffixes = (
    ".kdbx",
    ".kdbx-key",
    ".seed",
    ".mnemonic",
)
tracked_cmd = ["git", "ls-files", "-z"]
staged_cmd = ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"]
tracked_paths = [p for p in subprocess.check_output(tracked_cmd).decode().split("\0") if p]
staged_paths = [p for p in subprocess.check_output(staged_cmd).decode().split("\0") if p]

candidate_paths = sorted(set(tracked_paths + staged_paths))
violations = []

rpc_secret_re = re.compile(r"(?:alchemy\.com/v2|infura\.io/v3)/([A-Za-z0-9_-]{16,})")


def is_allowlisted(path: str) -> bool:
    return any(rx.search(path) for rx in allowlist)


def is_generated_public_safe(path: str) -> bool:
    if not path.startswith(special_prefixes):
        return True
    name = Path(path).name
    return name in {"README.md", ".gitkeep"} or ".example." in name or ".redacted." in name


def env_forbidden(path: str) -> bool:
    name = Path(path).name
    if name == ".env" or name.startswith(".env."):
        return ".example." not in path and not path.endswith(".env.example")
    if path.startswith("ops/") and name.endswith(".env"):
        return ".example." not in path and not path.endswith("env.example")
    return False


def path_violations(path: str):
    if is_allowlisted(path):
        return []
    issues = []
    name = Path(path).name
    low = name.lower()
    if not is_generated_public_safe(path):
        issues.append("generated-output path outside allowlist")
    if low in forbidden_exact:
        issues.append(f"forbidden secret filename: {name}")
    if low.endswith(".password.txt"):
        issues.append(f"forbidden password file: {name}")
    if low.endswith(forbidden_suffixes):
        issues.append(f"forbidden secret filename: {name}")
    if low.startswith("recovery-key"):
        issues.append(f"forbidden recovery material filename: {name}")
    if env_forbidden(path):
        issues.append(f"forbidden env file tracked or staged: {path}")
    return issues


def staged_blob(path: str) -> bytes:
    return subprocess.check_output(["git", "show", f":{path}"], stderr=subprocess.DEVNULL)


def file_bytes(path: str) -> bytes:
    fs_path = root / path
    if not fs_path.exists() or not fs_path.is_file():
        return b""
    return fs_path.read_bytes()

for path in candidate_paths:
    for issue in path_violations(path):
        violations.append((path, issue))

    data = b""
    try:
        if path in staged_paths:
            data = staged_blob(path)
        elif path in tracked_paths:
            data = file_bytes(path)
    except subprocess.CalledProcessError:
        data = b""
    if not data:
        continue
    text = data.decode("utf-8", errors="ignore")
    for match in rpc_secret_re.finditer(text):
        token = match.group(1)
        if "<" in token or "$" in token:
            continue
        violations.append((path, "likely credential-bearing RPC URL"))
        break

if violations:
    print("Public-safe ops boundary check failed:", file=sys.stderr)
    for path, issue in violations:
        print(f"- {path}: {issue}", file=sys.stderr)
    sys.exit(1)

print("Public-safe ops boundary check passed.")
PY
