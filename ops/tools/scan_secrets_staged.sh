#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks not found. Install it to run staged secret scans." >&2
  exit 2
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/path-gitleaks-staged.XXXXXX")
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

STAGED_PATHS=()
while IFS= read -r -d '' path; do
  STAGED_PATHS+=("$path")
done < <(git diff --cached --name-only --diff-filter=ACMR -z)

if [[ ${#STAGED_PATHS[@]} -eq 0 ]]; then
  echo "No staged files to scan."
  exit 0
fi

for path in "${STAGED_PATHS[@]}"; do
  dest="$TMP_DIR/$path"
  mkdir -p "$(dirname "$dest")"
  git show ":$path" > "$dest"
done

CONFIG_ARGS=()
if [[ -f "$ROOT/.gitleaks.toml" ]]; then
  CONFIG_ARGS=(--config "$ROOT/.gitleaks.toml")
fi

gitleaks detect "${CONFIG_ARGS[@]}" --no-git --redact --source "$TMP_DIR"
