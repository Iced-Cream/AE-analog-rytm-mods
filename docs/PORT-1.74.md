# Moving from OS 1.73 to OS 1.74 (2026-10-17)

Elektron's 1.74 (2026-10-01) changes nothing on the MK1 that the release notes name
(its two items are MKII Outbox 8 features), but the MK1 image is a new compile, so
every image address was re-derived.

What moved, measured on the two stock MAIN OS images (both 2,824,228 B):

- **RAM did not move.** Every .bss / SRAM address referenced by code (4009 pointer
  pairs across 0x4167..0x4217, 0x80......) is the same, so the RAM symbols, the
  param_info table at 0x416a6aa4 and 0010's delay lines are unchanged.
- **Code**: +0 up to ~0x40056600, +0x6c from there to the end of the code. The only
  real code changes are ~80 instructions around 0x40056668..0x40056ba6 and two tiny
  spots at 0x4014aa70 / 0x4014d040; no mod touches or calls them.
- **Read-only data**: +0x6c below ~0x4018d400, +0x60 from 0x4018d400 to the end
  (machine tables, names, machine_fn, knob descriptors, cave3, the embedded
  bootstrap). The embedded bootstrap is byte-identical, now 0x4028c768..0x402a1b84.
- cave2 (0x402a2780..0x402a3000) and __bss_start did not move. `cave` (after the
  bootstrap) did: 0x402a1b90..0x402a2000, 96 B smaller (1136 B). So 0008's claim
  there is trimmed to its real size and 0010's `ret_gate` moved to its .tab (cave3).

How: `tools/port_os.py OLD NEW addr...` maps an address by comparing a window around
it in both images, with image pointers masked (or counted as equal when they moved
by one of the image's deltas), for each delta the image shows; it refuses ties and
low-information windows instead of guessing. Every address in code position in the
stubs, the registry (addr / start / end / rejoin, and pointers inside expect /
replace bytes), re/symbols.toml and the mkreg/gen scripts went through it (525
addresses); the few it refused were checked by hand (base, cave2, main()'s spin).
Comments, notes and `evidence` prose still cite 1.73 addresses.

Checked:
- every build passes build.py's expect checks and verify.py;
- for the 0009 build and three builds of the original rytm1_mods set (SMP CUT,
  RANDOM, TX), every byte run the build changes in
  1.73 is found, pointers ported, at the ported address in the 1.74 build (pointers
  into the mods' own caves only checked to land in the matching cave: the stubs'
  internal .align padding differs because the caves start at new offsets);
- every code pool's only reference is still its machine_fn entry (cave11's font-row
  look-alikes as before);
- in an emulator, BD TX-9 DIGI's hits render identically to the 1.73 build, and the
  chorus send renders byte-identically (base and FDB), page included;
- on the instrument: the full 1.74 build plays as the 1.73 builds did.
