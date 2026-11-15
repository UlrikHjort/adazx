# Print the runs of dark rows in one column of a PNG written by AdaZX:
#   python3 png_runs.py image.png X   ->  "start:length" for each run
#   python3 png_runs.py image.png row Y  (along a row)
#   python3 png_runs.py image.png pixel X Y  ->  RRGGBB
import struct, sys, zlib

rgb = []

def read_png(path):
    d = open(path, 'rb').read()
    i = 8
    idat = b''
    while i < len(d):
        n = struct.unpack('>I', d[i:i + 4])[0]
        kind = d[i + 4:i + 8]
        c = d[i + 8:i + 8 + n]
        if kind == b'IHDR':
            w, h, _, ct = struct.unpack('>IIBB', c[:10])
        elif kind == b'IDAT':
            idat += c
        i += 12 + n
    raw = zlib.decompress(idat)
    bpp = {2: 3, 6: 4}[ct]
    stride = w * bpp
    rows, prev, p = [], bytearray(stride), 0
    rgb.clear()
    for _ in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                q = a + b - c
                pa, pb, pc = abs(q - a), abs(q - b), abs(q - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc
                                      else b if pb <= pc else c)) & 255
        rows.append([line[x * bpp] for x in range(w)])
        rgb.append([(line[x * bpp] << 16) | (line[x * bpp + 1] << 8)
                    | line[x * bpp + 2] for x in range(w)])
        prev = line
    return rows

rows = read_png(sys.argv[1])
if sys.argv[2] == 'pixel':               # the colour at X Y, as RRGGBB
    print('%06X' % rgb[int(sys.argv[4])][int(sys.argv[3])])
    sys.exit(0)
if sys.argv[2] == 'row':                 # runs along row Y instead
    line = rows[int(sys.argv[3])] + [255]
    cells = [[v] for v in line]
    x = 0
else:
    x = int(sys.argv[2])
    cells = rows + [[255] * len(rows[0])]
runs, start = [], None
for y, r in enumerate(cells):
    dark = r[x] < 128
    if dark and start is None:
        start = y
    elif not dark and start is not None:
        runs.append('%d:%d' % (start, y - start))
        start = None
print(' '.join(runs))
