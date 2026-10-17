# 0010 FX SENDS - design and status

## v2 (2026-10-15): the comb dropped, the A4 chorus's controls; built, not flashed

The user's probe readings (mod 0011) showed the Rytm at ~120 MIPS, with stock audio
alone at 77 % and the CPU at 100 % once a send was on. So v2 changes three things:
- the comb is removed: v1 ran both effects whenever any track sent;
- the line and buffers move to DRAM's cached address, 0x428a0000 (re/fx-engine.md);
- the chorus takes the A4's controls.

A one-to-one port of the A4 chorus (0x400f7f50 in A4 OS 1.55) was read and rejected.
It has six voices with filter loops on most of them, lines moved by DMA, and ~2 KB of
tables: about 8,000-9,000 instructions a block, roughly 10 % of the Rytm.

| knob | id | storage | meaning |
|---|---|---|---|
| CHR | 1 | sound word 0, bits 0..6 | chorus send (bits 8..14, v1's CMB, left alone) |
| PRE | 2 | RAM | pre-delay: base delay 48 + 7.2 * PRE samples (1 .. 20 ms) |
| SPD | 3 | RAM | LFO rate, phase step (SPD+1)^2 * 1398 a block |
| DEP | 4 | RAM | sweep from PRE up to PRE + 3 * DEP samples (0 .. 8 ms) |
| WID | 5 | RAM | R's triangle WID/127 of half a cycle behind L's (0 = mono) |
| FDB | 11 | RAM | the taps' average fed back into the line, FDB * 230 / 32768 (<= 0.89) |
| HPF | 12 | RAM | one-pole high-pass on the bus, a = HPF^2 / 2 in Q15 (127: ~2 kHz) |
| VOL | 13 | RAM | the return's level, as v1 |

Only id 1 keeps container 0. Id 2 loses v1's container patch, so no stock path writes
the sound word for it.

Measured in the emulator:
- With CHR on BD: WID 0 gives an L/R correlation of 1.000, against 0.6 at the default
  (96).
- FDB 127 stretches the return's tail from ~20 to ~340 ms.
- HPF 127 cuts the return's energy below 300 Hz from 97 % to 27 %.
- Cost: chorus_run is 2,630 instructions a block with HPF off (~3,000 with it on).
  0010 in all is ~3,200, against v1's ~3,930 with the comb.

The v1 notes below describe the comb, which no longer exists.

## v1 (2026-10-13): built, not flashed

A chorus and a comb filter as two more send effects, with a second AMP page (page 11)
holding each track's two sends and the effects' six global settings. Requested as on
the A4 (chorus / comb sends on a page behind AMP).

| knob | id | storage | meaning |
|---|---|---|---|
| CHR | 1 | sound word 0, bits 0..6 | chorus send |
| CMB | 2 | sound word 0, bits 8..14 | comb send |
| SPD | 3 | RAM | chorus LFO 0.05..8 Hz, `(SPD+1)^2 * 1398` phase a block |
| DEP | 4 | RAM | chorus depth 0..7.9 ms around 10 ms |
| TUN | 5 | RAM | comb pitch, MIDI note (A4 period table) |
| FDB | 11 | RAM | comb feedback 0..0.89 |
| DMP | 12 | RAM | comb damping |
| VOL | 13 | RAM | return level, applied as `(2 * VOL * FX level)^2` like a stock return |

The ids are dead Error records. CHR / CMB take container index 0, as 0008's ids
did. The six global ones keep -1, so no stock path writes anything for them: those
records carry MIDI CC mappings (CC 6, 7, 10, 98/99, 120, 121), and with container 0 a
CC could have overwritten the sound's word. The knobs reach the gates through
`param_apply_delta`, as for 0003 / 0004 / 0008. **Unverified on hardware:** that a
knob with container -1 is still routed there.

## Audio

See `re/fx-engine.md`. `fx_gate` (both `jsr 0x401075a4`) runs the stock FX block,
then:

1. **Clear.** DRAM `0x428a0000..+0x6200` (the cached address; see re/fx-engine.md) is cleared 1 KB a block until done (25 blocks
   after boot); nothing else runs until then.
2. **Coefficients.** Per physical voice, the owning track's CHR / CMB from its live
   sound, `v^2 * 66572` (v 127 -> 0.5 in Q31), gliding 1/4 a block. The voices with a
   non-zero coefficient form the active list.
3. **Buses.** Two **mono** buses: the sum over the active voices of coefficient *
   `rx[i]`. Pan is ignored for the effects' input, and so is the track's SEND TO FX
   switch.
4. **Chorus.** One 2048-long line, two linearly interpolated taps (L at the LFO phase,
   R a quarter cycle later), triangle LFO. The delay glides sample by sample from the
   last block's end value. Wet only.
5. **Comb.** The A4 comb (`lp += (buf[w-D] - lp) * damp; y = x + lp * fb`), mono,
   added to both sides of the return with saturation.
6. **Idle.** With every target zero, it keeps running for 4500 blocks (~3 s) of tail,
   then stops and the return is dropped.

`ret_gate` (both `jsr 0x40107f20`) runs the stock return output, then subtracts
`g * return` from the PRE words, in stock's sign convention: stock's bus and ours are
both positive in the voice, and both PRE words are `-(g * bus)`.

## Known limits of v1

- **Settings not saved.** The global settings are RAM: defaults (SPD 24, DEP 64, TUN 48
  = C3, FDB 80, DMP 40, VOL 100) at power-up, shared by all kits.
- **Mono input.** Pan and SEND TO FX are not applied to the buses.
- **Display.** The comb tune shows a number, not a note name.
- **Exclusions.** It excludes 0004 / 0008 (the sound word).
- **CPU.** Not measured.

## Next

1. **Hardware checks:**
   - the page cycles (AMP twice) and all eight knobs turn;
   - sends are audible on PRE;
   - no UI lag with a few tracks sending;
   - the levels.
2. **Kit storage** for the six global settings (index 29 / 0 of the FX numbering, or
   the kit object): needs a probe.
3. **Sound spare room** (`+0x6d..+0x6f`, stored slot 42), to drop the exclusion.
4. **CPU readout** (0008's P_DIAG method).
5. **Optional:** stereo buses with pan, SEND TO FX, POST routing, a note-name display
   for TUN.
