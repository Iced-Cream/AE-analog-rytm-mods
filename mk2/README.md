# MKII ports (Analog Rytm MKII, OS 1.74)

The AE mods in `mods/` are for the Analog Rytm **MK1**. This folder holds their
ports to the **MKII**, OS 1.74, as [elekloader](https://github.com/irpina/elekloader)
elemods: each folder has a `mod.json` and its source, built with elekloader's
SDK and linked with core-ar2 0.10 (OS 1.74 only), next to the rytm2_mods mods.

On core 0.10, duck 1.1 and fx-sends 1.1 use core's lockable parameters: their
settings are saved with the kit (fx-sends' CHR with the sound, as before) and
are p-locked, scene-locked, given performance depths, put on MIDI and, where
continuous, made LFO destinations, as stock parameters are. They need core
0.10. cpu-probe 1.0 and tx-machines 0.3 are unchanged (core 0.4 and 0.5 or
later); none of the four mods' sites overlaps one of core 0.10's. duck shares
COMP with comp-preview 1.1 or later, through core's page-key lists.

| folder | MK1 mod | what | status |
|---|---|---|---|
| [cpu-probe](cpu-probe/README.md) | 0011 | CPU, AUDIO and PEAK readouts on the CHANNELS page | hardware (1.0) |
| [duck](duck/README.md) | 0012 | DUCK page behind COMP: VCA ducking keyed by a track; 1.1: kit, locks, FX LFO | 1.0 hardware; 1.1 linked only |
| [fx-sends](fx-sends/README.md) | 0010 | a chorus send: CHR behind AMP; 1.1: CHORUS page behind DELAY, kit, locks, LFO, vel/AT | 1.0 hardware; 1.1 linked only |
| [tx-machines](tx-machines/README.md) | 0009 | all seven machines (core-ar2 0.5) | emulator + hardware tested |

"Hardware" means checked in rytm-emu and then on an Analog Rytm MKII (OS 1.74,
core-ar2 0.4, 21 Oct 2026; tx-machines on core-ar2 0.5). Each README says what
was checked and what was not.

**Core 0.10** (6 Nov 2026): all four build with elekloader main (7d0bf15) and
link with core-ar2 0.10 on stock 1.74 (the builds below). duck 1.1 and
fx-sends 1.1 have not run yet, in an emulator or on a unit.

| build on core 0.10 | links |
|---|---|
| each AE mod alone | yes (fx-sends: 14 sound, 56 kit bits; duck: 39 kit bits) |
| cpu-probe, tx-machines + fx-sends or duck | yes |
| fx-sends + duck | no, 88 of 64 kit bits (below) |
| cpu-probe, duck, tx-machines + all eleven rytm2_mods mods (lfo-rnd 1.3, voice-dac 1.5 without DEP) | yes, 55 of 56 sound bits |
| cpu-probe, fx-sends, tx-machines + the rytm2_mods mods without voice-dac, or without lfo-rnd | yes |
| fx-sends + lfo-rnd 1.3 + voice-dac 1.5 | no, 62 bits (below) |

## Building

With an elekloader checkout (main) and the stock OS 1.74 `.syx`:

```
python3 -m elekloader.sdk.build mk2/duck --stock Analog_Rytm_MKII_OS1.74.syx
python3 -m elekloader.patch --stock Analog_Rytm_MKII_OS1.74.syx \
  --mod mods/core-ar2/out/core-0.10.elemod \
  --mod mk2/duck/out/duck-1.1.elemod \
  --version AE10 --out rytm-ae.syx --lockfile rytm-ae.lock.json
```

Keep the lockfile: it decides where fx-sends' and duck's fields sit in the sound's and the kit's storage, and their lock codes (NRPNs) and CCs.

## Builds that cannot be made

These follow from what the MKII has room for, and the patcher refuses them.
Decided 2026-11-06: where storage is the limit, each mod is judged on its own.

- **fx-sends with both voice-dac and lfo-rnd**: the three need 62 bits of
  core-ar2's 56-bit sound storage: fx-sends 7, lfo-rnd 1.3 16, voice-dac 1.5
  32 and core's LFO destination field (`core_lfo_dst`, 7, placed when a build
  has a sound LFO destination). fx-sends links with either one.
- **fx-sends 1.1 with duck 1.1**: the chorus's seven settings (49), DUCK's
  five (32) and core's FX LFO destination field (`core_fx_lfo_dst`, 7) need
  88 of the kit's 64 bits. fx-sends 1.0 and duck 1.0 kept their settings in
  RAM and link together.
