        | duck - DUCK (AE 0012), a track-keyed ducker on a page behind COMP, for
        | the Analog Rytm MKII, OS 1.74.
        |
        | With the FX track selected, press AMP (COMP) a second time for the DUCK
        | page:
        |   SRC  the key track: OFF, BD SD RS CP BT LT MT HT CH OH CY CB
        |   DEP  depth: 127 pulls the other voices fully down (90 ~ -10 dB)
        |   ATK  attack, 0 instant .. 127 ~85 ms (time constant)
        |   HLD  hold at full depth after a hit, 0 .. 170 ms
        |   REL  release, 5 ms .. ~2 s (time constant)
        | 1.1 (core-ar2 0.10): the five are kit fields (duck_src .. duck_rel,
        | the MK1's defaults as their inits, SRC OFF), so each kit keeps its own,
        | and lockable: the FX track's parameters, p-locked with an FX trig
        | held, locked in scenes and performances, on MIDI on the FX channel.
        | DEP, ATK, HLD and REL are FX LFO destinations; SRC, a choice of track,
        | is not, and jumps ("smooth": false). Every block the engine reads the
        | five as stock would play them (core_param_values on track 12) into
        | dk_set, which it reads as before. 1.0 held them in RAM, global.
        |
        | The engine. The audio interrupt calls 0x40109940(frame) once a block
        | (`jsr` at 0x401212b2): the amp envelopes, the overdrive and, for each
        | voice, the VCA L / R words at frame +10+2v and +26+2v (u16), level x pan
        | from the track's parameters - the MK1's layout. They are computed afresh
        | every call, so scaling them afterwards never accumulates. That call is
        | repointed at duck_gate, which makes it and then scales every voice but
        | the key's.
        |
        | The key: the source track's physical voice in the receive buffer
        | 0x80007440 (12 longs a frame, voice v in slot SLOT_MAP[v], at +8 + 4 *
        | slot). The buffer is refilled later in the block (0x401213c4), so here
        | it holds the previous block's voices: one block (0.67 ms) of latency,
        | about what the MK1's frame index gave. A hit opens the gate at -36 dBFS
        | once the voice fell below -48 dBFS since the last one.
        |
        | The page: page 14 after COMP (page 11) in the COMP view's list, through
        | core-ar2 0.4's page tables. Its knobs are HH TEST's parameter records 443..447 (a hidden
        | machine's, renamed): the MKII has none of the MK1's spare Error records
        | left once rytm2_mods is in. The COMP view's page list is also what
        | comp-preview changes, so the two cannot be in one build.

        .equ    PAGE_COMP,      11
        .equ    PAGE_DUCK,      14
        .equ    ID0,            443               | SRC DEP ATK HLD REL: 443..447

        .equ    VCA_FN,         0x40109940
        .equ    RXBUF,          0x80007440
        .equ    RX_STRIDE,      48                | 12 longs a frame
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

        .extern core_store_get, core_store_set, core_param_handle, core_param_values
        .extern duck_src, duck_dep, duck_atk, duck_hld, duck_rel
        .equ    PARAM_NONE,     0x80000000        | CORE_PARAM_NONE
        .equ    FX_TRACK,       12
        .equ    LIVE_KITS,      0x412558e3        | the kits as edited
        .equ    LIVE_KIT_SIZE,  2531
        .equ    WORKING_KIT,    0x405c8f20+0x19d3f7 | the working kit's index, a long, unaligned

        .text

        | ==================================================================
        | The engine
        | ==================================================================
        .globl  duck_gate
        .align  2
duck_gate:
        move.l  4(%sp),-(%sp)
        jsr     VCA_FN
        addq.l  #4,%sp
        bsr.w   dk_read                           | the settings as stock would play them
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

        | the key's peak over the last block's frames
        lea     slot_off,%a0
        mvz.b   (%a0,%d5.l),%d0                   | +8 + 4 * slot
        add.l   #RXBUF,%d0
        move.l  %d0,%a0
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

        | ------------------------------------------------------------------
        | dk_read() - the five settings on the FX track (the kit's, the FX
        | trig's p-lock, the scene's lock, smoothed but SRC, plus the
        | performances and the FX LFO; core_param_values, 8.8) into dk_set,
        | rounded and clamped to each knob's range. Handles on the first call.
        | C convention; clobbers d0/d1/a0/a1.
        | ------------------------------------------------------------------
        .align  2
dk_read:
        lea     dk_h,%a0
        tst.l   (%a0)
        bne.s   3f
        move.l  %d2,-(%sp)
        moveq   #0,%d2
2:      lea     dk_fields,%a0
        move.l  (%a0,%d2.l*4),-(%sp)
        jsr     core_param_handle
        addq.l  #4,%sp
        lea     dk_h,%a0
        move.l  %d0,(%a0,%d2.l*4)
        addq.l  #1,%d2
        moveq   #KNOBS,%d0
        cmp.l   %d0,%d2
        bne.s   2b
        move.l  (%sp)+,%d2
        lea     dk_h,%a0
        tst.l   (%a0)
        beq.s   9f                                | no codes: dk_set keeps its last
3:      pea     dk_out
        clr.l   -(%sp)                            | flags
        pea     KNOBS                             | n
        pea     dk_h
        pea     FX_TRACK
        jsr     core_param_values
        lea     20(%sp),%sp
        move.l  %d2,-(%sp)
        lea     dk_out,%a0
        lea     dk_set,%a1
        moveq   #0,%d2                            | knob
4:      move.l  (%a0)+,%d0
        cmp.l   #PARAM_NONE,%d0
        beq.s   6f
        add.l   #128,%d0
        asr.l   #8,%d0
        bpl.s   5f
        moveq   #0,%d0
5:      lea     knob_max,%a1
        mvz.b   (%a1,%d2.l),%d1
        cmp.l   %d1,%d0
        ble.s   7f
        move.l  %d1,%d0
7:      lea     dk_set,%a1
        move.b  %d0,(%a1,%d2.l)
6:      addq.l  #1,%d2
        moveq   #KNOBS,%d0
        cmp.l   %d0,%d2
        bne.s   4b
        move.l  (%sp)+,%d2
9:      rts

        | ==================================================================
        | The page, through core-ar2's core_pages and core_params (C convention)
        | ==================================================================

        | cur_kit() -> d0 = the working kit as edited (the FX track's item), or
        | 0. Clobbers d0/d1/a0.
        .align  2
cur_kit:
        lea     WORKING_KIT,%a0
        moveq   #4,%d1
        moveq   #0,%d0
1:      lsl.l   #8,%d0
        move.b  (%a0)+,%d0
        subq.l  #1,%d1
        bne.s   1b
        cmp.l   #128,%d0
        bcc.s   8f
        move.l  #LIVE_KIT_SIZE,%d1
        mulu.l  %d1,%d0
        add.l   #LIVE_KITS,%d0
        rts
8:      moveq   #0,%d0
        rts

        | kit_get(d0 = knob 0..4) -> d0 = its field in the working kit (0 with
        | no kit). Clobbers d0/d1/a0/a1.
        .align  2
kit_get:
        move.l  %d0,-(%sp)
        bsr.s   cur_kit
        move.l  (%sp)+,%d1
        tst.l   %d0
        beq.s   9f
        clr.l   -(%sp)                            | index, unused for a kit
        move.l  %d0,-(%sp)                        | item: the kit
        lea     dk_fields,%a0
        move.l  (%a0,%d1.l*4),-(%sp)              | the field's descriptor
        jsr     core_store_get
        lea     12(%sp),%sp
9:      rts

        | knob_of(d0 = id) -> d0 = knob 0..4 or -1 (flags set)
        .align  2
knob_of:
        sub.l   #ID0,%d0
        bmi.s   1f
        moveq   #KNOBS,%d1
        cmp.l   %d1,%d0
        bcs.s   2f
1:      moveq   #-1,%d0
2:      tst.l   %d0
        rts

        | int get(long id, long *value): the knob's setting in 8.8
        .align  2
dk_get:
        move.l  4(%sp),%d0
        bsr.w   knob_of
        bmi.s   9f
        bsr.s   kit_get
        lsl.l   #8,%d0
        move.l  8(%sp),%a0
        move.l  %d0,(%a0)
        moveq   #1,%d0
        rts
9:      moveq   #0,%d0
        rts

        | int delta(void *view, long id, long delta, long func): the delta in 8.8, added
        | to the knob's 8.8 value, whose whole part is the setting in the
        | working kit; dk_acc keeps the turn's fraction while the kit holds its
        | whole part
        .align  2
dk_delta:
        move.l  8(%sp),%d0
        bsr.w   knob_of
        bmi.w   8f
        lea     -12(%sp),%sp
        movem.l %d2-%d4,(%sp)
        move.l  %d0,%d2                           | d2 = the knob
        bsr.w   cur_kit
        move.l  %d0,%d3                           | d3 = the kit
        beq.s   7f
        move.l  %d2,%d0
        bsr.w   kit_get
        move.l  %d0,%d4                           | d4 = the stored setting
        lsl.l   #8,%d0
        lea     dk_acc,%a0
        mvz.w   (%a0,%d2.l*2),%d1
        move.l  %d1,%a1
        lsr.l   #8,%d1
        cmp.l   %d4,%d1                           | dk_acc still on the stored step:
        bne.s   1f
        move.l  %a1,%d0                           | keep its fraction
1:      add.l   24(%sp),%d0                       | the delta
        bpl.s   2f
        clr.l   %d0
2:      lea     knob_max,%a0
        mvz.b   (%a0,%d2.l),%d1
        lsl.l   #8,%d1
        cmp.l   %d1,%d0
        ble.s   3f
        move.l  %d1,%d0
3:      lea     dk_acc,%a0
        move.w  %d0,(%a0,%d2.l*2)
        lsr.l   #8,%d0
        cmp.l   %d4,%d0
        beq.s   7f
        move.l  %d0,-(%sp)                        | value
        clr.l   -(%sp)                            | index
        move.l  %d3,-(%sp)                        | item: the kit
        lea     dk_fields,%a0
        move.l  (%a0,%d2.l*4),-(%sp)
        jsr     core_store_set
        lea     16(%sp),%sp
7:      movem.l (%sp),%d2-%d4
        lea     12(%sp),%sp
        moveq   #1,%d0
        rts
8:      moveq   #0,%d0
        rts

        | int text(struct core_text *t): t = {obj, id, value, buf}. SRC: the
        | track's name, from the value shown (a held trig's lock, a scene's);
        | the others pass, and core writes the number, as for any lockable
        | parameter.
        .align  2
dk_text:
        move.l  4(%sp),%a1
        move.l  4(%a1),%d0                        | the id
        bsr.w   knob_of
        bne.s   8f                                | not SRC (or not ours): pass
        move.l  4(%sp),%a1
        move.l  8(%a1),%d0                        | the value, 8.8
        add.l   #128,%d0
        asr.l   #8,%d0
        bpl.s   4f
        moveq   #0,%d0
4:      moveq   #12,%d1
        cmp.l   %d1,%d0
        ble.s   5f
        move.l  %d1,%d0
5:      move.l  12(%a1),%a1                       | the buffer
        lea     src_names,%a0                     | SRC: the track's name
        lsl.l   #2,%d0
        add.l   %d0,%a0
1:      move.b  (%a0)+,%d1
        beq.s   3f
        move.b  %d1,(%a1)+
        bra.s   1b
3:      clr.b   (%a1)
        moveq   #1,%d0
        rts
8:      moveq   #0,%d0
        rts

        | ev_tick, until done once: the five knobs' RAM records (built at boot
        | from the records patched in mod.json) take a stock dial's encoder feel
        | and its dial art, from COMP's MIX (id 94, 0..127); SRC's range is
        | then 0..12. Stock gives HH TEST's records a select box for SEL, which
        | DEP would otherwise draw as.
        .equ    PARAM_INFO,     0x419a4888        | RAM records, 0x54 bytes an id
        .equ    PI_STRIDE,      0x54
        .equ    PI_DRAW,        0x24              | the draw callback, 16 B
        .equ    ID_DONOR,       94
        .globl  duck_tick
        .align  2
duck_tick:
        lea     dk_ready,%a0
        tst.b   (%a0)
        bne.s   9f
        moveq   #1,%d0
        move.b  %d0,(%a0)
        lea     PARAM_INFO+ID_DONOR*PI_STRIDE,%a0
        lea     PARAM_INFO+ID0*PI_STRIDE,%a1
        moveq   #KNOBS,%d0
1:      move.l  4(%a0),4(%a1)                     | the encoder's range, 8.8
        move.l  8(%a0),8(%a1)
        move.l  16(%a0),16(%a1)                   | its acceleration
        move.l  PI_DRAW(%a0),PI_DRAW(%a1)         | the dial art
        move.l  PI_DRAW+4(%a0),PI_DRAW+4(%a1)
        move.l  PI_DRAW+8(%a0),PI_DRAW+8(%a1)
        move.l  PI_DRAW+12(%a0),PI_DRAW+12(%a1)
        lea     PI_STRIDE(%a1),%a1
        subq.l  #1,%d0
        bne.s   1b
        move.l  #12<<8,%d0                        | SRC: 0..12
        move.l  %d0,PARAM_INFO+ID0*PI_STRIDE+8
        | SRC draws its track's name in place of the dial, as LFO MOD draws
        | FREE: the draw callback is a functor {obj, 0, manager, invoker};
        | MOD's empty one lends its obj and manager, the invoker is dk_src_draw
        lea     PARAM_INFO+ID_TEXT*PI_STRIDE+PI_DRAW,%a0
        lea     PARAM_INFO+ID0*PI_STRIDE+PI_DRAW,%a1
        move.l  (%a0),(%a1)
        move.l  4(%a0),4(%a1)
        move.l  8(%a0),8(%a1)
        lea     dk_src_draw,%a0
        move.l  %a0,12(%a1)
9:      rts

        | SRC's knob, as text: (obj, value 8.8, bitmap, x, y), as stock's MOD
        | draws (0x400fbe0e): the font, then the string centred over "XXX"
        .equ    ID_TEXT,        70                | LFO MOD: a text knob
        .equ    KNOB_FONT,      0x40071be8
        .equ    FONT_OBJ,       0x417e389c
        .equ    DRAW_TEXT,      0x4007154c
        .equ    STR_FMT,        0x402413d4        | "%s"
        .equ    STR_WIDTH,      0x402413d8        | "XXX"
        .align  2
dk_src_draw:
        move.l  %d2,-(%sp)
        move.l  12(%sp),%d2                       | the value, 8.8
        add.l   #128,%d2
        asr.l   #8,%d2
        bpl.s   1f
        moveq   #0,%d2
1:      moveq   #12,%d0
        cmp.l   %d0,%d2
        ble.s   2f
        move.l  %d0,%d2
2:      lsl.l   #2,%d2
        lea     src_names,%a0
        add.l   %a0,%d2                           | the name
        pea     FONT_OBJ
        jsr     KNOB_FONT
        addq.l  #4,%sp
        move.l  %d2,-(%sp)
        pea     STR_FMT
        pea     STR_WIDTH
        clr.l   -(%sp)
        pea     1
        move.l  20+24(%sp),%d1                    | y - 2
        subq.l  #2,%d1
        move.l  %d1,-(%sp)
        move.l  20+24(%sp),-(%sp)                 | x
        move.l  %d0,-(%sp)                        | the font
        move.l  16+32(%sp),-(%sp)                 | the bitmap
        jsr     DRAW_TEXT
        lea     36(%sp),%sp
        move.l  (%sp)+,%d2
        rts

        | ==================================================================
        | Data
        | ==================================================================
        .align  4
        .globl  duck_view_page
duck_view_page: .long   8, PAGE_DUCK, 0           | core_view_pages: CORE_VIEW_COMP, always shown
        .globl  duck_page, duck_params
duck_page:      .long   PAGE_DUCK, str_page       | core_pages: {page, name, A..D, E..H}
                .long   ID0, ID0+1, ID0+2, ID0+3
                .long   ID0+4, 0, 0, 0
duck_params:    .long   ID0, ID0+KNOBS-1, dk_get, dk_delta, dk_text  | core_params
dk_state:       .long   0, 0, 1                   | env, hold, armed
dk_acc:         .short  0, 90<<8, 3<<8, 22<<8, 36<<8  | the turns' fractions, 8.8
dk_ready:       .byte   0
knob_max:       .byte   12, 127, 127, 127, 127
dk_set:         .byte   0, 90, 3, 22, 36          | SRC DEP ATK HLD REL: the engine's copy
        .align  4
dk_fields:      .long   duck_src, duck_dep, duck_atk, duck_hld, duck_rel
        .globl  duck_src_param, duck_dep_param, duck_atk_param, duck_hld_param, duck_rel_param
        .macro  DK_PARAM name, k, max
duck_\name\()_param:                              | core_lock_params: struct core_lock_param
                .long   duck_\name, ID0+\k
                .short  0, \max
                .long   duck_str_\name, duck_str_\name\()_l, str_cat
        .endm
        DK_PARAM src, 0, 12
        DK_PARAM dep, 1, 127
        DK_PARAM atk, 2, 127
        DK_PARAM hld, 3, 127
        DK_PARAM rel, 4, 127
dk_h:           .space  KNOBS*4                   | their handles
dk_out:         .space  KNOBS*4                   | core_param_values' answers
src_voice:      .byte   0, 2, 7, 7, 1, 3, 5, 5, 4, 4, 6, 6  | BD SD RS CP BT LT MT HT CH OH CY CB
        | physical voice -> its receive-buffer offset, +8 + 4 * slot, from the
        | stock map 0x401ef480 (0, 3, 1, 4, 6, 5, 7, 2)
slot_off:       .byte   8, 20, 12, 24, 32, 28, 36, 16
src_names:      .ascii  "OFF\0BD\0\0SD\0\0RS\0\0CP\0\0BT\0\0LT\0\0MT\0\0HT\0\0CH\0\0OH\0\0CY\0\0CB\0\0"
        .globl  duck_str_group, duck_str_src_l, duck_str_src, duck_str_dep_l, duck_str_dep
        .globl  duck_str_atk_l, duck_str_atk, duck_str_hld_l, duck_str_hld, duck_str_rel_l, duck_str_rel
str_cat:        .asciz  "DUCK"                    | DUCK:Duck Depth in the FX LFO's DST
str_page:       .asciz  "DUCK"
duck_str_group: .asciz  "DUCK"
duck_str_src_l: .asciz  "Duck Source"
duck_str_src:   .asciz  "SRC"
duck_str_dep_l: .asciz  "Duck Depth"
duck_str_dep:   .asciz  "DEP"
duck_str_atk_l: .asciz  "Duck Attack"
duck_str_atk:   .asciz  "ATK"
duck_str_hld_l: .asciz  "Duck Hold"
duck_str_hld:   .asciz  "HLD"
duck_str_rel_l: .asciz  "Duck Release"
duck_str_rel:   .asciz  "REL"
        .align  2
