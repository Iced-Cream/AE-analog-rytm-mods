        | fx-sends - FX SENDS (AE 0010), a chorus as one more send effect, on a
        | second AMP page, for the Analog Rytm MKII, OS 1.74.
        |
        | Press AMP a second time on a drum track for the SEND page:
        |   CHR  chorus send   (per track, saved with the sound)
        | and on the FX track, DELAY a second time for the CHORUS page:
        |   PRE  pre-delay, 1 .. 20 ms                     \
        |   SPD  speed, 0.05 .. 8 Hz                        |  the FX track's
        |   DEP  depth, 0 .. 8 ms of sweep                  |  parameters (1.1):
        |   WID  stereo width: 0 mono, 127 the two taps     |  saved with the kit,
        |        sweeping in opposite phase                 |  lockable, FX LFO
        |   FDB  feedback, 0 .. 0.89                        |  destinations
        |   HPF  high-pass on the chorus input, off .. ~2 kHz
        |   VOL  the return's level                        /
        |
        | Where it acts. The MKII's delay and reverb run on the ColdFire in the
        | audio interrupt, as the MK1's do: fx_generate 0x4010e6bc(rx) mixes the
        | eight voice slots of the receive buffer (0x80007440, 12 longs a frame,
        | voice v in slot 0x401ef480[v], at +8 + 4 * slot) into the two sends and
        | runs both; the return mixer 0x4010ee4e(idx) writes the returns into the
        | output frames, PRE (into the analog distortion and compressor) in words
        | 12/13 of each 64-byte frame, POST in 14/15. Both have two callers (the
        | main path and a second one), and all four calls are repointed here.
        | After the stock FX the voices are mixed into a mono bus by each track's
        | CHR send, the chorus runs (stereo out), and after the stock return
        | output the return is added into the PRE words, scaled like a stock
        | return: (2 * VOL * FX track level)^2.
        |
        | The chorus is the MK1's: two interpolated taps on one line, each swept
        | by a triangle LFO from PRE up to PRE + DEP; WID sets the right tap's
        | phase against the left's. The input is high-passed (one pole, HPF) and
        | the taps' average is fed back into the line (FDB).
        |
        | Storage: CHR is a 7-bit sound field in core-ar2 0.3's mod storage
        | (fx_sends_chr), so it travels with the sound and the sound's stock bytes
        | stay stock. The MK1 kept it in the sound's free parameter word.
        |
        | The chorus settings (1.1, core-ar2 0.10) are 7-bit kit fields
        | (fx_sends_pre .. fx_sends_vol, with the MK1's defaults as their inits),
        | lockable and FX LFO destinations: the FX track's parameters, p-locked
        | with an FX trig held, locked in scenes and performances, on MIDI on the
        | FX channel. While the chorus runs, the audio reads all seven as stock
        | would play them (core_param_values on track 12) every block into
        | globals, which the chorus and the return read as before.
        |
        | Locks (1.1, core-ar2 0.10): CHR is a lockable parameter (core_lock_params):
        | p-locked with a trig held, locked in scenes, given performance depths,
        | on MIDI as NRPN 4 / its code - 42, an LFO destination (AMP:Chorus Send
        | in DST) and a velocity and aftertouch destination, as a stock
        | parameter. The audio reads the value stock would play
        | (core_param_value_h: the sound's CHR, the trig's p-lock, the scene's
        | lock, smoothed as stock smooths, plus the performances, the velocity
        | and aftertouch routes and the LFO), one
        | voice's track a block in turn, so each voice's entry in chr_trk is at
        | most 8 blocks (5 ms) old, as often as coefs_build reads it; an edit
        | updates its track's entry at once.
        |
        | The page: page 15 after AMP (page 7) in the AMP view's list, through
        | core-ar2 0.4's page tables. Its knobs are CY TEST's parameter records 449..456 (a hidden
        | machine's, renamed).
        |
        | Memory: the line and buffers are this mod's .bss (8.5 KB), not raw DRAM.
        |
        | Cost: nothing while no track sends and the tail has died (~3 s).

        .equ    PAGE_AMP,       7
        .equ    PAGE_FX,        15                | SEND: CHR
        .equ    PAGE_CHO,       16                | CHORUS: PRE .. VOL
        .equ    CHORUS_VIEW,    5                 | CORE_VIEW_DELAY: DELAY pressed again
        .equ    ID0,            449               | CHR PRE SPD DEP WID FDB HPF VOL: 449..456
        .equ    KNOBS,          8

        .equ    TRACKS,         12
        .equ    VOICES,         8
        .equ    FRAMES,         32
        .equ    RX_STRIDE,      48                | receive frame: 12 longs
        .equ    OUT_STRIDE,     64
        .equ    OUT_PRE,        0x30              | PRE return L, R: words 12, 13
        .equ    VOICE_OWNER,    0x40291138        | per physical voice: its track
        .equ    FX_LEVEL,       0x8000f7a4        | the FX track's level (stock returns use it)
        .equ    STOCK_FX,       0x4010e6bc
        .equ    STOCK_RET,      0x4010ee4e
        .equ    TAIL_BLOCKS,    4500              | ~3 s after the last send

        .equ    CMASK,          2047              | chorus line, 2048 longs

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

        | state, at st
        .equ    ST_TAIL,        0                 | blocks of tail left
        .equ    ST_RET,         4                 | byte: the return holds audio
        .equ    ST_CPH,         8                 | chorus LFO phase
        .equ    ST_CW,          12                | chorus write index
        .equ    ST_HLP,         16                | high-pass state (its low-pass part)
        .equ    ST_FB,          20                | the taps' last average, fed back
        .equ    ST_DL,          24                | chorus delays at the block's end, 16.16
        .equ    ST_DR,          28
        .equ    ST_NACT,        32                | sending voices this block
        .equ    ST_CDIV,        36                | blocks until coefs_build runs again
        .equ    ST_ANY,         40                | its last result: a track sends
        .equ    ST_COEF,        44                | per voice: chorus coefficient (Q31)
        .equ    ST_TGT,         76                | per voice: its target, from CHR
        .equ    ST_S1,          108               | per voice: the first glide stage
        .equ    ST_ACT,         140               | per sending voice: rx offset,
                                                  | coefficient, its step a frame
        .equ    ST_SIZE,        236
        .equ    COEF_K,         66572             | v^2 * K: v 127 -> 0.5 in Q31

        | the live sound, through the selected track's accessor
        .equ    PROJECT_SINGLETON, 0x4017fa0a
        .equ    TRACK_INDEX_OF, 0x400b693e
        .equ    KIT_TRACK_SOUND, 0x400a67ca
        .equ    PROJ_TRACKSEL,  48
        .equ    PROJ_KIT,       352
        .equ    VT_STORAGE,     0x28              | the accessor's live-sound getter
        .equ    VT_CONFIG_CHANGED, 16             | the accessor's change notice
        .equ    SOUND_CONFIG_CHANGED, 0x401cb88c  | SoundConfigChangedInfo's vtable

        .extern core_store_get, core_store_set, fx_sends_chr
        .extern core_param_handle, core_param_value_h, core_param_values
        .extern fx_sends_pre, fx_sends_spd, fx_sends_dep, fx_sends_wid
        .extern fx_sends_fdb, fx_sends_hpf, fx_sends_vol
        .equ    FX_TRACK,       12
        .equ    LIVE_KITS,      0x412558e3        | the kits as edited
        .equ    LIVE_KIT_SIZE,  2531
        .equ    WORKING_KIT,    0x405c8f20+0x19d3f7 | the working kit's index, a long, unaligned
        .equ    PARAM_NONE,     0x80000000        | CORE_PARAM_NONE

        .text

        | ==================================================================
        | The audio
        | ==================================================================

        | ------------------------------------------------------------------
        | fx_gate(rx) - both calls to the stock FX block come here. Runs it,
        | then the bus and the chorus. C convention.
        | Frame: 0..47 saved registers and MACSR; the caller's rx at 52.
        | ------------------------------------------------------------------
        .globl  fx_sends_fx_gate
        .align  2
fx_sends_fx_gate:
        move.l  4(%sp),-(%sp)
        jsr     STOCK_FX
        addq.l  #4,%sp
        lea     -48(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        move.l  %macsr,%d0
        move.l  %d0,44(%sp)
        bsr.w   chr_read                          | core's C, before the MAC mode changes
        bsr.w   cho_read
        move.l  #0xa0,%macsr                      | as the stock FX: fractional, saturating
        lea     st,%a6

        | the send targets, from each voice's owning track, every 8th block
        | (5 ms; chr_read refreshes a voice every 8th block too); the walk
        | over the voices is the mod's one cost while nothing sends. The
        | coefficients glide toward them every block while any send is on or
        | still settling, and ramp sample by sample inside the block.
        subq.l  #1,ST_CDIV(%a6)
        bpl.s   11f
        moveq   #7,%d0
        move.l  %d0,ST_CDIV(%a6)
        bsr.w   coefs_build                       | d0 = non-zero if any send
        move.l  %d0,ST_ANY(%a6)
11:     move.l  ST_ANY(%a6),%d0
        or.l    ST_NACT(%a6),%d0
        beq.s   12f
        bsr.w   coefs_glide
12:     tst.l   ST_ANY(%a6)
        beq.s   2f
        move.l  #TAIL_BLOCKS,%d0
        move.l  %d0,ST_TAIL(%a6)
        bra.s   3f
2:      move.l  ST_TAIL(%a6),%d0
        beq.s   98f                               | idle
        subq.l  #1,ST_TAIL(%a6)
3:      move.l  52(%sp),%a5                       | rx
        bsr.w   buses_mix
        bsr.w   chorus_run
        moveq   #-1,%d0                           | the return has something
        move.b  %d0,ST_RET(%a6)
        bra.s   99f
98:     clr.b   ST_RET(%a6)
99:     move.l  44(%sp),%d0
        move.l  %d0,%macsr
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     48(%sp),%sp
        rts

        | ------------------------------------------------------------------
        | ret_gate(idx) - both calls to the stock return mixer come here. Runs
        | it, then adds this mod's return (made by the last fx_gate, the same
        | one-block lag as the stock returns) into the PRE words of the output
        | frames at (idx << 11) + 0x80000000, kept as stock keeps them: the
        | 24-bit value in the low bytes (lsr.l #8 of the Q31 sum).
        | ------------------------------------------------------------------
        .globl  fx_sends_ret_gate
        .align  2
fx_sends_ret_gate:
        move.l  4(%sp),-(%sp)
        jsr     STOCK_RET
        addq.l  #4,%sp
        lea     st,%a0
        tst.b   ST_RET(%a0)
        bne.s   1f
        rts
1:      lea     -28(%sp),%sp
        movem.l %d2-%d6/%a2,(%sp)
        move.l  %macsr,%d0
        move.l  %d0,24(%sp)
        move.l  #0xa0,%macsr
        movclr.l %acc0,%d0
        | g = (2 * VOL * FX level)^2, VOL and the level 8.8 - the stock form
        lea     globals,%a0
        mvz.b   G_VOL(%a0),%d0                    | VOL
        lsl.l   #8,%d0
        add.l   %d0,%d0
        mvs.w   FX_LEVEL,%d1
        muls.l  %d1,%d0
        mac.l   %d0,%d0,%acc0
        movclr.l %acc0,%d3                        | g, Q31
        move.l  32(%sp),%d0                       | idx
        moveq   #11,%d1
        lsl.l   %d1,%d0
        add.l   #0x80000000+OUT_PRE,%d0
        move.l  %d0,%a1
        lea     outb,%a2
        moveq   #FRAMES,%d6
2:      move.l  (%a2)+,%d0                        | L
        mac.l   %d3,%d0,%acc0
        movclr.l %acc0,%d0
        move.l  (%a1),%d1
        lsl.l   #8,%d1                            | back to Q31
        sub.l   %d0,%d1                           | stock writes -(g * return)
        sats.l  %d1
        lsr.l   #8,%d1
        move.l  %d1,(%a1)+
        move.l  (%a2)+,%d0                        | R
        mac.l   %d3,%d0,%acc0
        movclr.l %acc0,%d0
        move.l  (%a1),%d1
        lsl.l   #8,%d1
        sub.l   %d0,%d1
        sats.l  %d1
        lsr.l   #8,%d1
        move.l  %d1,(%a1)+
        lea     OUT_STRIDE-8(%a1),%a1
        subq.l  #1,%d6
        bne.s   2b
        move.l  24(%sp),%d0
        move.l  %d0,%macsr
        movem.l (%sp),%d2-%d6/%a2
        lea     28(%sp),%sp
        rts

        | ------------------------------------------------------------------
        | chr_read() - one voice a block, in turn: its owning track's CHR as
        | stock would play it (the sound's, the trig's p-lock, the scene's lock,
        | smoothed, plus the performances, the routes and the LFO;
        | core_param_value_h, 8.8) into
        | chr_trk, rounded to 0..127. The handle is looked up on the first call.
        | C convention; clobbers d0/d1/a0/a1.
        | ------------------------------------------------------------------
        .align  2
chr_read:
        lea     chr_h,%a0
        move.l  (%a0),%d0
        bne.s   1f
        move.l  #fx_sends_chr,-(%sp)
        jsr     core_param_handle
        addq.l  #4,%sp
        lea     chr_h,%a0
        move.l  %d0,(%a0)
        beq.s   9f                                | no lock code: chr_trk from the tick
1:      move.l  %d2,-(%sp)
        lea     chr_rr,%a0
        mvz.b   (%a0),%d1
        addq.l  #1,%d1
        moveq   #VOICES-1,%d2
        and.l   %d1,%d2
        move.b  %d2,(%a0)
        lea     VOICE_OWNER,%a0
        mvz.b   (%a0,%d2.l),%d2                   | d2 = the voice's track
        moveq   #TRACKS-1,%d1
        cmp.l   %d1,%d2
        bhi.s   8f
        clr.l   -(%sp)                            | flags
        move.l  chr_h,-(%sp)                      | handle
        move.l  %d2,-(%sp)                        | track
        jsr     core_param_value_h
        lea     12(%sp),%sp
        cmp.l   #PARAM_NONE,%d0
        beq.s   8f
        add.l   #128,%d0                          | rounded to whole steps
        asr.l   #8,%d0
        bpl.s   2f
        moveq   #0,%d0
2:      moveq   #127,%d1
        cmp.l   %d1,%d0
        ble.s   3f
        move.l  %d1,%d0
3:      lea     chr_trk,%a0
        move.b  %d0,(%a0,%d2.l)
8:      move.l  (%sp)+,%d2
9:      rts

        | ------------------------------------------------------------------
        | cho_read() - while the chorus runs (a track sends, or its tail),
        | the seven settings as stock would play them on the FX track (the
        | kit's, the FX trig's p-lock, the scene's lock, smoothed, plus the
        | performances and the FX LFO; core_param_values, 8.8) into globals,
        | rounded to 0..127. Handles on the first call. C convention;
        | clobbers d0/d1/a0/a1.
        | ------------------------------------------------------------------
        .align  2
cho_read:
        lea     st,%a0
        tst.l   ST_ANY(%a0)
        bne.s   1f
        tst.l   ST_TAIL(%a0)
        beq.w   9f                                | idle: nothing reads them
1:      lea     cho_h,%a0
        tst.l   (%a0)
        bne.s   3f
        move.l  %d2,-(%sp)
        moveq   #0,%d2
2:      lea     cho_fields,%a0
        move.l  (%a0,%d2.l*4),-(%sp)
        jsr     core_param_handle
        addq.l  #4,%sp
        lea     cho_h,%a0
        move.l  %d0,(%a0,%d2.l*4)
        addq.l  #1,%d2
        moveq   #KNOBS-1,%d0
        cmp.l   %d0,%d2
        bne.s   2b
        move.l  (%sp)+,%d2
        lea     cho_h,%a0
        tst.l   (%a0)
        beq.w   9f                                | no codes: the chorus keeps its last
3:      pea     cho_out
        clr.l   -(%sp)                            | flags
        pea     KNOBS-1                           | n
        pea     cho_h
        pea     FX_TRACK
        jsr     core_param_values
        lea     20(%sp),%sp
        lea     cho_out,%a0
        lea     globals,%a1
        moveq   #KNOBS-1,%d1
4:      move.l  (%a0)+,%d0
        cmp.l   #PARAM_NONE,%d0
        beq.s   6f
        add.l   #128,%d0
        asr.l   #8,%d0
        bpl.s   5f
        moveq   #0,%d0
5:      cmp.l   #127,%d0
        ble.s   7f
        moveq   #127,%d0
7:      move.b  %d0,(%a1)
6:      addq.l  #1,%a1
        subq.l  #1,%d1
        bne.s   4b
9:      rts

        | ------------------------------------------------------------------
        | coefs_build(a6 = st) -> d0 non-zero if any track sends. Per physical
        | voice, its owning track's CHR (chr_trk) as a target coefficient,
        | CHR^2 * K. Clobbers d0-d7/a0-a4.
        | ------------------------------------------------------------------
        .align  2
coefs_build:
        moveq   #0,%d7                            | any target
        moveq   #0,%d6                            | voice
        lea     ST_TGT(%a6),%a2
        lea     VOICE_OWNER,%a4
        lea     chr_trk,%a1
1:      moveq   #0,%d4                            | target
        mvz.b   (%a4,%d6.l),%d0
        moveq   #TRACKS-1,%d1
        cmp.l   %d1,%d0
        bhi.s   3f
        mvz.b   (%a1,%d0.l),%d1                   | CHR
        mulu.w  %d1,%d1
        move.l  #COEF_K,%d4
        mulu.l  %d1,%d4
        or.l    %d4,%d7
3:      move.l  %d4,(%a2)+
        addq.l  #1,%d6
        moveq   #VOICES,%d0
        cmp.l   %d0,%d6
        bne.s   1b
        move.l  %d7,%d0
        rts

        | ------------------------------------------------------------------
        | coefs_glide(a6 = st) -> d0 = sending voices. Each voice's coefficient
        | follows its target through two one-pole stages, an eighth of the way
        | a block each (no zipper when an LFO or a lock moves CHR fast: the
        | targets step every 8th block), and settles to zero once the target
        | is zero and both stages are tiny. The voices with a coefficient at
        | either end of the block go into the active list with the block-start
        | value and a per-frame step, so buses_mix ramps it sample by sample.
        | Clobbers d0-d6/a0-a4.
        | ------------------------------------------------------------------
        .align  2
coefs_glide:
        moveq   #0,%d6                            | voice
        lea     ST_TGT(%a6),%a1
        lea     ST_S1(%a6),%a2
        lea     ST_COEF(%a6),%a4
        lea     ST_ACT(%a6),%a3
        clr.l   ST_NACT(%a6)
        lea     slot_off,%a0
1:      move.l  (%a1)+,%d4                        | target
        move.l  (%a2),%d1                         | s1 += (target - s1) / 8
        move.l  %d4,%d0
        sub.l   %d1,%d0
        asr.l   #3,%d0
        add.l   %d0,%d1
        move.l  (%a4),%d2                         | the coefficient now
        move.l  %d1,%d3                           | new = c + (s1 - c) / 8
        sub.l   %d2,%d3
        asr.l   #3,%d3
        add.l   %d2,%d3
        tst.l   %d4
        bne.s   2f
        cmp.l   #0x10000,%d1                      | target zero: settle once
        bcc.s   2f                                | both stages are tiny
        cmp.l   #0x10000,%d3
        bcc.s   2f
        clr.l   %d1
        clr.l   %d3
2:      move.l  %d1,(%a2)+
        move.l  %d3,(%a4)+
        move.l  %d2,%d0
        or.l    %d3,%d0
        beq.s   6f
        mvz.b   (%a0,%d6.l),%d0                   | active: rx offset,
        move.l  %d0,(%a3)+
        move.l  %d2,(%a3)+                        | the coefficient at frame 0,
        sub.l   %d2,%d3
        asr.l   #5,%d3                            | its step a frame (FRAMES 32)
        move.l  %d3,(%a3)+
        addq.l  #1,ST_NACT(%a6)
6:      addq.l  #1,%d6
        moveq   #VOICES,%d0
        cmp.l   %d0,%d6
        bne.s   1b
        move.l  ST_NACT(%a6),%d0
        rts

        | ------------------------------------------------------------------
        | buses_mix(a5 = rx, a6 = st): the mono chorus send bus, 32 frames.
        | Clobbers d0-d6/a0-a5.
        | ------------------------------------------------------------------
        .align  2
buses_mix:
        movclr.l %acc0,%d0                        | start from a clear accumulator
        lea     busc,%a0
        moveq   #FRAMES,%d6
        moveq   #1,%d0                            | one sending voice (the usual
        cmp.l   ST_NACT(%a6),%d0                  | case): straight down its frames
        bne.s   1f
        lea     ST_ACT(%a6),%a4
        move.l  (%a4)+,%d3
        move.l  (%a4)+,%d1                        | the coefficient
        move.l  (%a4)+,%d2                        | its step a frame
        add.l   %d3,%a5
4:      move.l  (%a5),%d0
        lea     RX_STRIDE(%a5),%a5
        mac.l   %d1,%d0,%acc0
        add.l   %d2,%d1
        movclr.l %acc0,%d3
        move.l  %d3,(%a0)+
        subq.l  #1,%d6
        bne.s   4b
        rts
1:      lea     ST_ACT(%a6),%a4
        move.l  ST_NACT(%a6),%d5
        beq.s   3f
2:      move.l  (%a4)+,%d3                        | rx offset
        move.l  (%a4),%d1                         | the coefficient
        move.l  (%a5,%d3.l),%d0                   | the voice's sample
        mac.l   %d1,%d0,%acc0
        add.l   4(%a4),%d1                        | ramped a frame on
        move.l  %d1,(%a4)
        addq.l  #8,%a4
        subq.l  #1,%d5
        bne.s   2b
3:      movclr.l %acc0,%d0
        move.l  %d0,(%a0)+
        lea     RX_STRIDE(%a5),%a5
        subq.l  #1,%d6
        bne.s   1b
        rts

        | ------------------------------------------------------------------
        | chorus_run(a6 = st): busc (mono) -> outb (stereo), wet only.
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
        mvz.b   G_HPF(%a0),%d0
        beq.s   5f
        mulu.w  %d0,%d0
        lsr.l   #1,%d0
        swap    %d0
        clr.w   %d0                               | a, Q31
        move.l  ST_HLP(%a6),%d2
        lea     busc,%a1
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
5:      mvz.b   G_SPD(%a0),%d0
        addq.l  #1,%d0
        mulu.w  %d0,%d0
        move.l  #C_RATE_K,%d1
        mulu.l  %d1,%d0
        add.l   ST_CPH(%a6),%d0
        move.l  %d0,ST_CPH(%a6)                   | the phase at the block's end
        mvz.b   G_DEP(%a0),%d5
        mulu.w  #C_DEPTH_K*2,%d5                  | depth * 2: tri (Q15) * it is 16.16
        mvz.b   G_PRE(%a0),%d3
        move.l  #C_PRE_K,%d1
        mulu.l  %d1,%d3
        add.l   #C_PRE0,%d3                       | the base delay, 16.16
        move.l  %d0,%d2                           | L at phase
        bsr.w   tri_delay
        move.l  %d2,%d4                           | delay L at the end
        mvz.b   G_WID(%a0),%d2                    | R at phase - WID * half a cycle
        move.l  #C_WID_K,%d1
        mulu.l  %d1,%d2
        neg.l   %d2
        add.l   ST_CPH(%a6),%d2
        bsr.w   tri_delay
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
        mvz.b   G_FDB(%a0),%d5                    | feedback, Q31
        mulu.w  #FB_SCALE,%d5
        swap    %d5
        clr.w   %d5
        move.l  ST_FB(%a6),%a5                    | the taps' last average
        lea     cline,%a0
        lea     busc,%a1
        lea     outb,%a2
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

        | ==================================================================
        | CHR in core-ar2's sound storage
        | ==================================================================

        | accessor_of(d0 = track) -> d0 = the track's sound accessor in the
        | active kit, or 0. Clobbers d0/d1/a0/a1.
        .align  2
accessor_of:
        move.l  %d0,-(%sp)                        | track, as the second argument
        jsr     PROJECT_SINGLETON
        move.l  %d0,%a0
        pea     PROJ_KIT(%a0)                     | the active kit
        jsr     KIT_TRACK_SOUND
        addq.l  #8,%sp
        rts

        | live_of(d0 = accessor) -> d0 = its live sound, or 0. Clobbers d0/d1/a0/a1.
        .align  2
live_of:
        tst.l   %d0
        beq.s   9f
        move.l  %d0,-(%sp)                        | the accessor is the argument
        move.l  %d0,%a0
        move.l  (%a0),%a1
        move.l  VT_STORAGE(%a1),%a1
        jsr     (%a1)
        addq.l  #4,%sp
9:      rts

        | chr_of(d0 = live sound) -> d0 = its CHR, 0..127. Clobbers d0/d1/a0/a1.
        .align  2
chr_of:
        clr.l   -(%sp)                            | index, unused for a sound
        move.l  %d0,-(%sp)                        | item: the live sound
        move.l  #fx_sends_chr,-(%sp)              | the field's descriptor, absolute
        jsr     core_store_get
        lea     12(%sp),%sp
        rts

        | sel_track() -> d0 = the selected track. Clobbers d0/d1/a0/a1.
        .align  2
sel_track:
        jsr     PROJECT_SINGLETON
        move.l  %d0,%a0
        pea     PROJ_TRACKSEL(%a0)
        jsr     TRACK_INDEX_OF
        addq.l  #4,%sp
        rts

        | ==================================================================
        | The page, through core-ar2's core_pages and core_params (C convention)
        | ==================================================================

        | knob_of(d0 = id) -> d0 = knob 0..7 or -1 (flags set)
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

        | kit_get(d0 = knob 1..7) -> d0 = its field in the working kit, 0..127
        | (0 with no kit). Clobbers d0/d1/a0/a1.
        .align  2
kit_get:
        move.l  %d0,-(%sp)
        bsr.w   cur_kit
        move.l  (%sp)+,%d1
        tst.l   %d0
        beq.s   9f
        clr.l   -(%sp)                            | index, unused for a kit
        move.l  %d0,-(%sp)                        | item: the kit
        lea     cho_fields-4,%a0
        move.l  (%a0,%d1.l*4),-(%sp)              | the field's descriptor
        jsr     core_store_get
        lea     12(%sp),%sp
9:      rts

        | value_of(d0 = knob) -> d0 = 0..127: CHR from the selected track's
        | sound, the rest from the working kit. Clobbers d0/d1/a0/a1.
        .align  2
value_of:
        tst.l   %d0
        bne.w   kit_get
        bsr.w   sel_track
        moveq   #TRACKS-1,%d1
        cmp.l   %d1,%d0
        bhi.s   8f
        bsr.w   accessor_of
        bsr.w   live_of
        tst.l   %d0
        beq.s   8f
        bra.w   chr_of
8:      moveq   #0,%d0
        rts

        | int get(long id, long *value): the knob's setting in 8.8
        .align  2
fs_get:
        move.l  4(%sp),%d0
        bsr.w   knob_of
        bmi.s   9f
        bsr.w   value_of
        lsl.l   #8,%d0
        move.l  8(%sp),%a0
        move.l  %d0,(%a0)
        moveq   #1,%d0
        rts
9:      moveq   #0,%d0
        rts

        | int delta(void *view, long id, long delta, long func): the delta in 8.8, added
        | to the knob's 8.8 value, whose whole part is the setting. The chorus
        | settings keep their fractions in acc while the kit holds acc's whole
        | part; CHR keeps one fraction, for the track it was last turned on.
        .align  2
fs_delta:
        move.l  8(%sp),%d0
        bsr.w   knob_of
        bmi.w   8f
        tst.l   %d0
        beq.w   20f
        lea     -12(%sp),%sp                      | a kit field
        movem.l %d2-%d4,(%sp)
        move.l  %d0,%d2                           | d2 = the knob
        bsr.w   cur_kit
        move.l  %d0,%d3                           | d3 = the kit
        beq.s   17f
        move.l  %d2,%d0
        bsr.w   kit_get
        move.l  %d0,%d4                           | d4 = the stored setting
        lsl.l   #8,%d0
        lea     acc,%a0
        mvz.w   (%a0,%d2.l*2),%d1
        move.l  %d1,%a1
        lsr.l   #8,%d1
        cmp.l   %d4,%d1                           | acc still on the stored step:
        bne.s   11f
        move.l  %a1,%d0                           | keep its fraction
11:     add.l   24(%sp),%d0                       | the delta
        bsr.w   clamp
        lea     acc,%a0
        move.w  %d0,(%a0,%d2.l*2)
        lsr.l   #8,%d0
        cmp.l   %d4,%d0
        beq.s   17f
        move.l  %d0,-(%sp)                        | value
        clr.l   -(%sp)                            | index
        move.l  %d3,-(%sp)                        | item: the kit
        lea     cho_fields-4,%a0
        move.l  (%a0,%d2.l*4),-(%sp)
        jsr     core_store_set
        lea     16(%sp),%sp
17:     movem.l (%sp),%d2-%d4
        lea     12(%sp),%sp
        moveq   #1,%d0
        rts

        | CHR: the selected track's sound
20:     lea     -16(%sp),%sp
        movem.l %d2-%d4/%a2,(%sp)
        bsr.w   sel_track
        move.l  %d0,%d2                           | d2 = the track
        moveq   #TRACKS-1,%d1
        cmp.l   %d1,%d0
        bhi.w   7f
        bsr.w   accessor_of
        move.l  %d0,%a2                           | a2 = the accessor
        bsr.w   live_of
        move.l  %d0,%d3                           | d3 = the live sound
        beq.w   7f
        bsr.w   chr_of
        move.l  %d0,%d4                           | d4 = the old CHR
        lsl.l   #8,%d0
        lea     chr_frac,%a0
        cmp.b   1(%a0),%d2                        | the fraction's track
        bne.s   1f
        mvz.b   (%a0),%d1
        or.l    %d1,%d0
1:      add.l   28(%sp),%d0                       | the delta
        bsr.w   clamp
        lea     chr_frac,%a0
        move.b  %d0,(%a0)
        move.b  %d2,1(%a0)
        lsr.l   #8,%d0
        lea     chr_trk,%a0
        move.b  %d0,(%a0,%d2.l)                   | the audio's copy, at once
        cmp.l   %d4,%d0
        beq.s   7f
        move.l  %d0,-(%sp)                        | value
        clr.l   -(%sp)                            | index
        move.l  %d3,-(%sp)                        | item: the live sound
        move.l  #fx_sends_chr,-(%sp)
        jsr     core_store_set
        lea     16(%sp),%sp
        | the change notice stock's sound settings setters send: without it
        | the change is lost at a reboot unless the kit is saved
        lea     -8(%sp),%sp                       | SoundConfigChangedInfo, kind 1
        move.l  #SOUND_CONFIG_CHANGED,(%sp)
        moveq   #1,%d0
        move.b  %d0,4(%sp)
        move.l  %sp,-(%sp)
        move.l  %a2,-(%sp)                        | the accessor
        move.l  (%a2),%a0
        move.l  VT_CONFIG_CHANGED(%a0),%a0
        jsr     (%a0)
        lea     16(%sp),%sp
7:      movem.l (%sp),%d2-%d4/%a2
        lea     16(%sp),%sp
        moveq   #1,%d0
        rts
8:      moveq   #0,%d0
        rts

        | clamp(d0) -> d0 within 0 .. 127 << 8
        .align  2
clamp:
        tst.l   %d0
        bpl.s   1f
        clr.l   %d0
1:      move.l  #127<<8,%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:      rts

        | int text(struct core_text *t): passes. All eight are lockable
        | parameters, whose value text core writes as a number (a held trig's
        | lock, a scene's), as 1.0 wrote it from the setting.
        .align  2
fs_text:
        moveq   #0,%d0
        rts

        | ==================================================================
        | The UI tick and the project
        | ==================================================================

        | ev_tick: once, the eight knobs' RAM records (built at boot from the
        | records patched in mod.json) take a stock dial's encoder feel and
        | its dial art, from COMP's MIX (id 94, 0..127). Every tick, each
        | track's CHR into chr_trk, which the audio reads, only while CHR has
        | no handle (chr_read reads it otherwise).
        .equ    PARAM_INFO,     0x419a4888        | RAM records, 0x54 bytes an id
        .equ    PI_STRIDE,      0x54
        .equ    PI_DRAW,        0x24              | the draw callback, 16 B
        .equ    ID_DONOR,       94
        .globl  fx_sends_tick
        .align  2
fx_sends_tick:
        lea     ready,%a0
        tst.b   (%a0)
        bne.s   5f
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
5:      tst.l   chr_h                             | the audio reads CHR itself
        bne.s   9f
        move.l  %d2,-(%sp)
        moveq   #0,%d2
6:      move.l  %d2,%d0
        bsr.w   accessor_of
        bsr.w   live_of
        tst.l   %d0
        beq.s   7f
        bsr.w   chr_of
7:      lea     chr_trk,%a0
        move.b  %d0,(%a0,%d2.l)
        addq.l  #1,%d2
        moveq   #TRACKS,%d0
        cmp.l   %d0,%d2
        bne.s   6b
        move.l  (%sp)+,%d2
9:      rts

        | ev_project(how, dropped): a project was loaded or made: the audio's
        | copies go to 0 until the next tick reads the new kit's sounds
        .globl  fx_sends_project
        .align  2
fx_sends_project:
        lea     chr_trk,%a0
        clr.l   (%a0)+
        clr.l   (%a0)+
        clr.l   (%a0)
        rts

        | ==================================================================
        | Data
        | ==================================================================
        .align  4
        .globl  fx_sends_view_page
fx_sends_view_page: .long 3, PAGE_FX, 0           | core_view_pages: CORE_VIEW_AMP, always shown
        .globl  fx_sends_view_cho
fx_sends_view_cho: .long CHORUS_VIEW, PAGE_CHO, 0  | core_view_pages: the FX track's
        .globl  fx_sends_page, fx_sends_page_cho, fx_sends_params
fx_sends_page:  .long   PAGE_FX, str_page         | core_pages: {page, name, A..D, E..H}
                .long   ID0, 0, 0, 0
                .long   0, 0, 0, 0
fx_sends_page_cho: .long PAGE_CHO, str_page_cho
                .long   ID0+1, ID0+2, ID0+3, ID0+4
                .long   ID0+5, ID0+6, ID0+7, 0
fx_sends_params: .long  ID0, ID0+KNOBS-1, fs_get, fs_delta, fs_text  | core_params
acc:            .short  0, 40<<8, 24<<8, 64<<8, 96<<8, 0, 0, 100<<8  | the turns' fractions, 8.8
globals:        .byte   40, 24, 64, 96, 0, 0, 100 | PRE SPD DEP WID FDB HPF VOL: the audio's copy
ready:          .byte   0
chr_rr:         .byte   VOICES-1                  | chr_read's last voice
        .align  4
        .globl  fx_sends_chr_param
fx_sends_chr_param:                               | core_lock_params: struct core_lock_param
                .long   fx_sends_chr, ID0         | field, the page knob's id
                .short  0, 127                    | min, max
                .long   fx_sends_str_chr, fx_sends_str_chr_l, str_cat
chr_h:          .long   0                         | CHR's handle (core_param_handle)
        | the chorus settings' fields (knobs 1..7), their lock parameters and
        | their handles
cho_fields:     .long   fx_sends_pre, fx_sends_spd, fx_sends_dep, fx_sends_wid
                .long   fx_sends_fdb, fx_sends_hpf, fx_sends_vol
        .globl  fx_sends_pre_param, fx_sends_spd_param, fx_sends_dep_param, fx_sends_wid_param
        .globl  fx_sends_fdb_param, fx_sends_hpf_param, fx_sends_vol_param
        .macro  CHO_PARAM name, field, k
fx_sends_\name\()_param:
                .long   \field, ID0+\k
                .short  0, 127
                .long   fx_sends_str_\name, fx_sends_str_\name\()_l, str_cat_cho
        .endm
        CHO_PARAM pre, fx_sends_pre, 1
        CHO_PARAM spd, fx_sends_spd, 2
        CHO_PARAM dep, fx_sends_dep, 3
        CHO_PARAM wid, fx_sends_wid, 4
        CHO_PARAM fdb, fx_sends_fdb, 5
        CHO_PARAM hpf, fx_sends_hpf, 6
        CHO_PARAM vol, fx_sends_vol, 7
cho_h:          .space  (KNOBS-1)*4               | their handles
cho_out:        .space  (KNOBS-1)*4               | core_param_values' answers
chr_frac:       .byte   0, 0xff                   | CHR's fraction, and its track
        | physical voice -> its receive-buffer offset, +8 + 4 * slot, from the
        | stock map 0x401ef480 (0, 3, 1, 4, 6, 5, 7, 2)
slot_off:       .byte   8, 20, 12, 24, 32, 28, 36, 16
        .globl  fx_sends_str_group
        .globl  fx_sends_str_chr_l, fx_sends_str_pre_l, fx_sends_str_spd_l, fx_sends_str_dep_l
        .globl  fx_sends_str_wid_l, fx_sends_str_fdb_l, fx_sends_str_hpf_l, fx_sends_str_vol_l
        .globl  fx_sends_str_chr, fx_sends_str_pre, fx_sends_str_spd, fx_sends_str_dep
        .globl  fx_sends_str_wid, fx_sends_str_fdb, fx_sends_str_hpf, fx_sends_str_vol
str_cat:        .asciz  "AMP"                     | AMP:Chorus Send, as AMP:Reverb Send
str_cat_cho:    .asciz  "CHO"                     | CHO:Chorus Speed, as DEL:, REV:
str_page_cho:   .asciz  "CHOR"
str_page:       .asciz  "SEND"                    | the page title shows 4 characters
fx_sends_str_group: .asciz "FX SENDS"
fx_sends_str_chr_l: .asciz "Chorus Send"
fx_sends_str_pre_l: .asciz "Chorus Pre-Delay"
fx_sends_str_spd_l: .asciz "Chorus Speed"
fx_sends_str_dep_l: .asciz "Chorus Depth"
fx_sends_str_wid_l: .asciz "Chorus Width"
fx_sends_str_fdb_l: .asciz "Chorus Feedback"
fx_sends_str_hpf_l: .asciz "Chorus High-Pass"
fx_sends_str_vol_l: .asciz "Chorus Level"
fx_sends_str_chr: .asciz "CHR"
fx_sends_str_pre: .asciz "PRE"
fx_sends_str_spd: .asciz "SPD"
fx_sends_str_dep: .asciz "DEP"
fx_sends_str_wid: .asciz "WID"
fx_sends_str_fdb: .asciz "FDB"
fx_sends_str_hpf: .asciz "HPF"
fx_sends_str_vol: .asciz "VOL"
        .align  2

        .bss
        .align  4
st:             .space  ST_SIZE
chr_trk:        .space  TRACKS                    | each track's CHR, for the audio
        .align  4
cline:          .space  (CMASK+1)*4               | the chorus line
busc:           .space  FRAMES*4                  | the chorus send
outb:           .space  FRAMES*8                  | the return, 32 stereo frames
