"""Generate mod 0009's registry block from the stock image (every expect read, not typed).
Usage: python3 tools/mkreg_0009.py build/stock_mainos.bin registry/allocations.toml \
         SIZE_TEXT SIZE_M35 SIZE_M37 SIZE_M38 SIZE_M39 SIZE_M40 SIZE_M41
Replaces the existing 0009 block. Sizes: the section sizes from the linked stub, rounded up."""
import sys, re, hashlib
B = 0x40000400
img = open(sys.argv[1], 'rb').read()
reg_path = sys.argv[2]
OWNER = "0009-tx-machines"

def at(a, n):
    return img[a - B:a - B + n].hex()

def s_at(hexptr):
    o = int(hexptr, 16) - B
    m = re.match(rb'[\x20-\x7e]{0,40}\x00', img[o:o + 41])
    return m.group()[:-1].decode() if m else '?'

def sha(lo, hi):
    return hashlib.sha256(img[lo - B:hi - B]).hexdigest()

out = []
def patch(addr, size, comment, replace=None, sym=None):
    e = at(addr, size)
    if replace is not None and e == replace:
        return
    l = ['[[patch]]', f'owner   = "{OWNER}"', f'addr    = 0x{addr:08x}', f'size    = {size}',
         f'expect  = "{e}"' + (f'       # {comment}' if comment else '')]
    l.append(f'replace = "{replace}"' if replace is not None else f'from_symbol = "{sym}"')
    out.append('\n'.join(l))

