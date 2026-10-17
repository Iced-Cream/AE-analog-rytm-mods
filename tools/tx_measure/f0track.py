"""Pitch track of hits at given onset times (s): autocorrelation f0 (30..600 Hz) of
the 1.2 kHz-lowpassed signal in 80 ms windows at fixed offsets after each onset,
plus the body band's level (dB re peak) there.
Usage: f0track.py file.wav t1 t2 ..."""
import math
import sys
sys.path.insert(0, __file__.rsplit('\\', 1)[0].rsplit('/', 1)[0])
from wavhits import read_wav, lp4

OFFS = (5, 20, 40, 80, 150, 300, 600)
WIN = 0.080

def f0(s, fs):
    n = len(s)
    e0 = sum(v * v for v in s) or 1e-12
    best, bl = 0, 0
    lo, hi = int(fs / 600), min(int(fs / 30), n // 2)
    r = [0.0] * (hi + 2)
    for lag in range(lo, min(hi + 2, n - 1)):
        r[lag] = sum(s[i] * s[i + lag] for i in range(0, n - lag, 2)) * 2 / e0 * n / (n - lag)
    # first strong maximum (avoid octave-down picks)
    top = max(r[lo:hi + 1])
    for lag in range(lo + 1, hi + 1):
        if r[lag] >= r[lag - 1] and r[lag] >= r[lag + 1] and r[lag] > 0.8 * top:
            a, b, c = r[lag - 1], r[lag], r[lag + 1]
            d = 0.5 * (a - c) / (a - 2 * b + c) if a - 2 * b + c else 0
            return fs / (lag + d), b
    return 0, 0

fs, x = read_wav(sys.argv[1])
ts = [float(t) for t in sys.argv[2:]] + [len(x) / fs]
print('            ' + ''.join('%11dms' % o for o in OFFS))
for k in range(len(ts) - 1):
    seg0 = x[int(ts[k] * fs):int(ts[k + 1] * fs)]
    pk0 = max(abs(v) for v in seg0)
    i = next(j for j, v in enumerate(seg0) if abs(v) > pk0 * 0.03)
    lp = lp4(seg0[i:], 1200, fs)
    w = int(WIN * fs)
    pk = max(abs(v) for v in lp) or 1e-9
    row = []
    for o in OFFS:
        s = lp[int(o * fs / 1000):int(o * fs / 1000) + w]
        if len(s) < w:
            row.append('%13s' % '-')
            continue
        f, c = f0(s, fs)
        lv = 20 * math.log10((max(abs(v) for v in s) or 1e-9) / pk)
        row.append('%6.1f/%4.0fdB' % (f, lv) if c > 0.3 and lv > -45 else '%13s' % ('.. %3.0fdB' % lv))
    print('  @%6.2fs ' % (ts[k] + i / fs) + ''.join(row))
