# The analog voices and the machines that drive them

Stock MK1 OS 1.73, MAIN OS at `0x40000400`. Read from `build/mainos_emac.dis`
and `build/stock_mainos.bin` on 2026-10-10, static only - nothing here has run.
**[measured]** = read directly; **[inferred]** = reasoning on top.

Asked: can a new BD machine (808/909 style, after the Machinedrum TX-8/TX-9 user
machines in `MACHINEDRUM_USR/`) be added on the analog core? Short answer: the
mechanism is far more accessible than expected - a machine is one function called
per audio block - but the hardware control formats are only partly decoded.

## A machine is one function per block [measured]

The audio interrupt, right after `lfo_block` (`jsr` at `0x40119b12`), loops over
the 8 physical voices (`0x40119c4e..0x40119d42`):

- `track = voice_owner[voice]` (`0x40254e2c`)
- `machine = (s8) 0x8000553c[track]` - the per-track machine type; `> 52` skips
- `fn = machine_fn[machine]`, **table at `0x402543d0`, 53 longs**
- `fn(voice, ctx = 0x80004ce0, &PARAMS_EFF[track][9], level)`
  - `&PARAMS_EFF[track][9]` = `0x800062d2 + 84 * track`: the eight machine
    parameters after LFO, as words
  - `level` = `0x80004ca8[track]` if bit 0 of `0x8000ab54[track]`, else `0x3c0000`
    (accent/velocity scale, not traced)

The table cannot grow in place: `0x402544a4` (its end) is referenced as data.

| # | machine | fn | # | machine | fn |
|---|---|---|---|---|---|
| 0 | BD HARD | `4010a490` | 26 | BD SHARP | `4010b7a0` |
| 1 | BD CLASSIC | `401096f0` | 30 | BD ACOUSTIC | `40109034` |
| 13 | BD FM | `40109d88` | 35 | BD HARD 2 | `40108b24` |
| 21 | BD PLASTIC | `4010b08a` | 36 | BD CLASSIC 2 | `40107f88` |
| 22 | BD SILKY | `4010ab5c` | 41 | BD FM 2 | `401084cc` |
| 27 | DISABLE | `4010d0b0` | 43 | FUNC. GEN. | `4010d410` |
| 44 | **BD TEST** | `40116cae` | 45..52 | SD/RS/BT/LT/MT/HH/CY/CB TEST | |

Full list: names at `0x4018d690` (pairs long/short, index = machine type).

## The BD voice is a dual-VCO "XD" core [measured names, inferred topology]

String evidence: BD TEST's parameters `BD_TUNE1 BD_TUNE2 BD_LEVEL1 BD_LEVEL2
BD_WAVE1 BD_WAVE2 BD_FMOD_EN BD_RMOD_EN`, wave option text `SAW1 SAW2 SINE2`,
`FM RM OFS`, calibration pages `XD_SIN1 XD_SAW1 XD_SIN2 XD_SAW2` ("%s XD VOICE
OSC1/OSC2"). So: two VCOs, sine and saw outputs, FM and ring-mod switches, a level
per oscillator. SD and RS are the same core (`SD_*`, `RS_*` test params;
BD CLASSIC handles voices 0, 2 and 7 with different frame offsets).

Per-machine oscillator calibration exists: table `0x4024075c` lists `BD_HD`(0),
`BD_CL`(1), `BD_FM/1,/2`(13), `BD_PL`(21), `BD_SI`(22), `BD_SH`(26) ... with their
machine type. Calibration RAM tables `0x427802f4`, `0x42781410`, `0x4278252c`,
`0x42783648` (0x1400 B each) for SIN1/SAW1/SIN2/SAW2.

## The control frame at `0x80004ce0` [measured offsets, partly decoded]

From BD TEST (`0x40116cae`), which maps its parameters straight through:

| offset (BD voice) | what | BD TEST writes |
|---|---|---|
| `+90`, `+92` | osc 1 / osc 2 tune, s16 | `(p - 0x4000) * 2` |
| `+94`, `+96` | osc 1 / osc 2 level, u16 | `p * 2` |
| `+160..` | switch bitfield; bit numbers from `0x401c33d0..0x401c33ec` (BD), `0x401c33b4` (SD), `0x401c3398` (RS) | wave select, FM enable, RM enable |
| `+161` bit 4 | set when the voice's state word is 0 (new note) | |
| `+360..+391` | four 8-byte envelope segment descriptors | resets them |
| `+844..+850` | four words | `0x4000, 0, 0x4000, 0` |

SD voice: tunes at `+98`, descriptors `+392`, `+860`. RS voice: `+106`, `+424`, `+876`.

Who ships the frame to the hardware is **not found**. `0xec07xxxx`/`0xec09xxxx` are
byte-wide control registers (UART/SPI-like), not a per-voice CV bank; the frame is
probably DMA'd to the FPGA [inferred].

## How a real machine shapes a kick: BD CLASSIC [measured]

`0x401096f0`, ~1.7 KB:

- **Pitch**: tune param -> `0x40117a44` -> `0x40117a6e` (pitch/calibration
  helpers, not read) -> scaled by `401408` (osc 1) / `267919` (osc 2), clamped to
  0..32767, cached per voice in `0x402543a4` and per (voice, param) in
  `0x427a41ec..`. Recomputed only when the parameter changes.
- **Oscillators**: `0x40112950(voice, osc, wave, tune, 16, gate, out)` called once
  per oscillator.
- **Envelopes**: a per-voice state word at `0x80010004 + 32 * voice` steps 0 -> 1 ->
  2 -> 3 -> -1 (attack, decay, ..., done). Each step rewrites the segment
  descriptors at `+360`: level bytes (`0x7f`), a 4-bit field and a 20-bit rate.
  So the sweep and decay are run by hardware segments the CPU reprograms per
  phase, not by per-block CV writes [inferred from the field shapes].
- **Digital layer**: fills the per-voice 32-sample buffer
  `0x80006c70 + 128 * voice` with an exponential ramp, then tail-calls
  `0x40114e1a`.

## Each analog voice has a sample-rate digital input [measured + inferred]

`voice_out` (`0x4010795e`) sums per-voice buffers (`0x80006c70`, `0x800070b0`,
`0x80006870`) into the voices' DAC words - the `DAC_VOICE_BD..RS` channels.
`0x40114e1a` (shared machine tail) runs two recursive digital sine oscillators for
32 samples and a filter whose coefficients come from `0x401c5ea8`, indexed by a
per-machine settings struct passed as its 3rd argument (BD HARD passes
`0x401fe438`). So every machine can inject its own digital audio - clicks,
transients, noise - into its analog voice, 32 samples per block.
Where in the analog chain this enters (before or after the voice's filter/amp) is
not established.

## Open, in the order a new machine needs them

1. ~~The machine list~~ - **found**: `machine_voice_mask`, byte `0x4018d869[2m]`,
   one bit per physical voice (BD/SD machines `0x85` = voices 0, 2, 7). Machines
   34..52 hold 0, which hides them. Checked by `0x40006fc6(machine, voice)` from
   set-machine (`0x400ba1e2`), the kit setter and the audio interrupt. Mod 0009
   uses it. (The `moveq #53` cluster at `0x40038bb6` is drawing code.)
