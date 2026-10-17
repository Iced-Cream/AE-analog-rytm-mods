# User manual - Analog Rytm MK1, OS 1.74 mods

What each mod does on the instrument and how to use it. For building see
[BUILD.md](../BUILD.md), for installing [FLASHING.md](FLASHING.md), and read
[HAZARDS.md](HAZARDS.md) before flashing.

Every build is the stock MK1 OS 1.74 plus the mods it lists; everything not
mentioned behaves as stock, and the unit still reports OS 1.74.

| build | file | mods |
|---|---|---|
| `make full` | `AR1_OS1.74_0000_0009_0010_0012.syx` | TX machines, FX SENDS, DUCK |
| `make fx` | `AR1_OS1.74_0000_0009_0010.syx` | TX machines, FX SENDS |
| `make tx` | `AR1_OS1.74_0009.syx` | TX machines |
| `make probe` | `AR1_OS1.74_0000_0009_0010_0011.syx` | TX machines, FX SENDS, CPU probe |

| mod | where | what |
|---|---|---|
| 0009 | BD, SD, BT, LT and MT/HT tracks, machine list | BD TX-9, BD TX-9 DIGI, SD TX-9, SD TX-8, XT TX-9, XT TX-8, BT TX-8 |
| 0010 | AMP key, pressed twice | SEND page: chorus send per track, chorus settings |
| 0011 | GLOBAL > MIDI CONFIG > CHANNELS (probe build) | processor load readouts |
| 0012 | FX track, AMP (COMP) pressed twice | DUCK page: one track ducks all the others |

0000 is the shared code the others call into. It has no controls.

## 0009 - TX machines

Seven machines ported from the Machinedrum user machines TX-8 / TX-9 (808- and
909-style). They sit at the end of each track's machine list: in the machine menu,
press LEFT from the first machine to wrap round to them.

| track | machine | knobs |
|---|---|---|
| BD | BD TX-9 | LEV PTC DEC TUN DPT ACC WAV ATK |
| BD | BD TX-9 DIGI | LEV PTC DEC TUN DPT ACC WAV ATK (fully digital) |
| SD | SD TX-9 | LEV PTC DEC TON SNP ACC BND DTU |
| SD | SD TX-8 | LEV PTC DEC TON SNP ACC DET TRA |
| LT, MT/HT | XT TX-9 | LEV PTC DEC TYP ACC BND NOI TON |
| LT, MT/HT | XT TX-8 | LEV PTC DEC TYP TUN ACC DIO NOI |
| BT | BT TX-8 | PTC SIG ACC DEC / ATK HLD NOI LEV (as laid out on the page) |

Each TX machine (except BD TX-9 DIGI) plays on the voice's analog circuit: it runs a
stock machine (BD CLASSIC, SD CLASSIC, XT CLASSIC or BT CLASSIC) and moves its
settings every audio block (1.5 kHz) along the TX machine's curves; the parts the
analog circuit cannot make (the 909 click, the snare noises, the tom's second
partial) are generated digitally and fed into the voice. The note of a trig still sets the pitch.

**BD TX-9** (909 kick)

| label | what |
|---|---|
| LEV | level |
| PTC | pitch, +-12 semitones around 64 |
| DEC | decay, about 80 ms .. 450 ms |
| TUN | sweep time: how fast the pitch falls, as the 909's TUNE |
| DPT | sweep depth, up to about +37 semitones at the attack |
| ACC | level, and the hold before the decay (about 20 .. 40 ms) |
| WAV | BD CLASSIC's waveform |
| ATK | the 909 click, ported from the TX-9 (its exact waveform; 64 = the Machinedrum default) |

**BD TX-9 DIGI** (909 kick, fully digital)

The TX-9 kick generated digitally, like the Machinedrum does, instead of on the analog
oscillators. It plays through the BD voice's digital input - the path samples take - so
the track's filter, overdrive and AMP page still shape it. Same knobs as BD TX-9:

