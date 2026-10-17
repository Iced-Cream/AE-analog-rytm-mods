        | Mod 0012 - DUCK: a track-keyed ducker on a page behind COMP (see mod.toml).
        |
        | With the FX track selected, press AMP (COMP) a second time for the DUCK page:
        |   SRC  the key track: OFF, BD SD RS CP BT LT MT HT CH OH CY CB
        |   DEP  depth: 127 pulls the other voices fully down (90 ~ -10 dB)
        |   ATK  attack, 0 instant .. 127 ~85 ms (time constant)
        |   HLD  hold at full depth after a hit, 0 .. 170 ms
        |   REL  release, 5 ms .. ~2 s (time constant)
        | Global (one setting for the unit), held in RAM: back to defaults (SRC OFF)
        | at power-up.
        |
        | The engine. The audio interrupt calls vca_frame(frame) once a block
        | (0x40119e0e, `jsr 0x40102960`): for each voice it smooths level x pan and
        | writes the VCA L / R words, frame +10+2v and +26+2v (u16, linear in
        | amplitude: PAN keeps L + R constant, VOL is a square law in the stock code).
        | The words are rewritten from the routine's own smoothed state (0x405fbab0)
        | every call, so scaling them afterwards never accumulates. That call's
        | operand is repointed at duck_gate, which makes it and then scales every
        | voice but the key's.
        |
        | The key: the source track's physical voice in this block's receive frames.
        | The frame index 0x402acd70 is the one the stock FX block will read later in
        | this block (0x401078dc returns 0x8000cf34 + 40 * index, then advances it),
        | so it is read here without being advanced. A hit opens the gate at -36 dBFS
        | once the voice fell below -48 dBFS since the last one.
        |
        | The page. Page 12, listed after COMP (page 10) in the COMP view; five dead
        | Error records (ids 7, 8, 9, 14, 15) as its knobs. The four page hooks are
        | shared with 0010's page behind AMP: each gate here is the first link of a
        | chain (registry chain_pos -1) and passes any other page or id on through
        | CHAIN_* - 0010's gate when 0010 is in the build, else its own stock path
        | (the *_stock labels, which replay the displaced instructions).

        .include "symbols.inc"

        .equ    PAGE_COMP,      10
        .equ    PAGE_DUCK,      12

        .equ    VCA_FN,         0x40102960
        .equ    RX_BASE,        0x8000cf34
        .equ    RX_IDX,         0x402acd70
        .equ    RX_STRIDE,      40                | 10 longs: voices 0..7, IN L/R
        .equ    FRAMES,         32

        .equ    THR_ON,         0x02000000        | -36 dBFS: a hit
        .equ    THR_OFF,        0x00800000        | -48 dBFS: re-arm below this
        .equ    DEP_K,          516               | DEP * 516 = depth, Q16

        .equ    S_ENV,          0                 | Q16, 0..65536
        .equ    S_HOLD,         4                 | blocks
        .equ    S_ARMED,        8

        | the settings, by byte
        .equ    G_SRC,          0
        .equ    G_DEP,          1
        .equ    G_ATK,          2
        .equ    G_HLD,          3
        .equ    G_REL,          4
        .equ    KNOBS,          5

        .globl  pi_stock, get_stock, delta_stock, text_stock   | chain fallbacks: build.py --defsym
        .text

        | ==================================================================
        | The engine
        | ==================================================================
        .align  2
duck_gate:
        move.l  4(%sp),-(%sp)
        jsr     VCA_FN
        addq.l  #4,%sp
        lea     -20(%sp),%sp
        movem.l %d2-%d5/%a2,(%sp)
        lea     dk_state,%a2
        lea     dk_set,%a1
        mvz.b   G_SRC(%a1),%d0
        bne.s   10f
        clr.l   S_ENV(%a2)                        | OFF: nothing to do
        clr.l   S_HOLD(%a2)
        bra.w   99f
10:     lea     src_voice-1,%a0
        mvz.b   (%a0,%d0.l),%d5                   | d5 = the key's voice

        | the key's peak over this block's frames
        move.l  RX_IDX,%d0
        move.l  %d0,%d1
        lsl.l   #3,%d1
        lsl.l   #5,%d0
        add.l   %d1,%d0                           | 40 * index
        add.l   #RX_BASE,%d0
        move.l  %d0,%a0
        move.l  %d5,%d0
        lsl.l   #2,%d0
        add.l   %d0,%a0                           | its slot
        moveq   #0,%d2
        moveq   #FRAMES,%d3
1:      move.l  (%a0),%d0
        bpl.s   2f
        neg.l   %d0
2:      cmp.l   %d2,%d0
        bls.s   3f
        move.l  %d0,%d2
