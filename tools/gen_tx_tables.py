#!/usr/bin/env python3
"""Generate mods/0009-tx-machines/tables.inc: the curves of the four TX machines.

Sources
-------
The Machinedrum user machines in MACHINEDRUM_USR (org.spsx.usr.tx9-bd, tx8-bd,
tx9-sd, tx8-sd): DSP56300 code and tables. Two kinds of data come out of them:

* Analytic - read from the plugins' code and tables (see re/analog-voice.md and
  the 0009 design note): the TX-9 BD sweep (tables at P 0x187/0x1a8), the TX-9 SD
  oscillator pitch (f1 = 125 Hz * (1 + PTCH/128)), its detune ratio (table P 0x2ef)
  and its bend (constants in its render routine).
* Measured - decay times, levels and the TX-8 BD sigh, measured by running each
  plugin in the dsp56300 emulator (tools/tx_measure/) and analysing the output:
  time to -60 dB (kicks) or -40 dB (snares, per band), peak level per ACC step.
  Those numbers are the MEASURED tables below.

Targets
-------
Each Rytm machine runs a stock machine (BD CLASSIC or SD CLASSIC) with a
parameter set computed per block. Decays are matched to the stock machines'
own envelope timing, computed from their code:

* BD CLASSIC decay segment (0x40109cda): rate = sat(2 * (128q + 16383 << 16)
  * 0.50394) >> 11, 20 bits; SD CLASSIC body (0x40110fd8): rate =
  (64q + 16256) << 5. A rate is a 4-bit exponent e and a 16-bit mantissa m;
  per tick the level is multiplied by c = (0x80007fff - ((0x7fffffff - (m << 14))
  >> e)) / 2^31 (0x40117980), and the stock state machine counts 16 ticks per
  audio block. ASSUMED: those ticks are the hardware envelope's own (the timer
  and the descriptor share units; not measured on the device).
* SD CLASSIC noise (0x4011107c): a per-block multiplier 1.00787 * T[NOD],
  T = the stock table at 0x401c2cc0 (read from build/stock_mainos.bin).

All tables are 33 words, indexed like the TX plugins' own: p >> 2, linear over
p & 3, for a knob value p = 0..127.

    python3 tools/gen_tx_tables.py          # write
    python3 tools/gen_tx_tables.py --check  # fail if the file is out of date
"""
import hashlib
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tx_atk_data as A                 # BD attack waveforms (tools/tx_measure/atk_extract.py)

ROOT = Path(__file__).resolve().parent.parent
USR = ROOT / "MACHINEDRUM_USR"
OUT = ROOT / "mods" / "0009-tx-machines" / "tables.inc"

N = 32 * 44100 / 48000            # TX samples per Rytm block
BLOCK_MS = 32 / 48.0              # Rytm block, ms
Q23 = float(1 << 23)

# --------------------------------------------------------------- MEASURED
# (knob value -> measurement), emulator, other knobs at their MDM1 defaults
# unless noted. Times in ms.
TX9BD_T60 = {0: 80, 16: 95, 32: 115, 48: 145, 64: 185, 80: 234, 96: 299, 112: 379, 127: 454}  # vs DEC, ACC 96, includes the hold
TX8BD_T60 = {0: 120, 16: 244, 32: 419, 48: 619, 64: 858, 80: 1147, 96: 1502, 112: 1961, 127: 2514}  # vs DEC, PTCH 64
TX8BD_SIGH_ST = {0: 0.22, 32: 1.28, 64: 2.04, 96: 2.66, 127: 3.17}   # start offset, semitones, falls linearly over 165 ms
TX8BD_PEAK = {0: 0.291, 32: 0.468, 64: 0.653, 96: 0.837, 127: 0.972}  # vs ACC
TX9SD_BODY_T40 = {0: 35, 16: 45, 32: 60, 48: 90, 64: 125, 80: 170, 96: 229, 112: 319, 127: 434}   # vs DEC, low band
TX9SD_NOISE_T40 = {0: 105, 16: 140, 32: 170, 48: 195, 64: 215, 80: 229, 96: 244, 112: 264, 127: 274}  # vs TONE, high band
TX9SD_PEAK = {0: 0.16, 32: 0.27, 64: 0.38, 96: 0.49, 127: 0.60}      # vs ACC
TX8SD_BODY_T40 = {0: 170, 16: 145, 32: 130, 48: 110, 64: 95, 80: 85, 96: 75, 112: 65, 127: 55}    # vs PTCH, low band
TX8SD_NOISE_T40 = {0: 20, 16: 30, 32: 35, 48: 50, 64: 70, 80: 105, 96: 145, 112: 210, 127: 284}   # vs DEC, high band
TX8SD_PEAK = {0: 0.06, 32: 0.11, 64: 0.16, 96: 0.23, 127: 0.30}      # vs ACC
SIGH_MS = 165.0
# time to -30 dB (emulator; MD recordings agree at DEC 0 / 127: TX-9 75 / 360, TX-8 65 / 1250)
TX9BD_T30 = {0: 75, 16: 85, 32: 95, 48: 120, 64: 150, 80: 200, 96: 234, 112: 304, 127: 344}
TX8BD_T30 = {0: 55, 16: 125, 32: 205, 48: 294, 64: 414, 80: 544, 96: 713, 112: 933, 127: 1197}
# TX-8 BD: the resonator rings shorter as the pitch rises - t-30 vs PTCH at DEC 64. The
# Machinedrum itself (WAVS3, slope fits at DEC 64: 872 / 439 / 239 ms at PTCH 0 / 64 /
# 127) falls as f^-0.99 below PTCH 64 and f^-0.89 above, flatter than the emulator's
# 634 / 414 / 155; scaled to the table's 414 at 64.
TX8BD_T30_PTCH = {p: 414 * 2 ** (-(0.99 if p < 64 else 0.89) * (p - 64) / 64) for p in range(0, 128, 16)} | {127: 225}

