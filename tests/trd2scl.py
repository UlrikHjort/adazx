# Convert a TR-DOS .trd disc image into an .scl archive (for the tests):
#   python3 trd2scl.py disc.trd archive.scl
import sys
d = open(sys.argv[1], 'rb').read()
headers, data = [], b''
for k in range(128):
    e = d[k * 16:k * 16 + 16]
    if e[0] == 0:
        break
    if e[0] == 1:                       # deleted
        continue
    sectors, sec, trk = e[13], e[14], e[15]
    start = (trk * 16 + sec) * 256
    headers.append(e[:14])
    data += d[start:start + sectors * 256]
out = b'SINCLAIR' + bytes([len(headers)]) + b''.join(headers) + data
out += (sum(out) & 0xFFFFFFFF).to_bytes(4, 'little')
open(sys.argv[2], 'wb').write(out)
