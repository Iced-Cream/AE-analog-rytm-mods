# Analog Rytm MK1 - OS 1.74 mods. Build and verify use only the Python standard
# library (python3 >= 3.11) plus m68k binutils; see BUILD.md.
PY := python3

.PHONY: all setup symbols layout full fx tx probe control disasm clean

all: full

# The container tool, pinned to a known commit, plus one local patch: ELE2
# containers are padded to 4 bytes, as the stock MK1 file is (the tool pads to 2).
# With it, rebuilding the untouched stock .syx reproduces it byte for byte.
EFT_URL := https://github.com/mischa85/elektron-firmware-tool
EFT_REV := a5bce9a6af644386d900924082993a805e812874
EFT_DIR := vendor/elektron-firmware-tool

setup:
	test -d $(EFT_DIR)/.git || git clone $(EFT_URL) $(EFT_DIR)
	git -C $(EFT_DIR) checkout --quiet $(EFT_REV)
	git -C $(EFT_DIR) apply --check ../../tools/eft-ele2-align4.patch 2>/dev/null \
		&& git -C $(EFT_DIR) apply ../../tools/eft-ele2-align4.patch || true
	grep -q "stock pads to 4" $(EFT_DIR)/container.c
	$(MAKE) -C $(EFT_DIR)

# 0009's tables (mods/0009-tx-machines/tables.inc) are committed. With the
# Machinedrum TX plugins in MACHINEDRUM_USR/TX8 and TX9 (not included), every build
# first checks that tools/gen_tx_tables.py still reproduces them.
TXCHECK = if [ -d MACHINEDRUM_USR ]; then $(PY) tools/gen_tx_tables.py --check; 	else echo "MACHINEDRUM_USR/ not present: building from the committed tables.inc"; fi

symbols:
	$(PY) tools/symbols.py

layout:
	$(PY) tools/layout.py

# The full build: TX machines, the chorus send (SEND page) and the ducker (DUCK page).
FX_MODS := 0000-shared 0009-tx-machines 0010-fx-sends
full: symbols layout
	$(TXCHECK)
	$(PY) tools/build.py --mods $(FX_MODS) 0012-duck --tag 0000_0009_0010_0012
	$(PY) tools/verify.py --tag 0000_0009_0010_0012

# TX machines and the chorus send, without the ducker.
fx: symbols layout
	$(TXCHECK)
	$(PY) tools/build.py --mods $(FX_MODS) --tag 0000_0009_0010
	$(PY) tools/verify.py --tag 0000_0009_0010

# The TX machines alone: stock OS plus 0009, nothing else.
tx: symbols layout
	$(TXCHECK)
	$(PY) tools/build.py --mods 0009-tx-machines --tag 0009
	$(PY) tools/verify.py --tag 0009

# A measuring build: `fx` plus the CPU probe (0011) - processor load readouts in
# GLOBAL > MIDI CONFIG > CHANNELS. Not for daily use.
probe: symbols layout
	$(TXCHECK)
	$(PY) tools/build.py --mods $(FX_MODS) 0011-cpu-probe --tag 0000_0009_0010_0011
	$(PY) tools/verify.py --tag 0000_0009_0010_0011

# The pipeline test: no mods at all, stock MAIN OS repacked by the tool.
control: symbols layout
	$(PY) tools/build.py --mods --tag control
	$(PY) tools/verify.py --tag control

# Whole-image disassembly with EMAC decoding (build/mainos_emac.dis).
MAINOS_BASE := 0x40000400
disasm: control
	printf '\t.section .archtag,"a"\n\tmovclr.l %%acc0,%%d0\n\t.text\n\t.incbin "build/stock_mainos.bin"\n' \
		> build/mainos_wrap.s
	$$($(PY) -c 'import sys; sys.path.insert(0,"tools"); from toolchain import prefix; print(prefix())')as \
		-mcpu=5475 build/mainos_wrap.s -o build/mainos_wrap.o
	$$($(PY) -c 'import sys; sys.path.insert(0,"tools"); from toolchain import prefix; print(prefix())')objdump \
		-d -j .text --adjust-vma=$(MAINOS_BASE) build/mainos_wrap.o | sed 's/^ *//' > build/mainos_emac.dis

clean:
	rm -rf build