# --------------------------------------------------------------- MEASURED, Rytm
# From recordings of the stock machines on an MK1 (MACHINEDRUM_USR/WAVS, 2026-10-10).
RYTM_BDCL_T30 = {0: 75, 32: 175, 64: 645, 96: 3305}   # BD CLASSIC vs DEC, ms to -30 dB, HLD default
RYTM_BDCL_HLD_MS = 32 * 32 / 48.0                       # that default hold: 32 blocks
RYTM_BDCL_HZ = 48.0                                     # BD CLASSIC at TUN 0x3a00 (-6); 34 Hz at -12
# BD TX-9 v6 against the Machinedrum (WAVS2, defaults, 4 hits each): settled 53.1 vs
# 56.0 Hz, and after the shared ~40 ms hold the Rytm fell to -30 dB at 128 ms against
# 160 (decay part 88 vs ~115 ms). Trims, until more DEC settings are recorded:
# v7 against the Machinedrum (WAVS3, WAV 0, DEC 0 / 64 / 127): the sweep matches
# (207 > 173 > 122 > 85 > 65 Hz on both), the tail sits at 57.0 vs 56.0 Hz, and t-30 is
# 90 / 185 / 410 vs 80 / 165 / 365 ms (the -10 to -30 dB part 0.86x as long on the MD).
TX9BD_RYTM_ST = 12 * math.log2(56.0 / 53.1) - 12 * math.log2(57.0 / 56.0)   # semitones
TX9BD_RYTM_DEC = 1.3 * 0.87                             # x the decay-segment target
# The click (energy > 700 Hz, first 10 ms, re the body at 40..80 ms, with ATK 0's analog
# onset taken out) matches the MD at ATK 32 but is ~4 / ~8 dB hot at ATK 64 / 127. The MD
# takes clip, which may understate its loud clicks, so half of that is taken off.
TX9BD_ATK_TRIM_DB = {0: 0.0, 32: 0.0, 64: -2.0, 127: -4.0}
# SD TX-9 against the Machinedrum (WAVS3, SNP 0 / 64 / 127): noise band (> 3 kHz) re body
# -18.9 / -13.9 dB vs -20.4 / -15.7 at SNP 64 / 127, same decay; the Rytm's -24 dB at SNP
# 0 is a 5 ms onset transient of the analog voice, not the port's noise.
TX9SD_NOISE_TRIM_DB = -1.7
# BT CLASSIC (WAVS3, 2026-10-13, SNP 0; decays as slope fits): 60.8 Hz at TUN 64, a quarter
# semitone per step; t30 vs DEC at TUN 80 (77 Hz) and vs pitch at DEC 63. Modelled as
# separable, t30(DEC, f) = T77(DEC) * G(f) / G(77) - the DEC take's 412 ms at 77 Hz sits
# near G's 343 there (G falls as f^-1 low down, f^-3 above ~60 Hz).
BT_F64 = 60.8
BT_T30_77 = {0: 60, 32: 252, 64: 412, 96: 548, 127: 650}
BT_T30_F = [(24.8, 1863.0), (60.7, 726.0), (131.3, 64.0)]
# The MKII's BT CLASSIC (OS 1.74, recorded 2026-10-25, SNP 0 NOL 0 SWD 0; t30 from the 5 ms
# peak envelope): 60.67 Hz at TUN 64, a quarter semitone per step, as on the MK1, but it
# rings 1.3-1.5x longer. t30 vs DEC at TUN 80 (75.3 Hz) and vs pitch at DEC 63 (TUN 0..127).
BT_MK2_F64 = 60.67
BT_MK2_FDEC = 75.3
BT_MK2_T30_DEC = {0: 25, 16: 160, 32: 285, 48: 410, 64: 535, 80: 655, 96: 760, 112: 880, 127: 965}
BT_MK2_T30_F = [(24.5, 1890.0), (25.1, 1960.0), (30.4, 1905.0), (37.8, 2100.0), (47.5, 1405.0),
                (59.5, 1200.0), (75.3, 515.0), (95.7, 230.0), (132.2, 85.0), (153.6, 55.0)]
# BT TX-8 on the MK1-fitted tables (unit, 2026-10-24) rang 45 / 365 / 1535 ms at BT DEC 0 /
# 16 / 75 (49.7 Hz), 0.68 / 0.86 / 0.94 of the separable model: short decays fall off
# faster than it says. The model is scaled by that, linear between, constant beyond.
BT_MK2_CORR = {0: 0.681, 16: 0.863, 75: 0.941}
# Nor is pitch separable at the ends: on the unit (2026-10-25) BT TX-8 at PTC 0 (24.85 Hz)
# rang 1.7-2.0x the model (975 / 1395 ms at BT DEC 15 / 27), at PTC 127 (99.4 Hz) 0.80-0.85x
# (205 / 190 ms at BT DEC 85 / 73). G is scaled by this, log-linear in log f, 1 at 49.7 Hz.
BT_MK2_GCORR = [(24.85, 2.0), (49.7, 1.0), (99.4, 0.82)]
TX8_F64 = 49.7                       # the TX-8 BD at PTCH 64 (WAVS3: 49.4 .. 49.8 Hz)
TX9_F64 = 56.0                       # the TX-9 BD at PTCH 64 (WAVS2/3 tails: 56.0 Hz)
# BD TX-9 DIGI's decay: the emulator table, x the real MD's ratio to it (WAVS3: t30 80 /
# 165 / 365 ms at DEC 0 / 64 / 127 against the table's 75 / 150 / 344)
TX9D_T30_TRIM = 1.08
RYTM_SDCL_HZ0 = math.sqrt(114.0 * 475.0)                # SD CLASSIC at TUN 0x4000 (114 Hz at -12, 475 at +12)
# XT CLASSIC (recorded 2026-10-11, stock machine and the v4 tom ports at known words). The
# stock code tunes p = (TUN - 0x4000) / 6144 octaves (note 60), clamped to -2.67..+2.62.
# Pitch is exact 2^p, the same on the LT and MT/HT voices (v5 ports, 2026-10-11 WAVS2:
# 97.3 / 119 / 142 Hz on LT where 97.5 / 120 / 142.5 were due; MT identical at the same
# words). An earlier "MT is 0.55 octave higher" reading was a TX-8 take at TYPE 1.
RYTM_XT_F0 = 50.0                                       # Hz at TUN 0x4000, note 60
# Decay (t-30, ms), fitted as tau = TREF * 2^(-K_P (p - 1)) * g(DEC word), where g is
# piecewise power-law in DEC + 256 (the stock divides by it): log2 g = 0 at 0x4000,
# DEC_LO at 0, DEC_HI at 0x7f00. Fit to 18 hits (v4 and v5 takes): 0.11 octave rms.
# Long tails are also cut by the stock drift after 1.5 s.
RYTM_XT_TREF = 1120.0                                   # ms at p 1, DEC 0x4000
RYTM_XT_K_P = 1.90                                      # octaves of decay per octave of pitch
RYTM_XT_DEC_LO, RYTM_XT_DEC_HI = -4.0, 0.45

