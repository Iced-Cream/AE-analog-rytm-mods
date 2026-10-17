"""Generate mod 0011's registry block from the stock image (every expect read, not typed).
Usage: python3 tools/mkreg_0011.py build/stock_mainos.bin registry/allocations.toml SIZE_TEXT SIZE_TAB
Replaces the existing 0011 block, which sits just before 0010's."""
import re
import sys

B = 0x40000400
img = open(sys.argv[1], 'rb').read()
reg_path = sys.argv[2]
size_text, size_tab = sys.argv[3], sys.argv[4]
OWNER = "0011-cpu-probe"
MARK = '\n# ------------------------------------------------------- 0011-cpu-probe'
MARK10 = '\n# ------------------------------------------------------- 0010-fx-sends'


def at(a, n):
    return img[a - B:a - B + n].hex()


out = []


def patch(addr, size, comment, replace=None, sym=None, expect=None):
    e = at(addr, size)
    if expect is not None and e != expect:
        raise SystemExit(f'0x{addr:08x}: expected {expect}, image has {e}')
    l = ['[[patch]]', f'owner   = "{OWNER}"', f'addr    = 0x{addr:08x}', f'size    = {size}',
         f'expect  = "{e}"' + (f'       # {comment}' if comment else '')]
    l.append(f'replace = "{replace}"' if replace is not None else f'from_symbol = "{sym}"')
    out.append('\n'.join(l))


def detour(addr, size, expect_hex, entry, comment, rejoin=None, reemit=True):
    e = img[addr - B:addr - B + len(expect_hex) // 2].hex()
    if e != expect_hex:
        raise SystemExit(f'detour 0x{addr:08x}: expected {expect_hex}, image has {e}')
    l = [f'# {comment}', '[[detour]]', f'owner  = "{OWNER}"', f'addr   = 0x{addr:08x}',
         f'size   = {size}', f'expect = "{expect_hex}"', f'entry  = "{entry}"']
    if rejoin is not None:
        l.append(f'rejoin = "{rejoin}"' if isinstance(rejoin, str) else f'rejoin = 0x{rejoin:08x}')
    if not reemit:
        l.append('reemit = false')
    out.append('\n'.join(l))


head = f'''{MARK}
#
# The CPU probe (a measuring build, `make fxprobe`). Code in the tail of cave6 (after
# 0009's .m37) and at the start of cave2, which 0002 uses (0011 excludes it: the FX
# build has no 0002); variables in DRAM at 0x4a8a8000, past 0010's delay lines,
# cleared by the probe at start.

[[cave]]
owner   = "{OWNER}"
addr    = 0x401103dc
size    = {size_text}
section = ".text"
note    = "The audio interrupt's entry and exit hooks, the idle loop."

[[cave]]
owner   = "{OWNER}"
addr    = 0x402a2780
size    = {size_tab}
section = ".tab"
note    = "The three label getters and their formatting."
'''

detour(0x40118984, 6, '4fefff6448d77fff', 'isr_enter',
       'The audio interrupt (vector 191) at its entry: lea -156(sp); movem.l d0-fp,(sp).')
detour(0x4011a16c, 6, '4cd77fff4fef009c', 'isr_exit',
       'Its one exit: movem.l (sp),d0-fp; lea 156(sp),sp; then rte, which the stub re-emits.',
       rejoin='none')
if at(0x4011a174, 2) != '4e73':
    raise SystemExit('the audio interrupt exit is not followed by rte')
patch(0x400f9ecc, 4, "main()'s last call before its bra.s . spin -> idle_entry", sym='idle_entry',
      expect='400a0eaa')
if at(0x400f9ed0, 2) != '60fe':
    raise SystemExit('main() does not end in bra.s . after that call')
# The label getters: the stub pushes its own text in place of the label's, so the
# displaced `pea "LABEL"` is replaced on purpose, not replayed.
for a, s, e, n in ((0x40045082, '487940208587', 'lbl_perf', 'PERF CHANNEL'),
                   (0x400450aa, '487940208594', 'lbl_auto', 'AUTO CHANNEL'),
                   (0x400450d2, '4879402085a1', 'lbl_prog', 'PROG CH IN CH')):
    detour(a, 6, s, e, f'The {n} label getter: pea "{n}", replaced by the readout text.', reemit=False)

block = head + '\n' + '\n\n'.join(out) + '\n'
text = open(reg_path, 'rb').read().decode()
c0 = text.find(MARK)
c10 = text.find(MARK10)
if c10 < 0:
    raise SystemExit('0010 marker not found')
if c0 >= 0:
    text = text[:c0] + text[c10:]
    c10 = text.find(MARK10)
text = text[:c10].rstrip('\n') + '\n' + block + text[c10:]
open(reg_path, 'wb').write(text.encode())
print(f'0011 block: {len(out)} entries')
