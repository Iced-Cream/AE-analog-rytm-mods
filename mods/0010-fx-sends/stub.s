        | Mod 0010 - FX SENDS: a chorus as one more send effect, on a second AMP
        | page, with the Analog Four chorus's controls.
        |
        | Press AMP a second time for the FX SENDS page:
        |   CHR  chorus send   (per track, saved with the sound)
        |   PRE  pre-delay, 1 .. 20 ms                            |   SPD  speed, 0.05 .. 8 Hz                       |  global, shared by every
        |   DEP  depth, 0 .. 8 ms of sweep                 |  track's page; this
        |   WID  stereo width: 0 mono, 127 the two taps    |  version holds them in
        |        sweeping in opposite phase                |  RAM, back to their
        |   FDB  feedback, 0 .. 0.89                       |  defaults at power-up
        |   HPF  high-pass on the chorus input, off .. ~2 kHz
        |   VOL  the return's level                       /
        |
        | Where it acts (re/fx-engine.md). The Rytm's delay and reverb run on the
        | ColdFire in the audio interrupt: 0x401075a4(rx) mixes the eight voice slots
        | the codec captured (rx, 10 longs a frame, slot i = physical voice i) into the
        | delay and reverb sends, runs both, and the next interrupt's 0x40107f20(dac)
        | sends the returns to the DAC - PRE (into the analog distortion and
        | compressor) in words 12/13 of each 64-byte frame, POST in 14/15. This mod
        | follows the same path: after the stock FX it mixes the voices into a mono
        | bus by each track's CHR send, runs the chorus (stereo out), and after the
        | stock return output it adds the return into the PRE words, scaled like a
        | stock return: (2 * VOL * FX track level)^2.
        |
        | The chorus: two interpolated taps on one line, each swept by a triangle
        | LFO from PRE up to PRE + DEP; WID sets the right tap's phase against the
        | left's. The input is high-passed (one pole, HPF) and the taps' average is
        | fed back into the line (FDB). The Analog Four's own chorus (0x400f7f50 in
        | its OS) runs six voices with filters and DMA'd lines - about four times
        | the work, more than the Rytm has spare - so this keeps its controls on a
        | two-tap engine. v1 also had a comb filter; it was dropped (2026-10-15) for
        | the processor time.
        |
        | Storage: CHR in bits 0..6 of the sound's free parameter word (sound index
        | 0, live sound +0x14) - the word 0004 and 0008 use, which is why it
        | excludes both. Bits 8..14 held v1's comb send and are left as they are.
        |
        | Memory: the line and buffers live in DRAM the stock FX never touch, through
        | its cached address (below). DRAM is not cleared at boot, so it is cleared
        | here first, 1 KB a block, before anything runs.
        |
        | Cost: nothing while no track sends and the tail has died (~3 s); about
        | 2,300 instructions a block with everything on (emulator).

        .include "symbols.inc"
        .include "shared.inc"

        .equ    PAGE_AMP,       6
        .equ    PAGE_FX,        11                | MK1 pages are 0..10
        .equ    OFF_PARAMS,     0x14              | live sound parameter array
        .equ    PROJ_TRACKSEL,  48
        .equ    TRACKS,         12
        .equ    VOICES,         8
        .equ    FRAMES,         32
        .equ    RX_STRIDE,      40                | receive frame: 10 longs
        .equ    DAC_STRIDE,     64
        .equ    DAC_PRE,        0x30              | PRE return L, R: words 12, 13
        .equ    SOUND0,         232+96            | the kit's first Sound: kit_track_sound adds 0x60 (see 0008)
        .equ    SOUND_STRIDE,   352
        .equ    SOUND_LIVE,     16
        .equ    FX_LEVEL,       0x800062bc        | the FX track's level, 8.8 (stock returns use it)
        .equ    STOCK_FX,       0x40107610
        .equ    STOCK_RET,      0x40107f8c
        .equ    TAIL_BLOCKS,    4500              | ~3 s after the last send

        | DRAM, through its cached address. The same memory as 0x4a8a0000, the
        | uncached mirror stock gives its reverb and delay lines (0x4a800000..),
        | which it only moves by DMA. Read and written sample by sample from the
        | uncached mirror, the chorus cost ~2.5x its instruction count on the
        | hardware (0011's readings, 2026-10-14); nothing but this code touches it,
        | so the cache needs no flushing. Unused by stock through either address
        | (emulator RAM dump of a stock session: 0x42898000.. stays zero).
        .equ    FXRAM,          0x428a0000
        .equ    CLINE,          FXRAM             | chorus line, 2048 longs
        .equ    CMASK,          2047
        .equ    BUSC,           FXRAM+0x6000      | chorus send, 32 longs
        .equ    OUTB,           FXRAM+0x6100      | the return, 32 stereo frames
        .equ    FXRAM_LONGS,    0x6200/4
        .equ    CLEAR_STEP,     256               | longs cleared a block

        | the chorus: delays in 16.16 samples. Longest: 48 + 914 (PRE) + 762 (DEP)
        | = 1724 samples, inside the 2048-sample line.
        .equ    C_PRE0,         48<<16            | PRE 0: 1 ms
        .equ    C_PRE_K,        471859            | per PRE step: 7.2 samples (0.15 ms)
        .equ    C_DEPTH_K,      3                 | DEP 127 -> a 381-sample (7.9 ms) sweep
        .equ    C_RATE_K,       1398              | phase step a block = (SPD+1)^2 * K
        .equ    C_WID_K,        0x01020408        | WID 127 -> half a cycle between the taps
        .equ    FB_SCALE,       230               | FDB 127 -> 0.89 in Q15

        | the globals, by byte (knob k = 1..7 is byte k - 1)
        .equ    G_PRE,          0
        .equ    G_SPD,          1
        .equ    G_DEP,          2
        .equ    G_WID,          3
        .equ    G_FDB,          4
        .equ    G_HPF,          5
        .equ    G_VOL,          6

        | the eight knobs: id 1 per track (CHR); 2, 3, 4, 5, 11, 12, 13 global
        .equ    ID_CHR,         1

        .text

        | ------------------------------------------------------------------
        | page_info, answering PAGE_FX.
        | ------------------------------------------------------------------
        .align  2
page_info_gate:
        moveq   #PAGE_FX,%d0
        cmp.l   4(%sp),%d0
        bne.s   1f
        lea     page_fx,%a0
        move.l  %a0,%d0
        rts
1:      moveq   #10,%d1                           | displaced
        move.l  %sp@(4),%d0                       | displaced
        jmp     page_info_resume

        | ------------------------------------------------------------------
        | page_get_value for our ids: (%sp) return, 4 view, 8 id, 12 lock.
        | Answers 8.8 on the 0..127 scale.
        | ------------------------------------------------------------------
        .align  2
get_gate:
        move.l  8(%sp),%d0
        jsr     knob_of                           | d0 = knob 0..7, or -1
        bmi.s   9f
        jsr     knob_value
        lsl.l   #8,%d0
        rts
9:      lea     %sp@(-12),%sp                     | displaced
        moveml  %d2-%d3/%a2,%sp@                  | displaced
        jmp     page_get_value_body

        | ------------------------------------------------------------------
        | param_apply_delta for our ids, past its prologue: %sp@(0..11) d2/d3/a2,
        | a2 the view, %sp@(20) the id, %sp@(24) the delta in 8.8.
        | ------------------------------------------------------------------
        .align  2
delta_gate:
        move.l  %sp@(20),%d0
        jsr     knob_of
        bmi.w   9f
        move.l  %d0,%d3                           | the knob
        move.l  %sp@(24),%d2
        asr.l   #8,%d2                            | whole steps
        beq.s   7f
        move.l  %d3,%d0
        jsr     knob_value
        add.l   %d2,%d0
        bpl.s   1f
        clr.l   %d0
1:      moveq   #127,%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:      tst.l   %d3
        bne.s   5f
        | per track (CHR): the sound's word
        move.l  %d0,%d2                           | the new value
        jsr     word_sync                         | d0 word, a0 sound
        move.l  %a0,%d1
        beq.s   7f
        and.l   #0x7f00,%d0                       | CHR: bits 0..6
        or.l    %d2,%d0
        move.w  %d0,OFF_PARAMS(%a0)
        move.l  %d0,-(%sp)                        | the new word
        move.l  %sp@(24),-(%sp)                   | the id
        jsr     shared_mark_changed               | so it is saved with the sound
        addq.l  #8,%sp
        bra.s   6f
5:      lea     globals,%a0                       | global: RAM
        move.b  %d0,-1(%a0,%d3.l)
6:      move.l  %a2,-(%sp)
        jsr     view_invalidate                   | redraw now
        addq.l  #4,%sp
7:      movem.l (%sp),%d2-%d3/%a2                 | param_apply_delta's epilogue
        lea     12(%sp),%sp
        rts
9:      mvzb    %d3,%d3                           | displaced
        move.l  %a2@(116),-(%sp)                  | displaced
        jmp     param_apply_delta_track

        | ------------------------------------------------------------------
        | param_value_text for our ids, past its argument loads: %sp@(0..19)
        | d2-d4/a2-a3, d4 the id, %sp@(36) the output buffer. Plain 0..127.
        | ------------------------------------------------------------------
        .align  2
text_gate:
        move.l  %d4,%d0
        jsr     knob_of
        bmi.s   9f
        jsr     knob_value
        move.l  %sp@(36),%a1
        jsr     put_u3
        clr.b   (%a1)
        movem.l (%sp),%d2-%d4/%a2-%a3             | param_value_text's epilogue
        lea     20(%sp),%sp
        rts
9:      movel   %sp@(32),%d2                      | displaced
        movel   %sp@(36),%d3                      | displaced
        jmp     param_value_text_args

        | ------------------------------------------------------------------
        | fx_gate(rx) - both calls to the stock FX block are repointed here.
        | Runs it, then the buses and the two effects. C convention.
        | Frame: 0..43 saved registers; the caller's rx at 48.
        | ------------------------------------------------------------------
        .align  2
fx_gate:
        move.l  4(%sp),-(%sp)
        jsr     STOCK_FX
        addq.l  #4,%sp
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  #0xa0,%macsr                      | as the stock FX: fractional, saturating
        lea     st,%a6

        | DRAM first: clear it, a slice a block, before anything reads it
        move.l  ST_CLEAR(%a6),%d0
        cmp.l   #FXRAM_LONGS,%d0
        bcc.s   1f
        move.l  %d0,%d1
        lsl.l   #2,%d1
        add.l   #FXRAM,%d1
        move.l  %d1,%a0
        move.l  #CLEAR_STEP,%d1
        add.l   %d1,ST_CLEAR(%a6)
10:     clr.l   (%a0)+
        subq.l  #1,%d1
        bne.s   10b
        bra.w   99f

        | the send coefficients, from each voice's owning track, every 8th
        | block (5 ms): they glide anyway, and the walk over the voices is the
        | mod's one cost while nothing sends
1:      subq.l  #1,ST_CDIV(%a6)
        bpl.s   11f
        moveq   #7,%d0
        move.l  %d0,ST_CDIV(%a6)
        jsr     coefs_build                       | d0 = non-zero if any send
        move.l  %d0,ST_ANY(%a6)
11:     tst.l   ST_ANY(%a6)
        beq.s   2f
        move.l  #TAIL_BLOCKS,%d0
        move.l  %d0,ST_TAIL(%a6)
        bra.s   3f
2:      move.l  ST_TAIL(%a6),%d0
        beq.w   98f                               | idle
        subq.l  #1,ST_TAIL(%a6)
3:      move.l  48(%sp),%a5                       | rx
        jsr     buses_mix
        jsr     chorus_run
        moveq   #-1,%d0                           | the return has something
        move.b  %d0,ST_RET(%a6)
        bra.s   99f
98:     clr.b   ST_RET(%a6)
99:     move.l  #0x20,%macsr
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     44(%sp),%sp
        rts

        | ------------------------------------------------------------------
        | ret_gate(dac) - both calls to the stock return output are repointed
        | here. Runs it, then adds this mod's return (made by the last fx_gate,
        | the same one-block lag as the stock returns) into the PRE words.
        | ------------------------------------------------------------------
        .section .tab,"awx"                       | (in cave3 since OS 1.74: its cave
        .align  2                                 | is 0x60 smaller)
