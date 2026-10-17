# tx_measure - running the Machinedrum TX plugins off the hardware

Where the measured numbers in `tools/gen_tx_tables.py` come from. Nothing here is
part of the build; it reproduces the measurements.

## Pieces

| file | what |
|---|---|
| `decode.py` | `MACHINEDRUM_USR/*.syx` -> the unpacked MDS1 blob (`.bin`) |
| `dis56.cpp` | DSP56300 disassembler driver |
| `txrun.cpp` | runs a blob in the dsp56300 interpreter: init, params, trigger, N render blocks -> float32 |
| `anal.py` | kick analysis: per-cycle pitch, level, time to -20/-40/-60 dB |
| `anal2.py` | snare analysis: body band (< 900 Hz) pitch and decay, noise band (> 3 kHz) level and decay |
| `spec.py` | spectral peaks 40..2000 Hz in a time window |
| `sweep.sh` | render one note per value of one knob and print the analysis line |
| `atk_extract.py` | BD TX-9 click / TX-8 attack pulse and their ATK / ACC gains -> `tools/tx_atk_data.py` |
| `f0track.py`, `segs.py`, `tomhits.py` | tom recordings: pitch track, per-hit pitch and decay |

## Building (WSL / Linux)

The emulator is https://github.com/dsp56300/dsp56300 (GPL), not vendored:

    mkdir -p ~/dsp && cd ~/dsp
    git clone --depth 1 https://github.com/dsp56300/dsp56300.git
    cd dsp56300 && git submodule update --init --depth 1 source/asmjit
    python3 -m pip install --user --break-system-packages cmake
    mkdir build && cd build
    ~/.local/bin/cmake .. -DDSP56K_FORCE_INTERPRETER=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    ~/.local/bin/cmake --build . --target dsp56kEmu -j8
    cd .. && cp <this dir>/txrun.cpp source/
    g++ -std=c++17 -O2 -w -Isource -Isource/dsp56kEmu -Isource/asmjit/src source/txrun.cpp \
        build/source/dsp56kEmu/libdsp56kEmu.a build/source/dsp56kBase/libdsp56kBase.a \
        build/source/asmjit/libasmjit.a build/source/vtuneSdk/libvtuneSdk.a -lpthread -ldl -o txrun

## How a plugin is run (what the Machinedrum evidently does)

- The P image is loaded at 0 in **both P and X memory**: the plugins read their
  tables with `x:` addressing at their P addresses.
- Entry points are the words at blob `+0x40`, `+0x42`, `+0x44`: init, trigger, render.
- `r6` = the plugin's state block; parameters at `y:(r6+1..7)` in MDM1 order.
  MDM1 flag bit 0 set: the value is a fraction, `p << 16`; clear: `p << 7`
  (a table index, 512 sub-steps per segment).
- `r7` = the output buffer in Y, 32 samples per render, and **`m7 = 31`**: the
  snares write their noise through `y:(r7)+` and then add the body through
  `y:(r7)` without resetting `r7`, so the buffer has to be a 32-word ring.
- All other M registers linear (`$ffffff`). 44.1 kHz.

## Measuring

    python3 decode.py ../../MACHINEDRUM_USR /tmp/bins      # writes TX9-BD.bin etc.
    TXOUT=/tmp/n.f32 ./txrun /tmp/bins/TX9-SD.bin 400 64 64 64 64 96 64 64
    python3 anal2.py /tmp/n.f32 quiet
