#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PATH_REPO="${PATH_REPO:-$ROOT_DIR}"
export ROOT_DIR PATH_REPO

if [ -z "${WORKBOOK_DIR:-}" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/scripts/devnet/00_env.sh"
fi

need() { command -v "$1" >/dev/null 2>&1 || {
  echo "Missing dependency: $1" >&2
  exit 1
}; }

filter_json_lines() {
  # keep only single-line JSON objects (sncast emits JSONL plus plain text)
  awk '/^[[:space:]]*[{].*[}][[:space:]]*$/{print}'
}

json_put() {
  local file="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  if [ -s "$file" ]; then
    jq -S --arg k "$key" --arg v "$val" '.[$k]=$v' "$file" >"$tmp"
  else
    jq -S -n --arg k "$key" --arg v "$val" '{($k):$v}' >"$tmp"
  fi
  mv "$tmp" "$file"
}

record_address() { json_put "$ADDR_FILE" "$1" "$2"; }
record_tx() { json_put "$TX_FILE" "$1" "$2"; }

addr_from_file() {
  jq -r --arg k "$1" '.[$k] // empty' "$ADDR_FILE" 2>/dev/null || true
}

sncast_call_json() {
  local addr="$1" fn="$2"
  shift 2
  local argv=(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC"
    --contract-address "$addr" --function "$fn")
  if [ "$#" -gt 0 ]; then
    argv+=(--calldata)
    for w in "$@"; do argv+=("$w"); done
  fi
  "${argv[@]}" | filter_json_lines
}

sncast_invoke_json() {
  local addr="$1" fn="$2"
  shift 2
  local argv=(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json invoke --url "$RPC"
    --contract-address "$addr" --function "$fn")
  if [ "$#" -gt 0 ]; then
    argv+=(--calldata)
    for w in "$@"; do argv+=("$w"); done
  fi
  "${argv[@]}" | filter_json_lines
}

sncast_declare_json_dir() {
  local dir="$1" cname="$2"
  (cd "$dir" && sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json declare --url "$RPC" --contract-name "$cname") | filter_json_lines
}

sncast_declare_json_pkg() {
  local pkg="$1" cname="$2"
  (
    cd "$PATH_REPO" &&
      sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json declare --url "$RPC" \
        --package "$pkg" --contract-name "$cname"
  ) | filter_json_lines
}

sncast_deploy_json() {
  local class_hash="$1"
  shift 1
  local argv=(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json deploy --url "$RPC"
    --class-hash "$class_hash")
  if [ "$#" -gt 0 ]; then
    argv+=(--constructor-calldata)
    for w in "$@"; do argv+=("$w"); done
  fi
  "${argv[@]}" | filter_json_lines
}

json_class_hash() {
  jq -rs 'map(.class_hash // .declare.class_hash // empty) | map(select(. != null and . != "")) | last // empty'
}
json_tx_hash() {
  jq -rs 'map(.. | objects | (.transaction_hash? // .declare?.transaction_hash? // .invoke?.transaction_hash? // .deploy?.transaction_hash?)) | map(select(. != null and . != "")) | last // empty'
}
json_contract_address() {
  jq -rs 'map(.. | objects | (.contract_address? // .deploy?.contract_address?)) | map(select(. != null and . != "")) | last // empty'
}

encode_bytearray() {
  python3 - "$1" <<'PY'
import sys
b = sys.argv[1].encode('utf-8')
full = len(b) // 31
rem = len(b) % 31
out = []
out.append(str(full))
for i in range(full):
    chunk = b[i*31:(i+1)*31]
    out.append(hex(int.from_bytes(chunk, 'big')))
out.append(hex(int.from_bytes(b[-rem:], 'big')) if rem else "0")
out.append(str(rem))
print(" ".join(out))
PY
}

u256_split() {
  python3 - "$1" <<'PY'
import sys
n=int(sys.argv[1],0)
low=n & ((1<<128)-1)
high=n>>128
print(low, high)
PY
}

to_fri() {
  python3 - "$1" "${FRI_PER_STRK:-1000000000000000000}" <<'PY'
import sys
from decimal import Decimal, InvalidOperation, getcontext
raw = sys.argv[1].strip().replace("_", "")
mult = Decimal(sys.argv[2])
if raw.lower().startswith("0x"):
    print(int(raw, 16))
    sys.exit(0)
try:
    if any(c in raw for c in ".eE"):
        getcontext().prec = 80
        val = Decimal(raw)
    else:
        val = Decimal(int(raw, 10))
except (InvalidOperation, ValueError):
    print(f"Invalid amount: {raw}", file=sys.stderr)
    sys.exit(1)
print(int((val * mult).to_integral_value()))
PY
}

account_address() {
  jq -r --arg ns "$ACCOUNTS_NAMESPACE" --arg name "$ACCOUNT" '.[$ns][$name].address // empty' "$ACCOUNTS_FILE"
}

role_id() {
  python3 "$ROOT_DIR/scripts/devnet/_role_id.py" "$1"
}

decode_bytearray_json() {
  python3 "$ROOT_DIR/scripts/devnet/_decode_bytearray.py"
}

call_bytearray_to_file() {
  local out_file="$1" addr="$2" fn="$3"
  shift 3
  sncast_call_json "$addr" "$fn" "$@" | decode_bytearray_json >"$out_file"
}

class_hash_from_dir() {
  local dir="$1" cname="$2"
  (cd "$dir" && sncast utils class-hash --contract-name "$cname" | awk '/Class Hash:/ {print $3}' | tail -n1)
}

class_hash_from_pkg() {
  local pkg="$1" cname="$2"
  (
    cd "$PATH_REPO" &&
      sncast utils class-hash --package "$pkg" --contract-name "$cname" |
        awk '/Class Hash:/ {print $3}' |
        tail -n1
  )
}
