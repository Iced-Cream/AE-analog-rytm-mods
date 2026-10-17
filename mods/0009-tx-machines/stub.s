        | Mod 0009 - TX machines: the Machinedrum TX-8 / TX-9 kick and snare user
        | machines (MACHINEDRUM_USR) as Rytm machines on the analog voices, plus the
        | hidden BD TEST machine made selectable as a probe of the raw analog core.
        |
        | How a machine runs (re/analog-voice.md): once per audio block (32 samples
        | at 48 kHz) the interrupt calls machine_fn[type](voice, ctx, params, note)
        | for each physical voice, `params` pointing at the eight machine parameters
        | after LFO, `ctx` at the analog control frame.
        |
        | None of these machines drives the hardware itself. Each block it computes
        | the TX machine's curves, builds a parameter set and runs a stock machine
        | with it - BD CLASSIC for the kicks, SD CLASSIC for the snares - so tune
        | calibration, oscillator setup, envelope segments, transients and the
        | digital noise all stay stock code:
        |
        |   slot 36  BD TX-9  -> BD CLASSIC  LEV PTC DEC TUN DPT ACC WAV TRA  (cave4)
        |   slot 35  BD TX-8  -> BD CLASSIC  LEV PTC DEC SIG ACC HLD WAV TRA  (.m35)
        |   slot 37  SD TX-9  -> SD CLASSIC  LEV PTC DEC TON SNP ACC BND DTU  (.m37)
        |   slot 38  SD TX-8  -> SD CLASSIC  LEV PTC DEC TON SNP ACC DET TRA  (.m38)
        |   slot 39  XT TX-9  -> XT CLASSIC  LEV PTC DEC TYP ACC BND NOI TON  (.m39)
        |   slot 40  XT TX-8  -> XT CLASSIC  LEV PTC DEC TYP TUN ACC DIO NOI  (.m40)
        |   slot 42  BT TX-8  -> BT CLASSIC  LEV PTC DEC SIG ACC HLD NOI ATK  (.m42)
        |
        | Pitch sweeps and bends are applied to the stock TUN parameter every block
        | (12 * log2 of the TX frequency ratio, 0x100 per semitone). Decays go to
        | the stock machines' own envelopes (DEC, HLD, NOD) through tables matched to
        | the TX machines' measured decay times. ACC scales LEV. Tables: tables.inc,
        | from tools/gen_tx_tables.py.
        |
        | Each machine's code sits in the stock routine its slot used to point at
        | (BD HARD 2, SD HARD 2, SD CLASSIC 2 - dead on MK1); BD TX-9 and the shared
        | helpers in cave4 (the SD/RS/CY/CB TEST routines).

        .include "symbols.inc"

        .equ    TUN_BASE, 0x3a00                  | BD/SD CLASSIC's default tune
        .equ    TUN_MAX,  0x7f00

        | stack frame of every machine: 40 B of saved registers, then the 16 B
        | parameter block handed to the stock machine
        .equ    F_BLOCK, 40
        .equ    F_SIZE,  56
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

        | prologue: d6 = voice, a2 = params, a3 = state + 8 * voice
        .macro  ENTER state
        lea     -F_SIZE(%sp),%sp
        movem.l %d2-%d7/%a2-%a5,(%sp)
        move.l  A_VOICE(%sp),%d6
        move.l  A_PARAMS(%sp),%a2
        lea     \state,%a3
        move.l  %d6,%d0
        lsl.l   #3,%d0
        add.l   %d0,%a3
        .endm

        | run the stock machine on the block
        .macro  CALLSTOCK stock
        move.l  A_NOTE(%sp),-(%sp)
        pea     F_BLOCK+4(%sp)
        move.l  A_CTX+8(%sp),-(%sp)
        move.l  A_VOICE+12(%sp),-(%sp)
        jsr     \stock
        lea     16(%sp),%sp
        .endm

        | return to the interrupt
        .macro  EXIT
        movem.l (%sp),%d2-%d7/%a2-%a5
        lea     F_SIZE(%sp),%sp
        rts
        .endm

        | run the stock machine on the block, then return to the interrupt
        .macro  LEAVE stock
        CALLSTOCK \stock
        EXIT
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
        lea     MACHINE_VOICE_STATE,%a0
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

        | d4 = TUN_BASE + 48 * (PTC - 64): the TX-8 BD / TX-9 BD / TX-8 SD pitch,
        | exponential over 2 octaves around the stock default. From the PTC word.
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
        CALLSTOCK bd_classic_machine
        jsr     t9_attack
        EXIT

        | ==================================================== TX-9 SD noise
        | The TX-9 SNARE DRUM's noise, ported exactly (tables.inc, gen_tx_tables.py
        | noise9): white noise through its 3rd-order filter (re-warped to 48 kHz),
        | times its envelope - a state E stepped every 16 TX samples (N9_PHASE per
        | block), an attack C refilling to a ceiling D, then a decay toward a floor
        | F at the TONE rate - read through its amplitude curve, times SNAP and LEV.
        | Added into the voice's digital input (voice_out buffer A, 0x80006c70 +
        | 128 * voice), which enters the analog voice before its filter, as SD
        | CLASSIC's own noise would. Called by SD TX-9 after SD CLASSIC (whose
        | noise is off): d6 = voice, a2 = params. Clobbers d0-d7, a0-a5.
        .equ    N9S_E,    0
        .equ    N9S_C,    4
        .equ    N9S_CNT,  8
        .equ    N9S_PH,   12
        .equ    N9S_X1,   16                      | x1 x2 y1 y2 y3: filter state
        .equ    N9S_SEED, 36
        .equ    N9S_AMP,  40
        .equ    N9S_TRIG, 44
        .equ    VOICE_BUF_A, 0x80006c70

        .align  2
