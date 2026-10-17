"""Two-band analysis of a rendered snare/tom (float32, 44.1 kHz).
body: 4th-order lowpass ~900 Hz -> pitch (zero crossings) and level envelope
noise: 4th-order highpass ~3 kHz -> level envelope
Prints one line: body f at 3/10/40 ms, body t-20/t-40 (ms), noise peak re body
peak (dB), noise t-20/t-40."""
import struct, sys, math
FS = 44100.0
raw = open(sys.argv[1], 'rb').read()
x = list(struct.unpack('<%df' % (len(raw) // 4), raw))

def onepole_lp(sig, fc):
    a = math.exp(-2 * math.pi * fc / FS)
    y, o = 0.0, []
    for v in sig:
        y = (1 - a) * v + a * y
        o.append(y)
    return o

lp = x
for _ in range(4):
    lp = onepole_lp(lp, 900)
hp = x
for _ in range(4):
    l = onepole_lp(hp, 3000)
    hp = [a - b for a, b in zip(hp, l)]

def env(sig):
    W = int(FS * 0.005)
    return [(i / FS * 1000, max(abs(v) for v in sig[i:i + W])) for i in range(0, len(sig) - W, W)]

def tdrop(e, ref, thr):
    t = 0
    for ms, v in e:
        if v > 0 and 20 * math.log10(v / ref) > thr:
            t = ms + 5
    return t

eb, en = env(lp), env(hp)
pb = max(v for _, v in eb) or 1e-9
pn = max(v for _, v in en) or 1e-9
cross = [i - 1 + (-lp[i - 1]) / (lp[i] - lp[i - 1]) for i in range(1, len(lp)) if lp[i - 1] < 0 <= lp[i]]
def f_at(ms):
    c = [t for t in cross if ms * FS / 1000 <= t < (ms + 8) * FS / 1000]
    if len(c) < 2:
        c = [t for t in cross if t >= ms * FS / 1000][:2]
    return FS * (len(c) - 1) / (c[-1] - c[0]) if len(c) >= 2 else 0
print('body f %5.0f %5.0f %5.0f Hz | body t-20 %4.0f t-40 %4.0f | noise %+5.1f dB t-20 %4.0f t-40 %4.0f | peak %.2f' % (
    f_at(1), f_at(10), f_at(40), tdrop(eb, pb, -20), tdrop(eb, pb, -40),
    20 * math.log10(pn / pb), tdrop(en, pn, -20), tdrop(en, pn, -40), max(abs(v) for v in x)))
