#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}

if [[ -z "$NETWORK" ]]; then
  echo "Usage: NETWORK=<devnet|sepolia|mainnet> $0" >&2
  exit 2
fi

case "$NETWORK" in
  devnet)
    echo "Secret-snippet lint skipped on devnet."
    exit 0
    ;;
  sepolia|mainnet) ;;
  *)
    echo "Invalid NETWORK: $NETWORK" >&2
    exit 2
    ;;
esac

ROOT=$(git rev-parse --show-toplevel)
SCAN_PATHS=(
  "$ROOT/README.md"
  "$ROOT/AGENTS.md"
  "$ROOT/ops/procedure-templates"
  "$ROOT/workbook/ops"
  "$ROOT/docs"
)

PATTERNS=(
  'export[[:space:]]+SEPOLIA_PRIVATE_KEY[[:space:]]*='
  'export[[:space:]]+MAINNET_PRIVATE_KEY[[:space:]]*='
  'SEPOLIA_PRIVATE_KEY[[:space:]]*=[[:space:]]*["'\'']?0x[0-9a-fA-F]{64}'
  'MAINNET_PRIVATE_KEY[[:space:]]*=[[:space:]]*["'\'']?0x[0-9a-fA-F]{64}'
  '--private-key([[:space:]]|=|$)'
)

matches=""
for pattern in "${PATTERNS[@]}"; do
  found=$(rg -n --pcre2 --glob "*.md" "$pattern" "${SCAN_PATHS[@]}" 2>/dev/null || true)
  if [[ -n "$found" ]]; then
    if [[ -n "$matches" ]]; then
      matches+=$'\n'
    fi
    matches+="$found"
  fi
done

if [[ -n "$matches" ]]; then
  echo "Forbidden Sepolia/Mainnet secret snippet patterns detected:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo "Secret-snippet lint passed for $NETWORK."
