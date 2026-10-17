"""Translate MAIN OS addresses from one OS release to the next (both stock images).

Two releases of the MK1 OS are the same code base recompiled: code and read-only data
move by deltas that are constant over long runs, RAM (.bss, SRAM) did not move from
1.73 to 1.74. For an address x in the image this compares a window around x in the old
image with the window around x + d in the new one, for every delta d seen in the image,
with absolute image pointers masked out in both (they shift too). The best-scoring
delta wins if it scores well and beats the runner-up clearly; anything else is
reported as unresolved, never guessed.

    python3 tools/port_os.py OLD_MAINOS.bin NEW_MAINOS.bin 0x40118918 0x4018d869 ...
    python3 tools/port_os.py OLD NEW --deltas      # print the delta runs it found

Used for the 1.73 -> 1.74 port (docs/PORT-1.74.md).
"""
import sys

B = 0x40000400
BSS = 0x402a3000   # __bss_start on MK1 1.73 and 1.74: at and above it is RAM, not image
W = 40          # window half-width, bytes


def load(p):
    return open(p, 'rb').read()


def ptr_mask(img):
    """True for every byte that is part of a 4-byte, 2-aligned image pointer."""
    m = bytearray(len(img))
    end = B + len(img)
    for i in range(0, len(img) - 3, 2):
        v = int.from_bytes(img[i:i + 4], 'big')
        if B <= v < end:
            m[i:i + 4] = b'\x01\x01\x01\x01'
    return m


class Porter:
    def __init__(self, old, new):
        self.a, self.b = load(old), load(new)
        self.ma, self.mb = ptr_mask(self.a), ptr_mask(self.b)
        self.end = B + min(len(self.a), len(self.b))
        self.deltas = self._find_deltas()
        self.dset = set(self.deltas)

    def _find_deltas(self):
        """Deltas of the long runs: sample 32-byte windows, look them up near."""
        a, b = self.a, self.b
        seen = {}
        for o in range(0, len(a) - 64, 1024):
            w = a[o:o + 32]
            if len(set(w)) < 10:
                continue
            k = b.find(w, max(0, o - 0x2000), o + 0x2000)
            if k >= 0 and b.find(w, k + 1, o + 0x2000) < 0:
                seen[k - o] = seen.get(k - o, 0) + 1
        return sorted((d for d, n in seen.items() if n >= 3), key=lambda d: -seen[d])

    def score(self, x, d, W=W):
        """(bytes equal, informative bytes equal) over the window; a pointer in both
        images counts as equal when it moved by one of the image's deltas."""
        a, b, ma, mb = self.a, self.b, self.ma, self.mb
        lo, hi = x - W - B, x + W - B
        if lo + d < 0 or hi + d > len(b) or lo < 0 or hi > len(a):
            return -1, 0
        eq = info = 0
        i = lo
        while i < hi:
            j = i + d
            if ma[i] or mb[j]:
                if ma[i] and mb[j] and (i - lo) % 2 == 0 and i + 4 <= hi:
                    va = int.from_bytes(a[i:i + 4], 'big')
                    vb = int.from_bytes(b[j:j + 4], 'big')
                    if vb - va in self.dset:
                        eq += 4
                        info += 4
                        i += 4
                        continue
                i += 1
                continue
            if a[i] == b[j]:
                eq += 1
                if a[i] not in (0, 0xff):
                    info += 1
            i += 1
        return eq, info

    def port(self, x):
        """-> (new address or None, how). Sparse data (zeros, small values) widens
        the window until it holds enough information or reaches 600 bytes."""
        if not (B <= x < min(self.end, BSS)):
            return x, 'outside the image (RAM): unchanged'
        for w in (W, 160, 600):
            res = sorted(((self.score(x, d, w), d) for d in self.deltas), reverse=True)
            (s1, i1), d1 = res[0]
            (s2, _), d2 = res[1] if len(res) > 1 else ((-1, 0), 0)
            n = 2 * w
            if s1 >= n - max(2, n // 40) and i1 >= 16:
                if s1 - s2 >= max(6, n // 13):
                    return x + d1, f'delta {d1:+#x} (score {s1}/{n}, next {s2})'
                return None, f'ambiguous: {d1:+#x} {s1}/{n}, {d2:+#x} {s2}'
            if s1 < n - max(2, n // 40) and i1 >= 16:
                return None, f'unresolved: best {d1:+#x} {s1}/{n}, next {d2:+#x} {s2}'
        return None, f'low-information window (zeros/padding) up to 600 B: candidates {d1:+#x} {d2:+#x}'


def main():
    old, new, *rest = sys.argv[1:]
    p = Porter(old, new)
    if rest == ['--deltas']:
        print(' '.join(f'{d:+#x}' for d in p.deltas))
        return
    for t in rest:
        x = int(t, 16)
        y, how = p.port(x)
        print(f'0x{x:08x} -> {"0x%08x" % y if y is not None else "??????????"}  {how}')


if __name__ == '__main__':
    main()
