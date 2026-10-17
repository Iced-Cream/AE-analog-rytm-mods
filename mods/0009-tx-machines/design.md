# 0009 TX machines - design and status

MK1 only, found on the MK1 image directly. Background: `re/analog-voice.md`.

## History

- **v1 (BD TX-9 + BD TEST), flashed 2026-10-10.** Both machines appeared on the BD
  track and were selectable. Every BD TX-9 knob worked except DEC. v1 held BD
  CLASSIC's DEC and HLD at 127 and applied the TX-9 amp envelope by scaling the
  frame level word every block; the pitch sweep (tune words, also per block) was
  audible, the decay was not. So the voice's amplitude follows BD CLASSIC's
  envelope segments, not later per-block changes of that level word.
- **v2, flashed 2026-10-10.** DEC drives the stock envelopes. Added BD TX-8, SD TX-9,
  SD TX-8. Compared by ear with a Machinedrum running the originals: TX-9 BD DEC
  still near-dead, TX-8 BD DEC "about 15 % of the range", PTC barely audible on
  both kicks; snares too much like the stock Rytm snares, SD TX-9's noise sharper
  and thinner than the 909's. Recordings of both machines (`MACHINEDRUM_USR/WAVS`)
  confirmed the emulator against the real Machinedrum (pitches and decays) and the
  stock-machine models against the real Rytm (BD CLASSIC 48 Hz at 0x3a00, SD
  CLASSIC body decay 70 / 180 / 725 ms vs 46 / 185 / 718 predicted). The PTC / DEC
  weakness is therefore not in the models; recordings of the ports are pending.
- **v3 (this).** SD TX-9's noise is the TX-9's own, ported exactly and added to the
  voice's digital input (SD CLASSIC's noise and snap off). All four machines tuned to
  the Machinedrum's absolute pitches (from the recordings). BD DEC tables fitted to
  the recorded BD CLASSIC decays (TX-9 now uses DEC 0..47 of BD CLASSIC instead of
  0..40; the TX-9's own range is only 75..344 ms to -30 dB).
  Recordings of the v2 ports then showed the knob path is fine: BD TX-8 measured
  23 / 98 Hz at PTC 0 / 127 (MD 25 / 98) and 80 / 1170 ms to -30 dB at DEC 0 / 127
  (MD 65 / 1250). What the port lacked is the TX-8's coupling of decay to pitch (the
  resonator rings ~4x shorter across the PTC range: 634 / 414 / 155 ms at PTCH 0 / 64
  / 127), so PTC sounded like a bare transpose; v3 adds it (`t8bd_dq`, a DEC offset
  per PTC, exact at DEC 64). The Rytm ports carry more harmonics than the originals
  (2nd at -16 dB vs -20..-51), the same at every pitch: the analog voice path.
  The TX-8's fast "drop" at high PTCH is only its first cycle (the excitation pulse),
  not a sweep, and is not modelled.

## The machines

| slot | machine | runs | knobs (index 9..16) |
|---|---|---|---|
| 36 | BD TX-9 | BD CLASSIC | LEV PTC DEC TUN DPT ACC WAV TRA |
| 35 | ~~BD TX-8~~ (dropped in v10) | - | - |
| 37 | SD TX-9 | SD CLASSIC | LEV PTC DEC TON SNP ACC BND DTU |
| 38 | SD TX-8 | SD CLASSIC | LEV PTC DEC TON SNP ACC DET TRA |
| 39 | XT TX-9 | XT CLASSIC | LEV PTC DEC TYP ACC BND NOI TON |
| 40 | XT TX-8 | XT CLASSIC | LEV PTC DEC TYP TUN ACC DIO NOI |
| 42 | BT TX-8 | BT CLASSIC | LEV PTC DEC SIG ACC HLD NOI ATK |
| 41 | BD TX-9 DIGI | digital (BD CLASSIC silent) | LEV PTC DEC TUN DPT ACC WAV ATK |
| 44 | ~~BD TEST~~ (hidden again in v10) | stock | - |

