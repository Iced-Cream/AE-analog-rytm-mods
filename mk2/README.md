# MKII ports (Analog Rytm MKII, OS 1.74)

The AE mods in `mods/` are for the Analog Rytm **MK1**. This folder holds their
ports to the **MKII**, OS 1.74, as [elekloader](https://github.com/irpina/elekloader)
elemods: each folder has a `mod.json` and its source, built with elekloader's
SDK and linked with core-ar2 0.3 (OS 1.74 only), next to the rytm2_mods mods.

| folder | MK1 mod | what | status |
|---|---|---|---|
| [cpu-probe](cpu-probe/README.md) | 0011 | CPU, AUDIO and PEAK readouts on the CHANNELS page | emulator |
| [ae-pages](ae-pages/README.md) | (none) | the page framework duck and fx-sends share | emulator |
| [duck](duck/README.md) | 0012 | DUCK page behind COMP: VCA ducking keyed by a track | emulator |
| [fx-sends](fx-sends/README.md) | 0010 | FX SENDS page behind AMP: a chorus send | emulator |
| TX machines | 0009 | not ported yet | |

"Emulator" means built, linked and checked in rytm-emu; none of these has run
on a MKII yet. Each README says what was checked and what was not.

## Building

With an elekloader checkout (main) and the stock OS 1.74 `.syx`:

```
python3 -m elekloader.sdk.build mk2/duck --stock Analog_Rytm_MKII_OS1.74.syx
python3 -m elekloader.patch --stock Analog_Rytm_MKII_OS1.74.syx \
  --mod mods/core-ar2/out/core-0.3.elemod \
  --mod mk2/ae-pages/out/ae-pages-1.0.elemod \
  --mod mk2/duck/out/duck-1.0.elemod \
  --out rytm-ae.syx --lockfile rytm-ae.lock.json
```

Keep the lockfile: it decides where fx-sends' CHR sits in the sound's storage.

## Builds that cannot be made

These follow from what the MKII has room for, and the patcher refuses them:

- **duck with comp-preview**: both change the COMP view's page list.
- **fx-sends with both voice-dac and lfo-rnd**: the three need 62 bits of
  core-ar2's 56-bit sound storage. fx-sends links with either one.