tx9_noise:
        move.l  %a6,-(%sp)
        lea     -16(%sp),%sp                      | 0 count, 4 amp step, 8 LCG mult, 12 out
        move.l  #1664525,%d0
        move.l  %d0,8(%sp)
        move.l  %d6,%d0                           | out = buffer A of the voice
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

        .include "mods/0009-tx-machines/tables.inc"

        | ==================================================== BD TX-8 (slot 35): dropped
        | BT TX-8 (slot 42) replaced it; machine_fn[35] points at DISABLE. Its tables
        | (t8bd_*, a8_*) stay in tables.inc: BT TX-8 and BD TX-9 DIGI use them.

        | ==================================================== SD TX-9 (slot 37)
        | params: LEV 0, PTC 2, DEC 4, TON 6, SNP 8, ACC 10, BND 12, DTU 14
        | SD CLASSIC: LEV TUN DEC DET SNP(transient) NOD NOL BAL
        | state:  e (bend envelope, Q31)
        .section .m37,"ax"
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
        CALLSTOCK sd_classic_machine
        jsr     tx9_noise                         | the TX-9's own noise, digital
        EXIT

        .align  4
t9sd_state:     .space  8 * 8
n9_state:       .long   0, 0, 0, 0, 0, 0, 0, 0, 0, 0x35a7c100, 0, 0   | E C cnt ph x1 x2 y1 y2 y3 seed amp trig

        | ==================================================== SD TX-8 (slot 38)
        | params: LEV 0, PTC 2, DEC 4, TON 6, SNP 8, ACC 10, DET 12, TRA 14
        .section .m38,"ax"
        .align  2
tx8sd_machine:
        ENTER   t8sd_state
        jsr     ptc_2oct
        add.l   #TX8SD_TUNOFF,%d4                 | PTC 64 = the TX-8's 250 Hz
        jsr     clamp_tun
        PARAM   10,%d3
        SCALED_LEV t8sd_acc,%d3
        move.w  %d4,F_BLOCK+2(%sp)                | TUN
        PARAM   2,%d5
        LOOKUP  t8sd_body,%d5
        lsl.l   #8,%d0
        move.w  %d0,F_BLOCK+4(%sp)                | DEC: body decay from the pitch
        move.w  12(%a2),F_BLOCK+6(%sp)            | DET
        move.w  14(%a2),F_BLOCK+8(%sp)            | SNP <- TRA
        clr.l   F_BLOCK+10(%sp)                   | NOD 0, NOL 0: no stock noise
        move.w  6(%a2),F_BLOCK+14(%sp)            | BAL <- TON
        jsr     note_on
        bne.s   1f
        moveq   #1,%d0
        move.l  %d0,n8_state+N8S_TRIG
1:      CALLSTOCK sd_classic_machine
        jsr     tx8_noise                         | the TX-8's noise, matched, digital
        EXIT

        | ---------------------------------------------------- TX-8 SD noise
        | Matched to the TX-8 SNARE's noise (gen_tx_tables.py noise8): white noise
        | through a 2-pole high-pass and a 1-pole low-pass fitted to its spectrum,
        | an instant attack and an exponential decay per block from DEC (its
        | measured decay times), times SNAP, ACC and LEV. Added into buffer A like
        | the TX-9 noise. d6 = voice, a2 = params. Clobbers d0-d7, a0-a5.
        .equ    N8S_ENV,  0
        .equ    N8S_X1,   4                       | x1 x2 y1 y2 y3
        .equ    N8S_SEED, 24
        .equ    N8S_AMP,  28
        .equ    N8S_TRIG, 32
        .align  2
tx8_noise:
        move.l  %a6,-(%sp)
        lea     -16(%sp),%sp                      | 0 count, 4 amp step, 8 LCG mult, 12 out
        move.l  #1664525,%d0
        move.l  %d0,8(%sp)
        move.l  %d6,%d0
        lsl.l   #7,%d0
        add.l   #VOICE_BUF_A,%d0
        move.l  %d0,12(%sp)
        lea     n8_state,%a4
        tst.l   N8S_TRIG(%a4)
        beq.s   1f
        clr.l   N8S_TRIG(%a4)
        move.l  #0x7fffffff,%d0
        move.l  %d0,N8S_ENV(%a4)
