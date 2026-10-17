"""Harmonic levels of one hit of a recording: fundamental found by zero crossings in
a window, then DFT magnitude at k * f0 (k = 1..8) in dB re the fundamental.
Usage: harmonics.py file.wav HIT t0_ms dur_ms [--gap 0.25]"""
import math
import sys
sys.path.insert(0, __file__.rsplit('\\', 1)[0].rsplit('/', 1)[0])
from wavhits import read_wav, split, lp4, cycles

a = sys.argv[1:]
path, hit, t0, dur = a[0], int(a[1]), float(a[2]), float(a[3])
gap = float(a[a.index('--gap') + 1]) if '--gap' in a else 0.25
fs, x = read_wav(path)
s, e = split(x, fs, gap)[hit]
seg = x[s + int(t0 * fs / 1000): s + int((t0 + dur) * fs / 1000)]
cyc = cycles(lp4(seg, 300, fs), fs, dur)
f0 = sorted(f for _, f in cyc)[len(cyc) // 2] if cyc else 0
n = len(seg)
win = [seg[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / n)) for i in range(n)]
def mag(f):
    w = 2 * math.pi * f / fs
    return math.hypot(sum(v * math.cos(w * i) for i, v in enumerate(win)),
                      sum(v * math.sin(w * i) for i, v in enumerate(win)))
m1 = mag(f0) or 1e-12
print('%s hit %d, %g..%g ms: f0 %.1f Hz; harmonics dB re f0: %s' % (
    path.rsplit('\\', 1)[-1], hit, t0, t0 + dur, f0,
    ' '.join('%d:%.0f' % (k, 20 * math.log10(max(mag(k * f0), 1e-12) / m1)) for k in range(2, 9))))
