# The FX engine (Rytm MK1 OS 1.73)

How the delay and reverb are fed, run and returned. Read from `build/mainos_emac.dis`
on 2026-10-13, guided by the MKII project's `re/subsystems/compressor-hardware.md`
(its addresses differ; the structure is the same). Mod 0010 is built on this. Nothing
here has been measured on hardware yet.

## The signal path

Voices, mixer, distortion and compressor are analog. The codec captures each
voice's output, and the ColdFire mixes those captures into two send buses, runs the
delay and the reverb, and plays their returns back through the DAC into the analog
mix. A return goes either PRE (into the distortion and compressor) or POST.

## The audio interrupt's FX calls

The main path at 0x40119e88 and the short path at 0x401189ee make the same five
calls:

| call | callee | what |
|---|---|---|
| `0x40119e8e` / `0x401189f4` | `0x40107f20(dac)` | return output: the previous block's FX buffers into the DAC frame |
| `0x40119e9a` / `0x40118a00` | `0x40107f44(dac)` | ring cursors |
| `0x40119ea0` / `0x40118a06` | `0x40107870()` | the next receive frame pointer: `0x8000cf34 + 40 * k` |
| `0x40119eae` / `0x40118a14` | `0x401078a8(n, rx)` | fills `rx` from the codec: 32 frames of 10 longs (8 voice slots, then 2 negated words) |
| `0x40119eb6` / `0x40118a1c` | `0x401075a4(rx)` | the FX block |

## The FX block, `0x401075a4(rx)`

MACSR is set to 0xa0 on entry and to 0x20 on return.

1. **Send coefficients**, for two buses (d3 = 0 delay, 1 reverb), per physical voice
   i = 0..7:
   - the owning track is `t = voice_owner[i]` (0x40254e2c);
   - the send level `s` is the effective parameter word (`0x800050bc + 2*(2346 + 42t +
     bus)`, i.e. PARAMS_EFF track word 40 / 41 = Delay Send / Reverb Send);
   - `(panL, panR)` is the pan bank `0x40102c04()` = `0x405fbab0 + 64*((counter -
     4) & 7)`;
   - the target is `-(pan * s^2)` per side. The pan law `0x40102868` gives -1.0..0, so
     the targets are positive. Current values are at `0x416c4628` and per-frame steps
     at `0x416c45e8`, as a 32-sample linear ramp.
2. **Mix**: per frame, both sides of each bus are the sum over the 8 slots of
   coefficient * `rx[i]`. The delay send goes to `0x800074b4` and the reverb send to
   `0x800075b4`, each 32 interleaved L/R longs.
3. **Delay**: `0x4010690c`, output `0x800076b4`.
4. **Delay into reverb**: the delay output is mixed into the reverb bus by a ramped
   gain from `0x800066ce`.
5. **Reverb**: `0x4010631c`, in place at `0x800075b4`.
6. **Line DMA** between DRAM and SRAM (MCF547x multichannel DMA at 0xfc0455xx):
   - reverb: 9 lines at `0x4a800000` + 64 KB each;
   - delay taps: 8 at `0x4a890000` + 4 KB each;
   - delay: `0x4ac00000`, 4 MB.
7. **Return gains**: `(2 * level * FX track level)^2` in Q31.
   - The levels are `0x800066d0` (delay) and `0x800066e2` (reverb), 8.8.
   - The FX track level is `0x800062bc`.
   - The routing bytes are `0x800066d4` / `0x800066e4`; non-zero means POST.
   - The PRE bank is `0x427a2228` (delay) / `0x427a222c` (reverb); POST is
     `0x427a2230` / `0x427a2234`. Only the selected bank is non-zero.

The FX init at `0x40106d82` / `0x40106f0a` clears exactly those three DRAM ranges.
`0x4a898000..0x4ac00000` (3.4 MB) is never referenced by absolute address. Mod 0010
clears what it uses itself, because DRAM is not cleared at boot (the A4's lesson).

The 128 MB of DDR is at `0x40000000..0x47ffffff`, and only that range is cached
(ACR0). `0x4axxxxxx` is the uncached mirror: `0x4a8a0000` is the same memory as
`0x428a0000`. Stock keeps its lines there because it moves them by DMA. Code that
reads and writes a line sample by sample must use the cached address. 0010 did not at
first, and on the hardware its chorus cost about 2.5x its instruction count (0011's
readings, 2026-10-14). It now uses `0x428a0000`. An emulator RAM dump of a stock
session shows `0x42898000..` untouched.

## Return output, `0x40107f20(dac)`

It calls `0x40107a60(dac)` (PRE) and then `0x40107c50(dac)` (POST).

- **DAC frame**: `(dac << 11) + 0x80000000`, 32 frames of 64 bytes (16 longs).
  - Voice digital layers are in words 0..7 (VOICE_OUT).
  - **PRE return** is in words 12/13 (+0x30/+0x34).
  - **POST** is in words 14/15.
- **PRE word** = `-(gDel * delay + gRev * reverb ...) >> 8`, 24-bit, with the gains
  ramped. USB audio input routed PRE (`0x8000b334`, routing bytes `0x416c7b7c/7d`)
  joins the same sum.
- **Lag**: the returns written in interrupt k are the FX output of interrupt k-1.

## Storage facts found on the way

- **Drum-track parameters** live in the sound's 42 words (`page_get_value`:
  container index <= 41 -> `sound->+14 + 2*index` via the accessor's vtable +0x28).
- **FX track parameters** (kinds 56..59: DEL indices 9..18, REV 19..26, DIST 27..28,
  COMP 30..37; the FX track's LFO is kind 60, 1..8) do not go through a sound. The
  non-sound branch calls the view's vtable +160 and then that object's getter at
  +40, by id.
  - Index 29 and index 0 are unused in that numbering.
  - Whether the kit stores them, and whether every copy and save path carries them,
    is **not established**. That is what a kit-stored version of 0010's global
    settings needs: a marker probe like MKII mod 0013's.
- **Spare room in the sound** (MKII sound-storage.md; MK1 is the same code base, not
  re-checked): stored slots 42..47 and live bytes `+0x6d..+0x6f`. Opening them takes a
  detour on `sound_load` and one on `sound_save`. That would let 0010 drop its
  exclusion of 0004 / 0008.

## Budget

There is no MK1 load measurement. The MKII project saw the UI queue back up with
about 10 % of a block added. The A4 (same platform) measured 71 % average and 89 %
peak with its stock FX. Mod 0010 does nothing while no track sends. Measuring it is
the next step: 0008's P_DIAG approach (DMA timer 0 around the work) carries over.
