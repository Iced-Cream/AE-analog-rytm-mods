# TX machines (MKII), 0.2: all seven machines

Port of [0009-tx-machines](../../mods/0009-tx-machines/design.md) (Analog Rytm
MK1) to the Analog Rytm MKII, OS 1.74, as an elekloader elemod on core-ar2 0.5.
Version 0.1 had the two TX-9 machines (emulator and unit tested, below);
0.2 adds the other five of the MK1 mod, which so far are only assembled
(emulator and unit tests pending).

| slot | machine | track | knobs | runs |
|---|---|---|---|---|
| 36 | BD TX-9 | BD | LEV PTC DEC TUN DPT ACC WAV ATK | BD CLASSIC, plus the TX-9's click |
| 37 | SD TX-9 | SD | LEV PTC DEC TON SNP ACC BND DTU | SD CLASSIC, plus the TX-9's own noise |
| 38 | SD TX-8 | SD | LEV PTC DEC TON SNP ACC DET TRA | SD CLASSIC, plus the TX-8's noise (0.2, untested) |
| 39 | XT TX-9 | MT, HT | LEV PTC DEC TYP ACC BND NOI TON | XT CLASSIC; TYP picks LT, MT or HT tuning (0.2, untested) |
| 40 | XT TX-8 | MT, HT | LEV PTC DEC TYP TUN ACC DIO NOI | XT CLASSIC (0.2, untested) |
| 41 | BD TX-9 DIGI | BD | LEV PTC DEC TUN DPT ACC WAV ATK | BD TX-9 with the digital wave (0.2, untested) |
| 42 | BT TX-8 | BT | LEV PTC DEC SIG ACC HLD NOI ATK | its own tone and noise on the BT voice (0.2, untested) |

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

**0.2 (the five new machines):** assembled only. Points to check first: TYP
(records 366 and 374) shows LT/MT/HT through `core_params` and keeps its 0..2
range after the boot copy of a plain knob's control; each machine lists only
on its track; BT TX-8 does not use the digital stream (BT CLASSIC clears it
every block on OS 1.74); CPU with BD TX-9 DIGI.

**0.1 (BD TX-9, SD TX-9):**

**Emulator** (rytm-emu, OS 1.74, 23 Oct 2026, builds TX74 to TX7E): BD TX-9
is listed only on the BD track and SD TX-9 only on the SD track; their SRC
pages show the knobs in order with the MK1 defaults; ATK turns 0..127 as a
slider; both PTCs read 0..127 on a plain dial; the stock machines keep their
centred TUN and TRA picture, also after switching a track between a TX
machine and a stock one; a kit saved with both reloads with both.

**Unit** (Analog Rytm MKII, 23 Oct 2026, TX7E = stock 1.74 + core-ar2 0.5 +
this mod at 970868e + analoghealth, 20 recorded takes, sequencer trigs at
the pattern's default velocity), next to hugz202's Machinedrum (MD) and MK1
port recordings:

| | MKII | MD | MK1 port |
|---|---|---|---|
| BD TX-9 sweep at defaults | 168 > 117 > 80 > 63 > 57 > 56 Hz | 171 > 121 > 85 > 65 > 58 > 56 Hz | settles at 57 Hz |
| BD TX-9 DEC 0 / 64 / 127, to -30 dB | 80 / 145 / 360 ms | 80 / 165 / 365 ms | 90 / 185 / 410 ms |
| SD TX-9 body at defaults | 287 > 232 > 208 > 187 Hz | | 232 > 208 > 188 Hz |
| SD TX-9 noise re body, SNP 64 / 127 | -19.4 / -12.8 dB | -20.4 / -15.7 dB | -18.9 / -13.9 dB |
| SD TX-9 noise envelope to -30 dB | -9 / -19 / -31 dB at 100 / 150 / 200 ms | -10 / -19 / -31 dB | -9 / -19 / -28 dB |

Every knob responds: BD PTC 0 settles at 28 Hz, DPT 0 is flat and 127 sweeps
411 > 61 Hz, ATK 0 / 64 / 127 give the click at -53.8 / -51.9 / -47.8 dBFS
(above 700 Hz, first 10 ms); SD PTC 0 / 127 settle at 125 / 250 Hz, DEC 0 /
127 give a body of 65 / 405 ms to -40 dB, BND 127 bends 458 > 194 Hz in 14 ms,
TON 0 / 127 shorten and lengthen the noise. The noise does not follow the
body's envelope (identical at DEC 0, 64, 127), as on the MK1. CPU with both
machines playing: 76 % (68 % with the same kit idle), DSP 71 %, peak 83 %.

Below -30 dB the reference recordings reach their noise floor, so the noise
tails can only be compared to there. Left as they are: the BD click and the
SD noise sit a few dB above the MD's, about where the MK1 port sits, whose
click was kept hot on purpose (design.md, v8).

Not checked:

- The MIDI CC scaling of ATK (record 349's stock maximum was 55).
- A full kit of TX machines alongside rytm2_mods' mods, for CPU.
