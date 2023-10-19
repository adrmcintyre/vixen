alias r14 link
alias r15 pc

org 0x0000
.user_program
;   ; result should be (r2,r0) = (0x016d, 0x0030)
;   mov r0, #hi(53703)
;   add r0, #lo(53703)
;   mov r1, #hi(147)
;   add r1, #lo(147)
;   bl .math_udiv16fast
;   hlt

;  .here
;      ldw r0, [pc,#.args-.here-2]
;      ldw r1, [pc,#.args-.here-2]
;      ldw r2, [pc,#.args-.here-2]
;      ldw r3, [pc,#.args-.here-2]
;      bl .math_mul32x32
;      bra .verify
;  .args
;      dw 0x7f1a,0x38dd, 0x5693,0xb08c
;  .verify
;      ldw r0, [pc,#.expect-.verify-2]
;      ldw r1, [pc,#.expect-.verify-2]
;      sub r5, r1
;      sbc r4, r0
;      hlt
;  .expect
;      dw 0x6e56,0x08dc

    mov r13, #hi(.udiv32_test_vectors)
    add r13, #lo(.udiv32_test_vectors)
.test_loop
    ldw r0, [r13,#0]
    ldw r1, [r13,#2]
    ldw r2, [r13,#4]
    ldw r3, [r13,#6]
    orr r2, r2
    preq
    orr r3, r3
    preq
    hlt
    bl .math_udiv32_fast
    ldw r8,  [r13,#8]
    ldw r9,  [r13,#10]
    ldw r10, [r13,#12]
    ldw r11, [r13,#14]
    cmp r8, r4
    preq
    cmp r9, r5
    preq
    cmp r10, r0
    preq
    cmp r11, r1
    prne
    hlt
    add r13, #16
    bra .test_loop

.udiv32_test_vectors
    ;;  uhi    ulo      vhi    vlo      qhi    qlo      rhi    rlo
    dw  0xffd0,0x9c8e,  0x0003,0x7087,  0x0000,0x4a5f,  0x0002,0xd475
    dw  0xff94,0xbb00,  0x0000,0x532a,  0x0003,0x12be,  0x0000,0x0dd4
    dw  0xff81,0xa5a2,  0x0024,0x4a64,  0x0000,0x070a,  0x000e,0x01ba
    dw  0xf019,0x2d64,  0x1900,0xb281,  0x0000,0x0009,  0x0f12,0xe6db
    dw  0xe254,0x25da,  0x0000,0x001d,  0x07cd,0xefa6,  0x0000,0x000c
    dw  0xd925,0x973c,  0x024f,0x405f,  0x0000,0x005e,  0x000b,0xf45a
    dw  0xd032,0x3d36,  0x1477,0xda18,  0x0000,0x000a,  0x0383,0xb846
    dw  0xcd40,0x2cb1,  0x0000,0x0002,  0x66a0,0x1658,  0x0000,0x0001
    dw  0xb75a,0x2731,  0x0003,0x8c43,  0x0000,0x33ad,  0x0003,0x04ea
    dw  0xb464,0xe4e4,  0x0000,0xc28a,  0x0000,0xed62,  0x0000,0xaa10
    dw  0xa67e,0xbefb,  0x0024,0x5096,  0x0000,0x0495,  0x0019,0x7fad
    dw  0xa58d,0x96a9,  0x0000,0x0036,  0x0310,0xd81f,  0x0000,0x001f
    dw  0xa4cc,0x69ec,  0x01ce,0x74de,  0x0000,0x005b,  0x0068,0xdf02
    dw  0x9808,0x081a,  0x0000,0x0c92,  0x000c,0x182f,  0x0000,0x094c
    dw  0x92c6,0xbea8,  0x21ef,0x12f4,  0x0000,0x0004,  0x0b0a,0x72d8
    dw  0x92c3,0xb25c,  0x0000,0x003b,  0x027c,0xcef4,  0x0000,0x0020
    dw  0x91d9,0x823d,  0x0008,0x8e89,  0x0000,0x110b,  0x0004,0x495a
    dw  0x90c3,0xe9de,  0x6010,0x4a41,  0x0000,0x0001,  0x30b3,0x9f9d
    dw  0x9099,0x0aa5,  0x0000,0x003c,  0x0268,0xf360,  0x0000,0x0025
    dw  0x8272,0xded6,  0x000d,0x02d7,  0x0000,0x0a06,  0x0008,0x67cc
    dw  0x7d4f,0x995c,  0xe9f8,0x879d,  0x0000,0x0000,  0x7d4f,0x995c
    dw  0x6fd1,0x1874,  0x0000,0x0002,  0x37e8,0x8c3a,  0x0000,0x0000
    dw  0x638c,0x1fd9,  0x0000,0x0064,  0x00fe,0xd75b,  0x0000,0x004d
    dw  0x6028,0xa7d0,  0x0000,0x1064,  0x0005,0xdddf,  0x0000,0x0cb4
    dw  0x5037,0x7a4f,  0xef1c,0xad88,  0x0000,0x0000,  0x5037,0x7a4f
    dw  0x4251,0xca07,  0x0001,0x1492,  0x0000,0x3d63,  0x0000,0x0b91
    dw  0x3a85,0xb4be,  0x7b31,0xde32,  0x0000,0x0000,  0x3a85,0xb4be
    dw  0x274f,0xb70d,  0x0000,0x0256,  0x0010,0xd436,  0x0000,0x00e9
    dw  0x26a6,0x4883,  0x7021,0xa7df,  0x0000,0x0000,  0x26a6,0x4883
    dw  0x23f6,0x097b,  0x0027,0xcfcf,  0x0000,0x00e7,  0x0009,0x85b2
    dw  0x144c,0x942a,  0x0000,0x0173,  0x000e,0x01c7,  0x0000,0x00c5
    dw  0x0aa8,0x4949,  0x0000,0x03a2,  0x0002,0xef03,  0x0000,0x0063
    dw  0x0000,0x0000,  0x0000,0x0000,  0x0000,0x0000,  0x0000,0x0000

; 32 bit division
; worst case: 412 instrs
; could reduce to 387 with full unrolling
.math_udiv32 {
    alias r0 den_hi
    alias r1 den_lo
    alias r2 num_hi
    alias r3 num_lo
    alias r4 rem_hi
    alias r5 rem_lo
    alias r6 i

    mov rem_hi, #0
    mov rem_lo, #0
    mov i, #32
.loop
    asl den_lo, #1
    adc den_hi, den_hi
    adc rem_lo, rem_lo
    adc rem_hi, rem_hi
    sub rem_lo, num_lo
    sbc rem_hi, num_hi
    prhs
    orr den_lo, #1
    prhs
    bra .skip1
    add rem_lo, num_lo
    adc rem_hi, num_hi
.skip1
    asl den_lo, #1
    adc den_hi, den_hi
    adc rem_lo, rem_lo
    adc rem_hi, rem_hi
    sub rem_lo, num_lo
    sbc rem_hi, num_hi
    prhs
    orr den_lo, #1
    prhs
    bra .skip2
    add rem_lo, num_lo
    adc rem_hi, num_hi
.skip2
    asl den_lo, #1
    adc den_hi, den_hi
    adc rem_lo, rem_lo
    adc rem_hi, rem_hi
    sub rem_lo, num_lo
    sbc rem_hi, num_hi
    prhs
    orr den_lo, #1
    prhs
    bra .skip3
    add rem_lo, num_lo
    adc rem_hi, num_hi
.skip3
    asl den_lo, #1
    adc den_hi, den_hi
    adc rem_lo, rem_lo
    adc rem_hi, rem_hi
    sub rem_lo, num_lo
    sbc rem_hi, num_hi
    prhs
    orr den_lo, #1
    prhs
    bra .skip4
    add rem_lo, num_lo
    adc rem_hi, num_hi
.skip4
    sub i, #4
    prne
    bra .loop

    mov pc, link
}

; 32 bit x 32 bit multiply with 32 bit result
; 8 instructions
.math_mul32x32 {
    alias r0 uh
    alias r1 ul
    alias r2 vh
    alias r3 vl
    alias r4 qh
    alias r5 ql

    mul vh, ul      ; vh = ul*vh
    mul uh, vl      ; uh = uh*vl
    add uh, vh      ; uh = ul*vh + uh*vl

    mov ql, vl
    mov qh, vl
    mul ql, r1      ; ql = lo(ul*vl)
    muh qh, r1      ; qh = hi(ul*vl)

    add qh, uh      ; (qh,ql) = (ul*vh + uh*vl) << 16 + ul*vl

    mov pc, link
}

; 16-bit by 16-bit multiply with 32-bit result
; 4 instructions
.math_mul16x16 {
    alias r0 u
    alias r1 v
    alias r2 q_hi
    alias r3 q_lo

    mov q_lo, u
    mov q_hi, u
    mul q_lo, v
    muh q_hi, v

    mov pc, link
}

; 16-bit by 16-bit division with 16-bit quotient and remainder
; Instruction count: 22-30
.math_udiv16 {
    ; TODO - some of these registers can surely be dual purposed
    alias r0 u
    alias r1 v
    alias r2 q
    alias r2 v1
    alias r3 q_lo
    alias r4 r
    alias r5 n

    ; Calculate estimate of quotient using lookup table.

    ; shift v1 up until top bit set
    clz n, v                        ; count leading zeros
    mov v1, v
    lsl v1, n

    lsr v1, #8                      ; get top 8 bits
    lsl v1, #1                      ; convert to table offset
    mov r, #hi(.recip_7i_16o-0x100)   ; correct for bit 8 always being set
    add r, #lo(.recip_7i_16o-0x100)
    add r, v1
    ldw r, [r]
    
    mov q, u
    muh q, r ; q = ((uint32_t)u * r) >> 16;
    
    mov q_lo, #15
    sub q_lo, n
    lsr q, q_lo     ; q >>= 15-n; // Undo normalization of v

    prne            ; if (q > 0) --q; // Adjust guess down to avoid possible overflow
    sub q, #1

    mov n, q        ; u -= q * v; // Calculate remainder to u
    mul n, v
    sub u, n

    ; Final correction of quotient to satisfy division theorem.
    
    cmp u, v        ; if (u >= v)   // Failed to satisfy division theorem?
    prlo
    mov pc, link
    
    add q, #1       ; ++q;      // Adjust quotient and remainder.
    sub u, v        ; u -= v;

    cmp u, v        ; if (u >= v) ++q; // Failed again?
    prlo
    mov pc, link

    add q, #1
    sub u, v
    mov pc, link

.recip_7i_16o
    ; 256 bytes
    ; recip_7i_16o[i] = 0x007fffff / (0x80+i)
    dw 0xFFFF, 0xFE03, 0xFC0F, 0xFA23, 0xF83E, 0xF660, 0xF489, 0xF2B9
    dw 0xF0F0, 0xEF2E, 0xED73, 0xEBBD, 0xEA0E, 0xE865, 0xE6C2, 0xE525
    dw 0xE38E, 0xE1FC, 0xE070, 0xDEE9, 0xDD67, 0xDBEB, 0xDA74, 0xD901
    dw 0xD794, 0xD62B, 0xD4C7, 0xD368, 0xD20D, 0xD0B6, 0xCF64, 0xCE16
    dw 0xCCCC, 0xCB87, 0xCA45, 0xC907, 0xC7CE, 0xC698, 0xC565, 0xC437
    dw 0xC30C, 0xC1E4, 0xC0C0, 0xBFA0, 0xBE82, 0xBD69, 0xBC52, 0xBB3E
    dw 0xBA2E, 0xB921, 0xB817, 0xB70F, 0xB60B, 0xB509, 0xB40B, 0xB30F
    dw 0xB216, 0xB11F, 0xB02C, 0xAF3A, 0xAE4C, 0xAD60, 0xAC76, 0xAB8F
    dw 0xAAAA, 0xA9C8, 0xA8E8, 0xA80A, 0xA72F, 0xA655, 0xA57E, 0xA4A9
    dw 0xA3D7, 0xA306, 0xA237, 0xA16B, 0xA0A0, 0x9FD8, 0x9F11, 0x9E4C
    dw 0x9D89, 0x9CC8, 0x9C09, 0x9B4C, 0x9A90, 0x99D7, 0x991F, 0x9868
    dw 0x97B4, 0x9701, 0x964F, 0x95A0, 0x94F2, 0x9445, 0x939A, 0x92F1
    dw 0x9249, 0x91A2, 0x90FD, 0x905A, 0x8FB8, 0x8F17, 0x8E78, 0x8DDA
    dw 0x8D3D, 0x8CA2, 0x8C08, 0x8B70, 0x8AD8, 0x8A42, 0x89AE, 0x891A
    dw 0x8888, 0x87F7, 0x8767, 0x86D9, 0x864B, 0x85BF, 0x8534, 0x84A9
    dw 0x8421, 0x8399, 0x8312, 0x828C, 0x8208, 0x8184, 0x8102, 0x8080
}

// TODO entry to save/restore regs
// TODO signed versions
.math_udiv32_fast {
    ;
    ; Requires approx 107 instructions compared to
    ; around 412 instructions for naive method.
    ;
    alias r0  uh
    alias r1  ul
    alias r2  vh
    alias r3  vl
    alias r4  qh
    alias r5  ql
    alias r6  vh0
    alias r7  vl0
    alias r8  rh
    alias r9  rl
    alias r10 n
    alias r11 th
    alias r12 tl
    
    mov vh0, vh     ; v0 = v
    mov vl0, vl
    
    ;; Compute inverse of v

    ;; n = clz32(v), and v <<= n
    ;; where v = vh:vl
    clz n, vh       ; n = clz16(vh);
    mov th, #16     ; th = 16;
    tst n, #bit 4   ; if (n == th) {
    preq
    bra .else
    clz n, vl       ;    n = clz16(vl);
    mov vh, vl      ;    vh = vl;
    lsl vh, n       ;    vh = vh << n;
    mov vl, #0      ;    vl = 0;
    add n, th       ;    n = n + th;
    bra .done
.else               ; else {
    lsl vh, n       ;    vh = vh << n;
    rsb n, th       ;    n = th - n;
    mov tl, vl      ;    tl = vl;
    lsr tl, n       ;    tl = tl >> n;
    orr vh, tl      ;    vh = vh | tl;
    rsb n, th       ;    n = th - n;
    lsl vl, n       ;    vl = vl << n;
.done               ; }

    ;; TODO - if we're keeping math_udiv16 around, we can
    ;; surely just reuse recip_7i_16o instead of having
    ;; our own table.
    ;;
    ;; recip_0 = approx_recip(vh) = 0x3fff / vh[15:9]
    ;; where recip_0 = rh:00
    mov rh, vh      ; rh = vh;
    lsr rh, #9      ; rh = rh >> 9;
    mov th, #hi(.recip_6i_8o-0x40)
    add th, #lo(.recip_6i_8o-0x40)
    add th, rh
    ldb rh, [th]    ; rh = (u32)recip_6i_8o[rh-0x40];
    lsl rh, #8      ; rh = rh << 8;

    ;; Improve approximation with low precision Newton Raphson
    ;;
    ;; temp_0 = mul_hi_approx_bad(recip_0, vh)
    ;; where temp_0 = th:00
    ;;       recip_0 = rh:00
    ;;       v = vh:00
    mov th, rh      ; th = rh;
    muh th, vh      ; th = hi((u32) th * vh);

    ;; temp_0 = 0u - temp_0
    mov rl, #0      ; (rl used as temporary zero)
    rsb th, rl      ; th = -th

    ;; recip_1 = mul_hi_approx_bad(recip_0, temp_0) = recip_0 * temp_0
    ;; where temp_1 = qh:ql
    ;;       temp_0 = th:00
    ;;       recip_0 = rh:00
    mov qh, th      ; qh = th;
    muh qh, rh      ; qh = hi((u32) qh * rh);
    mov ql, rh      ; ql = rh;
    mul ql, th      ; ql = lo((u32) ql * th);

    ;; recip_1 <<= 1
    ;; where recip_1 = qh:ql
    add ql, ql
    adc qh, qh      ; qh:ql <<= 1

    ;; Second Newton Raphson iteration, at higher precision

    ;; temp_1 = mul_hi_approx(recip_1, v)
    ;; where temp_1 = th:tl
    ;;       recip_1 = qh:ql
    ;;       v = vh:vl
    mov th, qh      ; th = qh;
    muh th, vh      ; th = hi((u32) th * vh);
    mov tl, ql      ; tl = ql;
    muh tl, vh      ; tl = hi((u32) tl * vh);
    mov rh, vh      ; rh = vh
    mul rh, qh      ; rh = lo((u32) rh * qh);
    muh vl, qh      ; vl = hi((u32) vl * qh);

    add tl, vl      ; th:tl += 0:vl
    adc th, rl      ; (rl still zero from earlier)

    add tl, rh      ; th:tl += 0:rh
    adc th, rl      ; (rl still zero from earlier)

    ;; temp_1 = 0u - temp_1
    ;; where temp_1 = th:tl
    rsb tl, rl      ; th:tl = -th:tl
    rsc th, rl      ; (rl still zero from earlier)

    ;; recip_2 = mul_hi_approx(recip_1, temp_1)
    ;; where
    ;;      recip_2 = rh:rl
    ;;      recip_1 = qh:ql
    ;;      temp_1 = th:tl
    muh ql, th      ; ql = hi((u32) ql * th);
    muh tl, qh      ; tl = hi((u32) tl * qh);
    mov rh, qh      ; rh = qh;
    muh rh, th      ; rh = hi((u32) rh * th);
    mul qh, th      ; qh = lo((u32) qh * th);

    mov th, #0
    mov rl, qh      ; rl = qh;
    add rl, tl      ; rh:rl += tl;
    adc rh, th
    add rl, ql      ; rh:rl += ql;
    add rh, th

    ;; recip_2 <<= 1
    ;; where recip_2 = rh:rl
    add rl, rl      ; rh:rl <<= 1;
    adc rh, rh

    ;; End of Newton-Raphson reciprocal calculation

    ;; Calculate quotient estimate
    ;; q = mul_hi_approx(u, recip_2)
    ;; where
    ;;      q = qh:ql
    ;;      u = uh:ul
    ;;      recip_2 = rh:rl
    mov ql, ul      ; ql = ul;
    muh ql, rh      ; ql = hi((u32) ql * rh);
    muh rl, uh      ; rl = hi((u32) rl * uh);

    mov qh, uh      ; qh = uh;
    muh qh, rh      ; qh = hi((u32) qh * rh);
    mul rh, uh      ; rh = lo((u32) rh * uh);

    add ql, rl      ; qh:ql += rl
    adc qh, th      ; (th still zero from earlier)
    add ql, rh      ; qh:ql += rh
    adc qh, th      ; (th still zero from earlier)

    ;; Undo normalisation
    ;; q >>= (31-n)
    ;; where q = qh:ql
    mov tl, #31     ; tl = 31;
    rsb n, tl       ; n = tl - n;
    mov tl, #16     ; tl = 16;

    cmp n, tl       ; if (n >= tl) {
    prlo
    bra .undo_else
    sub n, tl       ;     n = n - tl;
    mov ql, qh      ;     ql = qh;
    mov qh, #0      ;     qh = 0;
    lsr ql, n       ;     ql = ql >> n;

    ;; Adjust quotient down to prevent potential overflow,
    ;; and avoid "one too high" error in prior calculation.
    ;; if (q>0) q -= 1;
    prne            ;
    sub ql, #1      ;     if (ql != 0) ql = ql - 1;
    bra .undo_end   ; }
.undo_else          ; else {
    lsr ql, n       ;     ql = ql >> n;
    rsb n, tl       ;     n = tl - n;
    mov th, qh
    lsl th, n       ;     th = qh << n;
    rsb n, tl       ;     n = tl - n;
    lsr qh, n       ;     qh = qh >> n;
    orr ql, th      ;     ql = ql | th;

    ;; Adjust quotient down to prevent potential overflow,
    ;; and avoid "one too high" error in prior calculation.
    ; if (q>0) q -= 1;
    prne            ;     if (ql == 0) {    
    bra .dec_ql
    sub qh, #1      ;         qh -= 1;          // we know ql == 0
    prhs            ;         if no borrow {    // i.e. qh was > 0, so qh:ql was != 0
    bra .dec_ql     ;             ql -= 1;      // safe to decrement
    mov qh, #0      ;         } else qh = 0;    // qh:ql were == 0: restore qh; ql is still 0
    bra .undo_end   ;     }
.dec_ql
    sub ql, #1      ;     else ql -= 1;         // qh or ql must have been > 0
.undo_end           ; }
    
    ; restore v
    mov vh, vh0     ; vh = vh0;
    mov vl, vl0     ; vl = vl0;

    ;; Calculate remainder
    ;;
    ;; Step 1: temp = q * v
    ;; where
    ;;      temp = th:tl
    ;;      q = qh:ql
    ;;      v = vh:vl

    mov th, ql      ; th = ql;
    muh th, vl      ; th = hi((u32) th * vl);

    mov n, ql       ; n = ql
    mul n, vh       ; n = lo((u32) n * vh);
    add th, n       ; th += n;

    mov n, qh       ; n = qh
    mul n, vl       ; n = lo((u32) n * vl);
    add th, n       ; th += n;

    mov tl, ql      ; tl = ql;
    mul tl, vl      ; tl = lo((u32) tl * vl);

    ;; Step 2: u -= temp
    ;; where
    ;;      u = uh:ul
    ;;      temp = th:tl
    sub ul, tl      ; uh:ul -= th:tl
    sbc uh, th

    ;; Quotient may be too low - adjust until correct.
    ;; Max 3 iterations required.
    ;;
    ;; while(u >= v) u -= v, q += 1;
    
    ;; we could save around 0.7 of an instruction on average by
    ;; unrolling this loop 3 times - not really worth it.
    mov tl, #0      ; tl = 0
.adj_loop           ; while(1) {
    sub ul, vl      ;     uh:ul -= vh:vl
    sbc uh, vh      ;
    prcc 
    bra .adj_break  ;     if (borrowed) break;
    add ql, #1      ;     qh:ql += 1;
    adc qh, tl      ;
    bra .adj_loop   ; }
.adj_break
    add ul, vl      ; uh:ul += vh:vl
    adc uh, vh

    mov pc, link

.recip_6i_8o
    ;; 64 bytes
    ; recip_6i_8o[i] = 0x3fff / (0x40+i)
    db 0xFF, 0xFC, 0xF8, 0xF4
    db 0xF0, 0xED, 0xEA, 0xE6
    db 0xE3, 0xE0, 0xDD, 0xDA
    db 0xD7, 0xD4, 0xD2, 0xCF
    db 0xCC, 0xCA, 0xC7, 0xC5
    db 0xC3, 0xC0, 0xBE, 0xBC
    db 0xBA, 0xB8, 0xB6, 0xB4
    db 0xB2, 0xB0, 0xAE, 0xAC
    db 0xAA, 0xA8, 0xA7, 0xA5
    db 0xA3, 0xA2, 0xA0, 0x9F
    db 0x9D, 0x9C, 0x9A, 0x99
    db 0x97, 0x96, 0x94, 0x93
    db 0x92, 0x90, 0x8F, 0x8E
    db 0x8D, 0x8C, 0x8A, 0x89
    db 0x88, 0x87, 0x86, 0x85
    db 0x84, 0x83, 0x82, 0x81
}


