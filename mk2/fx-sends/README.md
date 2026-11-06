# fx-sends (Analog Rytm MKII, OS 1.74)

FX SENDS, AE 0010, ported to the MKII as an elemod: a chorus as one more send
effect, with the Analog Four chorus's controls.

1.1 (core-ar2 0.10). On a drum track, press AMP a second time for the SEND
page; on the FX track, press DELAY a second time for the CHORUS page:

| page | knob | range | what | kept | locks, modulation |
|---|---|---|---|---|---|
| SEND | CHR | 0..127 | the track's send to the chorus | per sound | p-lock, scene, performance, LFO, velocity, aftertouch |
| CHORUS | PRE | 0..127 | pre-delay, 1 to 20 ms | per kit | p-lock (FX trig), scene, performance, FX LFO |
| CHORUS | SPD | 0..127 | LFO speed, 0.05 to 8 Hz | per kit | as PRE |
| CHORUS | DEP | 0..127 | sweep depth, 0 to 8 ms | per kit | as PRE |
| CHORUS | WID | 0..127 | stereo width: 0 mono, 127 the taps in opposite phase | per kit | as PRE |
| CHORUS | FDB | 0..127 | feedback, 0 to 0.89 | per kit | as PRE |
| CHORUS | HPF | 0..127 | one-pole high-pass on the chorus input, off to about 2 kHz | per kit | as PRE |
| CHORUS | VOL | 0..127 | the return's level | per kit | as PRE |

All eight are core-ar2 lockable parameters, each with an NRPN (MSB 4) and a CC
from core's pool: CHR on the track's channel, the chorus settings on the FX
track's. In the LFO menus they read AMP:Chorus Send and CHO:Chorus Speed and
so on. A new kit, or one saved without fx-sends, starts the chorus settings at
the MK1's defaults (PRE 40, SPD 24, DEP 64, WID 96, FDB 0, HPF 0, VOL 100,
field inits). In 1.0 they were global, held in RAM, and went back to those
defaults at power-up.

The chorus is the MK1's code: two linearly interpolated taps on one 2048-sample
line, each swept by a triangle LFO, the input high-passed, the taps' average
fed back. It runs in the audio interrupt after the stock delay and reverb, on
the voices the codec captured, and its return is added to the PRE return words
(the path into the analog distortion and compressor), scaled like a stock
return by (2 x VOL x FX track level)². Nothing runs while no track sends and
the tail has died (about 3 s).

## What changed from the MK1

- **Hooks.** keep2 on both calls to the stock FX block `fx_generate`
  (`0x40121406`, `0x4011fe56`) and both calls to the return mixer
  (`0x401213a4`, `0x4011fe2e`). The receive buffer is `0x80007440`, 12 longs a
  frame (10 on the MK1), voice v in slot `0x401ef480[v]`; the voice's owning
  track comes from `0x40291138`.
- **Output words.** The MKII's return mixer keeps the 24-bit value in the low
  bytes of each word (`lsr.l #8`); the chorus is added the same way. Its return
  goes in words 12/13 of each output frame, where stock puts the delay and
  reverb returns when their routing byte is 0 and where voice-dac adds its DAC
  sum. That this is the PRE path on the MKII is read from the code and from
  voice-dac's notes, **not checked on hardware for this mod**.
- **CHR storage.** The MK1 kept CHR in the sound's free parameter word. Here
  it is a 7-bit sound field in core-ar2's mod storage (`fx_sends_chr`),
  so it travels with the sound and the sound's stock bytes stay stock. Each
  edit sends stock's sound change notice, as lfo-rnd and voice-dac do, so it is
  kept without a kit save.
- **Chorus storage (1.1).** Seven 7-bit kit fields (`fx_sends_pre` ..
  `fx_sends_vol`) in core-ar2's kit storage, with `init` values so a kit
  without them reads the defaults.
- **The values the audio uses (1.1).** CHR is read as stock would play it
  (`core_param_value_h`: the sound's value, the trig's p-lock, the scene's
  lock, smoothed with stock's one-pole, plus the performances, the routes and
  the LFO), one voice's track a block in turn, so each voice's send is at most
  8 blocks (5 ms) old, as often as the send coefficients were rebuilt in 1.0;
  they still glide a quarter of the way a rebuild. While the chorus runs (a
  track sends, or its 3 s tail), the seven settings are read on the FX track
  every block in one `core_param_values` call. Both reads run before the audio
  switches the MAC to fractional mode. 1.0's UI tick copy of CHR is kept only
  for a core that gives CHR no lock code.
- **Memory.** The line and buffers (8.5 KB) are this mod's `.bss`, not raw
  DRAM, so there is no clearing pass after boot.
- **Knobs.** The hidden CY TEST machine's parameter records 449..456, renamed.
  At the first UI tick their RAM records take the dial art and encoder feel of
  COMP's MIX knob (as duck does). The chorus settings keep the turn's 8.8
  fraction while the kit holds its whole step; CHR keeps one fraction, for the
  track it was last turned on. The value text is core's (the number, a held
  trig's lock), so it is no longer drawn by the mod.
