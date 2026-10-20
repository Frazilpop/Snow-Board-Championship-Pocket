#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Snow Board Championship (Pocket) — after the Kaneko 16-bit core's diff_bus_trace.py
# (alphanu1), as World Rally 2 had it, with this board's map.
"""Diff the core's bus trace against MAME's.

    diff_bus_trace.py <core.txt> <mame.txt> <setname>

Both files are in tools/mame_snowboar_bus_trace.lua's format
(sim/snowboar/tb_snowboar.cpp writes the same). Exit status 0 only if the
68000's accesses match, strictly or but for IRQ placement.

Two comparisons over the same accesses:

  * every access, in order, instruction fetches included. fx68k and MAME's
    m68000 agree on the prefetch on this board, so this is the strict one;
  * every WRITE and every READ outside the program ROM, in order -- what the
    program asked for, as opposed to how the CPU fetched it. Where the first
    fails and this holds, the difference is in the fetching.

Only the lanes both sides drove are compared: a byte write has an undefined
value on the idle half of the bus.

Then the same every-access comparison again, this time picking up after a
divergence where IRQ 6 was taken at a neighbouring instruction: fx68k and
MAME's m68000 sample the interrupt at slightly different points of some
instructions, so now and then one of them takes the same IRQ an instruction
later. The streams are realigned on the next run of RESYNC_RUN identical
accesses within RESYNC_WINDOW of the divergence, and each realignment is
named: "irq entry" when an IRQ vector read (000078) is among the accesses
skipped or the few after them, "irq return" when the first difference is
the RTE reading back a stacked SR or PC that differs (the stack is in work
RAM), "other" for anything else. Only "other" fails.
"""
import sys
from collections import Counter

ROM_END = 0x100000       # snowboar_addr_decode.v: cs_rom = addr[23:20] == 0


def load(path, marks=None):
    """The accesses; with marks, a set, the index of the access after each
    '# frame N' line (the IRQ: MAME's vblank, the harness's IRQ 6 tick)."""
    out = []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) != 4:
                if marks is not None and line.startswith("# frame"):
                    marks.add(len(out))
                continue
            out.append((int(p[0], 16), p[1], int(p[2], 16), int(p[3], 16)))
    return out


def fmt(rec):
    a, rw, d, m = rec
    lane = {0xffff: "w", 0xff00: "hi", 0x00ff: "lo"}.get(m, f"{m:04x}")
    return f"{a:06x} {rw} {d:04x} .{lane}"


# gaelco2.cpp, snowboar_map -- both sets.
MAPS = {
    "snowboar": [
        (0x202890, 0x202900, "cg-1v sound 202890-2028ff"),
        (0x200000, 0x210000, "vram      200000-20ffff"),
        (0x210000, 0x212000, "palette   210000-211fff"),
        (0x212000, 0x214000, "extra ram 212000-213fff"),
        (0x218004, 0x21800a, "vregs     218004-218009"),
        (0x300000, 0x300002, "P1, ls259 300000-300001"),
        (0x300002, 0x300010, "ls259     300002-30000f"),
        (0x300010, 0x300012, "P2        300010-300011"),
        (0x300020, 0x300022, "COIN      300020-300021"),
        (0x310000, 0x320000, "protection 310000-31ffff"),
        (0xfe0000, 0xff0000, "work ram  fe0000-feffff"),
    ],
}
ALIAS = {"snowboara": "snowboar"}


def region_for(setname):
    """Return a namer for this set. Raises rather than defaulting."""
    name = ALIAS.get(setname, setname)
    if name not in MAPS:
        raise SystemExit(f"diff_bus_trace: no memory map for {setname!r}. "
                         f"Known: {', '.join(sorted(MAPS) + sorted(ALIAS))}.")
    windows = MAPS[name]

    def region(a):
        if a < ROM_END:
            return f"rom       000000-{ROM_END - 1:06x}"
        for lo, hi, n in windows:
            if lo <= a < hi:
                return n
        return f"OTHER     {a & 0xff0000:06x}"

    return region


def first_diff(a, m):
    for i in range(min(len(a), len(m))):
        aa, mm = a[i], m[i]
        if aa[0] != mm[0] or aa[1] != mm[1] or aa[3] != mm[3]:
            return i
        if (aa[2] & aa[3]) != (mm[2] & mm[3]):
            return i
    return None


def show(a, m, first):
    print(f"  {'core':<22} {'mame':<22}")
    for i in range(max(0, first - 6), min(len(a), len(m), first + 7)):
        mark = "<<" if i == first else "  "
        print(f"  {i:8d} {fmt(a[i]):<22} {fmt(m[i]):<22} {mark}")


