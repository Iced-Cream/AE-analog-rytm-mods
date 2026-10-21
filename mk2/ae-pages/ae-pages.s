        | ae-pages - the extra parameter pages the AE mods add, for the Analog Rytm
        | MKII, OS 1.74.
        |
        | On the MK1 the AE mods' pages (DUCK behind COMP, FX SENDS behind AMP)
        | share four stock hooks through build.py's detour chains: page_info,
        | page_get_value, param_apply_delta and param_value_text. On the MKII
        | rytm2_mods already holds the free instructions at the start of those
        | routines (lfo-rnd, voice-dac and the others each detour one, and rejoin
        | at the next), so this mod takes one more place in each and hands it on
        | to every page in its table. Each page mod adds a descriptor to the
        | table `ae_pages`:
        |
        |   +0   page id (12 and 13 are lfo-rnd's and voice-dac's; AE uses 14 on)
        |   +4   the page's entry for page_info: {name, ids A..H}, 36 bytes
        |   +8   long get(long id): the knob's value 0..127, or -1 if not its id
        |   +12  long delta(void *view, long id, long delta): 0 if not its id,
        |        else it applied the delta (8.8, as stock's encoder path gives it:
        |        a knob whose record has a small range gets fractions, which the
        |        page keeps, as stock keeps its 8.8 values' fractions)
        |   +16  long text(long id, char *buf): 0 if not its id, else it wrote
        |        the value's text
        |
        | C calling convention for the three functions.
        |
        | page_info (0x400ff5e0) itself starts with lfo-rnd's detour and ends,
        | for pages above 11, in voice-dac's, so it has no free instruction
        | left: its eight callers are repointed here instead, and anything not
        | in the table goes on to it.

        .equ    PAGE_INFO,      0x400ff5e0
        .equ    VIEW_INVALIDATE, 0x40078580

        .equ    D_PAGE,         0
        .equ    D_INFO,         4
        .equ    D_GET,          8
        .equ    D_DELTA,        12
        .equ    D_TEXT,         16

        .text

        | ------------------------------------------------------------------
        | page_info(page) for the eight callers: C convention, d0 the entry.
        | ------------------------------------------------------------------
        .globl  ae_pages_info
        .align  2
ae_pages_info:
        move.l  4(%sp),%d0
        lea     ae_pages,%a1
1:      move.l  (%a1)+,%d1
        beq.s   9f
        move.l  %d1,%a0
        cmp.l   D_PAGE(%a0),%d0
        bne.s   1b
        move.l  D_INFO(%a0),%d0
        rts
9:      jmp     PAGE_INFO

        | ------------------------------------------------------------------
        | page_get_value at 0x40038472, past its prologue and its two argument
        | loads: (%sp) d2/d3/a2, 12 return, 16 view, 20 id, 24 lock; d2 = id,
        | a2 = view. Ours: the value in 8.8. Not ours: `move.l 24(%sp),%d3;
        | blt.s 0x400384ca`, then on.
        | ------------------------------------------------------------------
        .globl  ae_pages_get
        .align  2
ae_pages_get:
        move.l  %a3,-(%sp)
        lea     ae_pages,%a3
1:      move.l  (%a3)+,%d0
        beq.s   8f
        move.l  %d0,%a0
        move.l  %d2,-(%sp)
        move.l  D_GET(%a0),%a0
        jsr     (%a0)
        addq.l  #4,%sp
        tst.l   %d0
        bmi.s   1b
        move.l  (%sp)+,%a3
        lsl.l   #8,%d0
        movem.l (%sp),%d2-%d3/%a2                 | page_get_value's epilogue
        lea     12(%sp),%sp
        rts
8:      move.l  (%sp)+,%a3
        move.l  24(%sp),%d3                       | displaced
        blt.s   9f                                | displaced
        jmp     0x40038478
9:      jmp     0x400384ca

        | ------------------------------------------------------------------
        | param_apply_delta at 0x400378c8, after ctrl-all's place: (%sp) the
        | pushed -1, 4 the pushed track source, 8 d2/d3/a2, 20 return, 24 view,
        | 28 id, 32 delta in 8.8; a2 the view, a0 its vtable, d0 the track.
        | Ours: the delta to the page, the view redrawn. Not ours: `move.l
        | %a2,-(%sp); movea.l 160(%a0),%a0`, then on.
        | ------------------------------------------------------------------
        .globl  ae_pages_delta
        .align  2
ae_pages_delta:
        lea     -12(%sp),%sp                      | 12 more
        movem.l %d0/%a0/%a3,(%sp)
        lea     ae_pages,%a3
1:      move.l  (%a3)+,%d0
        beq.s   8f
        move.l  %d0,%a0
        move.l  44(%sp),-(%sp)                    | delta, 8.8
        move.l  44(%sp),-(%sp)                    | id
        move.l  %a2,-(%sp)                        | view
        move.l  D_DELTA(%a0),%a0
        jsr     (%a0)
        lea     12(%sp),%sp
        tst.l   %d0
        beq.s   1b
        move.l  %a2,-(%sp)
        jsr     VIEW_INVALIDATE                   | redraw now
        addq.l  #4,%sp
        movem.l (%sp),%d0/%a0/%a3
        lea     20(%sp),%sp                       | ours and the two pushes
        movem.l (%sp),%d2-%d3/%a2                 | param_apply_delta's epilogue
        lea     12(%sp),%sp
        rts
8:      movem.l (%sp),%d0/%a0/%a3
        lea     12(%sp),%sp
        move.l  %a2,-(%sp)                        | displaced
        move.l  160(%a0),%a0                      | displaced
        jmp     0x400378ce

        | ------------------------------------------------------------------
        | param_value_text at 0x400a866c, just after param_info(id): (%sp) the
        | pushed id, 4 d2-d4/a2-a3, 24 return, 28 object, 32 id, 36, 40 the
        | output buffer; d4 = id, d3 = the buffer, d0 = the RAM record.
        | Ours: the text, and return. Not ours: `addq.l #4,%sp; movea.l
        | %d0,%a2; tst.l 28(%a2)`, then on.
        | ------------------------------------------------------------------
        .globl  ae_pages_text
        .align  2
ae_pages_text:
        addq.l  #4,%sp                            | displaced
        subq.l  #8,%sp
        movem.l %d0/%a3,(%sp)
        lea     ae_pages,%a3
1:      move.l  (%a3)+,%d0
        beq.s   8f
        move.l  %d0,%a0
        move.l  %d3,-(%sp)                        | buffer
        move.l  %d4,-(%sp)                        | id
        move.l  D_TEXT(%a0),%a0
        jsr     (%a0)
        addq.l  #8,%sp
        tst.l   %d0
        beq.s   1b
        movem.l (%sp),%d0/%a3
        addq.l  #8,%sp
        movem.l (%sp),%d2-%d4/%a2-%a3             | param_value_text's epilogue
        lea     20(%sp),%sp
        rts
8:      movem.l (%sp),%d0/%a3
        addq.l  #8,%sp
        move.l  %d0,%a2                           | displaced
        tst.l   28(%a2)                           | displaced
        jmp     0x400a8674