- **Pages.** SEND, page 15, after AMP (page 7) in the AMP view's list, with
  CHR on knob A; CHORUS, page 16, after DELAY (page 8) in the DELAY view's
  list, PRE..VOL on knobs A..G; through core-ar2's page tables (`core_pages`,
  `core_params`) and page-key lists (`core_view_pages`, order 30). 1.0 had all
  eight on one page behind AMP.

## Needs and conflicts

- 1.1 needs core-ar2 0.10 (lockable sound and kit fields, `init`,
  `core_param_values`); 1.0 needs 0.4.
- Sound storage: CHR (7) and, as CHR is an LFO destination, core's
  `core_lfo_dst` (7): 14 of 56 bits. With lfo-rnd 1.3 (16) it is 30; with
  voice-dac 1.5 (32) 46. With both it is 62, so **fx-sends cannot be in a
  build with both of them** ("the mods need 62 bits of sound storage").
- Kit storage: the seven settings (49) and core's `core_fx_lfo_dst` (7): 56
  of the kit's 64 bits. duck 1.1 needs 32 more, so **fx-sends 1.1 and duck 1.1
  cannot be in one build** ("the mods need 88 bits of kit storage"). Decided
  2026-11-06: mods are judged on their own where storage is the limit.
- Linked (6 Nov 2026, elekloader 7d0bf15): alone; with cpu-probe and
  tx-machines; with those and the rytm2_mods mods without voice-dac, and
  without lfo-rnd.
- 1.1 in the emulator (rytm-emu, 6 Nov 2026, core 0.10 + cpu-probe +
  tx-machines + fx-sends): SEND and CHORUS pages show (CHORUS on DELAY's
  second press); knob turns write the sound and kit fields; CC and NRPN reach
  the engine's copies; the sound LFO on CHR and the FX LFO on PRE and DEP sweep
  0..127; the fields survive a power-off without a save; a CHR lock recorded
  live by CC plays on its trig only. Open: a lock made with a trig held and
  the knob turned shows on the knob but did not reach playback in the
  emulator (not yet known if the method or the mod is at fault); scene locks,
  performances, vel/AT and the read cost are unchecked. Not run on a unit.
- With core 0.3 (before the page tables), linked and run in the emulator with
  core, ae-pages, cpu-probe, duck and the
  rytm2_mods v1.2 mods minus comp-preview (which then conflicted with duck) and
  minus lfo-rnd or voice-dac. It also linked with comp-preview when duck was left out.

## Status

Emulator (rytm-emu), core 0.4 + fx-sends, and core 0.4 with the rytm2_mods mods
(all but lfo-rnd, so with voice-dac 1.3 and comp-preview) and cpu-probe: the
page shows and its knobs
turn. Earlier, with core 0.3 + the ae-pages framework + fx-sends, and both full
builds above:

- The page shows behind AMP on the BD track with CHR PRE SPD DEP / WID FDB HPF
  VOL, long names in the header while a knob turns, values in the popups.
- Turning CHR stores it through core (`chr_trk[BD]` reads 20, as the knob).
- With CHR 20 and BD played, the chorus bus is the BD voice's slot times the
  send coefficient (checked against the receive buffer), and a run with VOL 0
  against VOL 100 differs only in the PRE words (12/13) of the output frames,
  L and R differing (WID 96). POST words are untouched.

**Hardware**, Analog Rytm MKII OS 1.74, 21 Oct 2026, core 0.4 with rytm2_mods
without lfo-rnd, and cpu-probe: CHORUS SEND opens behind AMP with popups and
long names, CHR on one track gives a chorus on that track only, and VOL changes
its level; DAC FILTER and the COMP preview work beside it; cpu-probe was read
with the chorus on. With core's page step (no lfo-rnd in the build) the header
names CHORUS SEND; with DAC SUM, the chorus and the preview together, the audio
interrupt reads 92% and peaks at 94%, nothing audible.

**1.1 not checked anywhere yet** (built and linked only): the two pages and
their knobs, CHR's and the chorus settings' locks, scene locks, performances,
LFO and routes, the CCs and NRPNs, the chorus settings kept through a kit save,
a reload and a power cycle without a separate save (1.1 sends no kit change
notice), that the borrowed ids 450..456 are kept from stock's FX setter on the
FX track (core-ar2 0.9 says core does this), and the audio's cost of the reads
(about 0.9% of a block for CHR's read with its routes, on a unit, and well
under 1% for the seven in one call, by core-ar2's figures). It changes the
sound path, so it waits for the owner's listening check too.

**1.0, not checked on hardware:** the level of the return against the delay and
reverb, and CHR surviving a kit save, a reload and a power
cycle (the same storage path lfo-rnd and voice-dac use, which was
hardware-tested for them).