# --------------------------------------------------------------- MEASURED, toms (emulator)
X9_F0 = [65.0, 80.0, 95.0]           # TX-9 TOM, TYPE 0..2: f = F0 * (1 + PTCH/128) (steady, PTCH 0 / 64 / 127)
X9_BEND_ST = {0: 11.2, 64: 13.1, 127: 15.1}   # attack bend, semitones above steady (2..17 ms window)
# The bend is fast: spectral peaks of TYPE 0 at 2..12 / 10..20 / 20..40 ms sit +17 / +6.3 /
# +1.4 semitones above steady - a time constant of ~9.5 ms. Its start (clamped by the
# tom core's range) is set so the 2..17 ms average matches X9_BEND_ST.
X9_BEND_TAU_MS = 9.5
X9_BEND_START = 1.3 * math.exp(7 / 9.5)       # start / X9_BEND_ST
# Envelope: nearly flat for the first ~12 % of t-30, then exponential (emulator: e.g.
# TYPE 0 DEC 64 -3/-10/-20/-30 dB at 80/170/260/355 ms). Played as a hold at the
# longest damping, then the DEC word for 0.9 t-30. TYPE 1, 2 ring 0.68x as long.
X9_HOLD_FRAC, X9_TAIL_FRAC, X9_T30_TYPE12 = 0.12, 0.9, 0.68
# Second partial at 2/3 f (TYPE 0 DEC 127, 120 ms windows: 61 Hz at -6.5 / -5.2 / -4.7 /
# -4.3 dB re the 91.5 Hz main at 70 / 130 / 190 / 250 ms; 0.062 dB/ms, the main 0.072).
X9S_A0, X9S_T30 = 0.16, 1.1          # start level (MD full scale, ACC 96), t-30 / main's
# On the MKII (unit, 2026-10-25) the partial measured 0..-5 dB under the main (40-200 ms
# spectra), the MD -6 dB on all eight hits, the design ~-5 dB: X9S_K is trimmed by this there.
X9S_MK2_TRIM_DB = -3.5
# TX-8 BD ATK starts the kick on a segment at ~2.2x the pitch (half-periods 2.0 ms at
# PTCH 127, body 4.7 ms), ~0.067 ms per ATK step long, then the body (emulator).
TX8BD_ATK_RATIO, TX8BD_ATK_MS_PER_STEP = 2.2, 0.067
TX8BD_PULSE_TRIM = 0.3               # the residual pulse, re the full difference
X9_PEAK = {0: 0.094, 32: 0.203, 64: 0.316, 96: 0.430, 127: 0.541}   # vs ACC
# TX-8 TOM, TYPE 0..2 (the congas 3..5 are dropped) at PTCH 64, TUNE 64: settled pitch
# from the Machinedrum (WAVS2 md tx8: 91.0 / 141.4 / 192.1 Hz); PTCH: 2 octaves
X8_F64 = [91.0, 141.4, 192.1]
X8_TUNE_ST = (-2.1, 3.2)             # TUNE 0 / 127, semitones (0 at 64)
X8_DIOD_ST = 5.6                     # DIOD 127: attack droop, semitones, decaying
X8_DIOD_TAU_MS = 40.0
X8_PEAK = {0: 0.079, 32: 0.138, 64: 0.199, 96: 0.262, 127: 0.322}   # vs ACC
XT_NOD_X9, XT_NOD_X8 = 10, 3        # XT CLASSIC NOD for the TX-9 (~40 ms) / TX-8 (~5 ms) noise decays
# t-30 vs DEC: TX-9 (TYPE 0, mean over PTCH 0/64/127: it does not depend on pitch) and
# TX-8 at 86.4 Hz (PTCH 64, TYPE 0; ~ f^-0.93; 127 extrapolated, the emulator run was 2 s)
X9_T30 = {0: 213, 16: 255, 32: 292, 48: 330, 64: 357, 80: 377, 96: 402, 112: 425, 127: 434}
X8_T30 = {0: 170, 16: 195, 32: 225, 48: 265, 64: 325, 80: 575, 96: 1010, 112: 1785, 127: 3100}
X8_T30_HZ, X8_T30_EXP = 86.4, 0.93

# --------------------------------------------------------------- MEASURED, TX-8 SD noise (emulator)
# Isolated as render(SNAP) - render(SNAP 0). Spectrum fitted (1.3 dB rms over 15 bands)
# by a 2-pole Butterworth high-pass and a 1-pole low-pass; decay exponential.
N8_FH, N8_Q, N8_FL = 2420.0, 0.71, 3000.0
N8_RMS_SNAP127 = 0.0702              # initial 5 ms RMS at SNAP 127, ACC 96 (TX full scale 1)
N8_SNAP = {0: 0.0, 32: 0.174, 64: 0.454, 127: 1.0}   # level vs SNAP, re 127

def nod_table():
    """Stock SD CLASSIC's noise-decay table, 0x401c2cc0 (128 Q31 longs), read from
    the extracted stock image (whose checksum build.py enforces)."""
    img = ROOT / "build" / "stock_mainos.bin"
    if img.exists():
        b = img.read_bytes()
        o = 0x401c2cc0 - 0x40000400
        return [int.from_bytes(b[o + 4 * i:o + 4 * i + 4], "big", signed=True) / 2**31 for i in range(128)]
    raise SystemExit("build/stock_mainos.bin missing: run `make build` once (it extracts the stock image)")


# --------------------------------------------------------------- plugins
def unpack7(d: bytes) -> bytes:
    out = bytearray()
    for i in range(0, len(d), 8):
        g = d[i:i + 8]
        for j, v in enumerate(g[1:]):
            out.append(v | (0x80 if g[0] & (0x40 >> j) else 0))
    return bytes(out)


def plugin(name: str, expect_id: bytes) -> list[int]:
    raw = (USR / name).read_bytes()
    data, start = bytearray(), None
    for i, x in enumerate(raw):
        if x == 0xF0:
            start = i
        elif x == 0xF7 and start is not None:
            m = raw[start:i + 1]
            if m[8] == 0x02:
                data += unpack7(m[14:len(m) - 5])
            start = None
    if data[:4] != b"MDS1" or expect_id not in data:
        raise SystemExit(f"{name} is not the plugin this was written for")
    n = int.from_bytes(data[0x14:0x18], "big")
    p = data[0x80:0x80 + 3 * n]
    w = [int.from_bytes(p[i:i + 3], "big") for i in range(0, len(p), 3)]
    return [x - (1 << 24) if x & 0x800000 else x for x in w]


# --------------------------------------------------------------- stock timing
def rate_time_blocks(rate20: int, thr_db: float) -> float:
    m, e = rate20 & 0xffff, (rate20 >> 16) & 0xf
    d0 = (0x7fffffff - (m << 14)) >> e
    c = ((0x80007fff - d0) & 0xffffffff) / 2**31
    return math.log(10 ** (thr_db / 20)) / math.log(c) / 16


def bd_rate(q: int) -> int:
    x = ((q << 8) >> 1) + 16383
    v = (x << 16) * 1082196484 // 2**31 * 2
    v = min(v, 0x7fffffff)
    return (v >> 11) & 0xfffff


def sd_body_rate(q: int) -> int:
    return ((64 * q + 16256) << 5) & 0xfffff


def sd_noise_blocks(q: int, nod, thr_db: float) -> float:
    d = min(nod[q] * 1.0078740, 0.9999999)
    return math.log(10 ** (thr_db / 20)) / math.log(d) if d > 0 else 0.0


