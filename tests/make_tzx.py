#!/usr/bin/env python3
"""Re-encode a .tap as a TZX made of generalized data blocks (&19) or of
CSW recordings (&18, RLE or Z-RLE), to test those block types.
usage: make_tzx.py gdb|csw|cswz IN.tap OUT.tzx"""
import struct, sys, zlib

def tap_blocks(data):
    p = 0
    while p + 2 <= len(data):
        n = data[p] | data[p + 1] << 8
        yield data[p + 2:p + 2 + n]
        p += 2 + n

def gdb_block(blk):
    pilot = 8063 if blk[0] < 128 else 3223
    # pilot/sync alphabet: 0 = pilot pulse, 1 = sync (667, 735)
    symp = struct.pack('<BHH', 0, 2168, 0) + struct.pack('<BHH', 0, 667, 735)
    prle = struct.pack('<BH', 0, pilot) + struct.pack('<BH', 1, 1)
    # data alphabet: 0 = two 855 pulses, 1 = two 1710 pulses
    symd = struct.pack('<BHH', 0, 855, 855) + struct.pack('<BHH', 0, 1710, 1710)
    body = (struct.pack('<HIBBIBB', 1000, 2, 2, 2, len(blk) * 8, 2, 2)
            + symp + prle + symd + bytes(blk))
    return b'\x19' + struct.pack('<I', len(body)) + body

def pulses(blk):
    out = [2168] * (8063 if blk[0] < 128 else 3223) + [667, 735]
    for b in blk:
        for bit in range(7, -1, -1):
            out += [1710, 1710] if b >> bit & 1 else [855, 855]
    return out

def csw_block(blk, z):
    rate = 44100
    rle = bytearray()
    for t in pulses(blk) + [3500000]:          # last: 1 s of silence
        n = max(1, round(t * rate / 3500000))
        rle += bytes([n]) if n < 256 else b'\0' + struct.pack('<I', n)
    data = zlib.compress(bytes(rle)) if z else bytes(rle)
    npulses = len(pulses(blk)) + 1
    body = (struct.pack('<H', 0) + struct.pack('<I', rate)[:3]
            + bytes([2 if z else 1]) + struct.pack('<I', npulses) + data)
    return b'\x18' + struct.pack('<I', len(body)) + body

mode, src, dst = sys.argv[1:4]
out = bytearray(b'ZXTape!\x1a\x01\x14')
for blk in tap_blocks(open(src, 'rb').read()):
    out += gdb_block(blk) if mode == 'gdb' else csw_block(blk, mode == 'cswz')
open(dst, 'wb').write(out)