3:      lea     RX_STRIDE(%a0),%a0
        subq.l  #1,%d3
        bne.s   1b

        | the gate: a hit opens it for HLD once the key fell below THR_OFF
        cmp.l   #THR_OFF,%d2
        bcc.s   4f
        moveq   #1,%d0
        move.l  %d0,S_ARMED(%a2)
4:      cmp.l   #THR_ON,%d2
        bcs.s   5f
        tst.l   S_ARMED(%a2)
        beq.s   5f
        clr.l   S_ARMED(%a2)
        mvz.b   G_HLD(%a1),%d0
        add.l   %d0,%d0                           | 2 blocks a step
        addq.l  #1,%d0
        move.l  %d0,S_HOLD(%a2)
        | a hit: attack while held
5:      move.l  S_ENV(%a2),%d0
        tst.l   S_HOLD(%a2)
        beq.s   6f
        subq.l  #1,S_HOLD(%a2)
        mvz.b   G_ATK(%a1),%d3
        addq.l  #1,%d3                            | time constant, blocks
        move.l  #65536,%d1
        sub.l   %d0,%d1
        divu.l  %d3,%d1                           | (1 - env) / (ATK + 1)
        bne.s   51f
        move.l  #65536,%d0                        | the last step
        bra.s   7f
51:     add.l   %d1,%d0
        bra.s   7f
        | release: env -= env / N, N = 8 + REL^2 / 5 blocks
6:      tst.l   %d0
        beq.s   7f
        mvz.b   G_REL(%a1),%d3
        mulu.w  %d3,%d3
        divu.w  #5,%d3
        mvz.w   %d3,%d3
        addq.l  #8,%d3
        move.l  %d0,%d1
        divu.l  %d3,%d1
        bne.s   61f
        moveq   #1,%d1                            | the last steps: one at a time
61:     sub.l   %d1,%d0
7:      move.l  %d0,S_ENV(%a2)
        beq.s   99f                               | no duck: leave the frame alone

        | g = 1 - depth * env, Q16; scale every voice but the key's
        mvz.b   G_DEP(%a1),%d1
        mulu.w  #DEP_K,%d1                        | depth, Q16
        mulu.l  %d0,%d1
        clr.w   %d1
        swap    %d1
        move.l  #65536,%d4
        sub.l   %d1,%d4
        move.l  24(%sp),%a0                       | the frame
        lea     10(%a0),%a0                       | VCA L, voice 0
        moveq   #0,%d3                            | voice
8:      cmp.l   %d5,%d3
        beq.s   9f
        mvz.w   (%a0),%d0
        mulu.l  %d4,%d0
        clr.w   %d0
        swap    %d0
        move.w  %d0,(%a0)
        mvz.w   16(%a0),%d0                       | VCA R, +26
        mulu.l  %d4,%d0
        clr.w   %d0
        swap    %d0
        move.w  %d0,16(%a0)
9:      addq.l  #2,%a0
        addq.l  #1,%d3
        moveq   #8,%d0
        cmp.l   %d0,%d3
        bne.s   8b
99:     movem.l (%sp),%d2-%d5/%a2
        lea     20(%sp),%sp
        rts

        | ==================================================================
        | The page
        | ==================================================================

        | page_info(id): page 12 is ours.
        .align  2
pi_gate:
        moveq   #PAGE_DUCK,%d0
        cmp.l   4(%sp),%d0
        bne.s   1f
        lea     page_duck,%a0
        move.l  %a0,%d0
        rts
1:      jmp     CHAIN_PI
        .align  2
pi_stock:
        moveq   #10,%d1                           | displaced
        move.l  %sp@(4),%d0                       | displaced
        jmp     page_info_resume

        | page_get_value: (%sp) return, 4 view, 8 id, 12 lock -> 8.8, 0..127 scale
        .align  2
get_gate:
        move.l  8(%sp),%d0
        bsr.w   knob_of                           | d0 = knob, or -1
        bmi.s   1f
        bsr.w   knob_value
        lsl.l   #8,%d0
        rts
1:      jmp     CHAIN_GET
        .align  2
get_stock:
        lea     %sp@(-12),%sp                     | displaced
        moveml  %d2-%d3/%a2,%sp@                  | displaced
        jmp     page_get_value_body

        | param_apply_delta past its prologue: %sp@(0..11) d2/d3/a2, a2 the view,
        | %sp@(20) the id, %sp@(24) the delta in 8.8
        .align  2
delta_gate:
        move.l  %sp@(20),%d0
        bsr.w   knob_of
        bmi.s   9f
        move.l  %d0,%d3                           | the knob
        move.l  %sp@(24),%d2
        asr.l   #8,%d2                            | whole steps
        beq.s   7f
        move.l  %d3,%d0
        bsr.w   knob_value
        add.l   %d2,%d0
        bpl.s   1f
        clr.l   %d0
