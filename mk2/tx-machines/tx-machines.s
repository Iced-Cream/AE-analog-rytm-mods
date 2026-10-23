        | tx-machines - TX machines (AE 0009), the Machinedrum TX-9 kick and snare
        | user machines as machines on the analog voices of the Analog Rytm MKII,
        | OS 1.74. This is phase 2 of the port: BD TX-9 and SD TX-9. The other
        | five (BD TX-9 DIGI, SD TX-8, XT TX-9, XT TX-8, BT TX-8) follow.
        |
        |   slot 36  BD TX-9  BD track  LEV PTC DEC TUN DPT ACC WAV ATK  -> BD CLASSIC
        |   slot 37  SD TX-9  SD track  LEV PTC DEC TON SNP ACC BND DTU  -> SD CLASSIC
        |
        | core-ar2 0.5 puts them in the machine table (core_machines, the entries
        | at the end): the engine, the home track, the voice and the knobs' names,
        | ranges and defaults. The knobs are the slots' own parameter records, so
        | a sound stores them as it stores any machine's.
        |
        | How a machine runs: once per audio block (32 frames at 48 kHz) the
        | interrupt calls engine(voice, frame, blk, pitch) for each physical
        | voice, blk pointing at the track's eight machine words (after LFO, LEV
        | first, value << 8). Neither machine drives the hardware itself. Each
        | block it computes the TX machine's curves, builds a block of its own and
        | runs the stock machine with it, BD CLASSIC for the kick and SD CLASSIC
        | for the snare, so tune calibration, oscillators and envelope segments
        | stay stock code. Pitch sweeps and bends go to the stock TUN every block
        | (12 log2 of the TX frequency ratio, 0x100 per semitone), decays to the
        | stock envelopes (DEC, HLD) through tables matched to the TX machines'
        | decay times, ACC scales LEV. BD TX-9 then adds the TX-9's click and SD
        | TX-9 the TX-9's own noise into the voice's digital stream 1, which BD /
        | SD CLASSIC rewrite every block.
        |
        | The code is the MK1 mod's (mods/0009-tx-machines/stub.s, v10), with the
        | MKII's addresses; the tables are its tables (tables.inc). The MKII's BD
        | CLASSIC and SD CLASSIC were recorded on a unit at the MK1 recordings'
        | settings and match them (README), so the MK1 tuning carries over.
        |
        | The MAC: the code is written for the fractional mode (MACSR 0x20). The
        | MKII's audio interrupt sets 0x20 before it calls any engine (0x4011fbfe),
        | as the MK1's does; each engine here still sets it itself, hands the
        | stock machine the MACSR it was called with, and puts that back on return.
        |
        | Checked in the OS 1.74 code: BD CLASSIC and SD CLASSIC write all 32
        | longs of their voice's stream 1 on every call (a ramp loop before their
        | one exit, 0x40110c20 / 0x40117f3e), so the click and the noise added
        | after them never pile up; both test the voice's state word at
        | 0x8000fef8 + 0x20 v for 0 on the call after a trig, as note_on does.
        |
        | The knobs' controls: the OS builds each record's control (slider, list,
        | stepped picture) at boot from the record's id, not from its range. All
        | of SD TX-9's (ids 350..357) and BD TX-9's 342..348 are plain sliders,
        | or WAV's list, but BD TX-9's ATK is id 349, BD CLASSIC 2's stepped
        | Transient picture, and both PTC knobs (ids 342 and 356, the hidden
        | machines' Tune) print their value centred, -64..63. tx_machines_tick
        | fixes them once, from a plain knob of the same machine, the way duck
        | and fx-sends fix their knobs and as MK1 v5 / v7 did for the same ids.

        .equ    STOCK_BD_CLASSIC, 0x401105c8
        .equ    STOCK_SD_CLASSIC, 0x401179bc
        .equ    VOICE_STATE,    0x8000fef8        | per physical voice, 0x20 each
        .equ    VOICE_BUF_A,    0x80006bf8        | stream 1, 0x80 (one block) each
        .equ    MACSR_FRAC,     0x20

        .equ    TUN_BASE, 0x3a00                  | BD/SD CLASSIC's default tune
        .equ    TUN_MAX,  0x7f00

        | stack frame of every machine: 40 B of saved registers, the 16 B
        | block handed to the stock machine, the caller's MACSR
        .equ    F_BLOCK, 40
        .equ    F_MACSR, 56
        .equ    F_SIZE,  60
        .equ    A_VOICE, F_SIZE + 4
        .equ    A_CTX,   F_SIZE + 8
        .equ    A_PARAMS, F_SIZE + 12
        .equ    A_NOTE,  F_SIZE + 16

        | p = parameter word >> 8, clamped to 0..127
        .macro  PARAM off, reg
        moveq   #0,\reg
        move.w  \off(%a2),\reg
        lsr.l   #8,\reg
        cmp.l   #127,\reg
        bls.s   .Lp\@
        moveq   #127,\reg
.Lp\@:
        .endm

        | prologue: d6 = voice, a2 = params, a3 = state + 8 * voice, MACSR 0x20
        .macro  ENTER state
        lea     -F_SIZE(%sp),%sp
        movem.l %d2-%d7/%a2-%a5,(%sp)
        move.l  %macsr,%d0
        move.l  %d0,F_MACSR(%sp)
        move.l  #MACSR_FRAC,%macsr
        move.l  A_VOICE(%sp),%d6
        move.l  A_PARAMS(%sp),%a2
        lea     \state,%a3
        move.l  %d6,%d0
        lsl.l   #3,%d0
        add.l   %d0,%a3
        .endm

        | run the stock machine on the block, in the caller's MACSR
        .macro  CALLSTOCK stock
        move.l  F_MACSR(%sp),%d0
        move.l  %d0,%macsr
        move.l  A_NOTE(%sp),-(%sp)
        pea     F_BLOCK+4(%sp)
        move.l  A_CTX+8(%sp),-(%sp)
        move.l  A_VOICE+12(%sp),-(%sp)
        jsr     \stock
        lea     16(%sp),%sp
        move.l  #MACSR_FRAC,%macsr
        .endm

        | return to the interrupt
        .macro  EXIT
        move.l  F_MACSR(%sp),%d0
        move.l  %d0,%macsr
        movem.l (%sp),%d2-%d7/%a2-%a5
        lea     F_SIZE(%sp),%sp
        rts
        .endm

        | d0 = 33-entry word table \tab at p = \preg
        .macro  LOOKUP tab, preg
        lea     \tab,%a0
        move.l  \preg,%d0
        jsr     interpw
        .endm

        | block word \slot = LEV * scale(\tab at ACC p \preg) >> 15
        .macro  SCALED_LEV tab, preg
        LOOKUP  \tab,\preg
        moveq   #0,%d1
        move.w  0(%a2),%d1
        mulu.l  %d0,%d1
        moveq   #15,%d0
        lsr.l   %d0,%d1
        move.w  %d1,F_BLOCK+0(%sp)
        .endm

        .text

        | ==================================================== shared helpers

        | d0 = 33-entry word table (a0) at p = d0, linear over p & 3, as the TX
        | plugins interpolate their own tables. Clobbers d1, d7, a0.
        .align  2
interpw:
        move.l  %d0,%d1
        lsr.l   #2,%d0
        moveq   #3,%d7
        and.l   %d7,%d1
        add.l   %d0,%d0
        add.l   %d0,%a0
        move.w  (%a0),%d0
        ext.l   %d0
        move.w  2(%a0),%d7
        ext.l   %d7
        sub.l   %d0,%d7
        muls.l  %d1,%d7
        asr.l   #2,%d7
        add.l   %d7,%d0
        rts

        | The same for a 33-entry long table (Q31). Clobbers d1, d7, a0.
        .align  2
interpl:
        move.l  %d0,%d1
        lsr.l   #2,%d0
        moveq   #3,%d7
        and.l   %d7,%d1
        lsl.l   #2,%d0
        add.l   %d0,%a0
        move.l  (%a0),%d0
        move.l  4(%a0),%d7
        sub.l   %d0,%d7
        asr.l   #2,%d7
        muls.l  %d1,%d7
        add.l   %d7,%d0
        rts

        | d0 = 3072 * log2(1 + K * e): the tune offset (0x100 per semitone) of a
        | frequency ratio 1 + K * e. In: d0 = K (Q12, < 40000), d1 = e (Q31, >= 0).
        | Clobbers d1, d7, a0, a1.
        .align  2
sweep_st:
        clr.w   %d1
        swap    %d1                               | e, Q15
        mulu.l  %d1,%d0
        moveq   #15,%d1
        lsr.l   %d1,%d0                           | K * e, Q12
        add.l   #4096,%d0                         | u = 1 + K * e
        suba.l  %a1,%a1
1:      cmp.l   #8192,%d0                         | whole octaves
        blt.s   2f
        lsr.l   #1,%d0
        adda.l  #3072,%a1
        bra.s   1b
2:      sub.l   #4096,%d0                         | mantissa 0..4095
        move.l  %d0,%d1
        lsr.l   #6,%d0
        moveq   #63,%d7
        and.l   %d7,%d1
        lea     tx_lt,%a0
        add.l   %d0,%d0
        add.l   %d0,%a0
        move.w  (%a0),%d0
        ext.l   %d0
        move.w  2(%a0),%d7
        ext.l   %d7
        sub.l   %d0,%d7
        muls.l  %d1,%d7
        asr.l   #6,%d7
        add.l   %d7,%d0
        add.l   %a1,%d0
        rts

        | Z set if a note started on voice d6 this block: its state word is 0 (the
        | interrupt clears it on the trig; the stock machine advances it on the
        | call that follows). Clobbers d0, a0.
        .align  2
note_on:
        move.l  %d6,%d0
        lsl.l   #5,%d0
        lea     VOICE_STATE,%a0
        tst.l   (%a0,%d0.l)
        rts

        | d4 = clamp(d4, 0, TUN_MAX)
        .align  2
clamp_tun:
        tst.l   %d4
        bge.s   1f
        moveq   #0,%d4
1:      cmp.l   #TUN_MAX,%d4
        ble.s   2f
        move.l  #TUN_MAX,%d4
2:      rts

        | d4 = TUN_BASE + 48 * (PTC - 64): the TX-9 BD pitch, exponential over 2
        | octaves around the stock default. From the PTC word.
        .align  2
ptc_2oct:
        moveq   #0,%d4
        move.w  2(%a2),%d4
        sub.l   #0x4000,%d4
        move.l  %d4,%d0
        add.l   %d4,%d4
        add.l   %d0,%d4
        asr.l   #4,%d4
        add.l   #TUN_BASE,%d4
        rts

        | ==================================================== BD TX-9 (slot 36)
        | params: LEV 0, PTC 2, DEC 4, TUN 6 (sweep time), DPT 8, ACC 10, WAV 12, ATK 14
        | BD CLASSIC: LEV TUN DEC HLD SWT SWD WAV TRA
        | state:  e (pitch envelope, Q31), attack sample position
        .align  2
tx9bd_machine:
        ENTER   t9bd_state
        PARAM   6,%d2                             | TUN
        PARAM   10,%d3                            | ACC
        jsr     note_on
        bne.s   1f
        lea     t9bd_e0,%a0
        move.l  %d2,%d0
        jsr     interpl
        move.l  %d0,(%a3)
        clr.l   4(%a3)
1:      jsr     ptc_2oct
        add.l   #TX9BD_TUNOFF,%d4                 | PTC 64 = the TX-9's 56 Hz
        PARAM   8,%d0                             | DPT -> K
        move.l  #TX9_KSTEP,%d1
        mulu.l  %d1,%d0
        lsr.l   #8,%d0
        move.l  (%a3),%d1
        jsr     sweep_st
        add.l   %d0,%d4
        jsr     clamp_tun
        lea     t9bd_cb,%a0                       | e *= cb(TUN)
        move.l  %d2,%d0
        jsr     interpl
        move.l  (%a3),%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        move.l  %d0,(%a3)

        SCALED_LEV t9bd_acc,%d3
        move.w  %d4,F_BLOCK+2(%sp)                | TUN
        PARAM   4,%d5
        LOOKUP  t9bd_dec,%d5
        lsl.l   #8,%d0
        move.w  %d0,F_BLOCK+4(%sp)                | DEC (stock envelope)
        LOOKUP  t9bd_hld,%d3
        lsl.l   #8,%d0
        move.w  %d0,F_BLOCK+6(%sp)                | HLD = the TX-9 hold
        clr.l   F_BLOCK+8(%sp)                    | SWT, SWD: stock sweep off
        move.w  12(%a2),F_BLOCK+12(%sp)           | WAV
        clr.w   F_BLOCK+14(%sp)                   | TRA off: the attack is the TX-9's
        CALLSTOCK STOCK_BD_CLASSIC
        jsr     t9_attack
        EXIT

        | ==================================================== BD TX-9 click
        | The TX-9 click (tables.inc, from the plugin via the MK1 repo's
        | tools/tx_measure/atk_extract.py), added into the voice's stream 1 after
        | BD CLASSIC, whose own transient is off. d6 = voice, a2 = params, a3 =
        | state (+4: sample position, cleared on a note). Clobbers d0-d5, d7, a0,
        | a1, a4, a5. stream 1 += (s << 8) * G, G = K * g(ATK) * g(ACC) * LEV,
        | <= 65535.
        .align  2
t9_attack:
        PARAM   14,%d3                            | ATK
        PARAM   10,%d4                            | ACC
        lea     a9_atk,%a4
        lea     a9_acc,%a5
        move.l  #A9_K,%d5
        move.l  #A9_N,%d2
        lea     a9_wave,%a1
        move.l  4(%a3),%d1
        cmp.l   %d2,%d1
        bge.s   9f
        movea.l %a4,%a0
        move.l  %d3,%d0
        jsr     interpw
        mulu.l  %d0,%d5
        moveq   #15,%d1
        lsr.l   %d1,%d5
        movea.l %a5,%a0
        move.l  %d4,%d0
        jsr     interpw
        mulu.l  %d0,%d5
        moveq   #15,%d1
        lsr.l   %d1,%d5
        moveq   #0,%d0
        move.w  0(%a2),%d0                        | LEV
        mulu.l  %d0,%d5
        moveq   #15,%d1
        lsr.l   %d1,%d5
        cmp.l   #65535,%d5
        bls.s   1f
        move.l  #65535,%d5
1:      move.l  %d6,%d0
        lsl.l   #7,%d0
        add.l   #VOICE_BUF_A,%d0
        movea.l %d0,%a0
        move.l  4(%a3),%d3
        moveq   #32,%d4
2:      cmp.l   %d2,%d3
        bge.s   3f
        move.b  (%a1,%d3.l),%d0
        extb.l  %d0
        lsl.l   #8,%d0
        muls.l  %d5,%d0
        add.l   %d0,(%a0)+
        addq.l  #1,%d3
        subq.l  #1,%d4
        bne.s   2b
3:      move.l  %d3,4(%a3)
9:      rts

        | ==================================================== SD TX-9 (slot 37)
        | params: LEV 0, PTC 2, DEC 4, TON 6, SNP 8, ACC 10, BND 12, DTU 14
        | SD CLASSIC: LEV TUN DEC DET SNP(transient) NOD NOL BAL
        | state:  e (bend envelope, Q31)
        .align  2
tx9sd_machine:
        ENTER   t9sd_state
        PARAM   2,%d2                             | PTC
        jsr     note_on
        bne.s   1f
        LOOKUP  t9sd_be0,%d2
        swap    %d0
        clr.w   %d0                               | Q15 -> Q31
        move.l  %d0,(%a3)
        moveq   #1,%d0
        move.l  %d0,n9_state+N9S_TRIG             | arm the noise envelope
1:      LOOKUP  t9sd_ptc,%d2
        move.l  %d0,%d4
        add.l   #TUN_BASE,%d4
        LOOKUP  t9sd_bk,%d2                       | K = bk(PTC) * BND / 128
        PARAM   12,%d1
        mulu.l  %d1,%d0
        lsr.l   #7,%d0
        move.l  (%a3),%d1
        jsr     sweep_st
        add.l   %d0,%d4
        jsr     clamp_tun
        move.l  (%a3),%d1                         | e *= the bend decay
        move.l  #T9SD_BEND_DECAY,%d0
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        move.l  %d0,(%a3)

        PARAM   10,%d3
        SCALED_LEV t9sd_acc,%d3
        move.w  %d4,F_BLOCK+2(%sp)                | TUN
        PARAM   4,%d5
        LOOKUP  t9sd_dec,%d5
        lsl.l   #8,%d0
        move.w  %d0,F_BLOCK+4(%sp)                | DEC (body)
        PARAM   14,%d5
        LOOKUP  t9sd_det,%d5
        move.w  %d0,F_BLOCK+6(%sp)                | DET
        clr.l   F_BLOCK+8(%sp)                    | SNP 0, NOD 0: no stock snap
        clr.w   F_BLOCK+12(%sp)                   | NOL 0: no stock noise
        move.w  #0x2000,%d0
        move.w  %d0,F_BLOCK+14(%sp)               | BAL: SD CLASSIC's default
        CALLSTOCK STOCK_SD_CLASSIC
        jsr     tx9_noise                         | the TX-9's own noise, digital
        EXIT

        | ==================================================== TX-9 SD noise
        | The TX-9 SNARE DRUM's noise, ported exactly (tables.inc, the MK1 repo's
        | gen_tx_tables.py noise9): white noise through its 3rd-order filter
        | (re-warped to 48 kHz), times its envelope - a state E stepped every 16
        | TX samples (N9_PHASE per block), an attack C refilling to a ceiling D,
        | then a decay toward a floor F at the TONE rate - read through its
        | amplitude curve, times SNAP and LEV. Added into the voice's stream 1,
        | which enters the analog voice before its filter, as SD CLASSIC's own
        | noise would. Called by SD TX-9 after SD CLASSIC (whose noise is off):
        | d6 = voice, a2 = params. One state: the machine runs on voice 2 only.
        | Clobbers d0-d7, a0-a5.
        .equ    N9S_E,    0
        .equ    N9S_C,    4
        .equ    N9S_CNT,  8
        .equ    N9S_PH,   12
        .equ    N9S_X1,   16                      | x1 x2 y1 y2 y3: filter state
        .equ    N9S_SEED, 36
        .equ    N9S_AMP,  40
        .equ    N9S_TRIG, 44

        .align  2