1:      PARAM   8,%d0                             | level = snap(SNP) * acc(ACC), Q15 * Q15
        lea     n8_snap,%a0
        jsr     interpw
        move.l  %d0,%d5
        PARAM   10,%d0
        lea     n8_acc,%a0
        jsr     interpw
        muls.l  %d0,%d5
        add.l   %d5,%d5                           | Q31
        moveq   #0,%d1
        move.w  0(%a2),%d1                        | * LEV
        swap    %d1
        mac.l   %d5,%d1,%acc0
        movclr.l %acc0,%d5
        move.l  N8S_ENV(%a4),%d1                  | * envelope
        mac.l   %d5,%d1,%acc0
        movclr.l %acc0,%d5
        PARAM   4,%d0                             | envelope *= decay(DEC)
        lea     n8_dec,%a0
        jsr     interpl
        move.l  N8S_ENV(%a4),%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        move.l  %d0,N8S_ENV(%a4)
        move.l  N8S_AMP(%a4),%d7                  | ramp from the last block's amplitude
        move.l  %d5,N8S_AMP(%a4)
        sub.l   %d7,%d5
        asr.l   #5,%d5
        move.l  %d5,4(%sp)
        movem.l N8S_X1(%a4),%d1-%d5
        move.l  N8S_SEED(%a4),%d6
        lea     n8_coef,%a6
        movem.l (%a6),%a0-%a5
        movea.l 12(%sp),%a6
        moveq   #32,%d0
        move.l  %d0,(%sp)
2:      move.l  8(%sp),%d0
        mulu.l  %d0,%d6
        add.l   #1013904223,%d6
        move.l  %d6,%d0
        asr.l   #1,%d0
        mac.l   %a0,%d0,%acc0
        mac.l   %a1,%d1,%acc0
        mac.l   %a2,%d2,%acc0
        mac.l   %a3,%d3,%acc0
        mac.l   %a4,%d4,%acc0
        mac.l   %a5,%d5,%acc0
        move.l  %d1,%d2
        move.l  %d0,%d1
        movclr.l %acc0,%d0
        add.l   %d0,%d0
        move.l  %d4,%d5
        move.l  %d3,%d4
        move.l  %d0,%d3
        mac.l   %d0,%d7,%acc1
        movclr.l %acc1,%d0
        add.l   %d0,%d0
        add.l   %d0,(%a6)+
        add.l   4(%sp),%d7
        subq.l  #1,(%sp)
        bne.s   2b
        lea     n8_state,%a4
        movem.l %d1-%d5,N8S_X1(%a4)
        move.l  %d6,N8S_SEED(%a4)
        lea     16(%sp),%sp
        move.l  (%sp)+,%a6
        rts

        .align  4
t8sd_state:     .space  8 * 8
n8_state:       .long   0, 0, 0, 0, 0, 0, 0x2468ace1, 0, 0   | env x1 x2 y1 y2 y3 seed amp trig

        | ==================================================== XT TX-9 (slot 39)
        | params: LEV 0, PTC 2, DEC 4, TYP 6, ACC 8, BND 10, NOI 12, TON 14
        | XT CLASSIC: LEV TUN DEC SWD SWT NOD NOL TON
        | state:  e (bend envelope, Q31)
        .section .m39,"ax"
        .align  2
tx9xt_machine:
        ENTER   x9_state
        PARAM   2,%d2                             | PTC
        jsr     note_on
        bne.s   1f
        move.l  #0x7fffffff,(%a3)
        clr.l   4(%a3)
1:      LOOKUP  x9_ptc,%d2
        move.l  %d0,%d4                           | TUN, TYPE 1
        moveq   #0,%d0
        move.w  6(%a2),%d0
        lsr.l   #8,%d0                            | TYPE 0..2 (LT MT HT)
        moveq   #2,%d1
        cmp.l   %d1,%d0
        bls.s   2f
        move.l  %d1,%d0
2:      move.l  %d0,%d5
        lea     x9_typ,%a0
        add.l   %d0,%d0
        move.w  (%a0,%d0.l),%d1
        ext.l   %d1
        add.l   %d1,%d4
        PARAM   4,%d2                             | DEC: a flat start at the longest
        LOOKUP  x9_hold,%d2                       | damping, then the tail's DEC word
        tst.l   %d5                               | from DEC and the steady pitch
        beq.s   3f
        moveq   #11,%d1                           | TYPE 1, 2: 0.68x as long
        mulu.l  %d1,%d0
        lsr.l   #4,%d0
3:      move.l  4(%a3),%d1
        addq.l  #1,4(%a3)
        cmp.l   %d0,%d1
        bge.s   4f
        move.l  #0x7f00,%d0
        bra.s   6f
4:      LOOKUP  x9_dec,%d2
        move.l  #X9_B,%d3
        add.l   %d0,%d3
        tst.l   %d5
        beq.s   5f
        moveq   #X9_TOFF,%d0
        add.l   %d0,%d3
5:      move.l  #X9_KP,%d1
        jsr     xt_dec
6:      move.w  %d0,F_BLOCK+4(%sp)
        PARAM   10,%d3                            | bend: start(BND) * e
        LOOKUP  x9_bnd,%d3
        move.l  (%a3),%d1
        clr.w   %d1
        swap    %d1
        muls.l  %d1,%d0
        moveq   #15,%d1
        asr.l   %d1,%d0
        add.l   %d0,%d4
        jsr     clamp_tun
        move.l  (%a3),%d1
        move.l  #X9_BDEC,%d0
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        move.l  %d0,(%a3)
        PARAM   8,%d3
        SCALED_LEV x9_acc,%d3
        move.w  %d4,F_BLOCK+2(%sp)                | TUN
        clr.w   F_BLOCK+6(%sp)                    | SWD 0: the bend is ours
        clr.w   F_BLOCK+8(%sp)                    | SWT 0
        move.w  #X9_NOD,%d0
        move.w  %d0,F_BLOCK+10(%sp)               | NOD: the TX-9's ~40 ms
        PARAM   12,%d5
        LOOKUP  x9_nol,%d5
        lsl.l   #8,%d0
        move.w  %d0,F_BLOCK+12(%sp)               | NOL <- NOI
        move.w  14(%a2),F_BLOCK+14(%sp)           | TON
        CALLSTOCK xt_classic_machine
        jsr     x9_sub                            | + the second partial (2/3 f)
        EXIT

        .align  4