def bd_seg_ms(q: int) -> float:
    """BD CLASSIC decay-segment length to -30 dB for DEC q, from the recordings
    (log-interpolated; above 96 extrapolated with the code-derived timing), less the
    recorded default hold."""
    pts = sorted(RYTM_BDCL_T30)
    if q <= pts[-1]:
        for a, b in zip(pts, pts[1:]):
            if q <= b:
                la, lb = math.log(RYTM_BDCL_T30[a]), math.log(RYTM_BDCL_T30[b])
                t = math.exp(la + (lb - la) * (q - a) / (b - a))
                break
    else:
        t = RYTM_BDCL_T30[pts[-1]] * rate_time_blocks(bd_rate(q), -30) / rate_time_blocks(bd_rate(pts[-1]), -30)
    return max(t - RYTM_BDCL_HLD_MS, 1.0)


def tun_bd(hz: float) -> float:
    """BD CLASSIC tune offset from 0x3a00 for a frequency (0x100 per semitone)."""
    return 3072 * math.log2(hz / RYTM_BDCL_HZ)


def tun_sd(hz: float) -> float:
    """SD CLASSIC tune offset from 0x3a00 for an oscillator-1 frequency."""
    return 0x600 + 3072 * math.log2(hz / RYTM_SDCL_HZ0)


def roots(coefs):
    """All roots of a polynomial (highest power first), Durand-Kerner."""
    a = [c / coefs[0] for c in coefs]
    n = len(a) - 1
    z = [complex(0.4, 0.9) ** k for k in range(n)]
    for _ in range(500):
        nz = []
        for i in range(n):
            num = sum(a[k] * z[i] ** (n - k) for k in range(n + 1))
            den = 1
            for j in range(n):
                if j != i:
                    den *= (z[i] - z[j])
            nz.append(z[i] - num / den)
        z = nz
    return z


def poly(rts):
    """Coefficients (highest power first, leading 1) of the polynomial with these roots."""
    c = [complex(1)]
    for r in rts:
        c = [x - r * y for x, y in zip(c + [0], [0] + c)]
    return [x.real for x in c]


def warp(r, ratio):
    """Map a z-plane root from rate fs to fs/ratio... angle and log-radius scale by ratio;
    negative real roots stay negative real."""
    if abs(r.imag) < 1e-12:
        return complex(math.copysign(abs(r.real) ** ratio, r.real), 0)
    return complex(math.e ** (math.log(abs(r)) * ratio)) * complex(math.cos(math.atan2(r.imag, r.real) * ratio),
                                                                     math.sin(math.atan2(r.imag, r.real) * ratio))


def noise_power(b, a, n=8192):
    """Sum of squares of the impulse response of b(z)/a(z) (a[0] = 1)."""
    x, y, s = [0.0] * len(b), [0.0] * len(a), 0.0
    for k in range(n):
        x = [1.0 if k == 0 else 0.0] + x[:-1]
        v = sum(bi * xi for bi, xi in zip(b, x)) - sum(ai * yi for ai, yi in zip(a[1:], y[:-1]))
        y = [v] + y[:-1]
        s += v * v
    return s


def noise9(sd9) -> list[str]:
    """The TX-9 SD noise, ported exactly (validated against the plugin in the emulator:
    envelope to 24-bit rounding, filter + LCG output to 0.2 % residual energy).

    Envelope, per TX step of 16 samples (1.8375 steps per Rytm block):
        E' = max(E - (E - F) T - max(0, E - TH) K2, EMIN)
        E  = min(E' + C, max(D, E'))
        C  *= CDEC after the first 6 steps
    with D, C, F linear in ACC and T = table 0x2ad (TONE). Amplitude = table 0x310 (E)
    * 0.6583 * SNAP. Noise: white -> y = 2 (c0 x + c1 x1 + c2 x2 + c3 y1 + c4 y2 + c5 y3),
    coefficients P 0x331.., re-warped from 44.1 to 48 kHz (poles and zeros: angle and
    log radius * 44.1/48), numerator rescaled to keep the white-noise power gain."""
    c = [sd9[0x331 + i] / Q23 for i in range(6)]
    b44 = [2 * c[0], 2 * c[1], 2 * c[2]]
    a44 = [1.0, -2 * c[3], -2 * c[4], -2 * c[5]]
    ratio = 44100.0 / 48000.0
    zb = roots(b44)
    pa = roots(a44)
    if max(abs(p) for p in pa) >= 1:
        raise SystemExit("TX-9 SD noise filter is not stable as decoded")
    a48 = poly([warp(p, ratio) for p in pa])
    b48 = [b44[0] * x for x in poly([warp(z, ratio) for z in zb])]
    g = math.sqrt(noise_power(b44, a44) / noise_power(b48, a48))
    b48 = [g * x for x in b48]
    # peak output for a +-0.5 white input (the port feeds seed >> 1): must stay < 1
    seed, x, y, peak = 12345, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], 0.0
    for _ in range(200000):
        seed = (seed * 1664525 + 1013904223) & 0xffffffff
        xv = (seed - (1 << 32) if seed & 0x80000000 else seed) / 2**32
        x = [xv] + x[:2]
        v = sum(bi * xi for bi, xi in zip(b48, x)) - sum(ai * yi for ai, yi in zip(a48[1:], y))
        y = [v] + y[:2]
        peak = max(peak, abs(v))
    if peak >= 0.95:
        raise SystemExit(f"TX-9 SD noise filter peaks at {peak:.2f} for a half-scale input")
    acc_step = 1 / 128
    E = {
        "N9_D0": 0x1e6666 / Q23, "N9_D1": 0x480000 / Q23 * acc_step,
        "N9_C0": 0x04f0bf / Q23, "N9_C1": 0x0de519 / Q23 * acc_step,
        "N9_F0": -(0x1000000 - 0xfc6666) / Q23, "N9_F1": -(0x1000000 - 0xf8cccd) / Q23 * acc_step,
        "N9_TH": 0x4cccd / Q23, "N9_K2": 0x72fa / Q23, "N9_CDEC": 0x79597f / Q23,
        "N9_EMIN": -(0x1000000 - 0xfb3333) / Q23,
        "N9_SNAPK": 0x544385 / Q23 / 128 * 10 ** (TX9SD_NOISE_TRIM_DB / 20),
    }
    out = ["", "        .text", f"| TX-9 SD noise (filter peak {peak:.2f} at half-scale input, gain {g:.4f})"]
    for k, v in E.items():
        out.append(f"        .equ    {k}, 0x{q31(v) & 0xffffffff:08x}")
    out.append(f"        .equ    N9_PHASE, {int(round(N / 16 * 65536))}   | TX steps per block, Q16")
    out.append("        .equ    N9_HOLD, 6                | steps before C starts to decay")
    out += longs("n9_t2ad", [q31(sd9[0x2ad + i] / Q23) for i in range(33)], "TX-9 SD noise decay per step (TONE)")
    out += longs("n9_t310", [q31(sd9[0x310 + i] / Q23) for i in range(33)], "TX-9 SD noise amplitude curve (E)")
    halved = [b48[0] / 2, b48[1] / 2, b48[2] / 2, -a48[1] / 2, -a48[2] / 2, -a48[3] / 2]
    out += longs("n9_coef", [q31(v) for v in halved], "b0 b1 b2 a1 a2 a3, halved (y = 2 * sum), 48 kHz")
    out += ["", "        .section .m37,\"ax\""]
    return out