def compare68(name, a, m):
    n = min(len(a), len(m))
    first = first_diff(a[:n], m[:n])
    print(f"\n  68000, {name}: core {len(a)}, mame {len(m)}")
    if first is None:
        print(f"  MATCH over all {n} compared accesses")
        return True
    print(f"  FIRST DIVERGENCE at access {first} of {n}")
    show(a, m, first)
    return False


RESYNC_WINDOW = 64
RESYNC_RUN = 64


def same(x, y):
    return (x[0] == y[0] and x[1] == y[1] and x[3] == y[3]
            and (x[2] & x[3]) == (y[2] & y[3]))


def compare68_resync(a, m, ma=frozenset(), mm=frozenset()):
    """ma, mm: the frame marks of each trace (load). In a data-only trace
    (BUS_TRACE_DATA_ONLY) there is no vector read; an IRQ entry is then
    known by a frame mark among the accesses skipped or just before."""
    i = j = 0
    events = []
    while i < len(a) and j < len(m):
        if same(a[i], m[j]):
            i += 1; j += 1
            continue
        found = None
        for tot in range(1, 2 * RESYNC_WINDOW + 1):
            for di in range(max(0, tot - RESYNC_WINDOW), min(RESYNC_WINDOW, tot) + 1):
                dj = tot - di
                if i + di + RESYNC_RUN > len(a) or j + dj + RESYNC_RUN > len(m):
                    continue
                if all(same(a[i + di + k], m[j + dj + k]) for k in range(RESYNC_RUN)):
                    found = (di, dj)
                    break
            if found:
                break
        if not found:
            events.append((i, j, None, None, "unrecoverable"))
            break
        di, dj = found
        # the stacking writes come before the vector read, so look a little past
        if (any(r[0] == 0x78 and r[1] == "R" for r in a[i:i + di + 8] + m[j:j + dj + 8])
                or any(k in ma for k in range(i - 4, i + di + 8))
                or any(k in mm for k in range(j - 4, j + dj + 8))):
            kind = "irq entry"
        elif a[i][1] == "R" and m[j][1] == "R" and a[i][0] == m[j][0] and 0xfe0000 <= a[i][0] < 0xff0000:
            kind = "irq return"
        else:
            kind = "other"
        events.append((i, j, di, dj, kind))
        i += di; j += dj
    kinds = Counter(e[4] for e in events)
    n = min(len(a), len(m))
    print(f"\n  68000, every access, realigning after IRQ placement: "
          f"{len(events)} realignments ({', '.join(f'{v} {k}' for k, v in sorted(kinds.items())) or 'none'})")
    bad = [e for e in events if e[4] in ("other", "unrecoverable")]
    for e in events[:12]:
        print(f"    core {e[0]:8d} mame {e[1]:8d}: {e[4]}"
              + (f", skipped {e[2]} / {e[3]}" if e[2] is not None else ""))
    if not bad:
        print(f"  MATCH to the end ({i} / {j} accesses) but for IRQ placement")
        return True
    e = bad[0]
    print(f"  FIRST DIVERGENCE NOT IRQ PLACEMENT at core {e[0]} / mame {e[1]} ({e[4]})")
    k = e[0] - e[1]
    print(f"  {'core':<31} {'mame':<22}")
    for q in range(max(0, e[1] - 6), min(len(m), e[1] + 7)):
        fa = fmt(a[q + k]) if 0 <= q + k < len(a) else ""
        print(f"  {q + k:8d} {fa:<22} {fmt(m[q]):<22} {'<<' if q == e[1] else ''}")
    return False


def main():
    if len(sys.argv) < 4:
        print("usage: diff_bus_trace.py <core.txt> <mame.txt> <setname>", file=sys.stderr)
        return 2
    region = region_for(sys.argv[3])
    marks_o, marks_m = set(), set()
    core, mame = load(sys.argv[1], marks_o), load(sys.argv[2], marks_m)
    if not core or not mame:
        print(f"empty trace: core={len(core)} mame={len(mame)}", file=sys.stderr)
        return 2

    ok = compare68("every access", core, mame)

    def keep(r):
        return r[1] == "W" or r[0] >= ROM_END
    ok_data = compare68("writes and data reads",
                        [r for r in core if keep(r)], [r for r in mame if keep(r)])
    ok_irq = compare68_resync(core, mame, marks_o, marks_m)

    # Census: a region on one side only is the core and the driver
    # disagreeing about the map, not about behaviour.
    ca = Counter(region(r[0]) for r in core)
    cm = Counter(region(r[0]) for r in mame)
    print("\n  region                          core      mame")
    for k in sorted(set(ca) | set(cm)):
        flag = "  <- one side only" if (k not in ca) != (k not in cm) else ""
        print(f"  {k:<28} {ca.get(k, 0):8d}  {cm.get(k, 0):8d}{flag}")

    # strict match, or a match but for IRQ placement: 0; anything else: 1
    return 0 if (ok or ok_irq) else 1


if __name__ == "__main__":
    sys.exit(main())
