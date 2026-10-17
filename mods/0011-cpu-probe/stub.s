        | Mod 0011 - CPU probe: three live readouts of the processor's load, shown
        | as the labels of SETTINGS > MIDI CONFIG > CHANNELS (see mod.toml):
        |
        |   PERF CHANNEL   ->  CPU 78.3%     time not spent idle, all of it
        |   AUTO CHANNEL   ->  AUDIO 61.2%   the audio interrupt's average share
        |   PROG CH IN CH  ->  PEAK 74.0%    its largest share of one block
        |
        | Each readout covers the time since it last drew (the menu redraws them
        | as it repaints), so leave the page up for a few seconds while playing.
        |
        | Timer: DMA timer 0's counter, free-running at the bus clock (stock reads
        | it as a time base too; 0008's diag uses it the same way).
        |
        | Audio: DTCN0 at the audio interrupt's entry (0x40118918, its prologue
        | re-emitted) and at its one exit (0x4011a100, the epilogue and rte
        | re-emitted): run time over the interval between entries, summed over the
        | window for the average, the largest single block for the peak. Intervals
        | that are stalls, not blocks, are left out. (A4 0004's method.)
        |
        | CPU: main() ends in `bra.s .` (0x400f9e64) once it has started the OS: the
        | code that runs when no task or interrupt wants the processor. Its last call
        | (0x400f9e5e) is repointed here, makes that call, then never returns: it
        | reads DTCN0 in a loop and adds up the gaps between reads that are short
        | enough to be its own loop (under GAP_MAX ticks). Any gap an interrupt or a
        | task took is longer and not counted. CPU = 1 - idle time / elapsed time.

        .equ    DTCN0,          0xfc07000c
        .equ    ISR_BODY,       0x4011898c        | past the audio interrupt's prologue
        .equ    MAIN_LAST,      0x400a0eaa        | main()'s last call before its spin
        .equ    LBL_CTOR,       0x4018b71a        | the labels' string constructor's call
        .equ    LBL_PERF_R,     0x40045088        | the three label getters, past
        .equ    LBL_AUTO_R,     0x400450b0        | their `pea "LABEL"`
        .equ    LBL_PROG_R,     0x400450d8
        .equ    GAP_MAX,        128               | ticks: about 1 us at a 125 MHz bus
        .equ    STALL,          0x00400000        | an interval this long is not a block

        | variables in DRAM nothing else uses, through its cached address (0010's
        | lines end at 0x428a6200; re/fx-engine.md). DRAM is not cleared at boot:
        | idle_entry clears them before any readout can draw.
        .equ    PV,             0x428a8000
        .equ    V_T0,           0                 | the audio interrupt's last entry
        .equ    V_IV,           4                 | the interval before it
        .equ    V_ASUM,         8                 | run time, this window
        .equ    V_AIV,          12                | intervals, this window
        .equ    V_PEAK,         16                | largest block, 0.1 %
        .equ    V_IDLE,         20                | idle ticks, this window
        .equ    V_CT0,          24                | the CPU window's start
        .equ    V_BUF,          32                | label text, 16 B each
        .equ    V_LONGS,        20                | longs cleared at start

        .text

        | ------------------------------------------------------------------
        | The audio interrupt's entry.
        | ------------------------------------------------------------------
        .align  2
isr_enter:
        lea     -156(%sp),%sp                     | displaced
        movem.l %d0-%fp,(%sp)                     | displaced
        move.l  DTCN0,%d0
        move.l  PV+V_T0,%d1
        move.l  %d0,PV+V_T0
        sub.l   %d1,%d0
        move.l  %d0,PV+V_IV
        jmp     ISR_BODY

        | ------------------------------------------------------------------
        | Its exit, where every register is about to be restored from the frame
        | (MACSR already is; nothing here uses the MAC).
        | ------------------------------------------------------------------
        .align  2
isr_exit:
        lea     PV,%a0
        move.l  DTCN0,%d0
        sub.l   V_T0(%a0),%d0                     | run
        move.l  V_IV(%a0),%d1
        beq.s   9f
        cmp.l   %d1,%d0
        bhi.s   9f
        cmp.l   #STALL,%d1
        bcc.s   9f
        move.l  V_AIV(%a0),%d2                    | keep the sums in range: halve
        cmp.l   #0x40000000,%d2                   | both if nobody reads them
        bcs.s   1f
        lsr.l   #1,%d2
        move.l  %d2,V_AIV(%a0)
        move.l  V_ASUM(%a0),%d2
        lsr.l   #1,%d2
        move.l  %d2,V_ASUM(%a0)
1:      add.l   %d0,V_ASUM(%a0)
        add.l   %d1,V_AIV(%a0)
        move.l  #1000,%d2
        mulu.l  %d2,%d0
        divu.l  %d1,%d0                           | this block, 0.1 %
        cmp.l   V_PEAK(%a0),%d0
        bls.s   9f
        move.l  %d0,V_PEAK(%a0)
9:      movem.l (%sp),%d0-%fp                     | displaced
        lea     156(%sp),%sp                      | displaced
        rte

        | ------------------------------------------------------------------
        | main()'s last call, then the idle loop in place of its `bra.s .`.
        | ------------------------------------------------------------------
        .align  2
idle_entry:
        jsr     MAIN_LAST
        lea     PV,%a0
        moveq   #V_LONGS-1,%d0
1:      clr.l   (%a0,%d0.l*4)
        subq.l  #1,%d0
        bpl.s   1b
        move.l  DTCN0,%d1
        move.l  %d1,V_CT0(%a0)
2:      move.l  DTCN0,%d0
        move.l  %d0,%d2
        sub.l   %d1,%d2
        move.l  %d0,%d1
        cmp.l   #GAP_MAX,%d2
        bcc.s   2b                                | interrupted: not idle time
        add.l   %d2,V_IDLE(%a0)
        bra.s   2b

        .section .tab,"ax"

        | ------------------------------------------------------------------
        | The three label getters, each at its `pea "LABEL"`: a0 holds the string
        | being built and must survive; d0/d1/a1 are free. Push the text instead
        | and rejoin.
        | ------------------------------------------------------------------
        .align  2
lbl_perf:
        move.l  %a0,-(%sp)
        lea     PV,%a0
        move.l  DTCN0,%d0
        move.l  V_CT0(%a0),%d1
        move.l  %d0,V_CT0(%a0)
        sub.l   %d1,%d0                           | elapsed
        move.l  V_IDLE(%a0),%d1
        clr.l   V_IDLE(%a0)
        jsr     tenths                            | idle, 0.1 %
        neg.l   %d0
        add.l   #1000,%d0                         | busy
        lea     str_cpu,%a1
        moveq   #0,%d1
        jsr     label
        move.l  (%sp)+,%a0
        pea     PV+V_BUF
        jmp     LBL_PERF_R

        .align  2
lbl_auto:
        move.l  %a0,-(%sp)
        lea     PV,%a0
        move.l  V_AIV(%a0),%d0
        move.l  V_ASUM(%a0),%d1
        clr.l   V_AIV(%a0)
        clr.l   V_ASUM(%a0)
        jsr     tenths
        lea     str_audio,%a1
        moveq   #16,%d1
        jsr     label
        move.l  (%sp)+,%a0
        pea     PV+V_BUF+16
        jmp     LBL_AUTO_R

        .align  2
lbl_prog:
        move.l  %a0,-(%sp)
        lea     PV,%a0
        move.l  V_PEAK(%a0),%d0
        clr.l   V_PEAK(%a0)
        lea     str_peak,%a1
        moveq   #32,%d1
        jsr     label
        move.l  (%sp)+,%a0
        pea     PV+V_BUF+32
        jmp     LBL_PROG_R

        | tenths(d1 = part, d0 = whole) -> d0 = part / whole in 0.1 %, 0..1000.
        | Clobbers d1.
        .align  2
tenths:
1:      cmp.l   #0x003fffff,%d0                   | so part * 1000 fits 32 bits
        bls.s   2f
        lsr.l   #1,%d0
        lsr.l   #1,%d1
        bra.s   1b
2:      tst.l   %d0
        beq.s   8f
        move.l  %d2,-(%sp)
        move.l  #1000,%d2
        mulu.l  %d2,%d1
        divu.l  %d0,%d1
        move.l  (%sp)+,%d2
        move.l  %d1,%d0
        cmp.l   #1000,%d0
        bls.s   9f
        move.l  #1000,%d0
9:      rts
8:      moveq   #0,%d0
        rts

        | label(d0 = 0.1 %, a1 = prefix, d1 = buffer offset): "PREFIX 12.3%" into
        | PV+V_BUF+d1. Clobbers d0/d1/a1, keeps a0 = PV.
        .align  2
label:
        move.l  %a2,-(%sp)
        lea     V_BUF(%a0,%d1.l),%a2
1:      move.b  (%a1)+,%d1
        move.b  %d1,(%a2)+
        bne.s   1b
        subq.l  #1,%a2
        cmp.l   #1000,%d0
        bls.s   2f
        move.l  #1000,%d0
2:      divu.w  #10,%d0                           | whole percent, tenths in the high word
        move.l  %d0,%d1
        and.l   #0xffff,%d0
        divu.w  #10,%d0                           | tens, units
        tst.w   %d0
        beq.s   4f
        cmp.w   #10,%d0                           | 100
        bne.s   3f
        move.b  #0x31,(%a2)+
        moveq   #0,%d0
3:      add.l   #0x30,%d0
        move.b  %d0,(%a2)+
4:      swap    %d0
        add.l   #0x30,%d0
        move.b  %d0,(%a2)+
        move.b  #0x2e,(%a2)+                      | .
        swap    %d1
        add.l   #0x30,%d1
        move.b  %d1,(%a2)+
        move.b  #0x25,(%a2)+                      | %
        clr.b   (%a2)
        move.l  (%sp)+,%a2
        rts

str_cpu:        .asciz  "CPU "
str_audio:      .asciz  "AUDIO "
str_peak:       .asciz  "PEAK "
        .align  2
