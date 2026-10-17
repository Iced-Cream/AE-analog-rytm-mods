"""Generate mod 0010's registry block from the stock image (every expect read, not typed).
Usage: python3 tools/mkreg_0010.py build/stock_mainos.bin registry/allocations.toml SIZE_TEXT SIZE_TAB
Replaces the existing 0010 block, which sits just before 0009's (mkreg_0009 rewrites
from its own marker to the end of the file)."""
import re
import sys

B = 0x40000400
img = open(sys.argv[1], 'rb').read()
reg_path = sys.argv[2]
size_text, size_tab = sys.argv[3], sys.argv[4]
OWNER = "0010-fx-sends"
MARK = '\n# ------------------------------------------------------- 0010-fx-sends'
MARK9 = '\n# ------------------------------------------------------- 0009-'


def at(a, n):
    return img[a - B:a - B + n].hex()


def s_at(hexptr):
    o = int(hexptr, 16) - B
    m = re.match(rb'[\x20-\x7e]{0,40}\x00', img[o:o + 41])
    return m.group()[:-1].decode() if m else '?'


out = []


def patch(addr, size, comment, replace=None, sym=None, expect=None):
    e = at(addr, size)
    if expect is not None and e != expect:
        raise SystemExit(f'0x{addr:08x}: expected {expect}, image has {e}')
    l = ['[[patch]]', f'owner   = "{OWNER}"', f'addr    = 0x{addr:08x}', f'size    = {size}',
         f'expect  = "{e}"' + (f'       # {comment}' if comment else '')]
    l.append(f'replace = "{replace}"' if replace is not None else f'from_symbol = "{sym}"')
    out.append('\n'.join(l))


def detour(addr, size, expect_hex, entry, comment):
    e = img[addr - B:addr - B + len(expect_hex) // 2].hex()
    if e != expect_hex:
        raise SystemExit(f'detour 0x{addr:08x}: expected {expect_hex}, image has {e}')
    out.append('\n'.join([f'# {comment}', '[[detour]]', f'owner  = "{OWNER}"', f'addr   = 0x{addr:08x}',
                          f'size   = {size}', f'expect = "{expect_hex}"', f'entry  = "{entry}"']))


head = f'''{MARK}
#
# A chorus and a comb as two more send effects, and a second AMP page (page 11) with
# each track's two sends and the effects' settings. Code in `cave`, data, strings and
# state in `cave3` - the pools 0004 and 0008 use, which it excludes (all three keep
# their settings in the sound's free word). Delay lines and buffers in DRAM the stock
# FX never touch (0x4a8a0000..), cleared by the mod before use. re/fx-engine.md.

[[cave]]
owner   = "{OWNER}"
addr    = 0x402a1b90
size    = {size_text}
section = ".text"
note    = "The page_info / get / delta / text gates, the FX and return hooks, the bus mixer, chorus, comb and helpers."

[[cave]]
owner   = "{OWNER}"
addr    = 0x4024db6c
size    = {size_tab}
section = ".tab"
note    = "The AMP view's page list, the FX SENDS descriptor, the knob ids, the global settings, the comb's period table, the state and the strings."
'''

# The AMP view's page list: {6} becomes {6, 11}.
patch(0x400c7290, 2, 'moveq #1,%d1 - the AMP view\'s page count', replace='7202', expect='7201')
patch(0x400c7296, 4, 'the one-entry list holding page 6', sym='fx_pages', expect='401af578')

detour(0x400f87a2, 6, '720a202f0004', 'page_info_gate', 'page_info answers page 11; every other id goes to stock.')
detour(0x400381a0, 6, '4feffff448d7040c', 'get_gate', 'The dials: page_get_value\'s entry.')
detour(0x400376e4, 6, '77832f2a0074', 'delta_gate', 'The knobs: param_apply_delta past its prologue (0003\'s gate rejoins here).')
detour(0x400a5974, 6, '242f0020262f0024', 'text_gate', 'The popup text: param_value_text past its argument loads.')

# The stock FX block and the return output, each called on both audio paths.
for a in (0x40118a8a, 0x40119f24):
    patch(a, 4, 'jsr 0x40107610, the FX block', sym='fx_gate', expect='40107610')
for a in (0x40118a62, 0x40119efc):
    patch(a, 4, 'jsr 0x40107f8c, the return output', sym='ret_gate', expect='40107f8c')

# The eight knobs: dead Error records. Id 1 (CHR) takes container index 0, the sound's
# free word, as 0008's did; the seven global ones (PRE SPD DEP WID FDB HPF VOL) keep -1,
# so no stock path (MIDI CC, p-locks) ever writes anything for them. (v1's id 2 was
# the comb send, per track, with container 0.)
ROM = 0x4018e064
KNOBS = [(1, 'str_chr_l', 'str_chr', True), (2, 'str_pre_l', 'str_pre', False),
         (3, 'str_spd_l', 'str_spd', False), (4, 'str_dep_l', 'str_dep', False),
         (5, 'str_wid_l', 'str_wid', False), (11, 'str_fdb_l', 'str_fdb', False),
         (12, 'str_hpf_l', 'str_hpf', False), (13, 'str_vol_l', 'str_vol', False)]
for i, lsym, ssym, cont in KNOBS:
    a = ROM + 52 * i
    if s_at(at(a + 0x30, 4)) != 'ERR':
        raise SystemExit(f'id {i} is not a dead Error record')
    if cont:
        patch(a + 0x04, 4, f'id {i}: container index', replace='00000000', expect='ffffffff')
    patch(a + 0x0c, 4, f'id {i}: max', replace='00007f00', expect='00000000')
    patch(a + 0x28, 4, f'id {i}: long name, was "{s_at(at(a + 0x28, 4))}"', sym=lsym)
    patch(a + 0x2c, 4, f'id {i}: group name, was "{s_at(at(a + 0x2c, 4))}"', sym='str_group')
    patch(a + 0x30, 4, f'id {i}: short name, was "{s_at(at(a + 0x30, 4))}"', sym=ssym)

block = head + '\n' + '\n\n'.join(out) + '\n'
text = open(reg_path, 'rb').read().decode()
c0 = text.find(MARK)
c9 = text.find(MARK9)
if c9 < 0:
    raise SystemExit('0009 marker not found')
if c0 >= 0:
    text = text[:c0] + text[c9:]
    c9 = text.find(MARK9)
text = text[:c9].rstrip('\n') + '\n' + block + text[c9:]
open(reg_path, 'wb').write(text.encode())
print(f'0010 block: {len(out)} entries')
