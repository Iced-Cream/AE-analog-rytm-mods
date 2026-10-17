        | Mod 0010 - the DSP and the helpers (included by stub.s).

        | state, at st
        .equ    ST_CLEAR,       0                 | longs of FXRAM cleared so far
        .equ    ST_TAIL,        4                 | blocks of tail left
        .equ    ST_RET,         8                 | byte: the return holds audio
        .equ    ST_CPH,         12                | chorus LFO phase
        .equ    ST_CW,          16                | chorus write index
        .equ    ST_HLP,         20                | high-pass state (its low-pass part)
        .equ    ST_FB,          24                | the taps' last average, fed back
        .equ    ST_DL,          28                | chorus delays at the block's end, 16.16
        .equ    ST_DR,          32
        .equ    ST_NACT,        36                | sending voices this block
        .equ    ST_COEF,        40                | per voice: chorus coefficient, a spare (Q31)
        .equ    ST_ACT,         104               | per sending voice: rx offset, cC, spare
        .equ    ST_CDIV,        200               | blocks until coefs_build runs again
        .equ    ST_ANY,         204               | its last result: a track sends
        .equ    ST_SIZE,        208
        .equ    COEF_K,         66572             | v^2 * K: v 127 -> 0.5 in Q31

        | the helpers in cave3 (.tab), the rest in cave (.text)
        .section .tab,"awx"

        | ------------------------------------------------------------------
        | knob_of(d0 = id 0..468) -> d0 = knob 0..7 (N clear), or -1 (N set).
        | Clobbers d0/a0/a1 only (get_gate runs before stock's prologue).
        | ------------------------------------------------------------------
        .align  2
knob_of:
        lea     knob_ids,%a0
        sub.l   %a1,%a1
1:      cmp.w   (%a0)+,%d0
        beq.s   2f
        addq.l  #1,%a1
        cmpa.l  #8,%a1
        bne.s   1b
        moveq   #-1,%d0
        rts
2:      move.l  %a1,%d0
        rts

        | ------------------------------------------------------------------
        | knob_value(d0 = knob) -> d0 = 0..127. Clobbers d0/d1/a0/a1.
        | ------------------------------------------------------------------
        .align  2
knob_value:
        tst.l   %d0
        bne.s   5f
        jsr     word_sync                         | CHR: the sound's word, bits 0..6
        moveq   #0x7f,%d1
        and.l   %d1,%d0
        rts
5:      lea     globals,%a0
        mvzb    -1(%a0,%d0.l),%d0
        rts

        | ------------------------------------------------------------------
        | word_sync() -> d0 = the selected track's sound word (0 without a
        | sound), a0 = its live sound or 0. Clobbers d0/d1/a0/a1.
        | ------------------------------------------------------------------
        .align  2
word_sync:
        jsr     project_singleton
        move.l  %d0,%a0
        pea     PROJ_TRACKSEL(%a0)
        jsr     track_index_of
        addq.l  #4,%sp
        jsr     shared_sound_of                   | d0 = a0 = the live sound
        beq.s   8f
        mvzw    OFF_PARAMS(%a0),%d0
        rts
8:      clr.l   %d0
        sub.l   %a0,%a0
        rts

        | put_u3(d0 = 0..999, a1 = out) - decimal, no leading zeros. Clobbers d0/d1.
        .align  2
put_u3:
        move.l  %d2,-(%sp)
        moveq   #0,%d2
        divu.w  #100,%d0
        mvzw    %d0,%d1
        beq.s   1f
        add.l   #0x30,%d1
        move.b  %d1,(%a1)+
        moveq   #1,%d2
1:      clr.w   %d0
        swap    %d0
        divu.w  #10,%d0
        mvzw    %d0,%d1
        tst.l   %d2
        bne.s   2f
        tst.l   %d1
        beq.s   3f
2:      add.l   #0x30,%d1
        move.b  %d1,(%a1)+
