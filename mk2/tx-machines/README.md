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
- **ATK's control.** BD TX-9's ATK is record 349, which the OS builds as a
  stepped picture (BD CLASSIC 2's Transient). Once after boot the mod gives it
  record 344's plain slider, the same fix the MK1 mod made in v7.
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

Not built against the stock file or run yet: this version assembles. Next:
the emulator (both machines listed only on their tracks, every knob turns,
ATK a 0..127 slider, a kit with them reloads), then a unit test.

Not checked:

- Anything audible on the MKII: pitch and decay ranges, the click and noise
  levels against the analog body.
- Whether anything reads record 349's old maximum (55) after boot, for
  example the MIDI CC scaling of ATK.
- CPU time. SD TX-9's noise runs a third-order filter over 32 samples a block
  while it sounds; stock already takes most of the audio period.