def tun_xt(hz: float) -> float:
    """XT CLASSIC tune word for a frequency (0x200 per semitone, 0x40117a80)."""
    return 0x4000 + 6144 * math.log2(hz / RYTM_XT_F0)


def xt_dec() -> list[str]:
    """Decay for the toms. Per block: idx = A[DEC] + B + (TUN * KP >> 16), then
    DEC word = xt_dxt[idx]. idx is 16 * (r + 6), r = log2(target / tau at DEC 0x4000)
    at that pitch; A = 16 log2 target (TX-8: at X8_T30_HZ, the pitch slope in KP / B)."""
    def dxt(i):
        r = i / 16 - 6
        x1 = math.log2(0x4000 + 256)
        x = x1 + r * ((x1 - 8) / -RYTM_XT_DEC_LO if r < 0 else (15 - x1) / RYTM_XT_DEC_HI)
        return max(0.0, min(0x7fff, 2 ** min(x, 15.0) - 256))
    p0 = 0x4000 / 6144
    k9 = 16 * RYTM_XT_K_P                                  # idx per octave of p
    k8 = k9 - 16 * X8_T30_EXP
    b9 = 96 - 16 * math.log2(RYTM_XT_TREF) - k9 - k9 * p0
    b8 = 96 - 16 * math.log2(RYTM_XT_TREF) - k9 - k8 * p0 - 16 * X8_T30_EXP * math.log2(RYTM_XT_F0 / X8_T30_HZ)
    out = words("xt_dxt", [dxt(i) for i in pts33()], "toms: XT CLASSIC DEC word for idx")
    out += [f"        .equ    X9_KP, {round(k9 / 6144 * 65536)}",
            f"        .equ    X8_KP, {round(k8 / 6144 * 65536)}",
            f"        .equ    X9_B, {round(b9)}",
            f"        .equ    X8_B, {round(b8)}",
            f"        .equ    X9_TOFF, {round(16 * math.log2(X9_T30_TYPE12))}   | idx offset for TYPE 1, 2"]
    return out


def noise8() -> list[str]:
    """The TX-8 SD noise, matched: white -> HP2(N8_FH, N8_Q) * LP1(N8_FL), designed
    at 48 kHz (bilinear with prewarp for the high-pass, matched pole for the low-pass,
    so the result keeps the engine's 2-zero / 3-pole form), level set so SNAP 127
    gives the measured RMS for a full-scale white input."""
    fs = 48000.0
    k = math.tan(math.pi * N8_FH / fs)
    norm = 1 / (1 + k / N8_Q + k * k)
    hb = [norm, -2 * norm, norm]
    ha = [1.0, 2 * (k * k - 1) * norm, (1 - k / N8_Q + k * k) * norm]
    p = math.exp(-2 * math.pi * N8_FL / fs)
    b = [x * (1 - p) for x in hb]
    a = [1.0, ha[1] - p, ha[2] - p * ha[1], -p * ha[2]]
    g = noise_power(b, a)
    amp127 = N8_RMS_SNAP127 / (math.sqrt(g) * (1 / math.sqrt(3)))     # uniform +-1 has rms 1/sqrt(3)
    halved = [b[0] / 2, b[1] / 2, b[2] / 2, -a[1] / 2, -a[2] / 2, -a[3] / 2]
    P = pts33()
    snap = [32767 * min(1.0, at(N8_SNAP, p) * amp127) for p in P]
    acc = [32767 * at(TX8SD_PEAK, p) / max(TX8SD_PEAK.values()) for p in P]
    dec = [q31(10 ** (-40 / at(TX8SD_NOISE_T40, p) * BLOCK_MS / 20)) for p in P]
    if amp127 >= 1:
        raise SystemExit(f"TX-8 SD noise needs amp {amp127:.2f} > 1")
    out = [f"| TX-8 SD noise (matched): HP2 {N8_FH:.0f} Hz Q {N8_Q}, LP1 {N8_FL:.0f} Hz; amp at SNAP 127 {amp127:.3f}"]
    out += longs("n8_coef", [q31(v) for v in halved], "b0 b1 b2 a1 a2 a3, halved (y = 2 * sum), 48 kHz")
    out += words("n8_snap", snap, "TX-8 SD noise amplitude for SNP, Q15")
    out += words("n8_acc", acc, "TX-8 SD noise level for ACC, Q15")
    out += longs("n8_dec", dec, "TX-8 SD noise decay per block for DEC, Q31")
    return out


def toms() -> list[str]:
    P = pts33()
    out = ["", "        .section .m39,\"ax\""]
    out += words("x9_ptc", [tun_xt(X9_F0[1] * (1 + min(p, 128) / 128)) for p in P], "TX-9 tom: TUN for PTC (TYPE 1, linear in Hz, LT voice)")
    out += words("x9_typ", [6144 * math.log2(f / X9_F0[1]) for f in X9_F0], "TX-9 tom: TUN offset per TYPE")
    out += words("x9_bnd", [512 * X9_BEND_START * at(X9_BEND_ST, p) for p in P], "TX-9 tom: attack bend start, TUN units, for BND")
    out += words("x9_acc", [32767 * math.sqrt(at(X9_PEAK, p) / max(X9_PEAK.values())) for p in P], "TX-9 tom: LEV scale for ACC")
    out += words("x9_nol", [min(127, 100 * math.sqrt(min(p, 127) / 64)) for p in P], "TX-9 tom: XT CLASSIC NOL for NOI")
    out += [f"        .equ    X9_BDEC, 0x{q31(math.exp(-BLOCK_MS / X9_BEND_TAU_MS)):08x}   | bend decay per block",
            f"        .equ    X9_NOD, {XT_NOD_X9 << 8}"]
    out += words("x9_dec", [16 * math.log2(X9_TAIL_FRAC * at(X9_T30, min(p, 127))) for p in P],
                 "TX-9 tom: 16 log2 of the tail's t-30 for DEC (TYPE 0)")
    out += words("x9_hold", [X9_HOLD_FRAC * at(X9_T30, min(p, 127)) / BLOCK_MS for p in P],
                 "TX-9 tom: flat start, blocks, for DEC (TYPE 0)")
    out += ["", "        .section .m40,\"ax\""]
    out += xt_dec()
    out += words("x8_dec", [16 * math.log2(at(X8_T30, min(p, 127))) for p in P], "TX-8 tom: 16 log2 t-30 at 86 Hz for DEC")
    out += words("x8_typ", [tun_xt(f) for f in X8_F64], "TX-8 tom: TUN per TYPE at PTC 64")
    lo, hi = X8_TUNE_ST
    out += words("x8_tune", [512 * (lo * (64 - p) / 64 if p < 64 else hi * (min(p, 127) - 64) / 63) for p in P],
                 "TX-8 tom: TUN offset for TUN (fine, 0 at 64)")
    out += words("x8_diod", [512 * X8_DIOD_ST * min(p, 127) / 127 for p in P], "TX-8 tom: attack droop start for DIO")
    out += words("x8_acc", [32767 * math.sqrt(at(X8_PEAK, p) / max(X8_PEAK.values())) for p in P], "TX-8 tom: LEV scale for ACC")
    out += words("x8_nol", [min(127, 100 * math.sqrt(min(p, 127) / 64)) for p in P], "TX-8 tom: XT CLASSIC NOL for NOI")
    out += [f"        .equ    X8_DDEC, 0x{q31(math.exp(-BLOCK_MS / X8_DIOD_TAU_MS)):08x}   | droop decay per block",
            f"        .equ    X8_NOD, {XT_NOD_X8 << 8}"]
    return out


