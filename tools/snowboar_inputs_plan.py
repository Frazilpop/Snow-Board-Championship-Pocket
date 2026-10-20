#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Snow Board Championship (Pocket): tools/mame_snowboar_inputs.lua's INPUTS
# schedule as the harness's --inputs plan, so the two run the same ride.
#
#   python3 -I tools/snowboar_inputs_plan.py race <frames> > build/sim/race.txt
#
# One line a frame where something changes, "<frame> coin=1 start=0 ...":
# the Lua script sets frame n's inputs in MAME's notifier n, which runs after
# vblank IRQ n's handler has read the ports, so the program sees them from
# IRQ n + 1; the harness applies line m at its own vblank IRQ m, so frame n's
# inputs are written on line n + 1. (Written on line n, the harness's race ran
# a frame ahead of MAME's: its frame f was MAME's f + 1.)
import sys


def every(n, frm, to, per, on):
    return frm <= n <= to and (n - frm) % per < on


def race(n):
    return {
        "coin": int(every(n, 600, 609, 1, 1)),
        "start": int(every(n, 700, 709, 1, 1)),
        "b1": int(every(n, 900, 905, 1, 1) or every(n, 1300, 1305, 1, 1)
                  or every(n, 2000, 9000, 16, 8)),               # Run
        "right": int(every(n, 2100, 9000, 120, 40)),
        "left": int(every(n, 2160, 9000, 120, 40)),
        "b2": int(every(n, 2100, 9000, 300, 6)),
        "b3": int(every(n, 2250, 9000, 300, 6)),
    }


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("none", "race"):
        sys.exit("usage: snowboar_inputs_plan.py none|race <frames>")
    mode, frames = sys.argv[1], int(sys.argv[2])
    prev = None
    print(f"# INPUTS={mode}, tools/mame_snowboar_inputs.lua's schedule")
    for n in range(0, frames + 1):
        cur = race(n) if mode == "race" else {k: 0 for k in race(0)}
        changed = {k: v for k, v in cur.items() if prev is None or prev[k] != v}
        if changed:
            print(n + 1 if n else 0, " ".join(f"{k}={v}" for k, v in changed.items()))
        prev = cur


if __name__ == "__main__":
    main()