ret_gate:
        move.l  4(%sp),-(%sp)
        jsr     STOCK_RET
        addq.l  #4,%sp
        lea     st,%a0
        tst.b   ST_RET(%a0)
        bne.s   1f
        rts
1:      lea     -24(%sp),%sp
        movem.l %d2-%d6/%a2,(%sp)
        move.l  #0xa0,%macsr
        movclr.l %acc0,%d0
        | g = (2 * VOL * FX level)^2, VOL and the level 8.8 - the stock form
        lea     globals,%a0
        mvzb    G_VOL(%a0),%d0                    | VOL
        lsl.l   #8,%d0
        add.l   %d0,%d0
        mvsw    FX_LEVEL,%d1
        muls.l  %d1,%d0
        mac.l   %d0,%d0,%acc0
        movclr.l %acc0,%d3                        | g, Q31
        move.l  28(%sp),%d0                       | dac
        moveq   #11,%d1
        lsl.l   %d1,%d0
        add.l   #0x80000000+DAC_PRE,%d0
        move.l  %d0,%a1
        move.l  #OUTB,%a2
        moveq   #FRAMES,%d6
2:      move.l  (%a2)+,%d0                        | L
        mac.l   %d3,%d0,%acc0
        movclr.l %acc0,%d0
        move.l  (%a1),%d1
        lsl.l   #8,%d1                            | back to Q31
        sub.l   %d0,%d1                           | stock writes -(g * return)
        sats.l  %d1
        asr.l   #8,%d1
        move.l  %d1,(%a1)+
        move.l  (%a2)+,%d0                        | R
        mac.l   %d3,%d0,%acc0
        movclr.l %acc0,%d0
        move.l  (%a1),%d1
        lsl.l   #8,%d1
        sub.l   %d0,%d1
        sats.l  %d1
        asr.l   #8,%d1
        move.l  %d1,(%a1)+
        lea     DAC_STRIDE-8(%a1),%a1
        subq.l  #1,%d6
        bne.s   2b
        move.l  #0x20,%macsr
        movem.l (%sp),%d2-%d6/%a2
        lea     24(%sp),%sp
        rts

        .include "mods/0010-fx-sends/dsp.s"