POOLS = [
    ("cave5", 0x40108b90, 0x401090a0, "BD HARD 2", 35, 0x402544bc, "BD ACOUSTIC 0x401090a0"),
    ("cave6", 0x40110084, 0x40110514, "SD HARD 2", 37, 0x402544c4, "SD ACOUSTIC 0x40110514"),
    ("cave7", 0x4010f79c, 0x4010fc18, "SD CLASSIC 2", 38, 0x402544c8, "RS FM 2 0x4010fc18"),
    ("cave8", 0x4010e9f8, 0x4010edc0, "RS HARD 2", 39, 0x402544cc, "RS CLASSIC 0x4010edc0"),
    ("cave9", 0x4010e63c, 0x4010e9f8, "RS CLASSIC 2", 40, 0x402544d0, "RS HARD 2 0x4010e9f8"),
    ("cave10", 0x40108538, 0x40108b90, "BD FM 2", 41, 0x402544d4, "BD HARD 2 0x40108b90"),
    ("cave11", 0x4010fc18, 0x40110084, "RS FM 2", 42, 0x402544d8, "SD HARD 2 0x40110084"),
    ("cave12", 0x401144b0, 0x4011476c, "BT IMPROVED", 34, 0x402544b8, "BT CLASSIC 0x4011476c"),
]
head = f'''

# ------------------------------------------------------- 0009-tx-machines
#
# Nine pools, all dead code (cave12, BT IMPROVED's routine, added for BD TX-9 DIGI,
# whose machine_fn[34] is pointed at DISABLE): cave4 is the stock SD/RS/CY/CB TEST machine routines
# (their four machine_fn entries are pointed at DISABLE by the patches below), and
# cave5..cave11 are the routines of hidden machines 35, 37, 38, 39, 40, 41 and 42; the
# machine_fn entries of 35, 37..40 and 42 point at the new machines that now live
# there, 41's at DISABLE (its routine holds the names). (Cave11's only other "hits" in
# a scan of every even-aligned long are 0x40110000-ish rows of the bitmap font data at
# 0x4026b1xx..0x4026f9xx, not pointers; no instruction outside it names an address in
# it.)

[[pool]]
name   = "cave4"
start  = 0x401164b0
end    = 0x40116c8a          # exclusive; 2010 B
stock  = "code"
expect_sha256 = "{sha(0x401164b0, 0x40116c8a)}"
status = "probably-verified"
note   = """
Four whole machine routines, back to back: SD TEST 0x401164b0, RS TEST 0x40116634,
CY TEST 0x401167dc, CB TEST 0x40116ad8, each ending in `jmp 0x40114e86` (CB TEST's
at 0x40116c84). The end bound is the next routine, 0x40116c8a, which the audio
interrupt calls (0x4011871c, 0x4011881a) and which stays untouched.

Reachability, all static (2026-10-10): the only references into the range from
outside it are the machine_fn entries 0x402544e4, 0x402544e8, 0x402544fc and
0x40254500 (every even-aligned long in the image and every operand in the
disassembly were scanned); branches inside stay inside. Those machines are never
offered (machine_voice_mask 0, checked by both set-machine paths and the audio
interrupt), and 0009 repoints the four entries at DISABLE so that even a kit
received over SysEx naming one cannot run this code. Anything else claiming cave4
must carry those four patches too.
"""
'''
for name, lo, hi, what, m, fnent, nxt in POOLS:
    head += f'''
[[pool]]
name   = "{name}"
start  = 0x{lo:08x}
end    = 0x{hi:08x}          # exclusive; {hi - lo} B
stock  = "code"
expect_sha256 = "{sha(lo, hi)}"
status = "probably-verified"
note   = """
The routine of hidden machine {m} ({what}), from its entry to the next routine
({nxt}). The only reference into the range is its own machine_fn entry
0x{fnent:08x} (same scan as cave4), which 0009 points at the machine it puts here.
Machine {m} was never offered on MK1 (mask 0) before 0009.
"""
'''
head += f'''
[[cave]]
owner   = "{OWNER}"
addr    = 0x401164b0
size    = SIZE_TEXT
section = ".text"
note    = "Shared helpers (interpolation, the log2 pitch sweep, note-on test), BD TX-9 and its tables, BD TX-9's per-voice state."

[[cave]]
owner   = "{OWNER}"
addr    = 0x40108b90
size    = SIZE_M35
section = ".m35"
note    = "Tables shared by BT TX-8 and BD TX-9 DIGI (BD TX-8 itself is dropped; machine_fn[35] -> DISABLE)."

[[cave]]
owner   = "{OWNER}"
addr    = 0x40110084
size    = SIZE_M37
section = ".m37"
note    = "SD TX-9: tables, machine, per-voice state."

[[cave]]
owner   = "{OWNER}"
addr    = 0x4010f79c
size    = SIZE_M38
section = ".m38"
note    = "SD TX-8: tables, machine, its matched noise routine and state."

[[cave]]
owner   = "{OWNER}"
addr    = 0x4010e9f8
size    = SIZE_M39
section = ".m39"
note    = "XT TX-9: tables, machine, per-voice state."

[[cave]]
owner   = "{OWNER}"
addr    = 0x4010e63c
size    = SIZE_M40
section = ".m40"
note    = "XT TX-8: tables, machine, per-voice state."

[[cave]]
owner   = "{OWNER}"
addr    = 0x40108538
size    = SIZE_M41
section = ".m41"
note    = "All the machine and parameter names. Machine 41 (BD FM 2) itself is pointed at DISABLE."

[[cave]]
owner   = "{OWNER}"
addr    = 0x4010fc18
size    = SIZE_M42
section = ".m42"
note    = "BT TX-8: tables, machine, per-voice state, its names; BD TX-9 DIGI's phase table."

[[cave]]
owner   = "{OWNER}"
addr    = 0x401144b0
size    = SIZE_M34
section = ".m34"
note    = "BD TX-9 DIGI's code (its tables and state sit in .m35, .m39, .m41, .m42 and .m38). Machine 34 (BT IMPROVED) itself is pointed at DISABLE."

# Machines 36 and 41 offered on the BD voice (bit 0; BD TEST 44 hidden again, BD TX-8 35 dropped), 37 and 38 on the SD voice
# (bit 2, category 1 like the stock SD machines), 39 and 40 on the LT and MT/HT voices
# (bits 3 and 5, category -1 like XT CLASSIC), 42 on the BT voice (bit 1, category 4
# like BT CLASSIC). Machine table entries, names and parameter records follow; records
# keep their index and storage.
'''

MASK = 0x4018d8c9
CAT = 0x4018d8c8
for m, bits in ((36, '01'), (37, '04'), (38, '04'), (39, '28'), (40, '28'), (42, '02'), (41, '01')):
    patch(MASK + 2 * m, 1, f'machine {m}: voice mask', replace=bits)
for m in (37, 38):
    patch(CAT + 2 * m, 1, f'machine {m}: category SD', replace='01')
