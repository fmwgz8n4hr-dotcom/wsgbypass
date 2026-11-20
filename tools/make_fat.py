#!/usr/bin/env python3
"""把 arm64 / arm64e 两个 thin dylib 合成一个 fat Mach-O。"""
import struct, sys

def build(slices, align=14):
    n = len(slices)
    hdr = 8 + n * 20
    off = (hdr + (1 << align) - 1) & ~((1 << align) - 1)
    offs, cur = [], off
    for _, _, d in slices:
        offs.append(cur)
        cur = (cur + len(d) + (1 << align) - 1) & ~((1 << align) - 1)
    out = bytearray(struct.pack('>II', 0xcafebabe, n))
    for (c, s, d), o in zip(slices, offs):
        out += struct.pack('>iiIII', c, s, o, len(d), align)
    for (c, s, d), o in zip(slices, offs):
        out += b'\0' * (o - len(out))
        out += d
    return bytes(out)

a, e, out = sys.argv[1], sys.argv[2], sys.argv[3]
A = open(a, 'rb').read()
E = open(e, 'rb').read()
fat = build([(0x0100000C, 0, A), (0x0100000C, -2147483646, E)])
open(out, 'wb').write(fat)
print(f'fat {len(fat)} B  (arm64 {len(A)} / arm64e {len(E)})')
