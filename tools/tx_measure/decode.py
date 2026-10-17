import sys, os

def msgs(b):
    out, s = [], None
    for i, x in enumerate(b):
        if x == 0xF0: s = i
        elif x == 0xF7 and s is not None:
            out.append(b[s:i+1]); s = None
    return out

def unpack7(d):
    out = bytearray()
    for i in range(0, len(d), 8):
        g = d[i:i+8]
        hi = g[0]
        for j, v in enumerate(g[1:]):
            out.append(v | (0x80 if hi & (0x40 >> j) else 0))
    return bytes(out)

def decode(path, payload_start=14, tail=4):
    b = open(path, 'rb').read()
    blob = bytearray()
    for m in msgs(b):
        if m[8] == 0x02:
            blob += unpack7(m[payload_start:len(m)-1-tail])
    return bytes(blob)

if __name__ == '__main__':
    outdir = sys.argv[2]
    for root, _, files in os.walk(sys.argv[1]):
        for f in sorted(files):
            if f.endswith('.syx'):
                blob = decode(os.path.join(root, f))
                open(os.path.join(outdir, f[:-4] + '.bin'), 'wb').write(blob)
                print(f, len(blob), blob[:48].hex(' '))
