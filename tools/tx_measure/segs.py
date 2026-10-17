"""Analyse hits at given onset times (s) in a recording: each segment runs to the
next onset. Spectral peaks 60..1200 Hz early (8..38 ms) and late (60..160 ms), and
the body band's (lowpass 1.2 kHz) time to -10 / -20 / -30 dB, floor-limited.
Usage: segs.py file.wav t1 t2 ..."""
import math
import sys
sys.path.insert(0, __file__.rsplit('\\', 1)[0].rsplit('/', 1)[0])
from wavhits import read_wav, lp4, env, t_below
from tomhits import peaks

fs, x = read_wav(sys.argv[1])
ts = [float(t) for t in sys.argv[2:]] + [len(x) / fs]
for k in range(len(ts) - 1):
    s = int(ts[k] * fs)
    # snap to the onset: first sample above -30 dB of the segment's peak
    seg0 = x[s:int(ts[k + 1] * fs)]
    pk0 = max(abs(v) for v in seg0)
    i = next(j for j, v in enumerate(seg0) if abs(v) > pk0 * 0.03)
    seg = seg0[i:]
    lp = lp4(seg, 1200, fs)
    ev = env(lp, fs)
    pk = max(v for _, v in ev) or 1e-9
    print('  @%5.2fs  early %-26s late %-26s t-10 %4.0f t-20 %4.0f t-30 %4.0f  peak %.2f' % (
        (s + i) / fs, peaks(seg, fs, 8, 30), peaks(seg, fs, 60, 100),
        t_below(ev, pk, -10), t_below(ev, pk, -20), t_below(ev, pk, -30), pk0))
