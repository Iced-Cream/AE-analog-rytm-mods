# duck (Analog Rytm MKII, OS 1.74)

DUCK, AE 0012, ported to the MKII as an elemod: sidechain-style pumping
without the analog compressor. Every audio block the other voices' analog VCA
words are scaled by a gain that dips when the key track's voice hits.

With the FX track selected, press AMP (COMP) a second time for the DUCK page:

| knob | range | what |
|---|---|---|
| SRC | OFF, BD SD RS CP BT LT MT HT CH OH CY CB | the key track |
| DEP | 0..127 | depth: 127 pulls the other voices fully down (90 is about -10 dB) |
| ATK | 0..127 | attack, instant to about 85 ms (time constant) |
| HLD | 0..127 | hold at full depth after a hit, 0 to 170 ms |
| REL | 0..127 | release, 5 ms to about 2 s (time constant) |

The settings are global and held in RAM: they return to the defaults (SRC OFF)
at power-up, as on the MK1. The delay and reverb returns are not ducked.
Voices that two tracks share (RS/CP, MT/HT, CH/OH, CY/CB) duck together.

## What changed from the MK1

- **Hooks.** The VCA words are written by `0x40109940(frame)`, called once a
  block at `0x401212b2`; that call goes through `duck_gate` (keep2). The words
  sit where they do on the MK1 (frame +10+2v and +26+2v).
- **Key.** The source voice is read from the receive buffer `0x80007440` (12
  longs a frame, voice v in slot `0x401ef480[v]`). It is refilled later in the
  block, so DUCK sees the previous block's audio: one block (0.67 ms) late.
- **Knobs.** Mod-kept ids (core-ar2 0.12; `"knobs": 5`, the linker's `__knobs` + 0..4: 555..559 alone in a build, other ids beside other mods), with no stock record
  behind them: `core_params` gives each knob's value, step and text, and
  `core_param_locks` its label and name (a lock with a trig held is none: the
  settings are global). Until duck 1.0 they were HH TEST's records 443..447;
  core 0.12 gives HH TEST (slot 50) to mod machines, so those records are
  no longer free. The settings keep 8.8 fractions, as stock does, so turns
  smaller than a step add up.
- **Page.** Page 14, after COMP (page 11) in the COMP view's list, through
  core-ar2 0.4's page tables (`core_pages`, `core_params`) and page-key
  lists (`core_view_pages`, order 30: after comp-preview's preview).

## Needs and conflicts

- Needs core-ar2 0.12 with knob looks (mod-kept ids on a page without a record; 1.0 needs 0.4 to 0.11).
- Shares the COMP key with comp-preview 1.1: core-ar2 0.4 builds the
  COMP view's list (COMP, the preview, then DUCK), so the two link together.
- Links with the other ten rytm2_mods v1.2 mods and the AE MKII ports.

## Status

**1.1 (core 0.12): emulator checked on the PC, not run on a unit.** Built with
core-0.12.elemod (sha256 8b949bff...) and elekloader's core-ar2-0.12-knobs
branch (31f87f1); the patched image verifies ("knob ids 555..559").
- Page: FX, AMP, AMP again shows DUCK with the five knobs on A..E.
- Value text OFF/BD../127; turns clamp (SRC at CB and OFF, DEP and ATK at 127,
  HLD at 0).
- Gain curve, SRC = BD, DEP 90, ATK 3, HLD 22, REL 36, SD's VCA L word:
  identical to the 1.0 row below (12735, 3761, 3711, 4759, 6711, 9296, 11607,
  12675); with SRC OFF it stays 12735.
- Labels and long names: the first build drew garbage (core calls label and
  name as C functions and reads the pointer from %a0; duck returned it in %d0
  only). With the fix (9fd1ac4) the labels read SRC DEP ATK HLD REL and the
  header DUCK SOURCE .. DUCK RELEASE; gain table unchanged.
- Knob looks (core 0.12 `core_knob_looks`): all five knobs take COMP MIX's
  look (stock id 191, which 1.0's records copied): its dial art and encoder
  steps, DEP..REL on 0..127 and SRC on 0..12 (SRC's UI record is MIX's with
  +8 = 12<<8, built at the first call). 1.1 is a plain 0..12 SRC again, as 1.0.
  To be checked in the emulator on the core with knob looks (2afb6d9f...).
- To do before this leaves draft: a unit run, and Connor's listening check.

The status below is duck 1.0 on core 0.4.

- Emulator (rytm-emu), core 0.4 + all eleven rytm2_mods mods (comp-preview
  1.1 included) + duck + cpu-probe: the COMP key steps COMP, preview, DUCK.
- Emulator (rytm-emu), core 0.4 + duck, and core 0.4 with the rytm2_mods
  mods (lfo-rnd 1.2, voice-dac 1.3) and cpu-probe: the page shows behind COMP.
  Earlier, with core 0.3 + the ae-pages framework + duck: the page shows behind COMP,
  the five knobs turn with value popups and long names. With SRC = BD, DEP
  90, ATK 3, HLD 22 (set directly in RAM; the emulator's encoder dead zone
  makes small turns unreliable), SD then BD 0.5 s later, SD's VCA L word:

  | t after BD | before | 15 ms | 25 ms | 55 ms | 105 ms | 205 ms | 405 ms | 1 s |
  |---|---|---|---|---|---|---|---|---|
  | MKII port | 12735 | 3761 | 3711 | 4759 | 6711 | 9296 | 11607 | 12675 |
  | MK1 (its design.md) | 12735 | 4103 | 3824 | 4669 | 6626 | 9228 | 11572 | 12673 |

  With SRC OFF the word stays at 12735.
- The emulator models the VCA words, not the analog VCA, so the audible
  result (and the -36/-48 dBFS key thresholds against the MKII's real input
  levels) were checked on hardware afterwards (below).
- Hardware, Analog Rytm MKII OS 1.74, 21 Oct 2026, core 0.4 with all eleven
  rytm2_mods mods and cpu-probe: COMP cycles COMP, comp-preview's preview,
  DUCK; each knob shows its popup and long name; with SRC BD and DEP about 90
  the other tracks duck on each BD hit, the preview's trace running beside it;
  DUCK stays shown on leaving the FX track. With core's page step and kept
  page, DUCK is kept on coming back after DELAY or a voice track, also with
  voice-dac and duck alone (no comp-preview), the header naming each page.
  Not measured: the exact gain
  curve against the table above.

Credit: hugz202 (AE-analog-rytm-mods, MIT) for the mod.