x9_state:       .space  8 * 8

        | ==================================================== XT TX-8 (slot 40)
        | params: LEV 0, PTC 2, DEC 4, TYP 6, TUN 8, ACC 10, DIO 12, NOI 14
        .section .m40,"ax"
        .align  2
tx8xt_machine:
        ENTER   x8_state
        jsr     note_on
        bne.s   1f
        move.l  #0x7fffffff,(%a3)
1:      moveq   #0,%d0
        move.w  6(%a2),%d0
        lsr.l   #8,%d0                            | TYPE 0..2 (LT MT HT)
        moveq   #2,%d1
        cmp.l   %d1,%d0
        bls.s   2f
        move.l  %d1,%d0
2:      lea     x8_typ,%a0
        add.l   %d0,%d0
        move.w  (%a0,%d0.l),%d4
        ext.l   %d4                               | TUN of the TYPE at PTC 64
        moveq   #0,%d0                            | + 96 per PTC step: 2 octaves
        move.w  2(%a2),%d0
        sub.l   #0x4000,%d0
        move.l  %d0,%d1
        add.l   %d0,%d0
        add.l   %d1,%d0
        asr.l   #3,%d0
        add.l   %d0,%d4
        PARAM   8,%d2                             | + fine TUNE
        LOOKUP  x8_tune,%d2
        add.l   %d0,%d4
        move.l  #X8_B,%d3
        PARAM   4,%d2                             | DEC word from DEC and the pitch
        LOOKUP  x8_dec,%d2
        add.l   %d0,%d3
        move.l  #X8_KP,%d1
        jsr     xt_dec
        move.w  %d0,F_BLOCK+4(%sp)
        PARAM   12,%d2                            | + diode droop * e
        LOOKUP  x8_diod,%d2
        move.l  (%a3),%d1
        clr.w   %d1
        swap    %d1
        muls.l  %d1,%d0
        moveq   #15,%d1
        asr.l   %d1,%d0
        add.l   %d0,%d4
        jsr     clamp_tun
        move.l  (%a3),%d1
        move.l  #X8_DDEC,%d0
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        move.l  %d0,(%a3)
        PARAM   10,%d3
        SCALED_LEV x8_acc,%d3
        move.w  %d4,F_BLOCK+2(%sp)                | TUN
        clr.w   F_BLOCK+6(%sp)                    | SWD 0
        clr.w   F_BLOCK+8(%sp)                    | SWT 0
        move.w  #X8_NOD,%d0
        move.w  %d0,F_BLOCK+10(%sp)               | NOD: the TX-8's short noise
        PARAM   14,%d5
        LOOKUP  x8_nol,%d5
        lsl.l   #8,%d0
        move.w  %d0,F_BLOCK+12(%sp)               | NOL <- NOI
        move.w  #0x4000,%d0
        move.w  %d0,F_BLOCK+14(%sp)               | TON: XT CLASSIC's default
        LEAVE   xt_classic_machine

        | ==================================================== BT TX-8 (slot 42)
        | The TX-8 BD on the BT voice's resonator: BT CLASSIC run every block, the
        | 808's sigh and attack step on its TUN (a quarter semitone per step), its
        | decay matched through BT DEC with a share for the pitch (gen_tx_tables.py
        | bt8, from recordings of BT CLASSIC and the Machinedrum).
        | params: LEV 0, PTC 2, DEC 4, SIG 6, ACC 8, HLD 10, NOI 12, ATK 14
        | BT CLASSIC: LEV TUN DEC - NOL SNP SWD -
        | state:  blocks since the note
        .section .m42,"ax"
        .align  2
bt8_machine:
        ENTER   b8_state
        jsr     note_on
        bne.s   1f
        clr.l   (%a3)
1:      moveq   #0,%d4                            | TUN: 3/4 step per PTC step,
        move.w  2(%a2),%d4                        | two octaves over PTC
        sub.l   #0x4000,%d4
        move.l  %d4,%d0
        add.l   %d4,%d4
        add.l   %d0,%d4
        asr.l   #2,%d4
        add.l   #BT8_TUNOFF,%d4
        move.l  (%a3),%d5                         | the sigh, as BD TX-8's, x4
        cmp.l   #T8_SIGH_BLOCKS,%d5
        bge.s   2f
        PARAM   6,%d2
        LOOKUP  t8bd_sig,%d2
        move.l  #T8_SIGH_BLOCKS,%d1
        sub.l   %d5,%d1
        muls.l  %d1,%d0
        move.l  #T8_SIGH_RECIP,%d1
        muls.l  %d1,%d0
        swap    %d0
        ext.l   %d0
        lsl.l   #2,%d0
        add.l   %d0,%d4
