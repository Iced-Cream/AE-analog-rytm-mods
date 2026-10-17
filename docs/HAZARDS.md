# Hazards - Analog Rytm MK1

Read before flashing.

## The bootstrap lives INSIDE MAIN OS - never write into it

On the MKII the bootstrap (the STARTUP menu and the DIN-MIDI OS UPGRADE that survive
a bad OS) is a separate section of the `.syx`, which the project simply never
rebuilds. **The MK1 `.syx` has only one section, MAIN OS, and the bootstrap image is
carried inside it:**

- `0x4028c768` holds the embedded bootstrap's version words, `0x4028c770..0x402a1b84`
  its image (87,068 B, ending in its USB descriptors). On OS 1.73 the same image sat
  0x60 lower.
- At every boot, the startup code (`0x400005aa`) compares that version with the one
  in flash at `0x1fff8`. If the embedded one is newer, `0x4011a7a4` shows BOOTSTRAP
  UPGRADE, erases the bootstrap sectors and writes the embedded image into them.

So a mod byte anywhere in that range could one day be written into the recovery
path itself - by this build, or by a later one whose version word is newer. The
rules that follow from it:

- No pool may overlap `0x4028c768..0x402a1b84`. The nearest pool, `cave`, starts
  12 bytes past its end.
- `tools/build.py` refuses to write a build whose embedded image differs from stock,
  and `tools/verify.py` checks it again on the `.syx` it reads back
  ("embedded bootstrap image unchanged"). Keep both checks.
- Do not power off during the first boot after flashing. If your unit was on an OS
  older than 1.74, that boot may be a genuine bootstrap upgrade (with our builds it
  is the manufacturer's own, unmodified image that gets written).

## The recovery route still exists

Hold FUNC while powering on for the STARTUP menu, TRIG 4 for OS UPGRADE, then send
the stock `Analog-Rytm_OS1.74.syx` from the Transfer app's
LEGACY OS UPGRADE mode over DIN MIDI. That menu is drawn by the bootstrap in flash,
not by MAIN OS, which is why the rule above matters.

## The container writer needed one fix for MK1

The vendored elektron-firmware-tool pads ELE2 containers to 2 bytes; the stock MK1
file pads to 4, so a "no change" rebuild came out 2 bytes shorter than stock. The
content was identical, but the null-repack self-check failed. `tools/eft-ele2-align4.patch`
(applied by `make setup`) pads to 4, and the untouched stock file now rebuilds byte
for byte. Every MK1 build uses the patched tool.

## Assembler target: ColdFire V4, EMAC, NO FPU

`-mcpu=5475 -mno-float` (from re/symbols.toml [meta]). The MK1 image uses mvz/mvs,
sats, mov3q and the EMAC unit, and no floating point in code. With -mno-float an FPU
instruction in a stub is an assembly error instead of a crash on the unit.

## Verify before flashing, every time

Every `make` target ends in `tools/verify.py`, which asserts:

- stock `.syx` rebuilds byte-identically (null repack)
- MAIN OS is unchanged in size and round-trips out of our `.syx`
- the embedded bootstrap image is stock, and the `.syx` carries MAIN OS only
- every byte that differs from stock lies inside a registry claim
- every detour jumps to its resolved entry, inside its own cave, and rejoins stock
  past exactly what it displaced
- no stub's movem overruns its stack frame

Do not flash a build that did not end in `PASS`.

## Dead code reused

0009 and 0012 put code where the firmware has routines it carries but never runs:
the machines Elektron left hidden (never offered in any machine list) and the
SD/RS/CY/CB TEST machines. Each such pool is recorded with its proof in
`registry/allocations.toml` (the only reference into it is its own machine table
entry, which the mod repoints), and the build checks the pool still holds the exact
stock bytes it was analysed on. A kit received over SysEx that names one of those
hidden machines plays the mod's machine or nothing, never the old code.

## RAM that is not cleared

0010's delay lines live in DRAM that is not cleared at power-up; the mod clears it
before use. Settings held in the mods' own RAM (the chorus's and DUCK's globals)
return to their defaults at every power-up.

## Status means what it says

A build that passes every check is only "built". What has run on an instrument is
listed in the README's Status section, for the exact images named there.
