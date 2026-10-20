#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Snow Board Championship (Pocket): the board's protection (the ispLSI 1016
# at 310000-31ffff) as a reference model, checked against a bus trace.
#
#   python3 -I tools/snowboar_prot.py build/mame/snowboar_bus.txt
#
# A word written anywhere in 310000-31ffff shifts into a 32-bit latch,
# latch = (latch << 16) | data; a read returns mangle(latch) with its bytes
# swapped. mangle and its three bit shuffles are transcribed from MAME's
# gaelco2_m.cpp (BSD-3-Clause, Manuel Abadia). The trace is
# mame_snowboar_bus_trace.lua's (or the harness's): every protection read in
# it is checked against the model, the latch starting at zero at power-on.
import sys

# (source bit, destination bit) for each shuffle, from MAME's masks and shifts
GET_LO = [(4, 5), (11, 14), (30, 3), (0, 6), (2, 8), (3, 11), (6, 15), (23, 0),
          (26, 10), (15, 1), (13, 2), (17, 7), (20, 12), (14, 9), (18, 13), (5, 4)]
GET_HI = [(10, 10), (12, 12), (28, 2), (25, 1), (27, 6), (1, 13), (24, 5), (29, 11),
          (31, 15), (21, 8), (16, 4), (19, 9), (9, 0), (22, 14), (7, 3), (8, 7)]
GET_OUT = [(6, 6), (11, 11), (14, 14), (15, 15), (7, 9), (2, 5), (3, 8), (4, 12),
           (1, 10), (0, 13), (9, 0), (10, 2), (12, 4), (8, 1), (13, 7), (5, 3)]


def shuffle(x, table):
    return sum(((x >> s) & 1) << d for s, d in table)


def mangle(x):
    a, b = shuffle(x, GET_LO), shuffle(x, GET_HI)
    return shuffle((((a ^ 0x0010) - (b ^ 0x0024)) & 0xffff) ^ 0x5496, GET_OUT)


def read_value(latch):
    m = mangle(latch)
    return ((m >> 8) | (m << 8)) & 0xffff


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: snowboar_prot.py TRACE")
    # every table is a permutation of 16 bits
    for t in (GET_LO, GET_HI, GET_OUT):
        assert len({d for _, d in t}) == 16 and len({s for s, _ in t}) == 16
    latch, reads, writes, bad, bytes_ = 0, 0, 0, 0, 0
    with open(sys.argv[1]) as f:
        for n, line in enumerate(f, 1):
            if line[0] == "#":
                continue
            a, rw, d, m = line.split()
            a = int(a, 16)
            if not 0x310000 <= a < 0x320000:
                continue
            d, m = int(d, 16), int(m, 16)
            if m != 0xffff:
                bytes_ += 1
            if rw == "W":
                latch = ((latch << 16) | d) & 0xffffffff
                writes += 1
            else:
                reads += 1
                want = read_value(latch)
                if want != d:
                    bad += 1
                    if bad <= 10:
                        print(f"line {n}: read {d:04x}, model {want:04x} (latch {latch:08x})")
    print(f"{writes} writes, {reads} reads, {bytes_} byte accesses: "
          + ("every read matches the model" if bad == 0 else f"{bad} reads differ"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