tx9_noise:
        move.l  %a6,-(%sp)
        lea     -16(%sp),%sp                      | 0 count, 4 amp step, 8 LCG mult, 12 out
        move.l  #1664525,%d0
        move.l  %d0,8(%sp)
        move.l  %d6,%d0                           | out = stream 1 of the voice
        lsl.l   #7,%d0
        add.l   #VOICE_BUF_A,%d0
        move.l  %d0,12(%sp)
        lea     n9_state,%a4
        PARAM   10,%d3                            | ACC
        tst.l   N9S_TRIG(%a4)
        beq.s   1f
        clr.l   N9S_TRIG(%a4)                     | a note: reload the attack
        move.l  %d3,%d0
        move.l  #N9_C1,%d1
        muls.l  %d1,%d0
        add.l   #N9_C0,%d0
        move.l  %d0,N9S_C(%a4)
        clr.l   N9S_CNT(%a4)
        clr.l   N9S_PH(%a4)
1:      move.l  %d3,%d4                           | d4 = D
        move.l  #N9_D1,%d1
        muls.l  %d1,%d4
        add.l   #N9_D0,%d4
        move.l  %d3,%d5                           | d5 = F
        move.l  #N9_F1,%d1
        muls.l  %d1,%d5
        add.l   #N9_F0,%d5
        PARAM   6,%d0                             | d2 = T (TONE)
        lea     n9_t2ad,%a0
        jsr     interpl
        move.l  %d0,%d2
        move.l  N9S_PH(%a4),%d3                   | steps this block
        add.l   #N9_PHASE,%d3
        move.l  %d3,%d0
        and.l   #0xffff,%d0
        move.l  %d0,N9S_PH(%a4)
        clr.w   %d3
        swap    %d3
        move.l  N9S_E(%a4),%d6
        bra.s   5f
