# ae-pages (Analog Rytm MKII, OS 1.74)

A small framework the AE MKII ports share: the extra parameter pages they add
(DUCK behind COMP, FX SENDS behind AMP). On its own it changes nothing the unit
does.

On the MK1 those pages share four stock routines through the build's detour
chains: `page_info`, `page_get_value`, `param_apply_delta` and
`param_value_text`. On the MKII, rytm2_mods (lfo-rnd, voice-dac, euclid-accents,
velocity-humanise, ctrl-all) already detours the first instructions of those
routines, each mod one instruction, each rejoining at the next. ae-pages takes
the next free place in each and hands it on to every page in its table:

| routine | place | how |
|---|---|---|
| `page_info` 0x400ff5e0 | its 8 callers (5 `jsr`, 3 `lea`) | keep2: no instruction of its own is left (lfo-rnd holds its start, voice-dac its out-of-range return) |
| `page_get_value` | 0x40038472 | jmp, after voice-dac's 0x4003846a |
| `param_apply_delta` | 0x400378c8 | jmp, after ctrl-all's 0x400378c2 |
| `param_value_text` | 0x400a866c | jmp, after voice-dac's 0x400a8664 |

## For a page mod

Add a descriptor to the table `ae_pages` (`contribute` in mod.json, `order`
= your page id):

| offset | |
|---|---|
| +0 | page id: 12 and 13 are lfo-rnd's and voice-dac's, so AE uses 14 on |
| +4 | the page's entry for `page_info`: `{name, ids A..H}`, 36 bytes |
| +8 | `long get(long id)`: the knob's value 0..127, or -1 if not yours |
| +12 | `long delta(void *view, long id, long delta)`: 0 if not yours, else apply the delta (8.8, fractions included); ae-pages redraws the view |
| +16 | `long text(long id, char *buf)`: 0 if not yours, else write the value's text |

C calling convention. The page's knobs need parameter ids no other mod uses:
the AE ports use hidden TEST machines' records (DUCK: HH TEST 443..447).

Status: built and used by duck in the emulator (page, values, popups). Not
run on hardware yet.
