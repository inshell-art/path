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

# If response is Array<felt252>, drop length prefix before decoding.
if len(vals) > 0 and vals[0] == len(vals) - 1:
    vals = vals[1:]

def decode_bytearray(payload):
    if len(payload) < 2:
        return b""
    full = payload[0]
    if full < 0:
        return None
    expected_len = full + 2
    if len(payload) != expected_len:
        return None
    idx = 1
    words = []
    for _ in range(full):
        if idx >= len(payload):
            return None
        words.append(payload[idx])
        idx += 1
    if idx + 1 > len(payload):
        return None
    pending_word = payload[idx]
    pending_len = payload[idx + 1]
    if pending_len < 0 or pending_len > 31:
        return None
    out = b"".join(w.to_bytes(31, "big") for w in words)
    if pending_len:
        tail = pending_word.to_bytes(31, "big")[-pending_len:]
        out += tail
    return out

def decode_word_array(payload):
    if not payload:
        return b""
    out = b"".join(w.to_bytes(31, "big") for w in payload)
    return out.rstrip(b"\\x00")

out = decode_bytearray(vals)
if out is None:
    out = decode_word_array(vals)

try:
    sys.stdout.write(out.decode("utf-8"))
except UnicodeDecodeError:
    sys.stdout.write(out.decode("utf-8", errors="replace"))