2:      move.l  %d6,%d0                           | E' = E - (E - F) T - max(0, E - TH) K2
        sub.l   %d5,%d0
        mac.l   %d0,%d2,%acc0
        move.l  %d6,%d0
        sub.l   #N9_TH,%d0
        bpl.s   3f
        moveq   #0,%d0
3:      move.l  #N9_K2,%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        sub.l   %d0,%d6
        cmp.l   #N9_EMIN,%d6
        bge.s   4f
        move.l  #N9_EMIN,%d6
4:      move.l  %d4,%d1                           | E = min(E' + C, max(D, E'))
        cmp.l   %d6,%d1
        bge.s   41f
        move.l  %d6,%d1
41:     move.l  N9S_C(%a4),%d0
        add.l   %d6,%d0
        cmp.l   %d1,%d0
        ble.s   42f
        move.l  %d1,%d0
42:     move.l  %d0,%d6
        move.l  N9S_CNT(%a4),%d0                  | C decays after N9_HOLD steps
        addq.l  #1,N9S_CNT(%a4)
        cmp.l   #N9_HOLD,%d0
        blt.s   5f
        move.l  N9S_C(%a4),%d0
        move.l  #N9_CDEC,%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        move.l  %d0,N9S_C(%a4)
5:      subq.l  #1,%d3
        bpl.s   2b
        move.l  %d6,N9S_E(%a4)

        move.l  %d6,%d0                           | amp = curve(E) * SNAP * LEV
        bpl.s   6f
        moveq   #0,%d0
