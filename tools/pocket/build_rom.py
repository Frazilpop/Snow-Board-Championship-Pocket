#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Snow Board Championship for the Analogue Pocket — the ROM image builder.
"""Build the Pocket's SDRAM image (<set>.rom) for Snow Board Championship from MAME zips.

    python3 -I tools/pocket/build_rom.py snowboar ~/Downloads build/pocket
    python3 -I tools/pocket/build_rom.py all      ~/Downloads build/pocket
    python3 -I tools/pocket/build_rom.py snowboar ~/Downloads build/roms --regions

THE CONTRACT is the SDRAM layout in LAYOUT below. One file per set,
0x1200000 bytes, every part at its fixed base, every gap zero. The Pocket
loads the file at bridge address 0 and the shell writes byte n to SDRAM
byte n; SDRAM word w is {byte[2w+1], byte[2w]}.

  maincpu  0x0000000  0x100000  68000 program, MAME's region as it is: byte 0
                                is the high byte of the first word
  (zero)   0x0100000  0x100000
  gfx      0x0200000  0x1000000 MAME's 20 MB gfx region (graphics and samples)
                                rewritten as 64-bit fetch lines, below

FETCH LINES. The gfx region is five 4 MB planes (tilelayout16, RGN_FRAC(1,5):
plane p of the 5 bpp pixel at p * 4 MB, p = 0 the least significant bit).
Within a plane, byte o = t*32 + h*16 + r is tile t, row r, left (h = 0) or
right (h = 1) eight pixels. The graphics fill only the lower 2 MB of each
plane (tiles 0-65535); the upper 2 MB of planes 0 and 1 hold the CG-1V's
samples (its banks are planes 0 and 1) and those of planes 2-4 are empty.
The image keeps one 8-byte line per o < 2 MB:

    SDRAM byte 0x200000 + 8*o + p  =  gfx[p * 0x400000 + o]              (p = 0..4)
    SDRAM byte 0x200000 + 8*o + 5  =  gfx[0x000000 + 0x200000 + o]       plane 0, upper half
    SDRAM byte 0x200000 + 8*o + 6  =  gfx[0x400000 + 0x200000 + o]       plane 1, upper half
    SDRAM byte 0x200000 + 8*o + 7  =  0

so one 64-bit read is the five planes of an 8-pixel run (plane p in bits
[8p+7:8p] of the line), and a sample byte at gfx offset G (plane G >> 22,
o = G & 0x3fffff) is byte p of line o when o < 0x200000, byte 5 + p of line
o & 0x1fffff when o >= 0x200000 and p <= 1. Every other byte of the region
is zero in MAME (verify_rom.py checks it), so nothing the board can name is
missing from the image.

snowboara: four mask ROMs where snowboar has 24 EPROMs. init_snowboara
(gaelco2_m.cpp) splits ic44, ic45 and ic46 into even and odd bytes
(ROM16_split_gfx) and ic43 loads at 0x1000000; this builder does the same,
so the image holds the gfx region MAME's driver init leaves.

FILES ARE FOUND BY CRC32, NOT BY NAME OR PATH. A merged snowboar.zip keeps
snowboara's own files under snowboara/; a split set keeps them in its own
zip. Every zip in ZIPDIR is indexed (central directory only, nothing
decompressed until needed), the set's own zip and its parent's are
preferred, and a directory ZIPDIR/<set>/ of loose files is accepted too.
Size and CRC pick the file; zipfile re-checks the CRC as it decompresses,
and the SHA1 is checked against MAME's before anything is written.

--regions writes OUTDIR/<set>_<region>.bin for MAME's two regions (maincpu,
gfx) at MAME's sizes, for the Verilator harness.

This reads ROMs named on the command line and writes only where told —
build/ by convention, which is gitignored. No ROM data is in this file.
"""

import argparse
import hashlib
import os
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

# --------------------------------------------------------------------- layout
# (region, base, slot size). gfx's slot holds the fetch lines, not the region.
LAYOUT = [
    ("maincpu", 0x0000000, 0x0100000),
    ("gfx",     0x0200000, 0x1000000),
]
IMAGE_SIZE = 0x1200000
GFX_SIZE = 0x1400000          # MAME's region
PLANE = 0x0400000             # one bit plane of the gfx region
HALF = 0x0200000              # the graphics half of a plane: tiles 0-65535
PLANES = 5
LINE = 8                      # bytes per fetch line
SAMPLE_BYTES = {5: 0, 6: 1}   # line byte -> the plane whose upper half it holds