Each TX machine is `machine(voice, ctx, params, note)` like any other: it builds a
parameter block and calls the stock machine, which does everything audible.

| TX knob | goes to |
|---|---|
| pitch (PTC) | stock TUN: `0x3a00 + 48 (p - 64)` for the 2-octave exponential ones; TX-9 SD from `f1 = 125 Hz (1 + p/128)` |
| sweep / bend / sigh | stock TUN, every block: `12 log2(ratio)` semitones (sigh: linear fall over 165 ms) |
| decay | stock DEC (BD/SD body) or NOD (SD noise), through tables matched to the TX decay times |
| TX-9 BD hold | stock HLD (one block per step), from ACC |
| ACC | LEV scaled by the square root of the TX level ratio (stock level goes as LEV squared) |
| SNAP (SD) | stock NOL |
| TX-9 SD detune | stock DET (osc 2 = TUN + DET); below unison clamped to unison |
| TX-8 SD tone | stock BAL |

Stock settings the wrappers fix: BD CLASSIC's own sweep off (SWT = SWD = 0); SD
TX-9's SD CLASSIC SNP (transient) 0x4000 and BAL 0x2000 (their defaults).

## Where the numbers come from

- **From the plugins' code**: the TX-9 BD sweep, the TX-9 SD pitch, detune and
  bend - formulas and tables read out of the DSP56300 code (disassembled with the
  dsp56300 project's disassembler).
- **Measured**: decay times, ACC levels and the TX-8 sigh, by running each plugin
  in the dsp56300 emulator (`tools/tx_measure/`) and analysing the renders: -60 dB
  for the kicks, -40 dB per band for the snares. The emulator reproduces the TX-9
  BD's hand-derived model exactly (silence at 185 ms vs 183 ms predicted).
- **Stock timing**: BD/SD CLASSIC decay segments and SD CLASSIC's noise decay,
  computed from their code (formulas in `tools/gen_tx_tables.py`).

- **v4, first flash 2026-10-11: crashed.** The registry lacked the claims for .m39,
  .m40 and .m41 (a failed script edit), so those sections were linked after cave4 and
  never written: machines 39/40 pointed into stock test-machine code (EXCEPTION, vector
  11 at PC 0x003c0000 - the note argument used as a return address) and every name
  pointed at unwritten bytes (garbled labels). Verify passed, because nothing checked
  where a `from_symbol` patch points. build.py now refuses a stub section with no claim
  and a `from_symbol` pointer outside the mod's claims (negative-tested). Kits saved with
  machine 39/40 under that build are safe to load with the fixed one.
- **v4.** XT TX-9 (slot 39) and XT TX-8 (slot 40) on the LT and MT/HT voices,
  running XT CLASSIC. SD TX-8's noise replaced by a matched digital noise. Machine
  41's routine holds all names (41 pointed at DISABLE).
- **v4 fixed, flashed 2026-10-11.** Toms load and play. But they were 5..12 semitones
  sharp (XT pitch had been assumed), DEC was XT CLASSIC's own, and the re-used records
  of ids 334 342 356 358 359 372 374 376 377 381 kept their centred value display, so
  XT TX-8 TYP read -64..-59.
- **v5.** Tom pitch and DEC calibrated (below). Those ten ids' formatter
  prototypes are patched from centred (0x416a6a2c) to plain 0..127 (0x416a6a4c) in
  the boot-time param_info constructor.
- **v6 (this; WAVS2 recordings, 2026-10-11).** v5 played toms 6.5 semitones low on MT:
  the "MT voice is higher" reading had come from a TX-8 take at TYPE 1, and both
  voices in fact tune and decay alike. So the voice correction is gone, and the decay
  model has been refitted on one voice (18 hits, 0.11 octave rms).
  - TX-8 tom: the congas are dropped (TYP 0..2), pitch is set to the MD's settled
    91 / 141 / 192 Hz, and TUNE is 0 at 64.
  - TX-9 tom: the bend now falls with tau 9.5 ms (it was 27); a flat start of 12 % of
    t-30 at the longest damping comes before the tail; TYPE 1, 2 ring 0.68x.
  - TYP on both toms shows LT / MT / HT through a std::function prototype of our own
    (`fmt_lmh`: stock manager 0x400f56ba, invoker → sprintf "%s").
  - BD TX-9 / TX-8: TRA is replaced by ATK, the TX attack added into buffer A after BD
    CLASSIC (whose transient is set to 0). The waveforms were extracted from the
    plugins (`tools/tx_measure/atk_extract.py` → `tools/tx_atk_data.py`), stored 8-bit
    at 48 kHz.
- **v7.** Field report on v6: the toms work and TX-8 is close; the TX-9 BD click
  level is right; the TX-8 BD pulse is too loud; BD TX-9 ATK still showed the stock
  transient picture.
  - BD TX-9 ATK (id 349) is a slider: the stock control setup for that id was the
    Transient one (knob descriptor 0x401ba364 at entry + 4, control prototypes at
    + 0x28 / + 0x48), so it is repointed to id 341's (0x401ba38c, 0x416a67bc,
    0x416a640c).
  - v7.1 fix: v7 first used descriptor 0x401ba328 = {1, 0x100, 0x40, 0, 0x78}, a
    1/256-step one with no push speed-up, so ATK felt sticky and pushing the encoder
    didn't speed it up. Id 341 holds {0x100, 0x800, 0, 0, 0x50} at run time (read
    from the emulator), which is 0x401ba38c.
  - BD TX-8 ATK: the real mechanism. The 808 kick starts on a segment at ~2.2x the
    pitch, 0.067 ms per ATK step (half-periods of 2.0 ms against the body's 4.7 at
    PTCH 127; ~8.5 ms at ATK 127), then drops to the body. It is played as a
    +13.7-semitone TUN step for ATK * 0.1 blocks. The pulse, which was mostly this
    effect, is trimmed to 0.3x.
  - XT TX-9: the second partial. It is exactly 2/3 f (61 / 74.5 / 91.5 Hz against 91.5
    / 112 / 134.5), ~5 dB under the main and decaying ~1.1x as long. A digital
    parabolic sine is added into buffer B after XT CLASSIC (its tail rewrites B every
    block, so a machine change mid-note leaves nothing behind). Code in .m37 (now
    full), tables and state in .m41.
  - BD TX-9 against the MD (WAVS2): a semitone flat (53.1 vs 56.0 Hz), the decay after
    the ~40 ms hold 1.3x too fast (-30 dB at 128 vs 160 ms), and a lopsided waveform
    (2nd harmonic -16..-18 dB vs the MD's -26, 3rd -27..-32 vs -46: BD CLASSIC WAV 1).
    Trimmed: TX9BD_RYTM_ST, TX9BD_RYTM_DEC; WAV defaults to 0. Kits keep their stored
    WAV.
  - Hidden machines and BT CLASSIC, read for a BT-path TX-8: `re/hidden-machines.md`.
- **v10 (2026-10-17).** BD TX-8 (slot 35) dropped: BT TX-8 replaces it. Its mask is
  back to 0 and machine_fn[35] points at DISABLE (so a kit naming it plays nothing);
  the routine and its names are gone from the stub, its tables stay (BT TX-8 and BD
  TX-9 DIGI use t8bd_sig, t8bd_acc and a8_*). BD TEST (slot 44) hidden again: mask 0,
  stock otherwise. Emulator list, LEFT from BD PLASTIC: FM, CLASSIC, HARD, TX-9 DIGI,
  TX-9.
- **v9 (2026-10-15).** BD TX-9 DIGI, slot 41 (once BD FM 2, then DISABLE): the TX-9
  kick computed digitally into buffer A each block - a parabolic sine refined by
  s (0.775 + 0.225 |s|), the TX-9's sweep envelope (BD TX-9's t9bd_e0 / cb, TX9_KSTEP),
  hold (t9bd_hld) and decay (d9_dec: TX9BD_T30 x 1.08, the real MD's ratio to the
  emulator table), amplitude the plugin's own linear law (d9_amp), the click via
  t9_attack. BD CLASSIC runs under it at LEV 0, so the voice's housekeeping stays stock,
  and since it rewrites buffer A every block the machine adds. Code in .m34 = cave12,
  BT IMPROVED's routine (machine 34 pointed at DISABLE; its only reference is its
  machine_fn entry); tables and state in the tails of .m35, .m39, .m41, .m42, names in
  .m38. Ids 382 / 389 get the plain formatter, 389 also id 341's descriptor and slider.
  Emulator: sweep 175 > 122 > 83 > 64 > 58 > 56 Hz against the recorded MD's 171 > 120
  > 85 > 65 > 58 > 56; -10/-20/-30 dB at 85/130/165 ms, the recording's exactly.
  ~2,260 instructions a block while sounding.
