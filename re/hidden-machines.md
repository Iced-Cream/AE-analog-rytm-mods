# Hidden machines (Rytm MK1 OS 1.73)

The machine table (`machine_fn`, 0x402543d0, 53 entries) lists 19 machines whose
voice-mask byte (0x4018d869 + 2m) is 0, so they never appear in the machine list. This
note compares each with its shipped counterpart, from the stock image: parameter
records (PARAM_ROM 0x4018e004), the routines (calls, data, frame writes) and the tables
they read. None of them has been played on hardware yet.

## Summary

The "2" machines look like **earlier development versions of the shipped machines**.
Their envelopes, transient samples and noise are identical: every table they read is a
byte-for-byte copy of the shipped machine's (transient table 0x401bd65c = 0x401bdc08,
sample gains/descriptors, SD noise decay 0x401c2460 = 0x401c2c60, BD HARD constants).
What differs:

- **Tune knob.** The "2"s have TUN 0..127 through `0x40117a14`, which weights the knob by
  1/3: half a semitone per step, ±32 semitones. The shipped machines have TUN 32..96
  (shown −32..+32) through `0x40117a44` (weight 2/3): a semitone per step, the same
  ±32 semitones.
- **No pitch cache.** The shipped machines keep the last tune/note per voice
  (0x427a41ec..) and its exponentiated result (0x402543a4) and skip the `exp2` call
  when nothing changed. This is CPU only, inaudible. The "2"s recompute every block.
- **Size.** The "2"s are 20..30 % smaller, consistent with the points above.

## Per machine

| slot | hidden | shipped twin | difference beyond tune knob + cache |
|---|---|---|---|
| 35 | BD HARD 2 | BD HARD (0) | One pitch control instead of two (see BD CLASSIC 2). |
| 36 | BD CLASSIC 2 | BD CLASSIC (1) | Writes one pitch CV (frame +92, scale 0x4168f) and leaves +90 at 0. BD CLASSIC writes both: +90 at scale 0x62000 (≈1.5x) and +92. BD TEST shows the BD voice has two oscillators (TU1/TU2), so +90 is very likely the second oscillator [inferred]. |
| 41 | BD FM 2 | BD FM (13) | Both FM oscillators tuned (two tune calls) as in BD FM. FMT is also 0..127. |
| 37 | SD HARD 2 | SD HARD (2) | None found. |
| 38 | SD CLASSIC 2 | SD CLASSIC (3) | DET (second oscillator interval) 0..127 instead of 0..32 (default 0x30 vs 0x0c). |
| 39 | RS HARD 2 | RS HARD (4) | Hard-wired to voice 7 (RS/CP): writes 0x8000ace4.., buffers 0x80006ff0 / 0x80007430 / gain 0x800070a8 directly instead of indexing by voice. Same in practice (RS only runs on voice 7). |
| 40 | RS CLASSIC 2 | RS CLASSIC (5) | As RS HARD 2. |
| 42 | RS FM 2 | none | SD FM's parameters (TUN DEC FMT FMD NOD NOL FMA) and code shape: an early SD FM, or an FM machine meant for the RS voice. |
| 34 | BT IMPROVED | BT CLASSIC (7) | Not a "2". No SWD (sweep) knob; uses XT CLASSIC's tail handling (damping ramps after 4500 blocks, frequency after 9000, i.e. long rings are cut after ~1.5 s); own table 0x401fe440. |
| 43 | FUNC. GEN. | none | Factory test generator: NOL, sine level / frequency (SLV SFQ), pulse level / count (PLV PLN). |
| 44..52 | BD/SD/RS/BT/LT/MT/HH/CY/CB TEST | none | Raw per-voice hardware tests: knobs write the analog controls directly, no envelopes, no calibration. |

## What mod 0009 has taken

| slot | taken how |
|---|---|
| 35, 37, 38, 39, 40 | Slot and routine region reused (BD TX-8, SD TX-9, SD TX-8, XT TX-9, XT TX-8). |
| 36 | Slot reused for BD TX-9; BD CLASSIC 2's code (0x40107f88) is still intact, unreferenced. |
| 41 | Slot disabled, routine region holds names, the TX-9 BD click, tom tables, the TYP formatter. |
| 44 | Made visible on the BD track, unchanged. |
| 45, 46, 51, 52 | Routines overwritten (shared helpers, cave4); entries point at DISABLE. |
| 34, 42, 43, 47..50 | Untouched. |

A build without 0009 (or stock firmware) restores all of them, still hidden.

## BD voice waveforms

The BD voice (the SD and RS voices have their own tables) has two oscillators.

- **Pitch and level.** BD TEST: TU1 / TU2 write frame +90 / +92, LE1 / LE2 write +94 /
  +96.
- **Switch bits.** Waveform and routing are bits in the frame's switch bytes (+160 + bit
  / 8). Per voice the bit numbers are in a 7-long table: BD 0x401c33d0 = [12, 44, 8, 47,
  46, 45, 40], SD 0x401c33b4, RS 0x401c3398.
  - entry 1 (bit 44): osc 1 waveform (BD TEST WF1);
  - entry 4 (bit 46): FM on;
  - entry 5 (bit 45): ring mod off;
  - entries 3 / 2 / 6 (bits 47 / 8 / 40): osc 2 waveform.

The osc 2 waveform is set by a shared helper (0x40100a24: frame, bit table, index), the
same mapping as BD TEST WF2:

| index | bit 47 | bit 8 | bit 40 | name (BD SHARP / ACOUSTIC WAV display) |
|---|---|---|---|---|
| 0 | 0 | 1 | 1 | SINE |
| 1 | 0 | 1 | 0 | ASIN |
| 2 | 1 | 1 | 1 | TRI |
| 3 | 0 | 0 | 1 | SSAW |
| 4 | 0 | 0 | 0 | SAW |
| 5 | 1 | 0 | 1 | SQR |

- **Names.** These are the strings of the BD SHARP / ACOUSTIC WAV formatter (0x401b94c4).
  SY RAW's WAV1 list is SINE ASIN TRI SSAW ASAW SAW RING (0x401b94dc).
- **BD CLASSIC.** Its WAV 0 / 1 / 2 sets exactly indices 0 / 1 / 2, i.e. SINE / ASIN /
  TRI. It always has osc 1 on waveform 0, FM off and RM off. It tunes osc 1 (+90) but
  writes its level (+94) as 0.

## BT CLASSIC (for a BT-path TX-8)

BT CLASSIC (0x40114700, voice 1 only) is the same kind of machine as XT CLASSIC: the BT
voice is an analog resonator (bridged-T).

- **Frequency word** (frame +118): `(exp2(p) k << 8 - T1) T0` squared, clamped to
  0..65535, using the calibration at 0x427a42c4/c8.
- **Damping word** (frame +120): the XT CLASSIC formula, `(-T0 512 / (DEC + 256) + T1 +
  p T0) >> 4`, with calibration at 0x427a42e4/e8.
- **Pitch.** `p = tune1/3((TUN - 0x4000) / 2 + 0x4000, note + sweep)` (a quarter
  semitone per TUN step), clamped to −1.33..+1.31 octave. Frame flag bit 7 of +165
  adds an octave.
- **Sweep.** SWD sets an offset added to the note, which decays ×0.961 per block.
- **Trigger.** A decaying pulse of LEV² written into the DAC ring (`0x4277f93c`), as
  XT CLASSIC does.
- **Noise.** Digital, NOL, written to buffer B (0x80007130) by the shared tail.
- **No long-tail cut.** Unlike XT CLASSIC and BT IMPROVED, there is no 4500 / 9000
  block ramp.