3:      swap    %d0
        mvzw    %d0,%d1
        add.l   #0x30,%d1
        move.b  %d1,(%a1)+
        move.l  (%sp)+,%d2
        rts

        .text

        | ------------------------------------------------------------------
        | coefs_build(a6 = st) -> d0 non-zero if any track sends. Per physical
        | voice, its owning track's CHR / CMB from the live sound; the
        | coefficients glide a quarter of the way a block (no zipper), and the
        | voices with one non-zero go into the active list. Clobbers d0-d7/a0-a4.
        | ------------------------------------------------------------------
        .align  2
coefs_build:
        moveq   #0,%d7                            | any target
        moveq   #0,%d6                            | voice
        lea     ST_COEF(%a6),%a2
        lea     ST_ACT(%a6),%a3
        clr.l   ST_NACT(%a6)
        lea     voice_owner,%a4
1:      moveq   #0,%d4                            | targets: chorus d4, comb d5
        moveq   #0,%d5
        mvzb    (%a4,%d6.l),%d0
        moveq   #TRACKS-1,%d1
        cmp.l   %d1,%d0
        bhi.s   3f
        move.l  #SOUND_STRIDE,%d1
        mulu.l  %d1,%d0
        move.l  project_instance,%d1
        beq.s   3f
        add.l   %d1,%d0
        move.l  %d0,%a0
        move.l  SOUND0+SOUND_LIVE(%a0),%d0
        beq.s   3f
        move.l  %d0,%a0
        mvzw    OFF_PARAMS(%a0),%d0
        moveq   #0x7f,%d1
        and.l   %d0,%d1                           | CHR
        mulu.w  %d1,%d1
        move.l  #COEF_K,%d4
        mulu.l  %d1,%d4
        or.l    %d4,%d7                           | (the comb target d5 stays 0)
3:      move.l  (%a2),%d0                         | chorus: glide
        sub.l   %d0,%d4
        asr.l   #2,%d4
        add.l   %d4,%d0
        cmp.l   #0x10000,%d0
        bcc.s   4f
        tst.l   %d4
        bgt.s   4f
        clr.l   %d0                               | settled at zero
4:      move.l  %d0,(%a2)+
        move.l  %d0,%d2
        move.l  (%a2),%d0                         | comb: glide
        sub.l   %d0,%d5
        asr.l   #2,%d5
        add.l   %d5,%d0
        cmp.l   #0x10000,%d0
        bcc.s   5f
        tst.l   %d5
        bgt.s   5f
        clr.l   %d0
5:      move.l  %d0,(%a2)+
        move.l  %d0,%d3
        or.l    %d2,%d0
        beq.s   6f
        move.l  %d6,%d0                           | active: rx offset, cC, cM
        lsl.l   #2,%d0
        move.l  %d0,(%a3)+
        move.l  %d2,(%a3)+
        move.l  %d3,(%a3)+
        addq.l  #1,ST_NACT(%a6)
6:      addq.l  #1,%d6
        moveq   #VOICES,%d0
        cmp.l   %d0,%d6
        bne.w   1b
        move.l  %d7,%d0
        rts

        | ------------------------------------------------------------------
        | buses_mix(a5 = rx, a6 = st): the mono chorus send bus, 32 frames.
        | Clobbers d0-d6/a0-a5. (In cave3: cave is full.)
        | ------------------------------------------------------------------
        .section .tab,"awx"
        .align  2
buses_mix:
        movclr.l %acc0,%d0                        | start from a clear accumulator
        move.l  #BUSC,%a0
        moveq   #FRAMES,%d6
        moveq   #1,%d0                            | one sending voice (the usual
        cmp.l   ST_NACT(%a6),%d0                  | case): straight down its frames
        bne.s   1f
        lea     ST_ACT(%a6),%a4
        move.l  (%a4)+,%d3
        move.l  (%a4)+,%d1                        | cC
        add.l   %d3,%a5
4:      move.l  (%a5),%d0
        lea     RX_STRIDE(%a5),%a5
        mac.l   %d1,%d0,%acc0
        movclr.l %acc0,%d3
        move.l  %d3,(%a0)+
        subq.l  #1,%d6
        bne.s   4b
        rts
1:      lea     ST_ACT(%a6),%a4
        move.l  ST_NACT(%a6),%d5
        beq.s   3f
