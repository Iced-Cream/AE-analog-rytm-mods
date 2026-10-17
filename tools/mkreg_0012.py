"""Generate mod 0012's registry block from the stock image (every expect read, not typed).
Usage: python3 tools/mkreg_0012.py build/stock_mainos.bin registry/allocations.toml SIZE_TEXT
Replaces the existing 0012 block, which sits just before 0011's (the 0011, 0010 and
0009 scripts rewrite from their own markers on)."""
import re
import sys

B = 0x40000400
img = open(sys.argv[1], 'rb').read()
reg_path = sys.argv[2]
size_text = sys.argv[3]
OWNER = "0012-duck"
MARK = '\n# ------------------------------------------------------- 0012-duck'
MARK11 = '\n# ------------------------------------------------------- 0011-'


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


def chained(addr, expect_hex, entry, tag, comment):
    """The first link of a chain on a page hook 0010 also detours (chain_pos -1)."""
    e = img[addr - B:addr - B + len(expect_hex) // 2].hex()
    if e != expect_hex:
        raise SystemExit(f'detour 0x{addr:08x}: expected {expect_hex}, image has {e}')
    out.append('\n'.join([f'# {comment}', '[[detour]]', f'owner  = "{OWNER}"', f'addr   = 0x{addr:08x}',
                          'size   = 6', f'expect = "{expect_hex}"', f'entry  = "{entry}"',
                          'chain_pos   = -1', f'chain_next  = "CHAIN_{tag}"',
                          f'chain_stock = "{tag.lower()}_stock"']))


head = f'''{MARK}
#
# DUCK: a track-keyed ducker on the voices' VCA words, and its page (page 12) behind
# COMP. Code, settings and state in cave2 after 0011's code; cave2's 0002 claim
# overlaps, hence 0012 excludes 0002. The four page hooks are shared with 0010: these
# detours are the first link of each chain (chain_pos -1), and pass everything else
# on to 0010's gate, or to their own stock path when 0010 is not in the build.

[[cave]]
owner   = "{OWNER}"
addr    = 0x402a28e0
size    = {size_text}
section = ".text"
note    = "duck_gate, the four page gates, the COMP view's page list, the DUCK page, settings, state and strings."
'''

# The engine: the audio interrupt's call of vca_frame.
patch(0x40119e10, 4, 'the audio interrupt\'s jsr 0x40102960 (vca_frame), operand', sym='duck_gate',
      expect='40102960')

# The COMP view's page list: {10} becomes {10, 12}.
patch(0x400c743e, 2, 'moveq #1,%d1 - the COMP view\'s page count', replace='7202', expect='7201')
patch(0x400c7444, 4, 'the one-entry list holding page 10', sym='duck_pages', expect='401af564')

chained(0x400f87a2, '720a202f0004', 'pi_gate', 'PI', 'page_info answers page 12.')
chained(0x400381a0, '4feffff448d7040c', 'get_gate', 'GET', 'The dials: page_get_value\'s entry.')
chained(0x400376e4, '77832f2a0074', 'delta_gate', 'DELTA', 'The knobs: param_apply_delta past its prologue.')
chained(0x400a5974, '242f0020262f0024', 'text_gate', 'TEXT', 'The popup text: param_value_text past its argument loads.')

# The five knobs: the dead Error records nobody else uses (0010 has 1-5 and 11-13).
# Container index stays -1, so no stock path (MIDI CC, p-locks) writes them.
ROM = 0x4018e064
KNOBS = [(7, 'str_src_l', 'str_src', 0x0c00), (8, 'str_dep_l', 'str_dep', 0x7f00),
         (9, 'str_atk_l', 'str_atk', 0x7f00), (14, 'str_hld_l', 'str_hld', 0x7f00),
         (15, 'str_rel_l', 'str_rel', 0x7f00)]
for i, lsym, ssym, mx in KNOBS:
    a = ROM + 52 * i
    if s_at(at(a + 0x30, 4)) != 'ERR' or at(a + 0x04, 4) != 'ffffffff':
        raise SystemExit(f'id {i} is not a dead Error record without a container')
    patch(a + 0x0c, 4, f'id {i}: max', replace=f'{mx:08x}')
    patch(a + 0x28, 4, f'id {i}: long name, was "{s_at(at(a + 0x28, 4))}"', sym=lsym)
    patch(a + 0x2c, 4, f'id {i}: group name, was "{s_at(at(a + 0x2c, 4))}"', sym='str_group')
    patch(a + 0x30, 4, f'id {i}: short name, was "{s_at(at(a + 0x30, 4))}"', sym=ssym)

block = head + '\n' + '\n\n'.join(out) + '\n'
text = open(reg_path, 'rb').read().decode()
c0 = text.find(MARK)
c11 = text.find(MARK11)
if c11 < 0:
    raise SystemExit('0011 marker not found')
if c0 >= 0:
    text = text[:c0] + text[c11:]
    c11 = text.find(MARK11)
text = text[:c11].rstrip('\n') + '\n' + block + text[c11:]
open(reg_path, 'wb').write(text.encode())
print(f'0012 block: {len(out)} entries')