# ------------------------------------------------------------------ ROM_START
# Transcribed from MAME's gaelco2.cpp, ROM_START( snowboar ) and
# ( snowboara ), in source order within each region. The plds region is left
# out: it is not on the board's buses.
#
#   ("L", name, crc, sha1, offset, length)   ROM_LOAD
#   ("B", name, crc, sha1, offset, length)   ROM_LOAD16_BYTE: byte k -> offset+2k
#   ("F", offset, length, value)             ROM_FILL
#   ("S", name, crc, sha1, length, dest1, dest2)
#        a gfx_temp ROM split as init_snowboara's ROM16_split_gfx does: its
#        even bytes to dest1.., its odd bytes to dest2..
#
# Region: (size, ops). Every region here has flag 0 and the image starts
# each from zeros; snowboara's gfx has two 2 MB stretches nothing loads
# (0xa00000, 0xe00000), ROM_FILL 0 on snowboar, and verify_rom.py reports
# what MAME holds there.


def L(n, c, h, o, s): return ("L", n, c, h, o, s)
def B(n, c, h, o, s): return ("B", n, c, h, o, s)
def F(o, s, v): return ("F", o, s, v)
def S(n, c, h, s, d1, d2): return ("S", n, c, h, s, d1, d2)


def _program(even, odd):
    return (0x100000, [B(*even, 0x000000, 0x080000), B(*odd, 0x000001, 0x080000)])


def _eproms(plane, roms):
    """Four or six 512 KB EPROMs loaded end to end from the start of a plane."""
    return [L(*r, plane * PLANE + k * 0x080000, 0x080000) for k, r in enumerate(roms)]


SETS = {
    # version 2.1, 20 Mar 1997 ("DEMO STICK" at Gaelco). The parent.
    "snowboar": {"parent": None, "regions": {
        "maincpu": _program(
            ("sb.53", 0x4742749e, "933e39893ab74895ae4a99a932f8245a03ea0b5d"),
            ("sb.55", 0x6ddc431f, "8801c0cf1711bb956447ba1e631db28bd075caea")),
        "gfx": (GFX_SIZE,
            _eproms(0, [
                ("sb.a0", 0xaa476e44, "2b87689489b9619e9e5ca32c3e3d2aec8ef31c88"),
                ("sb.a1", 0x6bc99195, "276e9383fac9cb5141b23ffdf381b0d7e60a6861"),
                ("sb.a2", 0xfae2ebba, "653a12846abe4de36f5565c3bf849fce7c2893b6"),
                ("sb.a3", 0x17ed9cf8, "c6cab61bbba3b2b1d06b64a68313946299205cc5"),
                ("sb.a4", 0x2ba3a5c8, "93de0382cbb41806ae3349ce7cfecdc1404bfb88"),     # sound
                ("sb.a5", 0xae011eb3, "17223404640c55637364fa6e51cf07d8e64df085")])    # sound
            + [F(0x0300000, 0x0100000, 0)]
            + _eproms(1, [
                ("sb.b0", 0x96c714cd, "c6225c43b88531a70436cc8a631b8ba401903e45"),
                ("sb.b1", 0x39a4c30c, "4598a68ef41483ba372aa3a40383de8eb70d706e"),
                ("sb.b2", 0xb58fcdd6, "21a8c00778be77165f89421fb2e3123244cf02c6"),
                ("sb.b3", 0x96afdebf, "880cfb365efa93bbee882aeb483ad6d75d8b7430"),
                ("sb.b4", 0xe62cf8df, "8df8df45d99967e52dcec5b589246799f7a39601"),     # sound
                ("sb.b5", 0xcaa90856, "a8f18a878b211366faaf66911c09d0452770cc3f")])    # sound
            + [F(0x0700000, 0x0100000, 0)]
            + _eproms(2, [
                ("sb.c0", 0xc9d57a71, "4e8b7d821e31afc0750db283470f9c76bceb54da"),
                ("sb.c1", 0x1d14a3d4, "eb89cadfe331f77dbc0463151574ba801c248238"),
                ("sb.c2", 0x55026352, "7b92f45624dbd122c29e44f82c3c2ffded190efa"),
                ("sb.c3", 0xd9b62dee, "409ab4d9a6f9341cf59510c130c705d1ec42d1b3")])
            + [F(0x0a00000, 0x0200000, 0)]
            + _eproms(3, [
                ("sb.d0", 0x7434c1ae, "8e0e6567a461c694a8ba2de5d4cf9ad73e0c83c8"),
                ("sb.d1", 0xf00cc6c8, "b4835e2187e1a985993471d09495cbc1f5cd9417"),
                ("sb.d2", 0x019f9aec, "1a97b84ebbf57e860792ef7a7dc6f51553ae3e26"),
                ("sb.d3", 0xd05bd286, "9eff6f5a4755375b7a16b9d4967a0df933e1b9c4")])
            + [F(0x0e00000, 0x0200000, 0)]
            + _eproms(4, [
                ("sb.e0", 0xe6195323, "5ba1cb750dd8cfd0721905174bda6cfbf8c8e694"),
                ("sb.e1", 0x9f38910b, "0243c19c7b1bdd3361fc6e177c64528bacafcc33"),
                ("sb.e2", 0xf5948c6c, "91bba817ced194b02885ce84b7a8132ef5ca631a"),
                ("sb.e3", 0x4baa678f, "a7fbbd687e2d8d7e96207c8ace0799a3cc9c3272")])
            + [F(0x1200000, 0x0200000, 0)])}},
    # version 2.0, 1996, mask ROM board.
    "snowboara": {"parent": "snowboar", "regions": {
        "maincpu": _program(
            ("sb_53.ic53", 0xe4eaefd4, "c7de2ae3a4a919fbe16d4997e3f9e2303b8c96b1"),
            ("sb_55.ic55", 0xe2476994, "2ad18652a1fc6ac058c8399373fb77e7a81d5bbd")),
        "gfx": (GFX_SIZE, [
            L("sb_ic43.ic43", 0xafce54ed, "1d2933d64790612918adbaabcd2a82dad79953c9",
              0x1000000, 0x0200000),
            F(0x1200000, 0x0200000, 0),
            S("sb_ic44.ic44", 0x1bbe88bc, "15bce9ada2b742ba4d537fa8efc0f29f661bff00",
              0x0400000, 0x0000000, 0x0400000),
            S("sb_ic45.ic45", 0x373983d9, "05e35a8b27cab469885f0ec2a5df200a366b50a1",    # sound
              0x0400000, 0x0200000, 0x0600000),
            S("sb_ic46.ic46", 0x22e7c648, "baddb9bc13accd83bea61533d7286cf61cd89279",
              0x0400000, 0x0800000, 0x0c00000),
        ])}},
}
REGION_ORDER = ["maincpu", "gfx"]
# MAME's tag for each region, for the region dump and verify_rom.py.
MAME_REGION = {"maincpu": ":maincpu", "gfx": ":gfx"}


