# MKII ports (Analog Rytm MKII, OS 1.74)

The AE mods in `mods/` are for the Analog Rytm **MK1**. This folder holds their
ports to the **MKII**, OS 1.74, as [elekloader](https://github.com/irpina/elekloader)
elemods: each folder has a `mod.json` and its source, built with elekloader's
SDK and linked with core-ar2 0.10 (OS 1.74 only), next to the rytm2_mods mods.
They need core 0.4 (tx-machines 0.5) or later; nothing in them changed for
0.10, and none of their sites overlaps one of core 0.10's.
duck and fx-sends add their pages through core-ar2 0.4's page tables
(`core_pages`, `core_params`), so they link beside rytm2_mods' pages: that
needs rytm2_mods' lfo-rnd 1.2, voice-dac 1.3, euclid-accents 1.2 and
velocity-humanise 1.2 or later (v1.2's builds of those four do not link with
core 0.4). duck shares COMP with comp-preview 1.1 or later, through core 0.4's
page-key lists.

| folder | MK1 mod | what | status |
|---|---|---|---|
| [cpu-probe](cpu-probe/README.md) | 0011 | CPU, AUDIO and PEAK readouts on the CHANNELS page | hardware |
| [duck](duck/README.md) | 0012 | DUCK page behind COMP: VCA ducking keyed by a track | hardware |
| [fx-sends](fx-sends/README.md) | 0010 | FX SENDS page behind AMP: a chorus send | hardware |
| [tx-machines](tx-machines/README.md) | 0009 | all seven machines (core-ar2 0.5) | emulator + hardware tested |

"Hardware" means checked in rytm-emu and then on an Analog Rytm MKII (OS 1.74,
core-ar2 0.4, 21 Oct 2026; tx-machines on core-ar2 0.5). Each README says what
was checked and what was not.

**Core 0.10** (6 Nov 2026): all four build with elekloader main (7d0bf15) and
link with core-ar2 0.10 on stock 1.74, each alone, all four together, and next
to the rytm2_mods mods (the builds below). Not yet run on core 0.10 in an
emulator or on a unit.

| build on core 0.10 | links |
|---|---|
| each AE mod alone; all four together | yes |
| cpu-probe, duck, tx-machines + all eleven rytm2_mods mods (lfo-rnd 1.3, voice-dac 1.5 without DEP) | yes, 55 of 56 sound bits |
| the same with the released lfo-rnd 1.2 and voice-dac 1.4 | yes, 55 of 56 sound bits |
| all four AE mods + the rytm2_mods mods without voice-dac | yes |
| cpu-probe, fx-sends, tx-machines + the rytm2_mods mods without lfo-rnd | yes |
| duck + comp-preview 1.1 | yes |
| fx-sends + lfo-rnd 1.3 + voice-dac 1.5 | no, 62 bits (below) |

## Building

With an elekloader checkout (main) and the stock OS 1.74 `.syx`:

```
python3 -m elekloader.sdk.build mk2/duck --stock Analog_Rytm_MKII_OS1.74.syx
python3 -m elekloader.patch --stock Analog_Rytm_MKII_OS1.74.syx \
  --mod mods/core-ar2/out/core-0.10.elemod \
  --mod mk2/duck/out/duck-1.0.elemod \
  --version AE10 --out rytm-ae.syx --lockfile rytm-ae.lock.json
```

Keep the lockfile: it decides where fx-sends' CHR sits in the sound's storage.

## Builds that cannot be made

This one follows from what the MKII has room for, and the patcher refuses it:

- **fx-sends with both voice-dac and lfo-rnd**: the three need 62 bits of
  core-ar2's 56-bit sound storage. With lfo-rnd 1.3 and voice-dac 1.5 that is
  fx-sends 7, lfo-rnd 16, voice-dac 32 and core 0.10's LFO destination field
  (`core_lfo_dst`, 7, placed when a build has a lockable LFO field); with
  lfo-rnd 1.2 and voice-dac 1.4 it is 7, 16 and 39. fx-sends links with
  either one.