2. `0x40112950`'s exact signature, and the waveform values.
3. The segment-descriptor format: what the level, the 4-bit field and the 20-bit
   rate mean in time and pitch.
4. `0x40117a44`/`0x40117a6e`: units of the tune word (semitones? calibrated Hz?).
5. Whether per-block tune writes (as BD TEST does) are smooth or zipper.
6. ~~Where the per-voice DAC input sits~~ - before the analog filter (mod 0008's
   notes on `voice_out`).

Also resolved for 0009: `0x40117a44(tune, note)` returns pitch in log2 units,
2^24 per octave (0x100 of the tune parameter = one semitone = one note), zero at
tune 0x4000 and note 60; `0x40117a6e` exponentiates it. BD CLASSIC's parameter
order is LEV TUN DEC HLD SWT SWD WAV TRA (records 108..115).

## Learned from the first flash (mod 0009 v1, 2026-10-10) [measured on the device]

- BD TEST and slot 36 appeared on the BD track once their `machine_voice_mask`
  byte was set: the machine list does walk the mask.
- Per-block changes of the BD CLASSIC tune parameter are audible (the TX-9 sweep
  worked), but per-block scaling of the frame level word `+96` after BD CLASSIC
  wrote it did not shape the decay: the amplitude follows BD CLASSIC's envelope
  segments. Decays have to go through the stock DEC/HLD (as 0009 v2 does).

## Envelope timing [computed from code; the tick rate is inferred]

- A segment rate is 20 bits: exponent e (bits 16..19), mantissa m (bits 0..15).
  Per tick the level is multiplied by `c = (0x80007fff - ((0x7fffffff - (m << 14))
  >> e)) / 2^31`; `0x40117914(threshold, rate) = log(threshold) / log(c)` gives
  the segment length that the stock state machine adds to its timer, which loses
  16 per block.
- BD CLASSIC decay (state 2): rate = `sat(2 (128 DEC + 16383 << 16) 0.50394) >> 11`;
  hold (state 1): `HLD >> 4` ticks = one block per HLD step.
- SD CLASSIC body: rate = `(64 DEC + 16256) << 5`. Its noise is digital, decaying
  by `1.00787 * T[NOD]` per block, `T` at `0x401c2c60`.
- XT CLASSIC (`0x401149b0`) tunes through `0x40117a14`, which weights the tune
  parameter by 1/3 instead of 2/3 (half the sensitivity of BD/SD).

## The cheapest route to a new BD machine [inferred]

Reuse slot 44 (BD TEST): it is a real machine type with eight parameter records
(`0x401932f8..`, kind `0x2c`), so storage, p-locks, kit save and the parameter page
already work for it. Repoint `machine_fn[44]` (`0x40254480`) at new code, rename
its strings and parameter records, and make it visible on the BD track (open item 1).