6:      move.l  %d0,%d1
        moveq   #26,%d7
        lsr.l   %d7,%d0                           | segment 0..31
        moveq   #18,%d7
        lsr.l   %d7,%d1
        and.l   #0xff,%d1                         | 8-bit fraction
        lea     n9_t310,%a0
        lsl.l   #2,%d0
        add.l   %d0,%a0
        move.l  (%a0),%d0
        move.l  4(%a0),%d7
        sub.l   %d0,%d7
        asr.l   #8,%d7
        muls.l  %d1,%d7
        add.l   %d7,%d0
        PARAM   8,%d1                             | SNAP
        move.l  #N9_SNAPK,%d7
        muls.l  %d7,%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        moveq   #0,%d1
        move.w  0(%a2),%d1                        | LEV word, Q15
        swap    %d1                               | -> Q31
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0                        | amp for the end of this block
        move.l  N9S_AMP(%a4),%d7                  | ramp from the last block's
        move.l  %d0,N9S_AMP(%a4)
        move.l  %d0,%d1                           | both below -114 dB: nothing to
        or.l    %d7,%d1                           | add, skip the filter
        cmp.l   #0x1000,%d1
        bcs.w   99f
        sub.l   %d7,%d0
        asr.l   #5,%d0
        move.l  %d0,4(%sp)

        movem.l N9S_X1(%a4),%d1-%d5
        move.l  N9S_SEED(%a4),%d6
        lea     n9_coef,%a6
        movem.l (%a6),%a0-%a5
        movea.l 12(%sp),%a6
        moveq   #32,%d0
        move.l  %d0,(%sp)