1:      lea     knob_max,%a0
        mvz.b   (%a0,%d3.l),%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:      lea     dk_set,%a0
        move.b  %d0,(%a0,%d3.l)
        move.l  %a2,-(%sp)
        jsr     view_invalidate                   | redraw now
        addq.l  #4,%sp
7:      movem.l (%sp),%d2-%d3/%a2                 | param_apply_delta's epilogue
        lea     12(%sp),%sp
        rts
9:      jmp     CHAIN_DELTA
        .align  2
delta_stock:
        mvzb    %d3,%d3                           | displaced
        move.l  %a2@(116),-(%sp)                  | displaced
        jmp     param_apply_delta_track

        | param_value_text past its argument loads: %sp@(0..19) d2-d4/a2-a3, d4 the
        | id, %sp@(36) the output buffer
        .align  2
text_gate:
        move.l  %d4,%d0
        bsr.w   knob_of
        bmi.s   9f
        move.l  %d0,%d1
        bsr.w   knob_value
        move.l  %sp@(36),%a1
        tst.l   %d1
        bne.s   2f
        lea     src_names,%a0                     | SRC: the track's name
        lsl.l   #2,%d0
        add.l   %d0,%a0
1:      move.b  (%a0)+,%d1
        beq.s   3f
        move.b  %d1,(%a1)+
        bra.s   1b
2:      bsr.w   put_u3
3:      clr.b   (%a1)
        movem.l (%sp),%d2-%d4/%a2-%a3             | param_value_text's epilogue
        lea     20(%sp),%sp
        rts
9:      jmp     CHAIN_TEXT
        .align  2
text_stock:
        movel   %sp@(32),%d2                      | displaced
        movel   %sp@(36),%d3                      | displaced
        jmp     param_value_text_args

        | knob_of(d0 = id) -> d0 = knob 0..4 or -1 (flags set). Clobbers a0.
        .align  2
knob_of:
        lea     knob_ids,%a0
        move.l  %d1,-(%sp)
        moveq   #0,%d1
1:      cmp.w   (%a0)+,%d0
        beq.s   2f
        addq.l  #1,%d1
        cmp.l   #KNOBS,%d1
        bne.s   1b
        moveq   #-1,%d1
2:      move.l  %d1,%d0
        move.l  (%sp)+,%d1
        tst.l   %d0
        rts

        | knob_value(d0 = knob) -> d0 = its setting. Clobbers a0.
knob_value:
        lea     dk_set,%a0
        mvz.b   (%a0,%d0.l),%d0
        rts

        | put_u3(d0 = 0..127, a1 = out) - decimal, no leading zeros, a1 past it.
        | Clobbers d0.
put_u3:
        move.l  %d1,-(%sp)
        moveq   #100,%d1
        cmp.l   %d1,%d0
        bcs.s   1f
        sub.l   %d1,%d0
        move.b  #0x31,(%a1)+                      | at most 127: the hundreds are 1
        divu.w  #10,%d0
        bra.s   2f
1:      divu.w  #10,%d0
        tst.w   %d0
        beq.s   3f
2:      move.l  %d0,%d1
        add.l   #0x30,%d1
        move.b  %d1,(%a1)+
3:      swap    %d0
        add.l   #0x30,%d0
        move.b  %d0,(%a1)+
        move.l  (%sp)+,%d1
        rts

        | ==================================================================
        | Data
        | ==================================================================
        .align  4
duck_pages:     .long   PAGE_COMP, PAGE_DUCK      | the COMP view's pages
page_duck:      .long   str_page                  | {name, top row, bottom row}
                .long   7, 8, 9, 14
                .long   15, 0, 0, 0
dk_state:       .long   0, 0, 1                   | env, hold, armed
knob_ids:       .short  7, 8, 9, 14, 15
knob_max:       .byte   12, 127, 127, 127, 127
dk_set:         .byte   0, 90, 3, 22, 36          | SRC DEP ATK HLD REL (defaults)
src_voice:      .byte   0, 2, 7, 7, 1, 3, 5, 5, 4, 4, 6, 6  | BD SD RS CP BT LT MT HT CH OH CY CB
src_names:      .ascii  "OFF\0BD\0\0SD\0\0RS\0\0CP\0\0BT\0\0LT\0\0MT\0\0HT\0\0CH\0\0OH\0\0CY\0\0CB\0\0"
str_page:       .asciz  "DUCK"
str_group:      .asciz  "DUCK"
str_src_l:      .asciz  "Duck Source"
str_src:        .asciz  "SRC"
str_dep_l:      .asciz  "Duck Depth"
str_dep:        .asciz  "DEP"
str_atk_l:      .asciz  "Duck Attack"
str_atk:        .asciz  "ATK"
str_hld_l:      .asciz  "Duck Hold"
str_hld:        .asciz  "HLD"
str_rel_l:      .asciz  "Duck Release"
str_rel:        .asciz  "REL"
