"""Per-hit tom analysis of a recording: strongest spectral peaks (60..1200 Hz) in an
early (8..38 ms) and a late (60..160 ms) window, and the body band's (lowpass
1.2 kHz) time to -10/-20/-30 dB.
Usage: tomhits.py file.wav [--gap 0.25]"""
import math
import sys
sys.path.insert(0, __file__.rsplit('\\', 1)[0].rsplit('/', 1)[0])
from wavhits import read_wav, split, lp4, env, t_below

def peaks(seg, fs, t0, dur):
    i0, n = int(t0 * fs / 1000), int(dur * fs / 1000)
    s = seg[i0:i0 + n]
    if len(s) < n:
        return '-'
    w = [s[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / n)) for i in range(n)]
    mags = []
    for f in range(60, 1205, 5):
        ww = 2 * math.pi * f / fs
        mags.append((f, math.hypot(sum(v * math.cos(ww * i) for i, v in enumerate(w)),
                                   sum(v * math.sin(ww * i) for i, v in enumerate(w)))))
    top = max(m for _, m in mags) or 1
    pk = [(f, m) for k, (f, m) in enumerate(mags[1:-1], 1)
          if m > mags[k - 1][1] and m >= mags[k + 1][1] and m > 0.25 * top]
    return ' '.join('%d(%.0f)' % (f, 20 * math.log10(m / top)) for f, m in sorted(pk, key=lambda p: -p[1])[:3])

a = sys.argv[1:]
gap = float(a[a.index('--gap') + 1]) if '--gap' in a else 0.25
fs, x = read_wav(a[0])
hits = split(x, fs, gap)
print(f'{a[0]}: {len(hits)} hits')
for k, (s, e) in enumerate(hits):
    seg = x[s:e]
    lp = lp4(seg, 1200, fs)
    ev = env(lp, fs)
    pk = max(v for _, v in ev) or 1e-9
    print('  hit %d @%5.2fs  early %-28s late %-28s  t-10 %4.0f t-20 %4.0f t-30 %4.0f  peak %.2f' % (
        k, s / fs, peaks(seg, fs, 8, 30), peaks(seg, fs, 60, 100),
        t_below(ev, pk, -10), t_below(ev, pk, -20), t_below(ev, pk, -30), max(abs(v) for v in seg)))
