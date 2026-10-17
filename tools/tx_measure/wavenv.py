"""Coarse level envelope of a WAV: peak per 50 ms window in dB re file peak, as text."""
import math
import sys
sys.path.insert(0, __file__.rsplit('\\', 1)[0].rsplit('/', 1)[0])
from wavhits import read_wav

fs, x = read_wav(sys.argv[1])
W = int(fs * 0.05)
pk = max(abs(v) for v in x) or 1
row = []
for i in range(0, len(x) - W, W):
    v = max(abs(s) for s in x[i:i + W])
    row.append(20 * math.log10(v / pk) if v > 0 else -120)
print(f'{sys.argv[1]}: {fs} Hz, {len(x) / fs:.2f} s; dB per 50 ms, 20 per line (1 s)')
for k in range(0, len(row), 20):
    print('%5.1fs ' % (k * 0.05) + ' '.join('%4.0f' % v for v in row[k:k + 20]))
