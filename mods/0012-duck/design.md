# 0012 DUCK - design notes

The question: can the Rytm get a selectable sidechain source, as on Digitakt II /
Digitone II, for kick-driven pumping? The compressor is analog and its detector is
wired to the mix, so its own sidechain cannot be re-routed. What firmware can do is
turn the other voices down itself, through their analog VCAs, keyed from a source.

## What was found (OS 1.74, MK1)

- **The control frame** is at `0x80004ce0` (984 B; the MKII's is at 0x800063c0). The
  audio interrupt rebuilds it every block (1.5 kHz) on its normal path.
- **The VCA words**: voice v's VCA L at frame +10+2v, R at +26+2v (u16). Written by
  `vca_frame(frame)` = `0x40102960` (1.73: 0x401028f4), called once a block from the
  interrupt at `0x40119e0e`, at `0x40102b26` / `0x40102b2a`. It smooths level x pan
  in its own state (table `0x405fbab0`) and writes the words from that state on every
  call, so anything done to the words after it never accumulates.
- **The law**: linear in amplitude. PAN keeps L + R constant (0x127e + 0x52d4 =
  2 x 0x32a9 at PAN +40); VOL is a square-ish law in the stock code (VOL 100 ->
  0x32a9, 84 -> 0x24ff, 68 -> 0x1979, 36 -> 0x08dc, 0 -> 0x006b). So multiplying a
  word by g scales that voice's amplitude by g (as the emulator models it; the
  hardware's exact VCA curve is for the ear to confirm).
- **A key signal** is available in the same interrupt: every voice comes back
  digitised in the receive frames, `0x8000cf34 + 40 * idx` (32 frames a block, ten
  longs each: voices 0..7, AUDIO IN L/R), `idx` at `0x402acd70` - the frames the
  stock FX block reads in the same block.
- The interrupt's other path (taken while `0x8000aa58` is set) does not call
  vca_frame; the words then simply keep their last values.

## The prototype

`duck_gate` replaces the operand of that one `jsr` (a 4-byte patch, no detour):
it calls vca_frame, takes the BD voice's peak over the block, runs a gate (opens at
-36 dBFS once the signal fell below -48 dBFS since the last hit) with attack ~3 ms,
hold 30 ms, release ~180 ms, and scales voices 1..7's VCA words by
g = 1 - 0.70 * env. 252 B in cave2; about 300 instructions a block (~0.3 % of the
unit's processor), most of it the peak scan.

Emulator, SD triggered then BD at t = 0 (SD's VCA word; BD's stays at 12969):

| t | before | ~15 ms | ~25 ms | ~55 ms | ~105 ms | ~205 ms | ~405 ms | ~1 s |
|---|---|---|---|---|---|---|---|---|
| SD VCA | 12735 | 4103 | 3824 | 4669 | 6626 | 9228 | 11572 | 12673 |

3824 / 12735 = 0.30: the full 70 % depth, back by about a second.

## Not in the prototype (what a full mod would add)

- A page (e.g. COMP pressed twice, as LFO RND / SMP CUT / FX SENDS do): SRC (the
  track, mapped to its voice), DEP, ATK, HLD, REL, and the key mode - audio (as now)
  or trig (reacts with no latency; the audio key comes ~1 block plus the codec's
  round trip after the hit, so the kick's click passes before the duck).
- Which voices duck (a mask), and the delay / reverb returns (digital: 0010's
  ret_gate already scales a return; the stock returns would need a similar hook).
- Settings kept with the kit or globally (0010's globals are RAM-only so far).
- Voices shared by two tracks (RS/CP, MT/HT, CH/OH, CY/CB) duck together.

## v2: the DUCK page (2026-10-17)

The prototype was flashed on 1.74 and ducked as intended. v2 adds the page:

- **Page 12 behind COMP.** The COMP view (FX track, AMP key) builds its page list
  from `{10}` at 0x401af564 (count `moveq #1` at 0x400c743e); 0012 points it at
  `{10, 12}`. The stock page descriptors are 36 B at 0x4024c634 + 36 * id
  (page_info), {name, 8 ids}; page 10 is COMP (THR ATK REL MUP / RAT SEQ MIX VOL).
- **Knobs**: the dead Error records 7, 8, 9, 14, 15 - the only ones left (0010 has
  1..5 and 11..13; 0 is the null id, 6 and 10 are real). So five knobs: SRC DEP
  ATK HLD / REL; the key thresholds stay fixed (-36 / -48 dBFS). Their container
  index stays -1 and the settings live in the stub (RAM), so nothing stock reads or
  writes them; records 7..9 and 14 keep their stock MIDI fields untouched.
- **SRC -> voice**: BD 0, SD 2, RS 7, CP 7, BT 1, LT 3, MT 5, HT 5, CH 4, OH 4, CY 6,
  CB 6 (the emulator's measured voice map; 0009's voice masks agree for BD BT SD LT
  MT/HT).
- **Shared hooks: detour chains.** page_info, page_get_value, param_apply_delta and
  param_value_text are already detoured by 0010 (and 0004/0008, which 0010
  excludes). tools/build.py now links chains: detours on one host with distinct
  chain_pos; the lowest gets the host's jmp, each stub's `chain_next` symbol is
  defined at link time as the next link's entry, or as its own `chain_stock`
  fallback (the displaced instructions + jmp back) when it is last; later links are
  assembled first. layout.py accepts such a pair, verify.py checks the host jumps to
  the chain's first link. 0012 is chain_pos -1, ahead of 0010.

Checked in the emulator (fxduck build, and 0009 + 0012 without 0010): COMP, then
DUCK on the second press; SRC shows BD.., DEP 100 etc. while turning; with SRC = BD a
hit takes SD's VCA from 12735 to 4578, with SRC OFF it stays; the SEND page and its
knobs (PRE 40 -> 60) still work through the chain; a stock knob (BD VOL -32) still
gives the stock VCA word (0x1979); without 0010 the AMP page is stock.