2:      PARAM   14,%d2                            | the attack: ~2.2x the pitch for
        move.l  #T8_ATK_BLK,%d1                   | the first ATK * 0.067 ms
        mulu.l  %d1,%d2
        moveq   #7,%d1
        lsr.l   %d1,%d2
        cmp.l   (%a3),%d2
        blt.s   3f
        add.l   #4*T8_ATK_TUN,%d4
3:      jsr     clamp_tun
        PARAM   8,%d3
        SCALED_LEV t8bd_acc,%d3
        move.w  %d4,F_BLOCK+2(%sp)                | TUN
        PARAM   10,%d0                            | HLD: the longest decay for the
        cmp.l   (%a3),%d0                         | first HLD blocks
        ble.s   4f
        move.l  #0x7f00,%d0
        bra.s   7f
4:      PARAM   4,%d5
        LOOKUP  b8_dec,%d5
        move.l  %d0,%d5
        PARAM   2,%d2
        LOOKUP  b8_dq,%d2                         | + the pitch's share
        add.l   %d5,%d0
        bge.s   5f
        moveq   #0,%d0
5:      cmp.l   #127,%d0
        ble.s   6f
        moveq   #127,%d0
6:      lsl.l   #8,%d0
7:      move.w  %d0,F_BLOCK+4(%sp)                | DEC
        clr.w   F_BLOCK+6(%sp)
        move.w  12(%a2),F_BLOCK+8(%sp)            | NOL <- NOI
        clr.l   F_BLOCK+10(%sp)                   | SNP 0 (the attack is ours), SWD 0
        clr.w   F_BLOCK+14(%sp)
        addq.l  #1,(%a3)
        LEAVE   bt_classic_machine

        .align  4
b8_state:       .space  8 * 8
str_btt8:       .asciz  "BT TX-8"
str_btt8s:      .asciz  "BTT8"
str_btt8g:      .asciz  "BT T8"
        .align  2

        | ==================================================== BD TX-9 DIGI (slot 41)
        | The TX-9 kick made digitally: an oscillator with the TX-9's pitch sweep,
        | hold and decay, written into the BD voice's digital input (buffer A, the
        | path samples take, so the track's filter, overdrive and AMP page still
        | apply). BD CLASSIC runs underneath at LEV 0 (silent; it keeps the voice's
        | own housekeeping, and it rewrites buffer A every block, so this adds).
        | params: as BD TX-9 - LEV 0, PTC 2, DEC 4, TUN 6, DPT 8, ACC 10, WAV 12, ATK 14
        |   WAV 0 a pure sine, 1 the Machinedrum's (sine + its 2nd harmonic at
        |   -26 dB, as recorded), 2 a triangle
        | The sine: s = 4x(1 - |x|), refined by s (0.775 + 0.225 |s|) (harmonics
        | near -50 dB). Pitch = 56 Hz * 2^((PTC - 64) / 64) * (1 + K(DPT) e), e the
        | TX-9's sweep envelope (BD TX-9's tables); level = TX-9 amplitude(ACC) *
        | LEV * env, env held for the TX-9's hold (ACC) then falling at the TX-9's
        | rate for DEC. Phase and gain glide sample by sample across the block.
        | state: d9_state (as BD TX-9's: e, the click's position), d9_ext (voice 0).
        .equ    D9_ENV,  0                        | amplitude envelope, Q31
        .equ    D9_HOLD, 4                        | blocks of hold left
        .equ    D9_PH,   8                        | oscillator phase
        .equ    D9_INC,  12                       | phase step at the last block's end (0: a new note)
        .equ    D9_G,    16                       | gain at the last block's end, Q31
        .section .m34,"ax"
        .align  2
tx9d_machine:
        ENTER   d9_state
        lea     d9_ext,%a4
        PARAM   6,%d2                             | TUN
        PARAM   10,%d3                            | ACC
        jsr     note_on
        bne.s   1f
        lea     t9bd_e0,%a0                       | a note: the TX-9's envelopes restart
        move.l  %d2,%d0
        jsr     interpl
        move.l  %d0,(%a3)
        clr.l   4(%a3)
        move.l  #0x7fffffff,%d0
        move.l  %d0,D9_ENV(%a4)
        LOOKUP  t9bd_hld,%d3
        move.l  %d0,D9_HOLD(%a4)
        clr.l   D9_PH(%a4)
        clr.l   D9_INC(%a4)
1:      clr.l   F_BLOCK+0(%sp)                    | BD CLASSIC, silent: LEV 0, TUN 0,
        clr.l   F_BLOCK+4(%sp)                    | DEC 0, HLD 0, no sweep, WAV 0,
        clr.l   F_BLOCK+8(%sp)                    | TRA 0
        clr.l   F_BLOCK+12(%sp)
        CALLSTOCK bd_classic_machine
        move.l  D9_ENV(%a4),%d0
        cmp.l   #0x00010000,%d0                   | died (or never played): only the
        bcs.w   9f                                | click, if any
        | the phase step at the block's end: base(PTC) * (1 + K e), and e decays
        PARAM   2,%d0
        lea     d9_inc,%a0
        jsr     interpl
        lsr.l   #8,%d0
        move.l  %d0,%d5                           | base >> 8
        PARAM   8,%d0                             | DPT -> K, Q12
        move.l  #TX9_KSTEP,%d1
        mulu.l  %d1,%d0
        lsr.l   #8,%d0
        move.l  (%a3),%d1
        clr.w   %d1
        swap    %d1                               | e, Q15
        mulu.l  %d1,%d0
        moveq   #15,%d1
        lsr.l   %d1,%d0
        add.l   #4096,%d0                         | 1 + K e, Q12
        mulu.l  %d0,%d5
        lsr.l   #4,%d5
        lea     t9bd_cb,%a0                       | e *= cb(TUN)
        move.l  %d2,%d0
        jsr     interpl
        move.l  (%a3),%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        move.l  %d0,(%a3)
        | the envelope: the hold, then the decay for DEC
        move.l  D9_HOLD(%a4),%d0
        beq.s   2f
        subq.l  #1,D9_HOLD(%a4)
        bra.s   3f