2:      move.l  (%a4)+,%d3                        | rx offset
        move.l  (%a4)+,%d1                        | cC
        addq.l  #4,%a4                            | (the spare)
        move.l  (%a5,%d3.l),%d0                   | the voice's sample
        mac.l   %d1,%d0,%acc0
        subq.l  #1,%d5
        bne.s   2b
3:      movclr.l %acc0,%d0
        move.l  %d0,(%a0)+
        lea     RX_STRIDE(%a5),%a5
        subq.l  #1,%d6
        bne.s   1b
        rts

        .text

        | ------------------------------------------------------------------
        | chorus_run(a6 = st): BUSC (mono) -> OUTB (stereo), wet only.
        |  1. HPF: a one-pole high-pass on the bus, in place: lp += a (x - lp),
        |     x -= lp, a = HPF^2 / 2 (Q15: 127 -> 0.25, about 2 kHz; 0 is off).
        |  2. Per sample: the line takes x + FDB * (the taps' last average),
        |     then two interpolated taps read it, L and R. Each tap's delay is
        |     PRE + DEP * a unipolar triangle; R's triangle runs WID / 127 of half
        |     a cycle behind L's (0: one tap twice, mono). The delays glide sample
        |     by sample from where the last block left them.
        | Clobbers d0-d7/a0-a5.
        | ------------------------------------------------------------------
        .macro  TAP dreg
        move.l  %d7,%d1
        swap    %d1
        clr.w   %d1                               | w << 16
        sub.l   \dreg,%d1                         | read position, 16.16
        move.l  %d1,%d0
        swap    %d0
        and.l   #CMASK,%d0                        | i
        move.l  (%a0,%d0.l*4),%a3                 | s[i]
        addq.l  #1,%d0
        and.l   #CMASK,%d0
        move.l  (%a0,%d0.l*4),%d0                 | s[i+1]
        sub.l   %a3,%d0
        and.l   #0xffff,%d1                       | frac -> Q31
        lsl.l   #8,%d1
        lsl.l   #7,%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        add.l   %a3,%d0
        .endm

        .align  2
chorus_run:
        lea     globals,%a0
        | 1. the high-pass, in place on the bus
        mvzb    G_HPF(%a0),%d0
        beq.s   5f
        mulu.w  %d0,%d0
        lsr.l   #1,%d0
        swap    %d0
        clr.w   %d0                               | a, Q31
        move.l  ST_HLP(%a6),%d2
        move.l  #BUSC,%a1
        moveq   #FRAMES,%d6
4:      move.l  (%a1),%d1                         | x
        sub.l   %d2,%d1
        sats.l  %d1
        mac.l   %d0,%d1,%acc1
        movclr.l %acc1,%d1
        add.l   %d1,%d2                           | lp += a (x - lp)
        move.l  (%a1),%d1
        sub.l   %d2,%d1
        sats.l  %d1
        move.l  %d1,(%a1)+                        | x - lp
        subq.l  #1,%d6
        bne.s   4b
        move.l  %d2,ST_HLP(%a6)
        lea     globals,%a0
        | 2. the taps' delays at the block's end
5:      mvzb    G_SPD(%a0),%d0
        addq.l  #1,%d0
        mulu.w  %d0,%d0
        move.l  #C_RATE_K,%d1
        mulu.l  %d1,%d0
        add.l   ST_CPH(%a6),%d0
        move.l  %d0,ST_CPH(%a6)                   | the phase at the block's end
        mvzb    G_DEP(%a0),%d5
        mulu.w  #C_DEPTH_K*2,%d5                  | depth * 2: tri (Q15) * it is 16.16
        mvzb    G_PRE(%a0),%d3
        move.l  #C_PRE_K,%d1
        mulu.l  %d1,%d3
        add.l   #C_PRE0,%d3                       | the base delay, 16.16
        move.l  %d0,%d2                           | L at phase
        jsr     tri_delay
        move.l  %d2,%d4                           | delay L at the end
        mvzb    G_WID(%a0),%d2                    | R at phase - WID * half a cycle
        move.l  #C_WID_K,%d1
        mulu.l  %d1,%d2
        neg.l   %d2
        add.l   ST_CPH(%a6),%d2
        jsr     tri_delay
        move.l  %d2,%d3                           | delay R at the end
        | steps from where the last block ended
        move.l  ST_DL(%a6),%d0
        move.l  %d4,ST_DL(%a6)
        sub.l   %d0,%d4
        asr.l   #5,%d4                            | step L
        move.l  %d0,%d2                           | delay L now
        move.l  ST_DR(%a6),%d0
        move.l  %d3,ST_DR(%a6)
        sub.l   %d0,%d3
        asr.l   #5,%d3
        move.l  %d3,%a4                           | step R
        move.l  %d0,%d3                           | delay R now
        mvzb    G_FDB(%a0),%d5                    | feedback, Q31
        mulu.w  #FB_SCALE,%d5
        swap    %d5
        clr.w   %d5
        move.l  ST_FB(%a6),%a5                    | the taps' last average
        move.l  #CLINE,%a0
        move.l  #BUSC,%a1
        move.l  #OUTB,%a2
        move.l  ST_CW(%a6),%d7
        moveq   #FRAMES,%d6
1:      move.l  (%a1)+,%d0
        mac.l   %d5,%a5,%acc1
        movclr.l %acc1,%d1
        add.l   %d1,%d0
        sats.l  %d0
        move.l  %d0,(%a0,%d7.l*4)                 | write the newest sample
        add.l   %d4,%d2
        TAP     %d2
        move.l  %d0,(%a2)+                        | L
        move.l  %d0,%a5
        add.l   %a4,%d3
        TAP     %d3
        move.l  %d0,(%a2)+                        | R
        asr.l   #1,%d0                            | the average, for the feedback
        move.l  %a5,%d1
        asr.l   #1,%d1
        add.l   %d1,%d0
        move.l  %d0,%a5
        addq.l  #1,%d7
        and.l   #CMASK,%d7
        subq.l  #1,%d6
        bne.w   1b
        move.l  %d7,ST_CW(%a6)
        move.l  %a5,ST_FB(%a6)
        rts

        .section .tab,"awx"

        | tri_delay(d2 = phase, d3 = base, d5 = depth * 2) -> d2 = base + depth *
        | tri, 16.16, tri the unipolar triangle 0..32767. Clobbers d0/d1.
        .align  2
tri_delay:
        clr.w   %d2
        swap    %d2                               | 0..65535
        move.l  #32768,%d1
        cmp.l   %d1,%d2
        bcs.s   1f
        move.l  #65535,%d0
        sub.l   %d2,%d0
        move.l  %d0,%d2                           | tri, 0..32767
1:      muls.l  %d5,%d2
        add.l   %d3,%d2
        rts

        | ------------------------------------------------------------------
        | Data
        | ------------------------------------------------------------------
        .section .tab,"awx"
        .balign 4
fx_pages:                                         | the AMP view's pages
        .long   PAGE_AMP, PAGE_FX

page_fx:                                          | {name, top row, bottom row}
        .long   str_page
        .long   1, 2, 3, 4
        .long   5, 11, 12, 13

knob_ids:       .short  1, 2, 3, 4, 5, 11, 12, 13
globals:        .byte   40, 24, 64, 96, 0, 0, 100 | PRE SPD DEP WID FDB HPF VOL (defaults)
        .balign 4
st:             .space  ST_SIZE

str_page:       .asciz  "SEND"                    | the page title shows 4 characters
str_group:      .asciz  "FX SENDS"
str_chr_l:      .asciz  "Chorus Send"
str_pre_l:      .asciz  "Chorus Pre-Delay"
str_spd_l:      .asciz  "Chorus Speed"
str_dep_l:      .asciz  "Chorus Depth"
str_wid_l:      .asciz  "Chorus Width"
str_fdb_l:      .asciz  "Chorus Feedback"
str_hpf_l:      .asciz  "Chorus High-Pass"
str_vol_l:      .asciz  "Chorus Level"
str_chr:        .asciz  "CHR"
str_pre:        .asciz  "PRE"
str_spd:        .asciz  "SPD"
str_dep:        .asciz  "DEP"
str_wid:        .asciz  "WID"
str_fdb:        .asciz  "FDB"
str_hpf:        .asciz  "HPF"
str_vol:        .asciz  "VOL"
