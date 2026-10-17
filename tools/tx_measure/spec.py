"""Spectral peaks of a rendered note: DFT magnitude 40..2000 Hz in 5 Hz steps,
over a window [t0, t0+dur) ms (Hann). Prints the strongest local maxima."""
import struct, sys, math
FS = 44100.0
raw = open(sys.argv[1], 'rb').read()
x = struct.unpack('<%df' % (len(raw) // 4), raw)
t0 = float(sys.argv[2]) if len(sys.argv) > 2 else 0
dur = float(sys.argv[3]) if len(sys.argv) > 3 else 50
i0, n = int(t0 * FS / 1000), int(dur * FS / 1000)
seg = [x[i0 + i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / n)) for i in range(n)]
mags = []
for f in range(40, 2005, 5):
    w = 2 * math.pi * f / FS
    re = sum(v * math.cos(w * i) for i, v in enumerate(seg))
    im = sum(v * math.sin(w * i) for i, v in enumerate(seg))
    mags.append((f, math.hypot(re, im)))
top = max(m for _, m in mags) or 1
peaks = [(f, m) for k, (f, m) in enumerate(mags[1:-1], 1) if m > mags[k-1][1] and m >= mags[k+1][1] and m > 0.2 * top]
print('window %g..%g ms peaks:' % (t0, t0 + dur), ' '.join('%d Hz(%.0f dB)' % (f, 20 * math.log10(m / top)) for f, m in sorted(peaks, key=lambda p: -p[1])[:6]))