| label | what |
|---|---|
| LEV | level |
| PTC | pitch, two octaves around 56 Hz (the TX-9's) |
| DEC | decay, as the Machinedrum (t-30 about 80 ms .. 370 ms) |
| TUN | sweep time, as the 909's TUNE |
| DPT | sweep depth |
| ACC | level, and the hold before the decay |
| WAV | 0 a pure sine, 1 the Machinedrum's (sine plus its slight 2nd harmonic, default), 2 triangle |
| ATK | the 909 click, as BD TX-9 |

Its pitch sweep and decay follow a Machinedrum recording closely (175 > 122 > 83 >
64 > 58 > 56 Hz, -30 dB at 165 ms at DEC 64). It costs
about 3 % of the processor while a hit sounds, nothing once it has died. In the BD
track's machine list, press LEFT from BD PLASTIC: BD FM, BD CLASSIC, BD HARD, then
BD TX-9 DIGI (4 presses) and BD TX-9 (5).

**SD TX-9** (909 snare)

| label | what |
|---|---|
| LEV | level |
| PTC | body pitch, about one octave |
| DEC | body decay |
| TON | noise (snappy) decay, as the 909's TONE |
| SNP | noise level (the 909 noise itself, ported from the TX-9: same filter and envelope) |
| ACC | level |
| BND | pitch bend at the attack (fast, downwards) |
| DTU | second oscillator's tuning above the first (up to about +18 semitones) |

**SD TX-8** (808 snare)

| label | what |
|---|---|
| LEV | level |
| PTC | body pitch, two octaves; the body rings shorter as the pitch rises, as on the 808 |
| DEC | noise (snappy) decay |
| TON | balance of the two body oscillators (SD CLASSIC's BAL) |
| SNP | noise level |
| ACC | level |
| DET | second oscillator's interval, default one octave (SD CLASSIC's DET) |
| TRA | transient (SD CLASSIC's snap) |

**XT TX-9** (909 tom, LT and MT/HT tracks)

| label | what |
|---|---|
| LEV | level |
| PTC | pitch, about one octave |
| DEC | decay, about 215 .. 435 ms on LT, 0.68x that on MT / HT, the same at any pitch (as the TX-9); flat for the first ~12 %, then falling |
| TYP | LT / MT / HT: the low, mid and high tom |
| ACC | level |
| BND | the attack bend: how far above the note the tom starts (it falls back in ~10 ms) |
| NOI | noise level |
| TON | noise tone (XT CLASSIC's) |

**XT TX-8** (808 tom, LT and MT/HT tracks)

| label | what |
|---|---|
| LEV | level |
| PTC | pitch, two octaves |
| DEC | decay, about 170 ms .. 1.3 s at 100 Hz (shorter as the pitch rises, as the 808); the TX-8's longest settings (up to 3 s) are beyond the Rytm's tom core |
| TYP | LT / MT / HT: the low, mid and high tom (the congas are left out) |
| TUN | fine tune, about -2 .. +3 semitones, 0 at 64 |
| ACC | level |
| DIO | "diode": the droop in pitch just after the hit |
| NOI | noise level |

**BT TX-8** (808 kick on the BT track)

The TX-8 kick played by the BT voice's resonator (BT CLASSIC), which rings like the
808's own bridged-T kick circuit, instead of BD CLASSIC's oscillators.

| label | what |
|---|---|
| PTC | pitch, two octaves (49.7 Hz at 64, as the TX-8) |
| SIG | the 808 "sigh": the pitch starts up to 3 semitones high and falls back over 165 ms |
| ACC | level |
| DEC | decay, matched to the TX-8 through BT CLASSIC's decay: about 160 ms .. 1.2 s at PTC 64. It follows the pitch, as on the 808. The TX-8's shortest settings (55 ms) are beyond the BT resonator at low pitch. |
| ATK | the 808 attack: the kick starts on a short segment at ~2.2x the pitch (up to ~8.5 ms at 127), plus a small click (BT CLASSIC's SNP is off) |
| HLD | hold before the decay (default 0) |
| NOI | BT CLASSIC's noise (default 0) |
| LEV | level |

Calibrated from recordings of the stock BT CLASSIC and the Machinedrum TX-8.

The toms run on the Rytm's tom core, an analog resonator - the same kind of circuit
as the 808's toms. Pitch and DEC are calibrated from recordings of the stock XT
CLASSIC and of the ports against the Machinedrum. Both voices tune the same, so a tom
plays at the same pitch on the LT, MT or HT track; the core reaches about 300 Hz.
XT TX-9 adds the 909 tom's second partial digitally: a sine at 2/3 of the pitch,
about 5 dB under the main, so the tail beats slightly as on the Machinedrum.

The BD attacks (ATK) are digital, added into the voice's input like the snare noise;
BD CLASSIC's own transient is off. Their level relative to the body follows the
Machinedrum's.

All the TX machines' knobs show 0..127 (PTC 64 is the middle); the toms' TYP shows
LT / MT / HT.

SD TX-8's noise is digital too: matched to the TX-8's (spectrum and decay), not
SD CLASSIC's.

**Things to know**

- Not ported: the TX-9 kick's drive, the TX-8 kick's TONE, and the TX-9 snare's
  detune below unison.
- Keep the AMP page decay long: the machine's own envelope does the shaping.
- A kit that uses a TX machine plays nothing on that track on stock firmware (the
  machine does not exist there); the rest of the kit is unaffected.
- Build: in every build (`make tx` is the TX machines alone).

## 0010 - FX SENDS (chorus send)

Press AMP a second time for the FX SENDS page: a chorus as a send effect, with the
Analog Four chorus's controls.

| label | what |
|---|---|
| CHR | this track's send to the chorus (saved with the sound) |
| PRE | pre-delay: the shortest delay of the sweep, 1 .. 20 ms |
| SPD | speed, about 0.05 .. 8 Hz |
| DEP | depth: how far the sweep reaches past PRE, 0 .. 8 ms |
| WID | stereo width: 0 mono, 127 the left and right taps sweeping in opposite phase |
| FDB | feedback, 0 .. 0.89: more makes it ring and flange |
| HPF | high-pass on the chorus input: 0 off, 127 about 2 kHz (keeps the low end dry) |
| VOL | the chorus return's level |

- **Engine.** Two interpolated taps on one delay line, each swept by a triangle LFO.
  The A4's own chorus runs six voices; on the Rytm that would cost about four times
  the processor time, so this keeps the A4's controls on a lighter engine.
- **Return path.** The return joins the delay and reverb returns before the distortion
  and compressor, and follows the FX track's level.
- **Global settings.** PRE, SPD, DEP, WID, FDB, HPF and VOL are shared: every track's
  page shows the same seven. In this version they are not saved and come back to
  their defaults at power-up. CHR is per track and saved with the sound.
- **Storage.** CHR lives in the sound's one spare parameter word (bits 0..6).
- **Not yet in this version.** The chorus's input ignores the track's pan and its
  SEND TO FX switch.
- **When it runs.** Nothing runs while no track sends; the chorus stops about 3 s
  after the last send is turned down. The sends are read every 5 ms and glide in over
  about 20 ms.
- **Build.** `make full` and `make fx`.

## 0011 - CPU probe (measuring build, `make probe`)

The `fx` build plus three live readouts of the processor's load. Open FUNC + TRK
(GLOBAL) > MIDI CONFIG > CHANNELS and scroll to the bottom:

| label shown | in place of | what |
|---|---|---|
| CPU 78.3% | PERF CHANNEL | time the processor was not idle: audio, sequencer, screen, card |
| AUDIO 61.2% | AUTO CHANNEL | the audio interrupt's average share of the time |
| PEAK 74.0% | PROG CH IN CH | the audio interrupt's largest share of one block |

Each figure covers the time since it was last drawn, so scroll away and back after
a few seconds of playing. CPU minus AUDIO is what the sequencer and the screen used;
100 minus CPU is what is left. The settings themselves still work; only their names
are replaced. Go back to `make full` for daily use.

On an Analog Rytm MK1 the stock audio engine alone uses about 77 % of the processor
with nothing playing; the TX machines and the chorus add to that, so this build is
the way to see how close a busy kit gets to the limit.

## 0012 - DUCK (sidechain-style ducking)

A ducker: one track's hits pull every other voice down, the
pumping a compressor with a sidechain gives. The Rytm's compressor is analog and its
detector hears the whole mix, so this does not use it: it turns the other voices
down at their own analog VCAs (where level and pan are set), before the mix.

Select the FX track (FX key) and press AMP - the COMP page - a second time for the
DUCK page:

| label | what |
|---|---|
| SRC | the key track: OFF (default), BD SD RS CP BT LT MT HT CH OH CY CB |
| DEP | depth: how far the others go down; 127 is silence, 90 about -10 dB (default) |
| ATK | how fast the duck comes in: 0 instant .. 127 about 85 ms (default 3) |
| HLD | how long it stays fully down after a hit: 0 .. 170 ms (default 22, ~30 ms) |
| REL | how fast the level comes back: 5 ms .. about 2 s (default 36, ~180 ms) |

- The key is the source track's own sound (its voice, as the unit hears it), so
  only hits that actually sound duck - a muted or silent trig does nothing. A hit
  counts above about -36 dBFS, and the next one once the voice fell below -48 dBFS.
- Every voice except the source's ducks, including the other track on a shared
  voice (RS/CP, MT/HT, CH/OH, CY/CB share one each: choosing CP keys on, and spares,
  that voice). The delay and reverb returns and external audio do not duck.
- The settings are global and held in RAM: they return to the defaults (SRC OFF) at
  power-up and are not saved with the kit.
- Costs about 300 instructions a block while a source is set (~0.3 % of the unit).
- Build: `make full`.
