"""Split a recording into hits and analyse each one.

Reads a WAV (PCM 16/24/32-bit or float32, any rate, mono or stereo -> left+right
mixed), finds hits separated by silence, and prints per hit:
  kick mode  (default): pitch per cycle (4th-order lowpass 300 Hz), level, time
             to -20/-40/-60 dB
  snare mode (--snare): body band (< 900 Hz) pitch and decay, noise band
             (> 3 kHz) level re body and decay, and the noise band's spectral
             centroid
Usage: wavhits.py file.wav [--snare] [--gap 0.4] [--dump N out.f32]
"""
import math
import struct
import sys


def read_wav(path):
    b = open(path, 'rb').read()
    if b[:4] != b'RIFF' or b[8:12] != b'WAVE':
        raise SystemExit('not a WAV file')
    i, fmt, data = 12, None, None
    while i + 8 <= len(b):
        cid, size = b[i:i + 4], struct.unpack('<I', b[i + 4:i + 8])[0]
        body = b[i + 8:i + 8 + size]
        if cid == b'fmt ':
            fmt = struct.unpack('<HHIIHH', body[:16])
            if fmt[0] == 0xFFFE and len(body) >= 26:          # extensible: real tag in the GUID
                fmt = (struct.unpack('<H', body[24:26])[0],) + fmt[1:]
        elif cid == b'data':
            data = body
        i += 8 + size + (size & 1)
    tag, ch, rate, _, align, bits = fmt
    n = len(data) // align
    out = []
    for k in range(n):
        acc = 0.0
        for c in range(ch):
            o = k * align + c * (bits // 8)
            if tag == 3 and bits == 32:
                v = struct.unpack('<f', data[o:o + 4])[0]
            elif bits == 16:
                v = struct.unpack('<h', data[o:o + 2])[0] / 32768.0
            elif bits == 24:
                x = data[o] | data[o + 1] << 8 | data[o + 2] << 16
                v = (x - (1 << 24) if x & 0x800000 else x) / 8388608.0
            elif bits == 32:
                v = struct.unpack('<i', data[o:o + 4])[0] / 2147483648.0
            else:
                raise SystemExit(f'unsupported format tag {tag} bits {bits}')
            acc += v
        out.append(acc / ch)
    return rate, out


def onepole_lp(sig, fc, fs):
    a = math.exp(-2 * math.pi * fc / fs)
    y, o = 0.0, []
    for v in sig:
        y = (1 - a) * v + a * y
        o.append(y)
    return o


def lp4(sig, fc, fs):
    for _ in range(4):
        sig = onepole_lp(sig, fc, fs)
    return sig


def hp4(sig, fc, fs):
    for _ in range(4):
        l = onepole_lp(sig, fc, fs)
        sig = [a - b for a, b in zip(sig, l)]
    return sig


def split(x, fs, gap_s):
    """Hits: runs whose 5 ms peak stays 8 dB above the noise floor (the median
    5 ms peak), merged across gaps shorter than gap_s."""
    W = int(fs * 0.005)
    pk = [max(abs(v) for v in x[i:i + W]) for i in range(0, len(x) - W, W)]
    floor = sorted(pk)[len(pk) // 2]
    thr = floor * 10 ** (8 / 20)
    act = [v > thr for v in pk]
    hits, start, last = [], None, None
    for k, a in enumerate(act):
        if a:
            if start is None:
                start = k
            last = k
        elif start is not None and (k - last) * 0.005 > gap_s:
            hits.append((start * W, (last + 1) * W))
            start = None
    if start is not None:
        hits.append((start * W, (last + 1) * W))
    # back the onset up to the first sample above -40 dB of the hit's own peak
    out = []
    for s, e in hits:
        if (e - s) < fs * 0.03:
            continue
        p = max(abs(v) for v in x[s:e])
        s0 = s
        while s0 > 0 and abs(x[s0 - 1]) > max(p * 0.01, thr):
            s0 -= 1
        out.append((s0, min(len(x), e + int(fs * 0.2))))
    return out


def env(sig, fs, ms=5):
    W = int(fs * ms / 1000)
    return [(i / fs * 1000, max(abs(v) for v in sig[i:i + W])) for i in range(0, len(sig) - W, W)]


def t_below(e, ref, thr_db):
    t = 0
    for ms, v in e:
        if v > 0 and 20 * math.log10(v / ref) > thr_db:
            t = ms + 5
    return t


def cycles(sig, fs, max_ms=300):
    c = [i - 1 + (-sig[i - 1]) / (sig[i] - sig[i - 1]) for i in range(1, min(len(sig), int(fs * max_ms / 1000)))
         if sig[i - 1] < 0 <= sig[i]]
    return [((a + b) / 2 / fs * 1000, fs / (b - a)) for a, b in zip(c, c[1:])]


def kick(seg, fs):
    lp = lp4(seg, 300, fs)
    e = env(seg, fs)
    pk = max(v for _, v in e)
    cyc = cycles(lp, fs, 400)
    late = [f for t, f in cyc if 150 < t < 400]
    return ('peak %.3f | f(t): %s | f_late %.1f Hz | t-10 %4.0f t-20 %4.0f t-30 %4.0f ms' % (
        pk, ' '.join('%.0f:%.0f' % c for c in cyc[:9]),
        (sum(late) / len(late)) if late else 0, t_below(e, pk, -10), t_below(e, pk, -20), t_below(e, pk, -30)))


def centroid(sig, fs, lo=1000, hi=12000, step=250):
    n = min(len(sig), int(fs * 0.05))
    seg = [sig[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / n)) for i in range(n)]
    num = den = 0.0
    for f in range(lo, hi, step):
        w = 2 * math.pi * f / fs
        re = sum(v * math.cos(w * i) for i, v in enumerate(seg))
        im = sum(v * math.sin(w * i) for i, v in enumerate(seg))
        m = math.hypot(re, im)
        num += f * m
        den += m
    return num / den if den else 0


def snare(seg, fs):
    lp, hp = lp4(seg, 900, fs), hp4(seg, 3000, fs)
    eb, en = env(lp, fs), env(hp, fs)
    pb, pn = max(v for _, v in eb) or 1e-9, max(v for _, v in en) or 1e-9
    cyc = cycles(lp, fs, 200)
    return ('body f(t): %s | body t-20 %4.0f t-40 %4.0f | noise %+5.1f dB t-20 %4.0f t-40 %4.0f centroid %5.0f Hz' % (
        ' '.join('%.0f:%.0f' % c for c in cyc[:6]), t_below(eb, pb, -20), t_below(eb, pb, -40),
        20 * math.log10(pn / pb), t_below(en, pn, -20), t_below(en, pn, -40), centroid(hp, fs)))


def main():
    a = sys.argv[1:]
    path = a[0]
    gap = float(a[a.index('--gap') + 1]) if '--gap' in a else 0.4
    fs, x = read_wav(path)
    hits = split(x, fs, gap)
    print(f'{path}: {fs} Hz, {len(x) / fs:.1f} s, {len(hits)} hits')
    if '--dump' in a:
        k, out = int(a[a.index('--dump') + 1]), a[a.index('--dump') + 2]
        s, e = hits[k]
        open(out, 'wb').write(struct.pack('<%df' % (e - s), *x[s:e]))
    for k, (s, e) in enumerate(hits):
        seg = x[s:e]
        line = snare(seg, fs) if '--snare' in a else kick(seg, fs)
        print(f'  hit {k} @{s / fs:6.2f}s ({(e - s) / fs:4.2f}s): {line}')


if __name__ == '__main__':
    main()