7:      move.l  8(%sp),%d0                        | seed = seed * 1664525 + 1013904223
        mulu.l  %d0,%d6
        add.l   #1013904223,%d6
        move.l  %d6,%d0
        asr.l   #1,%d0                            | x, half scale
        mac.l   %a0,%d0,%acc0
        mac.l   %a1,%d1,%acc0
        mac.l   %a2,%d2,%acc0
        mac.l   %a3,%d3,%acc0
        mac.l   %a4,%d4,%acc0
        mac.l   %a5,%d5,%acc0
        move.l  %d1,%d2
        move.l  %d0,%d1
        movclr.l %acc0,%d0
        add.l   %d0,%d0                           | y = 2 * sum
        move.l  %d4,%d5
        move.l  %d3,%d4
        move.l  %d0,%d3
        mac.l   %d0,%d7,%acc1                     | y * amp
        movclr.l %acc1,%d0
        add.l   %d0,%d0                           | back to the TX's full-scale input
        add.l   %d0,(%a6)+
        add.l   4(%sp),%d7
        subq.l  #1,(%sp)
        bne.s   7b
        lea     n9_state,%a4
        movem.l %d1-%d5,N9S_X1(%a4)
        move.l  %d6,N9S_SEED(%a4)
99:     lea     16(%sp),%sp
        move.l  (%sp)+,%a6
        rts

        | ev_tick, until done once (the records are built at boot, before the
        | first tick): each knob below takes a plain knob's parts from a donor
        | of its machine, 16 B each from its OS record (0x419a4888 + 0x54 id):
        |   +0x04 the descriptor, +0x24 the draw, +0x44 the last prototype:
        |         ATK (349) from HLD (344): a 0..127 slider, not TRA's picture
        |   +0x14 the value text, +0x24 the draw:
        |         BD TX-9 PTC (342) from HLD (344), SD TX-9 PTC (356) from DEC
        |         (351): 0..127, not centred, and no centre mark on the dial
        .equ    PARAM_INFO,     0x419a4888        | RAM records, 0x54 bytes an id
        .equ    PI_STRIDE,      0x54

        .macro  PI_COPY dst, src, offs:vararg
        lea     PARAM_INFO+\src*PI_STRIDE,%a0
        lea     PARAM_INFO+\dst*PI_STRIDE,%a1
        .irp    off, \offs
        move.l  \off(%a0),\off(%a1)
        move.l  \off+4(%a0),\off+4(%a1)
        move.l  \off+8(%a0),\off+8(%a1)
        move.l  \off+12(%a0),\off+12(%a1)
        .endr
        .endm

        .globl  tx_machines_tick
        .align  2