def x9_sub() -> list[str]:
    """The TX-9 tom's second partial: a sine at exactly 2/3 of the main pitch (all
    TYPEs and PTCHs, emulator, 120 ms windows), ~5 dB under it, decaying ~1.1x as
    long. Played digitally into buffer B after XT CLASSIC (which rewrites B every
    block): per sample (s16 of a parabolic sine) * G, G = X9S_K * x9_acc^2 * LEV * env,
    so A0 = X9S_A0 MD full scale at ACC 96."""
    P = pts33()
    inc = [round(2 / 3 * RYTM_XT_F0 * 2 ** ((1024 * i - 0x4000) / 6144) / 48000 * 2**32) for i in range(33)]
    sd = [(1 - 10 ** (-1.5 * BLOCK_MS / (X9S_T30 * at(X9_T30, min(p, 127))))) * 2**21 for p in P]
    k = X9S_A0 * 65536 * max(X9_PEAK.values()) / at(X9_PEAK, 96)
    out = [f"        .equ    X9S_K, {round(k)}"]
    out += longs("x9_sinc", [v for v in inc], "TX-9 tom partial: phase step per sample, TUN >> 10")
    out += words("x9_sd", sd, "TX-9 tom partial: (1 - decay per block) * 2^21, for DEC (TYPE 0)")
    return out


def bt_g(f: float, pts=None) -> float:
    """BT CLASSIC t30 vs pitch at DEC 63 (log-log between the points, end slopes beyond)."""
    pts = pts or BT_T30_F
    i = 0
    while i < len(pts) - 2 and f >= pts[i + 1][0]:
        i += 1
    (f0, t0), (f1, t1) = pts[i], pts[i + 1]
    return t0 * math.exp(math.log(t1 / t0) * math.log(f / f0) / math.log(f1 / f0))


def bt_gcorr(f: float) -> float:
    """BT_MK2_GCORR at f: log-linear in log f between its points, held beyond."""
    c = BT_MK2_GCORR
    if f <= c[0][0]:
        return c[0][1]
    if f >= c[-1][0]:
        return c[-1][1]
    i = 0 if f < c[1][0] else 1
    (f0, c0), (f1, c1) = c[i], c[i + 1]
    return c0 * math.exp(math.log(c1 / c0) * math.log(f / f0) / math.log(f1 / f0))


def bt8(mk2: bool = False) -> list[str]:
    """BT TX-8: the TX-8 BD on the BT voice's resonator (BT CLASSIC run every block).
    PTC -> TUN (49.7 Hz at PTC 64, two octaves over PTC; TUN = a quarter semitone);
    DEC -> BT DEC so that t30 matches the TX-8's, at PTC 64, plus an offset for PTC
    (exact at DEC 64), through the separable BT model above. mk2: the same from the
    MKII's BT CLASSIC (mk2/tx-machines)."""
    P = pts33()
    if mk2:
        t_dec, f_dec, pts, f64 = BT_MK2_T30_DEC, BT_MK2_FDEC, BT_MK2_T30_F, BT_MK2_F64
        t_dec = {q: at(t_dec, q) * at(BT_MK2_CORR, q) for q in range(128)}
    else:
        t_dec, f_dec, pts, f64 = BT_T30_77, 77.0, BT_T30_F, BT_F64
    g_ref = bt_g(f_dec, pts)
    if mk2:
        pts = [(f, t * bt_gcorr(f)) for f, t in pts]
    def bt_dec(t30, f):
        want = t30 * g_ref / bt_g(f, pts)
        return min(range(128), key=lambda q: abs(math.log(at(t_dec, q) / want)))
    def tmd(dm, p):
        return at(TX8BD_T30, dm) * at(TX8BD_T30_PTCH, p) / at(TX8BD_T30_PTCH, 64)
    def f_of(p):
        return TX8_F64 * 2 ** ((p - 64) / 64)
    dec = [bt_dec(tmd(p, 64), f_of(64)) for p in P]
    d64 = bt_dec(tmd(64, 64), f_of(64))
    dq = [bt_dec(tmd(64, p), f_of(p)) - d64 for p in P]
    tunoff = (64 + 48 * math.log2(TX8_F64 / f64)) * 256
    out = [f"| BT TX-8: at PTC 64 the BT DEC spans {dec[0]}..{dec[-1]} for DEC 0..127 "
           f"(t30 {at(t_dec, dec[0]) * bt_g(f_of(64), pts) / g_ref:.0f}..{at(t_dec, dec[-1]) * bt_g(f_of(64), pts) / g_ref:.0f} ms, "
           f"the TX-8 {tmd(0, 64):.0f}..{tmd(127, 64):.0f})"]
    out += [f"        .equ    BT8_TUNOFF, {round(tunoff)}   | BT CLASSIC TUN word at PTC 64 = {TX8_F64} Hz"]
    out += words("b8_dec", dec, "BT TX-8: BT CLASSIC DEC for DEC (t30 at PTC 64)")
    out += words("b8_dq", dq, "BT TX-8: DEC offset for PTC (exact at DEC 64)")
    return out


