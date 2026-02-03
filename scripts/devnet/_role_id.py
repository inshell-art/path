#!/usr/bin/env python3
import sys

RC = [
    0x0000000000000001, 0x0000000000008082,
    0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001,
    0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088,
    0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B,
    0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080,
    0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080,
    0x0000000080000001, 0x8000000080008008,
]
R = [
    [0, 36, 3, 41, 18],
    [1, 44, 10, 45, 2],
    [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56],
    [27, 20, 39, 8, 14],
]

def rol(x, n):
    return ((x << n) | (x >> (64 - n))) & 0xFFFFFFFFFFFFFFFF

def keccak_f(s):
    for rc in RC:
        c = [s[x] ^ s[x + 5] ^ s[x + 10] ^ s[x + 15] ^ s[x + 20] for x in range(5)]
        d = [c[(x - 1) % 5] ^ rol(c[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                s[x + 5 * y] ^= d[x]
        b = [0] * 25
        for x in range(5):
            for y in range(5):
                b[y + 5 * ((2 * x + 3 * y) % 5)] = rol(s[x + 5 * y], R[x][y])
        for x in range(5):
            for y in range(5):
                s[x + 5 * y] = b[x + 5 * y] ^ ((~b[(x + 1) % 5 + 5 * y]) & b[(x + 2) % 5 + 5 * y])
        s[0] ^= rc

def keccak_256(data: bytes) -> bytes:
    rate = 136
    s = [0] * 25
    pad = bytearray(data)
    pad.append(0x01)
    while (len(pad) % rate) != rate - 1:
        pad.append(0x00)
    pad.append(0x80)
    for b in range(0, len(pad), rate):
        block = pad[b:b + rate]
        for i in range(rate // 8):
            s[i] ^= int.from_bytes(block[i * 8:(i + 1) * 8], "little")
        keccak_f(s)
    out = bytearray()
    while len(out) < 32:
        for i in range(rate // 8):
            out += s[i].to_bytes(8, "little")
        if len(out) >= 32:
            break
        keccak_f(s)
    return bytes(out[:32])

if len(sys.argv) < 2:
    sys.exit("usage: role_id NAME")

name = sys.argv[1].encode()
mask = (1 << 250) - 1
h = keccak_256(name)
val = int.from_bytes(h, "big") & mask
print(hex(val))