# --------------------------------------------------------------- ROM finding
class RomIndex:
    """Every ROM file under ZIPDIR, keyed by (size, crc32).

    Zips: the central directory gives both without decompressing anything.
    Loose files: only under ZIPDIR/<set>/ for the sets asked about (and their
    parents), hashed on demand — a whole Downloads folder is not read.
    """

    def __init__(self, zipdir):
        self.zipdir = zipdir
        self.entries = {}        # (size, crc) -> [(stem, kind, path, member)]
        self._loose_done = set()
        for name in sorted(os.listdir(zipdir)):
            path = os.path.join(zipdir, name)
            if name.lower().endswith(".zip") and os.path.isfile(path):
                try:
                    zf = zipfile.ZipFile(path)
                except (zipfile.BadZipFile, OSError):
                    continue
                stem = os.path.splitext(name)[0]
                for info in zf.infolist():
                    if info.is_dir():
                        continue
                    self.entries.setdefault((info.file_size, info.CRC), []).append(
                        (stem, "zip", path, info.filename))
                zf.close()

    def _add_loose(self, setname):
        if setname in self._loose_done:
            return
        self._loose_done.add(setname)
        d = os.path.join(self.zipdir, setname)
        if not os.path.isdir(d):
            return
        for root, _, files in os.walk(d):
            for f in files:
                p = os.path.join(root, f)
                with open(p, "rb") as fh:
                    data = fh.read()
                self.entries.setdefault((len(data), zlib.crc32(data)), []).append(
                    (setname, "file", p, None))

    def find(self, size, crc, prefer):
        for s in prefer:
            self._add_loose(s)
        cands = self.entries.get((size, crc), [])
        if not cands:
            return None
        rank = {s: i for i, s in enumerate(prefer)}
        return sorted(cands, key=lambda c: (rank.get(c[0], len(prefer)), c[0]))[0]

    def read(self, size, crc, sha1, prefer, name):
        hit = self.find(size, crc, prefer)
        if hit is None:
            raise SystemExit(f"missing ROM {name} (size {size:#x}, crc {crc:08x}) "
                             f"in {self.zipdir}: looked in every zip, preferring "
                             f"{', '.join(p + '.zip' for p in prefer)}")
        _, kind, path, member = hit
        if kind == "zip":
            with zipfile.ZipFile(path) as zf:
                data = zf.read(member)      # zipfile checks the CRC as it reads
        else:
            with open(path, "rb") as fh:
                data = fh.read()
        where = f"{os.path.basename(path)}:{member}" if member else path
        if len(data) != size or zlib.crc32(data) != crc:
            raise SystemExit(f"{name}: {where} does not match its CRC")
        if hashlib.sha1(data).hexdigest() != sha1:
            raise SystemExit(f"{name}: {where} has MAME's CRC but not its SHA1")
        return data, where


