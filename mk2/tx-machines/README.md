# TX machines (MKII), 0.1: BD TX-9 and SD TX-9

Port of [0009-tx-machines](../../mods/0009-tx-machines/design.md) (Analog Rytm
MK1) to the Analog Rytm MKII, OS 1.74, as an elekloader elemod on core-ar2 0.5.
This first version has the two TX-9 machines; the other five of the MK1 mod
(BD TX-9 DIGI, SD TX-8, XT TX-9, XT TX-8, BT TX-8) follow.

| slot | machine | track | knobs | runs |
|---|---|---|---|---|
| 36 | BD TX-9 | BD | LEV PTC DEC TUN DPT ACC WAV ATK | BD CLASSIC, plus the TX-9's click |
| 37 | SD TX-9 | SD | LEV PTC DEC TON SNP ACC BND DTU | SD CLASSIC, plus the TX-9's own noise |

Pick them with the machine knob on the BD and SD tracks, as any machine.

## How it works

Each machine builds a parameter block every audio block from the TX-9's
curves and runs the stock CLASSIC machine with it (design.md of the MK1 mod
has the whole story). The code is the MK1 mod's v10 with the MKII's
addresses, and the tables are the MK1 mod's, unchanged:

- **The machine table.** core-ar2 0.5's `core_machines` puts the engine, the
  home track, the voice (BD voice only, SD voice only) and the knobs' names,
  ranges and defaults in hidden slots 36 and 37. The knobs are those slots'
  own parameter records, so sounds store them, MIDI reaches them on the usual
  CC 16..23, and a kit naming a TX machine loads on a build without this mod
  with that track set to DISABLE.
- **Knob controls.** The OS builds each record's control at boot from its id.
  BD TX-9's ATK is record 349, a stepped picture (BD CLASSIC 2's Transient),
  and both PTC knobs (342, 356, the hidden machines' Tune) print centred,
  -64..63. Once after boot the mod gives ATK record 344's plain slider and
  both PTCs a plain knob's value text and dial, the fixes the MK1 mod made in v5 and v7.
- **Checked in the OS 1.74 code:** BD CLASSIC and SD CLASSIC rewrite their
  voice's whole digital stream every block, so the click and the noise added
  after them never pile up; both mark a new note the way the MK1's did; the
  audio interrupt runs the engines with the MAC in fractional mode, as the
  MK1 code expects.

## Tuning: why the MK1 tables carry over

The MK1 mod was tuned against recordings of an MK1's stock BD CLASSIC and SD
CLASSIC. On 23 Oct 2026 the same machines were recorded on an MKII (stock
1.74 machines, 51 takes, knob sweeps of BD DEC and TUN, SD DEC, NOD and TUN):

| | MKII | MK1 |
|---|---|---|
| BD DEC 0 / 32 / 64 / 96, to -30 dB | 75 / 160 / 650 / 3225 ms | 75 / 175 / 645 / 3305 ms |
| BD pitch at TUN -6 / -12 | 50 / 33 Hz | 48 / 34 Hz |
| SD body at TUN -12 / +12 | 118 / 475 Hz | 114 / 475 Hz |

They agree within the recordings' accuracy, so nothing is retuned.

## Status

Emulator (rytm-emu, OS 1.74, 23 Oct 2026, build TX74 and TX74H = TX74 plus
analoghealth): BD TX-9 is listed only on the BD track and SD TX-9 only on the
SD track; their SRC pages show the knobs in order with the MK1 defaults; ATK
turns 0..127 as a slider; notes on both play without a fault; a kit saved
with both reloads with both. PTC printed centred in that build; with the
fix (TX7C) both PTCs read 0..127, 64 at the default, and the stock machines
keep their centred TUN and TRA picture, also after switching a track between
a TX machine and a stock one. The dial's centre mark went with a later commit
(not yet re-checked). The emulator gave no audio, so
nothing audible is checked yet. Next: a unit test with recordings.

Not checked:

- Anything audible on the MKII: pitch and decay ranges, the click and noise
  levels against the analog body.
- Whether anything reads record 349's old maximum (55) after boot, for
  example the MIDI CC scaling of ATK.
- CPU time. SD TX-9's noise runs a third-order filter over 32 samples a block
  while it sounds; stock already takes most of the audio period.
