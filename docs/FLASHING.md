# Flashing - Analog Rytm MK1

The MK1 takes one format, a `.syx`, sent like any OS update. Back up your projects
first (Transfer can back up the +Drive), and keep the stock file at hand:
`Analog-Rytm_OS1.74.syx`, from Elektron's Analog Rytm MKI support page.

## Normal route (Transfer, USB)

1. Connect over USB, power on.
2. Transfer > CONNECTION: set MIDI IN and OUT to the Analog Rytm.
3. Transfer > DROP: drag the `.syx` on.
4. Press `[YES]` on the device to confirm.

The unit restarts by itself. This route runs inside MAIN OS, so it needs a MAIN OS
that boots. **Do not power off during the first boot afterwards** (see HAZARDS.md:
the MK1's bootstrap upgrade runs from inside MAIN OS).

## Recovery route (STARTUP menu, DIN MIDI only)

1. Hold `[FUNC]` while powering on.
2. `[TRIG 4]` enters OS UPGRADE.
3. Transfer > CONNECTION: "LEGACY OS UPGRADE mode", select the stock `.syx`, UPGRADE.

This is served by the bootstrap in flash, not by MAIN OS, so it still comes up after
a MAIN OS that does not boot. It needs the DIN MIDI port (a USB-MIDI interface into
the Rytm's MIDI IN), not USB.

## A first session

1. Optional: `AR1_OS1.74_control.syx` (`make control`) - stock code, only repacked by
   the build's tool. If it boots and plays, the file format is proven on your unit,
   so any later problem is a mod, not the packer.
2. `AR1_OS1.74_0000_0009_0010_0012.syx` (`make full`). Check: the TX machines appear
   at the end of the BD, SD, BT, LT and MT/HT machine lists (LEFT from the first
   machine); AMP twice shows the SEND page; on the FX track, AMP twice shows the DUCK
   page; a kit saved with a TX machine and a chorus send reloads after a power cycle.

## Going back to stock

All builds carry version 1.74, the same as stock 1.74, so returning to stock is a
reinstall of the current version: send `Analog-Rytm_OS1.74.syx` by either route.
The device does not accept older OS versions than the one it runs.

Kits that use a TX machine play nothing on that track on stock firmware, and the
chorus sends are ignored; everything else in them loads normally.