2:      PARAM   4,%d0
        lea     d9_dec,%a0
        jsr     interpl
        move.l  D9_ENV(%a4),%d1
        mac.l   %d0,%d1,%acc0
        movclr.l %acc0,%d0
        move.l  %d0,D9_ENV(%a4)
3:      LOOKUP  d9_amp,%d3                        | gain = amp(ACC) * env * LEV, Q31
        move.l  D9_ENV(%a4),%d1
        clr.w   %d1
        swap    %d1
        mulu.l  %d1,%d0
        moveq   #15,%d1
        lsr.l   %d1,%d0
        moveq   #0,%d1
        move.w  0(%a2),%d1
        mulu.l  %d1,%d0
        moveq   #15,%d1
        lsr.l   %d1,%d0
        swap    %d0
        clr.w   %d0
        move.l  D9_G(%a4),%d3                     | glide from the last block's end
        move.l  %d0,D9_G(%a4)
        move.l  D9_INC(%a4),%d4
        move.l  %d5,D9_INC(%a4)
        tst.l   %d4
        bne.s   4f
        move.l  %d5,%d4                           | a note's first block: no glide
        move.l  %d0,%d3
4:      sub.l   %d3,%d0
        asr.l   #5,%d0
        move.l  %d0,%a5                           | gain step
        sub.l   %d4,%d5
        asr.l   #5,%d5                            | phase step's step
        move.l  %d6,%d0
        lsl.l   #7,%d0
        add.l   #VOICE_BUF_A,%d0
        movea.l %d0,%a0
        PARAM   12,%d6                            | WAV
        movea.l #32767,%a1                        | the clamp
        move.l  D9_PH(%a4),%d2
        moveq   #32,%d7
5:      add.l   %d5,%d4
        add.l   %d4,%d2
        move.l  %d2,%d0
        swap    %d0
        ext.l   %d0                               | x, Q15: -1 .. 1 over a cycle
        moveq   #2,%d1
        cmp.l   %d1,%d6
        beq.s   7f
        move.l  %d0,%d1                           | the sine: s = 4x(1 - |x|)
        bpl.s   51f
        neg.l   %d1
51:     sub.l   #32768,%d1
        muls.l  %d1,%d0
        neg.l   %d0
        asr.l   #8,%d0
        asr.l   #5,%d0                            | s, Q15
        move.l  %d0,%d1                           | * (0.775 + 0.225 |s|)
        bpl.s   52f
        neg.l   %d1
52:     mulu.w  #14746,%d1
        swap    %d1
        and.l   #0xffff,%d1
        add.l   #25395,%d1
        muls.l  %d1,%d0
        moveq   #15,%d1
        asr.l   %d1,%d0                           | (32768 at most: muls.w below
        tst.l   %d6                               | squares it the same either way)
        beq.s   8f
        move.l  %d0,%d1                           | WAV 1: + 0.1 y^2 - 0.05, the
        muls.w  %d0,%d1                           | Machinedrum's 2nd harmonic
        swap    %d1
        mulu.w  #6554,%d1
        lsr.l   #8,%d1
        lsr.l   #7,%d1
        sub.l   #1638,%d1
        add.l   %d1,%d0
        bra.s   8f
7:      move.l  %d0,%d1                           | WAV 2: a triangle, in phase
        bpl.s   71f
        neg.l   %d1
71:     cmp.l   #16384,%d1
        ble.s   72f
        neg.l   %d1
        add.l   #32768,%d1
72:     add.l   %d1,%d1
        tst.l   %d0
        bpl.s   73f
        neg.l   %d1
73:     move.l  %d1,%d0
8:      cmp.l   %a1,%d0                           | clamp to +-32767 (a1 = 32767)
        ble.s   81f
        move.l  %a1,%d0
81:     neg.l   %d0
        cmp.l   %a1,%d0
        ble.s   82f
        move.l  %a1,%d0
82:     neg.l   %d0
        swap    %d0
        clr.w   %d0                               | y, Q31
        mac.l   %d0,%d3,%acc0
        movclr.l %acc0,%d0
        add.l   %d0,(%a0)+
        add.l   %a5,%d3
        subq.l  #1,%d7
        bne.w   5b
        move.l  %d2,D9_PH(%a4)
9:      move.l  A_VOICE(%sp),%d6
        jsr     t9_attack                         | the TX-9 click, as BD TX-9's
        EXIT

        | its data, in the tails of other caves (.m34 holds the code alone)
        .section .m41,"ax"
        .align  4
d9_state:       .space  8 * 8
d9_ext:         .space  20                        | voice 0 only: the mask allows no other
        .section .m38,"ax"