patch(CAT + 2 * 42, 1, 'machine 42: category -1 (offered like XT TX-9; category 4 is not listed)', replace='ff')
for m in (39, 40):
    patch(CAT + 2 * m, 1, f'machine {m}: category -1, as XT CLASSIC', replace='ff')
FN = 0x40254430
for m, sym in ((36, 'tx9bd_machine'), (37, 'tx9sd_machine'), (38, 'tx8sd_machine'),
               (39, 'tx9xt_machine'), (40, 'tx8xt_machine'), (42, 'bt8_machine'), (41, 'tx9d_machine')):
    patch(FN + 4 * m, 4, f'machine_fn[{m}]', sym=sym)
for m in (45, 46, 51, 52):
    patch(FN + 4 * m, 4, f'machine_fn[{m}] -> DISABLE; its old code is cave4', replace='4010d11c')
patch(FN + 4 * 35, 4, 'machine_fn[35] -> DISABLE; BD TX-8 dropped (BT TX-8 replaces it), cave5 keeps tables', replace='4010d11c')
patch(FN + 4 * 34, 4, 'machine_fn[34] -> DISABLE; its old code is cave12', replace='4010d11c')
NAMES = 0x4018d6f0
for m, (l, s) in {36: ('str_bdt9', 'str_bdt9s'),
                  37: ('str_sdt9', 'str_sdt9s'), 38: ('str_sdt8', 'str_sdt8s'),
                  39: ('str_xtt9', 'str_xtt9s'), 40: ('str_xtt8', 'str_xtt8s'),
                  42: ('str_btt8', 'str_btt8s'), 41: ('str_bd9d', 'str_bd9ds')}.items():
    patch(NAMES + 8 * m, 4, f'machine {m} name "{s_at(at(NAMES + 8 * m, 4))}"', sym=l)
    patch(NAMES + 8 * m + 4, 4, f'machine {m} short "{s_at(at(NAMES + 8 * m + 4, 4))}"', sym=s)

ROM = 0x4018e064
def records(kind):
    r = {}
    for i in range(469):
        a = ROM + 52 * i
        if int.from_bytes(img[a - B:a - B + 4], 'big') == kind:
            r[int.from_bytes(img[a - B + 4:a - B + 8], 'big')] = (i, a)
    return r

