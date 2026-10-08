"""Convert an RGBA PNG (as written by rsvg-convert) to an uncompressed 32-bit
TGA with bottom-left origin — the safest format for WoW. Stdlib only.

Usage: python3 branding/png_to_tga.py in.png out.tga
"""
import struct
import sys
import zlib


def read_png_rgba(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, w = 8, b"", None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and ctype == 6 and interlace == 0, "need 8-bit RGBA, non-interlaced"
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw, bpp, stride = zlib.decompress(idat), 4, w * 4
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        ftype, line = raw[i], bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 255
            elif ftype == 2:
                line[x] = (line[x] + b) & 255
            elif ftype == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line))
        prev = line
    return w, h, rows


def write_tga(w, h, rows, path):
    out = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8))
    for row in reversed(rows):  # bottom-left origin
        for x in range(0, len(row), 4):
            r, g, b, a = row[x:x + 4]
            out += bytes((b, g, r, a))
    open(path, "wb").write(out)


if __name__ == "__main__":
    w, h, rows = read_png_rgba(sys.argv[1])
    write_tga(w, h, rows, sys.argv[2])
    print(f"{sys.argv[2]}: {w}x{h}, {len(rows[0]) * h + 18} bytes")