str_bd9d:       .asciz  "BD TX-9 DIGI"
str_bd9ds:      .asciz  "BD9D"
str_bd9dg:      .asciz  "BD T9D"
        .align  2

        .section .m40,"ax"

        | d0 = XT CLASSIC DEC word for idx d3 + (d4 * d1 >> 16): d4 the TUN word
        | sent, d1 the pitch slope (see xt_dec in gen_tx_tables.py). Shared by both
        | toms. Clobbers d1, d3, d7, a0.
        .align  2
xt_dec:
        move.l  %d4,%d0
        muls.l  %d1,%d0
        moveq   #16,%d1
        asr.l   %d1,%d0
        add.l   %d0,%d3
        bge.s   1f
        moveq   #0,%d3
1:      moveq   #127,%d0
        cmp.l   %d0,%d3
        ble.s   2f
        move.l  %d0,%d3
2:      lea     xt_dxt,%a0
        move.l  %d3,%d0
        jmp     interpw

        .align  4
x8_state:       .space  8 * 8

        | ==================================================== BD attacks
        | The TX-9 click and the TX-8 attack pulse (tables.inc, from the plugins via
        | tools/tx_measure/atk_extract.py), added into the voice's digital input
        | (buffer A) after BD CLASSIC, whose own transient is off. Called by the BD
        | machines after the stock call: d6 = voice, a2 = params, a3 = state (+4:
        | sample position, cleared on a note). Clobbers d0-d5, d7, a0, a1, a4, a5.
        .section .m41,"ax"
        .align  2
t9_attack:
        PARAM   14,%d3                            | ATK
        PARAM   10,%d4                            | ACC
        lea     a9_atk,%a4
        lea     a9_acc,%a5
        move.l  #A9_K,%d5
        move.l  #A9_N,%d2
        lea     a9_wave,%a1
        | in: d3 ATK, d4 ACC (0..127), a4 / a5 their gain tables, d5 K, d2 length,
        | a1 waveform (bytes). buffer A += (s << 8) * G, G = K * g(ATK) * g(ACC)
        | * LEV, <= 65535.
