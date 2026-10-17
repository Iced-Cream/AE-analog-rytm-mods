"""Analyse a rendered TX note (float32, 44.1 kHz): per-cycle pitch from
upward zero crossings, and level (peak per 5 ms) in dB re the note's peak.
Usage: anal.py file.f32 [quiet]  - quiet prints one summary line."""
import struct, sys, math
FS = 44100.0

def load(path):
    raw = open(path, 'rb').read()
    return struct.unpack('<%df' % (len(raw) // 4), raw)

def analyse(x):
    n = len(x)
    peak = max(abs(v) for v in x) or 1.0
    cross = []
    for i in range(1, n):
        if x[i - 1] < 0 <= x[i]:
            cross.append(i - 1 + (-x[i - 1]) / (x[i] - x[i - 1]))
    cyc = [((a + b) / 2 / FS * 1000, FS / (b - a)) for a, b in zip(cross, cross[1:])]
    W = int(FS * 0.005)
    lev = []
    for i in range(0, n - W, W):
        lv = max(abs(v) for v in x[i:i + W])
        lev.append((i / FS * 1000, 20 * math.log10(lv / peak) if lv > 0 else -120))
    def last_above(thr):
        t = 0
        for ms, db in lev:
            if db > thr:
                t = ms + 5
        return t
    return peak, cyc, lev, last_above

if __name__ == '__main__':
    x = load(sys.argv[1])
    peak, cyc, lev, last_above = analyse(x)
    if len(sys.argv) > 2:
        f0 = cyc[0][1] if cyc else 0
        fend = [f for t, f in cyc if t > 60]
        print('peak %.3f  f_first %.1f  f_60ms+ %.1f  t-20 %.0f  t-40 %.0f  t-60 %.0f' % (
            peak, f0, (sum(fend) / len(fend)) if fend else 0, last_above(-20), last_above(-40), last_above(-60)))
        sys.exit()
    print('peak %.3f' % peak)
    print('cycles (t ms, f Hz):', ' '.join('%.0f:%.0f' % c for c in cyc[:25]))
    print('level every 10 ms:', ' '.join('%.0f' % db for ms, db in lev[::2][:30]))
    for thr in (-20, -40, -60):
        print('last above %d dB: %.0f ms' % (thr, last_above(thr)))