- **v8.** From the WAVS3 recordings (2026-10-13; the user's main-out level
  changed during the session, so only levels relative to the same hit are used).
  - **BT TX-8**, new, slot 42 (RS FM 2's routine, cave11), on the BT track. It runs BT
    CLASSIC every block: PTC goes to TUN (49.7 Hz at 64, a quarter semitone per BT
    step, so 3/4 step per PTC step). The sigh and the 2.2x ATK step are BD TX-8's,
    times 4 in BT steps. HLD holds BT DEC 127 for HLD blocks. NOI goes to NOL. SNP
    and SWD are 0.
    - Decay: BT DEC from a table plus a PTC offset (gen_tx_tables.py bt8). It uses a
      separable model of BT CLASSIC's t30 fitted to the recordings: 1863 / 726 / 64 ms
      at 25 / 61 / 131 Hz (DEC 63), and ~50 / 252 / 412 / 548 / 650 ms at DEC 0..127
      (77 Hz).
    - At PTC 64 it spans 157..1197 ms. The TX-8's DEC 0 (55 ms) is out of reach.
    - Category -1 like XT CLASSIC, so it comes after DISABLE when stepping RIGHT. With
      category 4 (BT's) it was not found that way. It was probably at the end of the
      list, reached by LEFT, where BD TX-9/TX-8 sit (category 0).
  - **TX-8 decay vs pitch** (TX8BD_T30_PTCH, also used by BD TX-8): the real MD rings
    872 / 439 / 239 ms at PTCH 0 / 64 / 127 (slope fits). That is flatter than the
    emulator's 634 / 414 / 155, so the table follows the recording.
  - **BD TX-9**: the sweep matches the MD. The tail was 57.0 vs 56.0 Hz (−0.31 st
    more on TX9BD_RYTM_ST). t30 was 90 / 185 / 410 vs 80 / 165 / 365 ms at DEC 0 /
    64 / 127, so the decay is ×0.87.
  - **BD TX-9 click**: energy above 700 Hz in the first 10 ms, against the body. It
    is +4 dB at ATK 0..64 and +7 dB at 127 against the MD, but ATK 0 has no digital
    click: that part is BD CLASSIC's own onset. With it taken out, the click matches
    at ATK 32 and is ~4 / ~8 dB hot at 64 / 127. Half of that is trimmed
    (TX9BD_ATK_TRIM_DB), since the MD takes clip and the user liked the level.
  - **SD TX-9 noise**: +1.5 / +1.8 dB at SNP 64 / 127, with the same decay. Trimmed
    −1.7 dB.
  - **XT TX-9 partial moved to buffer A.** The v7 recordings show nothing at 2/3 f:
    −39..−45 dB against the MD's −6, no different from v6. In the emulator the
    partial was in buffer B at the designed level.
    - Ruled out: the resonator filtering it. The user plays samples on the tom tracks
      at a level matching the toms, and voice_out (0x4010795e) sums A, B and the
      sample buffer the same way for every voice.
    - Unexplained: why B is not heard. In the emulator, B keeps XT CLASSIC's noise
      at ~−30 dBFS for seconds after a hit, which would be a constant hiss on the
      hardware if B played as assumed.
    - v8 therefore writes the partial into buffer A, the path the BD attacks and SD
      noises take (proven on the hardware). Nothing stock writes A on the tom voices
      (XT CLASSIC hands its tail B only), so x9_sub stores rather than adds, and
      writes zeros once the partial has died. Checked in the emulator: A carries it,
      then returns to exactly 0.
    - x9_sub moved from .m37 (full) to .m42.
    - Caveat: a machine change on the tom track while a partial plays leaves that
      32-sample block in A until the next XT TX-9 note.

## The toms (v4)

XT CLASSIC is a different kind of machine from BD/SD CLASSIC: the LT and MT/HT voices
are analog resonators. Every block it writes the resonator frequency word (pitch
through `0x40117a14`, 0x200 per semitone, sweep computed on the CPU) and a damping
word (from DEC and the frequency) straight into the frame, and pings the voice with a
decaying pulse written into the DAC ring (`DAC_LT_TRIG` / `DAC_MT_TRIG`). Its noise is
digital (NOL, NOD from table 0x401c5550, TON tracking the pitch).

| TX | goes to |
|---|---|
| PTCH, TYPE (and TX-8 TUNE) | XT TUN, from the measured Hz per TYPE (TX-9: f0 (1 + p/128); TX-8: 2 octaves) |
| TX-9 BEND / TX-8 DIOD | the attack bend / droop, per block on TUN |
| DEC | XT DEC word per block, from the TX's t-30 and the pitch (v5, below) |
| NOIS | XT NOL; NOD fixed to the TX's noise decay |
| ACC | LEV |

**Calibration (v5, recordings of 2026-10-11; corrected in v6: there is no voice
difference, f0 is 50 Hz on both, and TREF is 1120 ms, K_P 1.90, g 1/16 / 1.37).** Pitch: XT CLASSIC plays
`f0(voice) * 2^p`, with p = (TUN - 0x4000) / 6144 at note 60. The v4 ports at known
words gave 50.0 Hz at p 0 on the LT voice (89 / 134 / 177 Hz at p 0.83 / 1.42 / 1.83, so it
is exactly exponential), and stock XT CLASSIC at TUN 0 settles to the same 50 Hz once
its default sweep has run out. The XT TX-8 recording (made on the other voice) gave 73 Hz,
so on voice 5 the machines subtract `XT_V5` (0.55 octave). Near the top the MT/HT
voice compresses (312 Hz where 410 was due), and stock TUN +63 on LT is only a click.

Decay is analog, and the stock damping word mixes DEC (through `-512 T0 / (DEC + 256)`)
with the pitch. It is fitted as t-30 = TREF(voice) * 2^(-1.75 (p - 1)) * g(DEC word),
with g piecewise power-law in DEC + 256: about 1/15 at 0 and 1.23 at 0x7f00, relative
to 0x4000. TREF is 1220 ms on LT and 530 ms on MT/HT. Per block, `xt_dec` computes
idx = A[DEC] + B[voice] + TUN * KP >> 16 (A = 16 log2 of the TX's t-30, from the
emulator) and looks the word up in `xt_dxt`. The TX-9's decay does not depend on pitch,
while the TX-8's goes as f^-0.93, which is folded into KP and B. This is a fit to seven
points per voice; expect DEC to sit within about 30 % of the TX.
Beyond 1.5 s, stock code ramps the damping up anyway, so the TX-8's 2..3 s settings
can't be reached.

## SD TX-8 noise (v4)

The TX-8 SNARE's noise comes from sample tables and cascaded filter sections - a port
would be long - so it is **matched**, not ported: isolated in the emulator (SNAP x
minus SNAP 0), its spectrum fitted (1.3 dB rms over 15 bands) by a 2-pole Butterworth
high-pass at 2.42 kHz and a 1-pole low-pass at 3 kHz, designed at 48 kHz; instant
attack, exponential decay per block from DEC (its measured decay times), level from
SNAP and ACC (measured), times LEV. Same engine and output (buffer A) as the TX-9 noise;
SD CLASSIC's noise off.

## SD TX-9 noise (v3)

The TX-9 SNARE's noise is digital on the Machinedrum too, so it is ported, not
approximated (`tx9_noise`, data from `noise9()` in the generator):

- white noise (32-bit LCG, half scale) through the plugin's 3rd-order filter,
  `y = 2 (c0 x + c1 x1 + c2 x2 + c3 y1 + c4 y2 + c5 y3)`, coefficients P 0x331..,
  re-warped from 44.1 to 48 kHz (pole/zero angles and log radii * 44.1/48, noise
  power kept);
- its envelope, stepped every 16 TX samples (1.84 per block): attack C refilling to
  a ceiling D, decay toward a floor F at the TONE rate (table P 0x2ad), amplitude
  through table P 0x310, times 0.658 SNAP, times LEV; ramped across each block;
- added into voice_out's buffer A (`0x80006c70 + 128 * voice`), which SD CLASSIC
  rewrites every block and which reaches the analog voice before its filter.

Validated in steps: the decoded model against the plugin in the emulator (envelope
to 24-bit rounding; isolated noise output to 0.2 % residual energy); the integer
model of the ColdFire code against that model (amplitude to 1e-4).

**Level is not calibrated**: digital full scale on buffer A is assumed to equal the
Machinedrum's full scale relative to the analog body. A recording of SD TX-9 at
SNAP 64 against the Machinedrum fixes that constant.

## Assumed, not measured

- The stock envelope segments tick 16 times per audio block (the stock state
  machine's timer does; whether the hardware envelope uses the same tick is
  inferred). If not, every decay is off by the same factor - longer or shorter -
  but DEC still works and stays monotonic.
- The absolute pitch at TUN 0x3a00 is unknown, so each machine's pitch range is
  anchored at the stock default for PTC 64, not at the TX machine's Hz.
- SD CLASSIC's BAL curve is not decoded: SD TX-8's TONE passes straight through.

## Not ported

- TX-9 BD: drive (DRV) - digital, not wanted for now. (ATK ported in v6.)
- TX-8 BD: TONE (slight brightness).
- Levels of the digital parts (BD attacks, TX-9 tom partial) against the analog
  body: set by the Machinedrum's ratios, with buffer full scale assumed to equal MD
  full scale. The user found this right for the TX-9 click; the rest is unverified.
- TX-8 BD: the extra pitch drop the resonator gives at high PTCH.
- TX-9 SD detune below unison (DTU < ~28).

## Space

| pool | what was there | used |
|---|---|---|
| cave4 `0x40116444` | SD/RS/CY/CB TEST machines (entries -> DISABLE) | 1148 / 2010 B |
| cave5 `0x40108b24` | BD HARD 2 (hidden) | 528 / 1296 B |
| cave6 `0x40110018` | SD HARD 2 (hidden) | 996 / 1168 B |
| cave7 `0x4010f730` | SD CLASSIC 2 (hidden) | 726 / 1148 B |
| cave11 `0x4010fbac` | RS FM 2 (hidden) | 616 / 1132 B (BT TX-8) |


## Not yet checked on hardware

- That DEC, HLD (TX-8 BD) and the SD decays now do what the tables intend.
- SD TX-9 / SD TX-8 appear on the SD track, and only there.
- Bend (SD TX-9) and sigh (BD TX-8) sound smooth at block rate.
- Kit save/reload with each machine.