bd_attack:
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

        | ==================================================== TX-9 tom partial
        | The 909 tom's second partial: a sine at 2/3 of the pitch being sent (d4,
        | the XT TUN word, bend included), decaying a little slower than the main
        | (x9_sd for DEC; TYPE 1, 2 x1.47 faster), written into buffer A - the
        | path the BD attacks and SD noises take. v7 added it into buffer B (XT
        | CLASSIC's noise buffer) and it was not heard on the hardware. Nothing
        | stock writes A on the tom voices, so the partial is stored, not added,
        | and once it has died the block is written as zeros (no stale block can
        | loop). The sine is a parabola: s = 4 x (1 - |x|). Called after the stock
        | call: d4 TUN, d6 voice, a2 params, a3 x9_state slot (+4: blocks since the
        | note, 1 on the first). Clobbers d0-d3, d5, d7, a0, a4.
        .section .m42,"ax"                        | (moved from .m37, which is full)
        .align  2
x9_sub:
        lea     x9sub_state,%a4                   | env (Q31), phase
        move.l  %d6,%d0
        lsl.l   #3,%d0
        add.l   %d0,%a4
        moveq   #1,%d0
        cmp.l   4(%a3),%d0
        bne.s   1f
        move.l  #0x7fffffff,(%a4)
        clr.l   4(%a4)
1:      move.l  (%a4),%d5
        bne.s   10f                               | 0: died, its zero block written
        rts
10:     cmp.l   #0x00200000,%d5                   | done below -60 dB: G = 0, the
        bge.s   6f                                | loop writes one block of zeros,
        moveq   #0,%d5                            | and env = 0 stops it until the
        clr.l   (%a4)                             | next note
        bra.w   7f
6:
        PARAM   4,%d2                             | env *= 1 - d
        LOOKUP  x9_sd,%d2
        moveq   #10,%d1
        lsl.l   %d1,%d0
        moveq   #0,%d1
        move.w  6(%a2),%d1
        lsr.l   #8,%d1
        beq.s   2f
        move.l  %d0,%d1                           | TYPE 1, 2: d * 1.47
        moveq   #15,%d7
        mulu.l  %d7,%d1
        lsr.l   #5,%d1
        add.l   %d1,%d0
2:      mac.l   %d5,%d0,%acc0
        movclr.l %acc0,%d1
        sub.l   %d1,%d5
        move.l  %d5,(%a4)
        PARAM   8,%d2                             | G = K * acc^2 * LEV * env
        LOOKUP  x9_acc,%d2
        mulu.l  %d0,%d0
        moveq   #15,%d1
        lsr.l   %d1,%d0
        move.l  #X9S_K,%d1
        mulu.l  %d1,%d0
        moveq   #15,%d1
        lsr.l   %d1,%d0
        moveq   #0,%d1
        move.w  0(%a2),%d1
        mulu.l  %d1,%d0
        moveq   #15,%d1
        lsr.l   %d1,%d0
        move.l  %d5,%d1
        swap    %d1
        and.l   #0xffff,%d1
        mulu.l  %d1,%d0
        moveq   #15,%d1
        lsr.l   %d1,%d0
        cmp.l   #65000,%d0
        bls.s   3f
        move.l  #65000,%d0
3:      move.l  %d0,%d5
7:      move.l  %d4,%d0                           | phase step from TUN
        moveq   #10,%d1
        lsr.l   %d1,%d0
        lea     x9_sinc,%a0
        lsl.l   #2,%d0
        add.l   %d0,%a0
        move.l  (%a0),%d3
        move.l  4(%a0),%d0
        sub.l   %d3,%d0
        asr.l   #4,%d0
        move.l  %d4,%d1
        and.l   #0x3ff,%d1
        muls.l  %d1,%d0
        asr.l   #6,%d0
        add.l   %d0,%d3
        move.l  %d6,%d0
        lsl.l   #7,%d0
        add.l   #VOICE_BUF_A,%d0
        movea.l %d0,%a0
        move.l  4(%a4),%d2
        moveq   #32,%d7
4:      add.l   %d3,%d2
        move.l  %d2,%d0
        swap    %d0
        ext.l   %d0                               | x, Q15
        move.l  %d0,%d1
        bpl.s   5f
        neg.l   %d1
5:      sub.l   #32768,%d1                        | |x| - 1
        muls.l  %d1,%d0
        neg.l   %d0                               | x (1 - |x|), Q30 / 4
        asr.l   #8,%d0
        asr.l   #5,%d0                            | s, Q15
        muls.l  %d5,%d0
        move.l  %d0,(%a0)+
        subq.l  #1,%d7
        bne.s   4b
        move.l  %d2,4(%a4)
        rts

        .section .m41,"ax"
        .align  4
x9sub_state:    .space  8 * 8

        | ==================================================== TYP display
        | XT TX-9 / TX-8 TYP shows LT / MT / HT. A std::function prototype for the
        | param_info value formatters (data, -, manager, invoker; the stock
        | manager of the plain prototype clones any empty functor), whose invoker
        | prints the name like the stock table formatters: (functor, value, buffer)
        | -> sprintf(buffer, "%s", name[value >> 8]).
        .equ    STOCK_FN_MANAGER, 0x400f5726
        .equ    STOCK_FMT_S,      0x4020943d      | "%s"
        .equ    STOCK_SPRINTF,    0x40096686
        .align  4
fmt_lmh:        .long   fmt_lmh, 0, STOCK_FN_MANAGER, fmt_lmh_invoke
typ_names:      .long   str_lt, str_mt, str_ht
fmt_lmh_invoke:
        move.l  8(%sp),%d0
        asr.l   #8,%d0
        bge.s   1f
        moveq   #0,%d0
1:      moveq   #2,%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:      lea     typ_names,%a0
        move.l  (%a0,%d0.l*4),%d1
        move.l  12(%sp),%d0
        move.l  %d0,4(%sp)
        move.l  #STOCK_FMT_S,%d0
        move.l  %d0,8(%sp)
        move.l  %d1,12(%sp)
        jmp     STOCK_SPRINTF

        | ==================================================== names
        | Reached by registry patches; all in .m41 (the dead BD FM 2 routine).
str_lt:         .asciz  "LT"
str_mt:         .asciz  "MT"
str_ht:         .asciz  "HT"
str_attack:     .asciz  "Attack"
str_atk:        .asciz  "ATK"
str_bdt9:       .asciz  "BD TX-9"
str_bdt9s:      .asciz  "BDT9"
str_bdt9g:      .asciz  "BD T9"
str_sdt9:       .asciz  "SD TX-9"
str_sdt9s:      .asciz  "SDT9"
str_sdt9g:      .asciz  "SD T9"
str_sdt8:       .asciz  "SD TX-8"
str_sdt8s:      .asciz  "SDT8"
str_sdt8g:      .asciz  "SD T8"
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
str_sigh:       .asciz  "Sigh"
str_sig:        .asciz  "SIG"
str_hold:       .asciz  "Hold Time"
str_hld:        .asciz  "HLD"
str_wave:       .asciz  "Waveform"
str_wav:        .asciz  "WAV"
str_trans:      .asciz  "Transient"
str_tra:        .asciz  "TRA"
str_tone:       .asciz  "Tone"
str_ton:        .asciz  "TON"
str_snappy:     .asciz  "Snappy"
str_snp:        .asciz  "SNP"
str_bend:       .asciz  "Bend"
str_bnd:        .asciz  "BND"
str_detune:     .asciz  "Detune"
str_dtu:        .asciz  "DTU"
str_det:        .asciz  "DET"
str_level:      .asciz  "Level"
str_lev:        .asciz  "LEV"
str_xtt9:       .asciz  "XT TX-9"
str_xtt9s:      .asciz  "XTT9"
str_xtt9g:      .asciz  "XT T9"
str_xtt8:       .asciz  "XT TX-8"
str_xtt8s:      .asciz  "XTT8"
str_xtt8g:      .asciz  "XT T8"
str_type:       .asciz  "Type"
str_typ:        .asciz  "TYP"
str_noise:      .asciz  "Noise"
str_noi:        .asciz  "NOI"
str_ntone:      .asciz  "Noise Tone"
str_tune:       .asciz  "Tune"
str_diode:      .asciz  "Diode"
str_dio:        .asciz  "DIO"

        | ==================================================== state (BD TX-9)
        .text
        .align  4
t9bd_state:     .space  8 * 8
