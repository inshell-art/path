#!/usr/bin/env python3
import json
import sys

def find_raw(obj):
    if isinstance(obj, dict):
        for key in ("response_raw", "response", "result"):
            if key in obj:
                val = obj[key]
                if isinstance(val, dict):
                    for k2 in ("response_raw", "response", "result"):
                        if k2 in val:
                            return val[k2]
                else:
                    return val
    return None

try:
    data = json.load(sys.stdin)
except Exception as exc:
    sys.exit(f"failed to parse json: {exc}")

raw = find_raw(data)
if raw is None:
    sys.exit("missing response_raw")

if isinstance(raw, dict):
    raw = raw.get("response_raw") or raw.get("response") or raw.get("result") or []

if not isinstance(raw, list):
    sys.exit("response_raw is not a list")

vals = []
for item in raw:
    if isinstance(item, str):
        vals.append(int(item, 0))
    else:
        vals.append(int(item))

if len(vals) > 0 and vals[0] == len(vals) - 1:
    # Response is Array<felt252>; drop length prefix to get ByteArray payload.
    vals = vals[1:]

if len(vals) < 2:
    print("")
    sys.exit(0)

full = vals[0]
if full < 0:
    sys.exit("invalid ByteArray length")

idx = 1
words = []
for _ in range(full):
    if idx >= len(vals):
        sys.exit("truncated ByteArray")
    words.append(vals[idx])
    idx += 1

if idx + 1 >= len(vals):
    sys.exit("truncated ByteArray pending word")

pending_word = vals[idx]
pending_len = vals[idx + 1]

out = b"".join(w.to_bytes(31, "big") for w in words)
if pending_len:
    tail = pending_word.to_bytes(31, "big")[-pending_len:]
    out += tail

try:
    sys.stdout.write(out.decode("utf-8"))
except UnicodeDecodeError:
    sys.stdout.write(out.decode("utf-8", errors="replace"))