# ------------------------------------------------------------- region build
def build_regions(setname, index, log=print):
    """MAME's regions for a set, as its ROM_START and driver init leave them."""
    spec = SETS[setname]
    prefer = [setname] + ([spec["parent"]] if spec["parent"] else [])
    out = {}
    for rname in REGION_ORDER:
        size, ops = spec["regions"][rname]
        buf = bytearray(size)
        for op in ops:
            kind = op[0]
            if kind == "F":
                _, off, n, v = op
                buf[off:off + n] = bytes([v]) * n
                log(f"    {rname:<8} {off:#09x} ROM_FILL {v:#04x} len {n:#x}")
                continue
            if kind == "S":
                _, name, crc, sha1, length, d1, d2 = op
                data, where = index.read(length, crc, sha1, prefer, name)
                half = length // 2
                if max(d1, d2) + half > size:
                    raise SystemExit(f"{setname}:{rname}: {name} overruns the region")
                buf[d1:d1 + half] = data[0::2]
                buf[d2:d2 + half] = data[1::2]
                log(f"    {rname:<8} {d1:#09x}/{d2:#09x} split {name:<20} {crc:08x} <- {where}")
                continue
            _, name, crc, sha1, off, length = op
            data, where = index.read(length, crc, sha1, prefer, name)
            if kind == "L":
                if off + length > size:
                    raise SystemExit(f"{setname}:{rname}: {name} overruns the region")
                buf[off:off + length] = data
            elif kind == "B":
                if off + 2 * length - 1 > size:
                    raise SystemExit(f"{setname}:{rname}: {name} overruns the region")
                buf[off:off + 2 * length - 1:2] = data
            else:
                raise AssertionError(kind)
            log(f"    {rname:<8} {off:#09x} {kind} {name:<20} {crc:08x} <- {where}")
        out[rname] = bytes(buf)
    return out


def gfx_lines(gfx):
    """The 20 MB gfx region as 2M fetch lines of 8 bytes (16 MB)."""
    if len(gfx) != GFX_SIZE:
        raise SystemExit(f"gfx is {len(gfx):#x}, expected {GFX_SIZE:#x}")
    out = bytearray(HALF * LINE)
    for p in range(PLANES):
        out[p::LINE] = gfx[p * PLANE:p * PLANE + HALF]
    for k, p in SAMPLE_BYTES.items():
        out[k::LINE] = gfx[p * PLANE + HALF:(p + 1) * PLANE]
    return bytes(out)


def gfx_from_lines(lines):
    """The inverse: MAME's gfx region from the fetch lines (for verify_rom.py);
    the upper halves of planes 2-4 come back zero."""
    upper = {p: lines[k::LINE] for k, p in SAMPLE_BYTES.items()}
    return b"".join(lines[p::LINE] + upper.get(p, bytes(HALF)) for p in range(PLANES))


def build_image(regions):
    img = bytearray(IMAGE_SIZE)
    parts = dict(regions, gfx=gfx_lines(regions["gfx"]))
    for rname, base, slot in LAYOUT:
        data = parts[rname]
        if len(data) > slot:
            raise SystemExit(f"{rname} is {len(data):#x}, over its {slot:#x} slot")
        img[base:base + len(data)] = data
    return bytes(img)


# -------------------------------------------------------------------- main
def expand_sets(arg):
    if arg == "all":
        return list(SETS)
    names = arg.split(",")
    for n in names:
        if n not in SETS:
            raise SystemExit(f"unknown set {n!r}; known: {', '.join(SETS)}")
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("set", help="set name, comma list, or 'all'")
    ap.add_argument("zipdir", help="directory holding the MAME zips")
    ap.add_argument("outdir", help="output directory (keep it under build/)")
    ap.add_argument("--regions", action="store_true",
                    help="write <set>_<region>.bin per MAME region instead of <set>.rom")
    ap.add_argument("-q", "--quiet", action="store_true")
    a = ap.parse_args()

    index = RomIndex(os.path.expanduser(a.zipdir))
    os.makedirs(a.outdir, exist_ok=True)
    log = (lambda *x: None) if a.quiet else print
    for s in expand_sets(a.set):
        print(f"{s}:")
        regions = build_regions(s, index, log)
        if a.regions:
            for rname in REGION_ORDER:
                p = os.path.join(a.outdir, f"{s}_{rname}.bin")
                with open(p, "wb") as f:
                    f.write(regions[rname])
                print(f"  {p}  {len(regions[rname]):#x}")
        else:
            img = build_image(regions)
            p = os.path.join(a.outdir, f"{s}.rom")
            with open(p, "wb") as f:
                f.write(img)
            print(f"  {p}  {len(img)} bytes  sha1 {hashlib.sha1(img).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