def attack(tag: str, wave: list, atk: dict, acc: dict, what: str, trim: float = 1.0) -> list[str]:
    """A BD attack waveform as 8-bit samples (normalised to its peak 127) and its gains.
    The machines add (s << 8) * G into voice buffer A per sample, G = A_K * gatk(ATK)
    * gacc(ACC) * LEV (each Q15, >> 15), so that ACC 96, LEV 32768 gives the waveform
    in Machinedrum full-scale units (as the SD noise ports do). G is clamped to 65535
    to keep a full-scale sample below 2^31."""
    peak = max(abs(v) for v in wave)
    amax = max(acc.values())
    P = pts33()
    out = [f"| BD TX-{tag} attack: {what}"]
    out += [f"        .equ    A{tag}_N, {len(wave)}",
            f"        .equ    A{tag}_K, {round(trim * peak * amax * 2**31 / (127 * 256))}"]
    out += words(f"a{tag}_atk", [32767 * at(atk, min(p, 127)) for p in P], f"TX-{tag} BD: attack gain for ATK, Q15")
    out += words(f"a{tag}_acc", [32767 * at(acc, min(p, 127)) / amax for p in P], f"TX-{tag} BD: attack gain for ACC, Q15")
    vals = [int(round(127 * v / peak)) for v in wave]
    out += ["", f"a{tag}_wave:                       | TX-{tag} BD: attack waveform, 48 kHz, 8 bit of its peak"]
    for i in range(0, len(vals), 16):
        out.append("        .byte   " + ", ".join(str(v) for v in vals[i:i + 16]))
    return out


def best_q(target_blocks: float, time_of) -> int:
    """The knob value 0..127 whose time is closest in ratio to the target."""
    return min(range(128), key=lambda q: abs(math.log(max(time_of(q), 1e-3) / max(target_blocks, 1e-3))))


# --------------------------------------------------------------- helpers
def at(table: dict, p: float) -> float:
    ks = sorted(table)
    if p <= ks[0]:
        return table[ks[0]]
    for a, b in zip(ks, ks[1:]):
        if p <= b:
            return table[a] + (table[b] - table[a]) * (p - a) / (b - a)
    return table[ks[-1]]


def pts33():
    return [min(4 * i, 127) if i < 32 else 128 for i in range(33)]


def words(name, vals, comment):
    vals = [int(round(v)) for v in vals]
    lines = ["", "        .align  2", f"{name}:                       | {comment}"]
    for i in range(0, len(vals), 11):
        lines.append("        .short  " + ", ".join(str(v) for v in vals[i:i + 11]))
    return lines


def longs(name, vals, comment):
    lines = ["", "        .align  2", f"{name}:                       | {comment}"]
    for i in range(0, len(vals), 4):
        lines.append("        .long   " + ", ".join(f"0x{v & 0xffffffff:08x}" for v in vals[i:i + 4]))
    return lines


def q31(x: float) -> int:
    return max(-2**31, min(int(round(x * 2**31)), 2**31 - 1))