tx_machines_tick:
        lea     tx_ready,%a0
        tst.b   (%a0)
        bne.w   9f
        moveq   #1,%d0
        move.b  %d0,(%a0)
        PI_COPY 349, 344, 0x04, 0x24, 0x44
        PI_COPY 342, 344, 0x14, 0x24
        PI_COPY 356, 351, 0x14, 0x24
9:      rts

        .include "tables.inc"

        | ==================================================== the machine table
        | struct core_machine (analog-rytm-mk2/machines.h): slot, engine, home,
        | voices, pad, name, label, then eight knobs {name, label, min, max,
        | default, centred}: LEV, then A..H.
        .macro  KNOB name, label, min, max, def, centred
        .long   \name, \label
        .byte   \min, \max, \def, \centred
        .endm

        .align  4
        .globl  tx_machines_bd9
tx_machines_bd9:
        .long   36, tx9bd_machine
        .byte   0, 0x01                           | BD track, BD voice
        .short  0
        .long   str_bdt9, str_bdt9s
        KNOB    str_level, str_lev, 0, 127, 100, 0
        KNOB    str_pitch, str_ptc, 0, 127, 64, 0
        KNOB    str_decay, str_dec, 0, 127, 64, 0
        KNOB    str_swt, str_tun, 0, 127, 64, 0
        KNOB    str_swd, str_dpt, 0, 127, 64, 0
        KNOB    str_accent, str_acc, 0, 127, 96, 0
        KNOB    str_wave, str_wav, 0, 2, 0, 0
        KNOB    str_attack, str_atk, 0, 127, 64, 0

        .align  4
        .globl  tx_machines_sd9