# idx -> (long sym, short sym, max, default)
L = {
 36: ('str_bdt9g', {9: ('str_level', 'str_lev', 0x7f00, 0x6400), 10: ('str_pitch', 'str_ptc', 0x7f00, 0x4000),
                    11: ('str_decay', 'str_dec', 0x7f00, 0x4000), 12: ('str_swt', 'str_tun', 0x7f00, 0x4000),
                    13: ('str_swd', 'str_dpt', 0x7f00, 0x4000), 14: ('str_accent', 'str_acc', 0x7f00, 0x6000),
                    15: ('str_wave', 'str_wav', 0x0200, 0x0000), 16: ('str_attack', 'str_atk', 0x7f00, 0x4000)}),
 37: ('str_sdt9g', {9: ('str_level', 'str_lev', 0x7f00, 0x6400), 10: ('str_pitch', 'str_ptc', 0x7f00, 0x4000),
                    11: ('str_decay', 'str_dec', 0x7f00, 0x4000), 12: ('str_tone', 'str_ton', 0x7f00, 0x4000),
                    13: ('str_snappy', 'str_snp', 0x7f00, 0x4000), 14: ('str_accent', 'str_acc', 0x7f00, 0x6000),
                    15: ('str_bend', 'str_bnd', 0x7f00, 0x4000), 16: ('str_detune', 'str_dtu', 0x7f00, 0x4000)}),
 39: ('str_xtt9g', {9: ('str_level', 'str_lev', 0x7f00, 0x6400), 10: ('str_pitch', 'str_ptc', 0x7f00, 0x4000),
                    11: ('str_decay', 'str_dec', 0x7f00, 0x4000), 12: ('str_type', 'str_typ', 0x0200, 0x0100),
                    13: ('str_accent', 'str_acc', 0x7f00, 0x6000), 14: ('str_bend', 'str_bnd', 0x7f00, 0x4000),
                    15: ('str_noise', 'str_noi', 0x7f00, 0x4000), 16: ('str_ntone', 'str_ton', 0x7f00, 0x4000)}),
 40: ('str_xtt8g', {9: ('str_level', 'str_lev', 0x7f00, 0x6400), 10: ('str_pitch', 'str_ptc', 0x7f00, 0x4000),
                    11: ('str_decay', 'str_dec', 0x7f00, 0x4000), 12: ('str_type', 'str_typ', 0x0200, 0x0100),
                    13: ('str_tune', 'str_tun', 0x7f00, 0x4000), 14: ('str_accent', 'str_acc', 0x7f00, 0x6000),
                    15: ('str_diode', 'str_dio', 0x7f00, 0x4000), 16: ('str_noise', 'str_noi', 0x7f00, 0x4000)}),
 41: ('str_bd9dg', {9: ('str_level', 'str_lev', 0x7f00, 0x6400), 10: ('str_pitch', 'str_ptc', 0x7f00, 0x4000),
                    11: ('str_decay', 'str_dec', 0x7f00, 0x4000), 12: ('str_swt', 'str_tun', 0x7f00, 0x4000),
                    13: ('str_swd', 'str_dpt', 0x7f00, 0x4000), 14: ('str_accent', 'str_acc', 0x7f00, 0x6000),
                    15: ('str_wave', 'str_wav', 0x0200, 0x0100), 16: ('str_attack', 'str_atk', 0x7f00, 0x4000)}),
 42: ('str_btt8g', {9: ('str_level', 'str_lev', 0x7f00, 0x6400), 10: ('str_pitch', 'str_ptc', 0x7f00, 0x4000),
                    11: ('str_decay', 'str_dec', 0x7f00, 0x4000), 12: ('str_sigh', 'str_sig', 0x7f00, 0x4000),
                    13: ('str_accent', 'str_acc', 0x7f00, 0x6000), 14: ('str_hold', 'str_hld', 0x7f00, 0x0000),
                    15: ('str_noise', 'str_noi', 0x7f00, 0x0000), 16: ('str_attack', 'str_atk', 0x7f00, 0x4000)}),
 38: ('str_sdt8g', {9: ('str_level', 'str_lev', 0x7f00, 0x6400), 10: ('str_pitch', 'str_ptc', 0x7f00, 0x4000),
                    11: ('str_decay', 'str_dec', 0x7f00, 0x4000), 12: ('str_tone', 'str_ton', 0x7f00, 0x4000),
                    13: ('str_snappy', 'str_snp', 0x7f00, 0x4000), 14: ('str_accent', 'str_acc', 0x7f00, 0x6000),
                    15: ('str_detune', 'str_det', 0x2000, 0x0c00), 16: ('str_trans', 'str_tra', 0x7f00, 0x4000)}),
}
for kind, (group, layout) in L.items():
    recs = records(kind)
    assert sorted(recs) == list(range(9, 17)), (kind, sorted(recs))
    for idx, (lsym, ssym, mx, df) in sorted(layout.items()):
        i, a = recs[idx]
        if at(a + 0x08, 4) != '00000000':
            patch(a + 0x08, 4, f'id {i}: min', replace='00000000')
        patch(a + 0x0c, 4, f'id {i}: max', replace=f'{mx:08x}')
        patch(a + 0x10, 4, f'id {i}: default', replace=f'{df:08x}')
        patch(a + 0x28, 4, f'id {i} (machine {kind} idx {idx}): long "{s_at(at(a + 0x28, 4))}"', sym=lsym)
        patch(a + 0x2c, 4, f'id {i}: group "{s_at(at(a + 0x2c, 4))}"', sym=group)
        patch(a + 0x30, 4, f'id {i}: short "{s_at(at(a + 0x30, 4))}"', sym=ssym)

# Value display: each parameter id's text formatter is copied at boot from a shared
# prototype, by an unrolled constructor (`pea SRC` or `move.l #SRC,(sp)`, then
# `pea entry+0x18`, entry = 0x416a6aa4 + 88 * id). Records reused from bipolar stock
# controls (Tune, Osc Balance, Symmetry) show -64..63; point them at the plain
# 0..127 prototype, so every TX knob reads like the Machinedrum's.
FMT_PLAIN, FMT_CENTRED = 0x416a6a4c, 0x416a6a2c
for pid in (342, 356, 358, 359, 372, 376, 377, 381, 390, 392, 382, 389):
    entry = (0x416a6aa4 + 88 * pid + 0x18).to_bytes(4, 'big')
    k = img.find(b'\x48\x79' + entry)
    if k < 0 or img[k - 6:k - 4] not in (b'\x48\x79', b'\x2e\xbc'):
        raise SystemExit(f'id {pid}: formatter constructor block not found')
    imm = B + k - 4
    if int.from_bytes(img[k - 4:k], 'big') != FMT_CENTRED:
        raise SystemExit(f'id {pid}: formatter is not the centred prototype')
    patch(imm, 4, f'id {pid}: value display, centred -> plain', replace=f'{FMT_PLAIN:08x}')
