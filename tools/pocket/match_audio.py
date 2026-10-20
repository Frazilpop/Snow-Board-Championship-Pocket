#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Snow Board Championship (Pocket) — compare the harness's CG-1V output with
# MAME's -wavwrite (World Rally 2's), standard library only.
"""Compare the board's sound with MAME's.

    match_audio.py CORE.s16 MAME.wav [--from SECONDS] [--to SECONDS] [--lags N]
                   [--rate HZ]

CORE.s16 is sim/snowboar/tb_snowboar's --audio: the CG-1V's samples from
release (MAME's power-on), signed 16-bit pairs, its first output then its
second; --rate is theirs, 7812 (default: MAME's stream rate, which the
harness keeps) or 7812.5 (the chip's own, a PIX=pocket build). MAME.wav is -wavwrite's, at its own output rate, with
MAME's speaker routing (gaelco2.cpp snowboar(): the CG-1V's first output to
the left channel, its second to the right), so the core's are paired that way.

MAME resamples its 7812 Hz stream to its output rate, and its WAV is not
in step with emulated time (under -nothrottle it can drop a frame's worth),
so the two are not compared sample for sample. With -samplerate 7812 the
WAV is the stream itself, and "same" counts the samples of each second
equal to MAME's, unsmoothed, at the lag found. MAME's channel is averaged
over each CG-1V sample period (128 us), both are smoothed over four samples,
and each second is scored at the lag (within +-N samples, default 200)
where they agree best: the correlation and both levels. The same sound at
the same level reads a correlation near 1 and equal levels.
"""
import math
import struct
import sys
import wave

RATE = 7812.0


def read_core(path):
    d = open(path, "rb").read()
    n = len(d) // 4
    v = struct.unpack("<%dh" % (2 * n), d[:4 * n])
    return list(v[0::2]), list(v[1::2])


def read_mame(path):
    w = wave.open(path)
    assert w.getsampwidth() == 2, "16-bit WAV expected"
    ch, rate, n = w.getnchannels(), w.getframerate(), w.getnframes()
    v = struct.unpack("<%dh" % (n * ch), w.readframes(n))
    return [list(v[c::ch]) for c in range(ch)], rate


def decimate(x, rate, count):
    """MAME's channel averaged over each 128 us CG-1V period."""
    out = []
    step = rate / RATE
    for k in range(count):
        a, b = int(round(k * step)), int(round((k + 1) * step))
        seg = x[a:b]
        out.append(sum(seg) / len(seg) if seg else 0.0)
    return out


def smooth(x, w=4):
    out, acc = [], 0.0
    for i, v in enumerate(x):
        acc += v
        if i >= w:
            acc -= x[i - w]
        out.append(acc / w)
    return out


def best_lag(o, m, lo, hi, lags):
    best = (-2.0, 0, 0.0, 0.0)
    for lag in range(-lags, lags + 1):
        if lo + lag < 0 or hi + lag > len(m):
            continue
        sxy = sxx = syy = 0.0
        for k in range(lo, hi, 2):
            x, y = o[k], m[k + lag]
            sxy += x * y; sxx += x * x; syy += y * y
        if sxx == 0 or syy == 0:
            continue
        r = sxy / math.sqrt(sxx * syy)
        if r > best[0]:
            best = (r, lag, math.sqrt(2 * sxx / (hi - lo)), math.sqrt(2 * syy / (hi - lo)))
    return best


def main(argv):
    args, opts, i = [], {}, 1
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            opts[argv[i]] = argv[i + 1]; i += 2
        else:
            args.append(argv[i]); i += 1
    if len(args) < 2:
        print(__doc__)
        return 2
    global RATE
    RATE = float(opts.get("--rate", "7812"))
    ol, orr = read_core(args[0])
    (mch, rate) = read_mame(args[1])
    lags = int(opts.get("--lags", "200"))
    count = min(len(ol), int(len(mch[0]) / rate * RATE))
    t0 = float(opts.get("--from", "0"))
    t1 = min(float(opts.get("--to", str(count / RATE))), (count - lags) / RATE)
    print(f"core {len(ol)} samples ({len(ol) / RATE:.3f} s), MAME {len(mch[0])} at {rate} Hz"
          f" ({len(mch[0]) / rate:.3f} s)")
    left, right = (mch[0], mch[1]) if len(mch) == 2 else (mch[0], mch[0])
    same_rate = rate == RATE
    pairs = [("first/left", smooth(ol), smooth(decimate(left, rate, count)), ol, left),
             ("second/right", smooth(orr), smooth(decimate(right, rate, count)), orr, right)]
    sec = int(t0)
    while sec + 1 <= t1:
        lo, hi = int(sec * RATE), int((sec + 1) * RATE)
        row = [f"{sec:3d} s"]
        for name, o, m, raw_o, raw_m in pairs:
            r, lag, rms_o, rms_m = best_lag(o, m, lo, hi, lags)
            if rms_o == 0 and rms_m == 0:
                row.append(f"{name} silent on both".ljust(52))
            else:
                row.append(f"{name} corr {r:6.3f} lag {lag:+4d} rms {rms_o:6.0f} / {rms_m:6.0f}")
                if same_rate:
                    same = sum(1 for k in range(lo, hi) if raw_o[k] == raw_m[k + lag])
                    row[-1] += f" same {100 * same / (hi - lo):5.1f}%"
        print("  ".join(row))
        sec += 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