tx_machines_sd9:
        .long   37, tx9sd_machine
        .byte   1, 0x04                           | SD track, SD voice
        .short  0
        .long   str_sdt9, str_sdt9s
        KNOB    str_level, str_lev, 0, 127, 100, 0
        KNOB    str_pitch, str_ptc, 0, 127, 64, 0
        KNOB    str_decay, str_dec, 0, 127, 64, 0
        KNOB    str_tone, str_ton, 0, 127, 64, 0
        KNOB    str_snappy, str_snp, 0, 127, 64, 0
        KNOB    str_accent, str_acc, 0, 127, 96, 0
        KNOB    str_bend, str_bnd, 0, 127, 64, 0
        KNOB    str_detune, str_dtu, 0, 127, 64, 0

str_bdt9:       .asciz  "BD TX-9"
str_bdt9s:      .asciz  "BDT9"
str_sdt9:       .asciz  "SD TX-9"
str_sdt9s:      .asciz  "SDT9"
str_level:      .asciz  "Level"
str_lev:        .asciz  "LEV"
str_pitch:      .asciz  "Pitch"
str_ptc:        .asciz  "PTC"
str_decay:      .asciz  "Decay"
str_dec:        .asciz  "DEC"
str_swt:        .asciz  "Sweep Time"
str_tun:        .asciz  "TUN"
str_swd:        .asciz  "Sweep Depth"
str_dpt:        .asciz  "DPT"
str_accent:     .asciz  "Accent"
str_acc:        .asciz  "ACC"
str_wave:       .asciz  "Waveform"
str_wav:        .asciz  "WAV"
str_attack:     .asciz  "Attack"
str_atk:        .asciz  "ATK"
str_tone:       .asciz  "Tone"
str_ton:        .asciz  "TON"
str_snappy:     .asciz  "Snappy"
str_snp:        .asciz  "SNP"
str_bend:       .asciz  "Bend"
str_bnd:        .asciz  "BND"
str_detune:     .asciz  "Detune"
str_dtu:        .asciz  "DTU"

        | ==================================================== state
        .data
        .align  4
n9_state:       .long   0, 0, 0, 0, 0, 0, 0, 0, 0, 0x35a7c100, 0, 0   | E C cnt ph x1 x2 y1 y2 y3 seed amp trig

        .bss
        .align  4
tx_ready:       .space  4
t9bd_state:     .space  8 * 8
t9sd_state:     .space  8 * 8
