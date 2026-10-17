# Building

## Prerequisites

- Python 3.11 or newer (standard library only).
- git, make and a C compiler (for the container tool).
- m68k binutils: `apt install binutils-m68k-linux-gnu` on Debian / Ubuntu (WSL
  included), `brew install m68k-elf-binutils` on macOS. Either prefix is found
  automatically.
- The official Analog Rytm MK1 **OS 1.74** `.syx`, saved as
  `stock/Analog-Rytm_OS1.74.syx`. The build checks it against `stock/SHA256SUMS`.

## Steps

    make setup     # once: fetch elektron-firmware-tool at its pinned commit, patch, build it
    make           # the full build (= make full)

The result is `build/AR1_OS1.74_<mods>.syx`, ready to send (docs/FLASHING.md):

| target | output | mods |
|---|---|---|
| `make full` | `AR1_OS1.74_0000_0009_0010_0012.syx` | TX machines, FX SENDS, DUCK |
| `make fx` | `AR1_OS1.74_0000_0009_0010.syx` | TX machines, FX SENDS |
| `make tx` | `AR1_OS1.74_0009.syx` | TX machines |
| `make probe` | `AR1_OS1.74_0000_0009_0010_0011.syx` | TX machines, FX SENDS, CPU probe |
| `make control` | `AR1_OS1.74_control.syx` | none: stock code, repacked (a pipeline test) |

Every target ends by running `tools/verify.py` on its output and stops on any FAIL.
Do not flash a build that did not end in `PASS`.

## What the checks cover

- the stock `.syx` rebuilds byte for byte (the container tool is proven on it);
- MAIN OS keeps its size and round-trips out of the new `.syx`;
- the embedded bootstrap image (the recovery menu's code) is stock;
- every byte that differs from stock lies inside a registry claim, and every claim's
  stock bytes matched before it was written;
- every detour jumps to its resolved entry, re-emits what it displaced and rejoins
  stock exactly past it; chained detours jump to the first link of their chain.

## Changing a mod

- Code is in `mods/<id>/stub.s` (GNU as, ColdFire V4e: `-mcpu=5475 -mno-float`).
  Firmware addresses come from `re/symbols.toml` (as `build/symbols.inc`).
- 0009-0012's registry blocks are generated from the stock image by
  `tools/mkreg_00NN.py` (expected bytes are read, never typed). Run them in order
  0009, 0010, 0011, 0012 after changing a hook or a section size, e.g.
  `python3 tools/mkreg_0012.py build/stock_mainos.bin registry/allocations.toml 0x458`
  (the sizes each script takes are in the current registry's cave claims).
- 0009's curves are `mods/0009-tx-machines/tables.inc`, written by
  `tools/gen_tx_tables.py`. Regenerating them needs the Machinedrum TX plugins in
  `MACHINEDRUM_USR/TX8` and `TX9` (not included); without them the build uses the
  committed tables.
- `make disasm` writes a disassembly of the stock image to `build/mainos_emac.dis`.

## A new OS version

`tools/port_os.py OLD_MAINOS NEW_MAINOS addr...` maps addresses from one stock image
to another, and refuses rather than guesses where it cannot tell. How the 1.73 to
1.74 move was done and checked: docs/PORT-1.74.md.