# BD TX-9 ATK (id 349) was a stock Transient knob: a stepped selector with a picture.
# Make it the plain slider BD TX-8 ATK (id 341, once Tick Level) is: knob descriptor
# (entry + 4, 20 bytes copied from 0x401ba364 -> 0x401ba38c = {0x100, 0x800, 0, 0,
# 0x50}, the one id 341 holds at run time [measured in the emulator]; 0x401ba328 =
# {1, 0x100, 0x40, 0, 0x78} is a 1/256-step descriptor with no push speed-up, which
# made v7's ATK sticky) and the control prototypes at entry + 0x28 (0x416a658c ->
# 0x416a67bc) and + 0x48 (0x416a644c -> 0x416a640c).
def slot_imm(pid, off, want):
    entry = (0x416a6aa4 + 88 * pid + off).to_bytes(4, 'big')
    k = img.find(b'\x48\x79' + entry)
    if k < 0 or img[k - 6:k - 4] not in (b'\x48\x79', b'\x2e\xbc') or int.from_bytes(img[k - 4:k], 'big') != want:
        raise SystemExit(f'id {pid} +{off:#x}: constructor immediate not as expected')
    return B + k - 4
patch(slot_imm(349, 0x04, 0x401ba3c4), 4, 'id 349: knob descriptor, stepped -> as id 341', replace='401ba3ec')
patch(slot_imm(349, 0x28, 0x416a658c), 4, 'id 349: control, transient picture -> slider', replace='416a67bc')
patch(slot_imm(349, 0x48, 0x416a644c), 4, 'id 349: control (+0x48), as id 341', replace='416a640c')
# BD TX-9 DIGI ATK (id 389, once BD FM 2's FMT): its own stepped descriptor 0x401ba2ec and
# the bipolar control -> id 341's descriptor and slider, as id 349.
patch(slot_imm(389, 0x04, 0x401ba34c), 4, 'id 389: knob descriptor -> as id 341', replace='401ba3ec')
patch(slot_imm(389, 0x28, 0x416a682c), 4, 'id 389: control, bipolar -> slider', replace='416a67bc')
# XT TX-9 / TX-8 TYP (ids 366 plain, 374 centred) show LT / MT / HT: point them at the
# stub's own formatter prototype (fmt_lmh, in .m41).
for pid, was in ((366, FMT_PLAIN), (374, FMT_CENTRED)):
    entry = (0x416a6aa4 + 88 * pid + 0x18).to_bytes(4, 'big')
    k = img.find(b'\x48\x79' + entry)
    if k < 0 or img[k - 6:k - 4] not in (b'\x48\x79', b'\x2e\xbc'):
        raise SystemExit(f'id {pid}: formatter constructor block not found')
    if int.from_bytes(img[k - 4:k], 'big') != was:
        raise SystemExit(f'id {pid}: unexpected formatter prototype')
    patch(B + k - 4, 4, f'id {pid}: value display -> LT/MT/HT', sym='fmt_lmh')

block = head + '\n' + '\n\n'.join(out) + '\n'
for k, v in zip(('SIZE_TEXT', 'SIZE_M35', 'SIZE_M37', 'SIZE_M38', 'SIZE_M39', 'SIZE_M40', 'SIZE_M41', 'SIZE_M42', 'SIZE_M34'), sys.argv[3:12]):
    block = block.replace(k, v)
text = open(reg_path, 'rb').read().decode()
cut = text.find('\n# ------------------------------------------------------- 0009-')
if cut >= 0:
    text = text[:cut].rstrip('\n') + '\n'
open(reg_path, 'wb').write((text + block).encode())
print('patches:', len(out))