def render() -> str:
    nod = nod_table()
    bd9 = plugin("TX9/TX9-BD.syx", b"org.spsx.usr.tx9-bd")
    sd9 = plugin("TX9/TX9-SD.syx", b"org.spsx.usr.tx9-sd")
    if bd9[0x5e] != 0xa67c or bd9[0x57] != 0x64e68 or bd9[0x1ea] != 0x200000:
        raise SystemExit("TX-9 BD code does not match the analysis")
    if sd9[0x4d] != 0x140000 or sd9[0x54] != 0x54fcc or sd9[0x57] != 0x6081a8:
        raise SystemExit("TX-9 SD code does not match the analysis")

    P = pts33()
    out = ["| Generated by tools/gen_tx_tables.py - do not edit.",
           f"| One Rytm block = {N:.2f} TX samples. 33-entry tables: p >> 2, linear over p & 3."]

    # ---- shared and TX-9 BD live in cave4 (.text); each other machine in its own section
    out += ["", "        .text"]
    # ---- shared: 3072 * log2(1 + i/64), the tune offset (0x100 per semitone)
    out += words("tx_lt", [3072 * math.log2(1 + i / 64) for i in range(65)], "3072 * log2(1 + i/64)")

    # ---- TX-9 BD
    cb = [q31((bd9[0x187 + i] / Q23) ** N) for i in range(33)]
    e0 = [q31(bd9[0x1a8 + i] / Q23) for i in range(33)]
    a_base, a_gain, a_trim = 0x233333 / Q23, 0x480000 / Q23, 0x4cccd / Q23
    a_max = a_base + a_gain * 127 / 128 - 2 * a_trim
    hold = [(bd9[0x22c + i] + 88) / N for i in range(33)]          # blocks
    hold_ms_default = at({4 * i: hold[i] for i in range(32)}, 96) * BLOCK_MS
    dec9 = [min(range(128), key=lambda q: abs(math.log(bd_seg_ms(q) / max(TX9BD_RYTM_DEC * (at(TX9BD_T30, p) - hold_ms_default), 1))))
            for p in P]
    acc9 = [32767 * math.sqrt((a_base - 2 * a_trim + a_gain * min(p, 127) / 128) / a_max) for p in P]
    k_step = 0x64e68 / 0xa67c / 128 * 4096
    out += [f"        .equ    TX9_KSTEP,  {int(round(k_step * 256))}     | TX-9 BD sweep K per DPT step, Q12 << 8"]
    out += [f"        .equ    TX9BD_TUNOFF, {int(round(tun_bd(0xa67c / Q23 * 0.5 * 44100 / 2) + 256 * TX9BD_RYTM_ST))}   | PTC 64 = 56 Hz on BD CLASSIC (48 Hz at 0x3a00, + the measured trim)"]
    out += longs("t9bd_cb", cb, "TX-9 BD pitch env decay per block (TUN)")
    out += longs("t9bd_e0", e0, "TX-9 BD pitch env start (TUN)")
    out += words("t9bd_dec", dec9, "TX-9 BD: BD CLASSIC DEC for DEC (T60 less the hold)")
    out += words("t9bd_hld", [min(127, round(h)) for h in hold], "TX-9 BD: BD CLASSIC HLD for ACC (= hold in blocks)")
    out += words("t9bd_acc", acc9, "TX-9 BD: LEV scale for ACC, Q15 (sqrt of the TX-9 amp target)")

    # ---- TX-8 BD
    out += ["", "        .section .m35,\"ax\""]
    dec8 = [min(range(128), key=lambda q: abs(math.log(bd_seg_ms(q) / at(TX8BD_T30, p)))) for p in P]
    out += [f"        .equ    TX8BD_TUNOFF, {int(round(tun_bd(49.7)))}   | PTC 64 = 49.7 Hz (measured TX-8 BD)"]
    sig8 = [256 * at(TX8BD_SIGH_ST, p) for p in P]
    acc8 = [32767 * math.sqrt(at(TX8BD_PEAK, p) / max(TX8BD_PEAK.values())) for p in P]
    out += [f"        .equ    T8_SIGH_BLOCKS, {int(round(SIGH_MS / BLOCK_MS))}"]
    out += [f"        .equ    T8_SIGH_RECIP,  {int(round(65536 / (SIGH_MS / BLOCK_MS)))}   | 65536 / T8_SIGH_BLOCKS"]
    out += words("t8bd_dec", dec8, "TX-8 BD: BD CLASSIC DEC for DEC (T30, at PTC 64)")
    q64 = min(range(128), key=lambda q: abs(math.log(bd_seg_ms(q) / TX8BD_T30[64])))
    dq8 = [min(range(128), key=lambda q: abs(math.log(bd_seg_ms(q) / at(TX8BD_T30_PTCH, p)))) - q64 for p in P]
    out += words("t8bd_dq", dq8, "TX-8 BD: DEC offset for PTC (decay shortens with pitch; exact at DEC 64)")
    out += words("t8bd_sig", sig8, "TX-8 BD: sigh start offset, tune units, for SIG")
    out += words("t8bd_acc", acc8, "TX-8 BD: LEV scale for ACC, Q15")
    out += attack("8", A.PULSE8, A.PULSE8_ATK, A.PULSE8_ACC,
                  "the pulse that cuts the 808's first peak (PTCH 64, ATK 64, 5.5 ms), trimmed: "
                  "the pitch step below now makes most of it", trim=TX8BD_PULSE_TRIM)
    out += [f"        .equ    T8_ATK_TUN, {round(256 * 12 * math.log2(TX8BD_ATK_RATIO))}   | attack segment: + semitones * 256",
            f"        .equ    T8_ATK_BLK, {round(TX8BD_ATK_MS_PER_STEP / BLOCK_MS * 128)}   | its length, blocks per ATK step, Q7"]

    # ---- TX-9 SD
    out += ["", "        .section .m37,\"ax\""]
    ptc = [tun_sd(125.0 * (1 + min(p, 128) / 128)) for p in P]
    ratio = [sd9[0x2ef + i] / Q23 * 0xc86c3 / 0x4424c for i in range(33)]
    det = [max(0.0, 256 * 12 * math.log2(r)) for r in ratio]
    k14 = 0x140000 / Q23
    def r_bend(p):          # $15 / $14 at BEND = 128
        pn = min(p, 128) / 128
        return (pn * 0x54fcc / Q23 + 0x6081a8 / Q23) / (k14 * (1 + pn))
    bk = [4096 * r_bend(p) for p in P]
    be0 = [32767 * (0x6755db / Q23 - 0x3aa147 / Q23 * k14 * (1 + min(p, 128) / 128)) for p in P]
    bdec = (1 - 0x7b8a6 / Q23) ** (N / 8)
    dec9s = [best_q(at(TX9SD_BODY_T40, p) / BLOCK_MS, lambda q: rate_time_blocks(sd_body_rate(q), -40)) for p in P]
    acc9s = [32767 * math.sqrt(at(TX9SD_PEAK, p) / max(TX9SD_PEAK.values())) for p in P]
    out += [f"        .equ    T9SD_BEND_DECAY, 0x{q31(bdec):08x}   | bend env per block"]
    out += words("t9sd_ptc", ptc, "TX-9 SD: SD CLASSIC tune re 0x3a00 for PTC (f1 = 125 Hz (1 + p/128))")
    out += words("t9sd_det", det, "TX-9 SD: DET for DTU (ratio from table 0x2ef; below unison clamped)")
    out += words("t9sd_bk", bk, "TX-9 SD: bend K at BND 128, Q12, for PTC")
    out += words("t9sd_be0", be0, "TX-9 SD: bend env start, Q15, for PTC")
    out += words("t9sd_dec", dec9s, "TX-9 SD: SD CLASSIC DEC for DEC (body T40)")
    out += words("t9sd_acc", acc9s, "TX-9 SD: LEV scale for ACC, Q15")
    out += noise9(sd9)

    # ---- TX-8 SD
    out += ["", "        .section .m38,\"ax\""]
    body8 = [best_q(at(TX8SD_BODY_T40, p) / BLOCK_MS, lambda q: rate_time_blocks(sd_body_rate(q), -40)) for p in P]
    acc8s = [32767 * math.sqrt(at(TX8SD_PEAK, p) / max(TX8SD_PEAK.values())) for p in P]
    out += [f"        .equ    TX8SD_TUNOFF, {int(round(tun_sd(250.0)))}   | PTC 64 = 250 Hz on SD CLASSIC"]
    out += words("t8sd_body", body8, "TX-8 SD: SD CLASSIC DEC for PTC (body T40 follows pitch)")
    out += words("t8sd_acc", acc8s, "TX-8 SD: LEV scale for ACC, Q15")
    out += noise8()
    out += toms()
    out += ["", "        .section .m42,\"ax\""]
    out += bt8()

    # ---- BD TX-9 DIGI: the TX-9 kick made digitally (its pitch env, hold and click
    # reuse the BD TX-9 tables above; these three are its own, spread over the caves
    # with room)
    out += ["", "        .section .m42,\"ax\""]
    out += longs("d9_inc", [round(TX9_F64 * 2 ** ((min(p, 128) - 64) / 64) / 48000 * 2**32) for p in P],
                 "BD TX-9 DIGI: phase step per sample at PTC (56 Hz at 64, 2 octaves), no sweep")
    out += ["", "        .section .m35,\"ax\""]
    out += longs("d9_dec", [q31(10 ** (-1.5 * BLOCK_MS / max(TX9D_T30_TRIM * at(TX9BD_T30, p) - hold_ms_default, 5))) for p in P],
                 "BD TX-9 DIGI: amplitude per block after the hold, for DEC (the TX-9's t30, no Rytm trim)")
    out += ["", "        .section .m39,\"ax\""]
    out += words("d9_amp", [32767 * min(0.95, a_base - 2 * a_trim + a_gain * min(p, 127) / 128) for p in P],
                 "BD TX-9 DIGI: the TX-9's amplitude for ACC, of full scale, Q15")
    out += ["", "        .section .m41,\"ax\""]
    trim9 = {p: v * 10 ** (at(TX9BD_ATK_TRIM_DB, p) / 20) for p, v in A.CLICK9_ATK.items()}
    out += attack("9", A.CLICK9, trim9, A.CLICK9_ACC, "the 909 click (fixed shape, 10.5 ms)")
    out += x9_sub()
    return "\n".join(out) + "\n"


def main():
    if "--mk2-x9s" in sys.argv:
        k = X9S_A0 * 65536 * max(X9_PEAK.values()) / at(X9_PEAK, 96) * 10 ** (X9S_MK2_TRIM_DB / 20)
        print(f"        .equ    X9S_K, {round(k)}   | {X9S_MK2_TRIM_DB} dB on the MKII (--mk2-x9s)")
        return
    if "--mk2-bt8" in sys.argv:
        print("\n".join(bt8(mk2=True)))
        return
    text = render()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text() != text:
            raise SystemExit(f"{OUT.relative_to(ROOT)} is out of date: run tools/gen_tx_tables.py")
        print("tables.inc current")
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
