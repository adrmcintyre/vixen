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

.here
    ldw r0, [pc,#.args-.here-2]
    ldw r1, [pc,#.args-.here-2]
    ldw r2, [pc,#.args-.here-2]
    ldw r3, [pc,#.args-.here-2]
    bl .math_mul32x32
    bra .verify
.args
    dw 0x7f1a,0x38dd, 0x5693,0xb08c
.verify
    ldw r0, [pc,#.expect-.verify-2]
    ldw r1, [pc,#.expect-.verify-2]
    sub r3, r1
    sbc r2, r0
    hlt
.expect
    dw 0x6e56,0x08dc

; 16 bit division
;   - 127 instructions
;   - 163 for non-unrolled version
;   - fully unrolled would be 115
.math_udiv16 {
    alias r0 den
    alias r1 num
    alias r2 rem
    alias r3 i

    mov rem, #0
    mov i, #16
    ; unroll loop 4 times
.loop
    asl den, #1
    adc rem, rem
    cmp rem, num
    prhs
    sub rem, num
    prhs
    orr den, #1

    asl den, #1
    adc rem, rem
    cmp rem, num
    prhs
    sub rem, num
    prhs
    orr den, #1

    asl den, #1
    adc rem, rem
    cmp rem, num
    prhs
    sub rem, num
    prhs
    orr den, #1

    asl den, #1
    adc rem, rem
    cmp rem, num
    prhs
    sub rem, num
    prhs
    orr den, #1

    sub i, #4
    prne
    bra .loop

    mov pc, link
}

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
; 30 instructions
.math_mul32x32 {
    alias r0 uh
    alias r1 ul
    alias r2 vh     ; qh
    alias r3 vl     ; ql
    alias r6 tmp
    alias r7 link_save

    mov link_save, link
    mul vh, ul  ; vh = ul*vh
    mul uh, vl  ; uh = uh*vl
    add uh, vh  ; uh = ul*vh + uh*vl
    mov tmp, uh ; tmp  = (ul*vh + uh*vl) << 16

    mov r0, vl          ; r0=vl, r1=ul
    bl .math_mul16x16   ; (vh,vl) = ul*vl
    add r2, tmp         ; (vh,vl) = (ul*vh + uh*vl) << 16 + ul*vl

    mov pc, link_save
}

; 16-bit by 16-bit multiply with 32-bit result
; 22 instructions - any real point in this? we're only saving 6 instructions
.math_mul16x16 {
    alias r0 u
    alias r1 v
    alias r2 q
    alias r3 q_lo
    alias r4 u_lo
    alias r5 v_lo

    mov u_lo, #0xff
    and u_lo, u         ; u_lo = u[7:0]
    lsr u, #8           ; u    = u[15:8]

    mov v_lo, #0xff
    and v_lo, v         ; v_lo = v[7:0]
    lsr v, #8           ; v    = v[15:8]

    mov q, u
    mul q, v            ; q = uh*rh
    mov q_lo, u_lo
    mul q_lo, v_lo      ; q_lo = ul*rl

    mul u, v_lo         ; u = uh*rl
    mul u_lo, v         ; u_lo = ul*rh
    mov v, #0x0100      ; tmp
    add u, u_lo         ; u = uh*rl + ul*rh
    prcs
    add q, v            ; carry in to bit 24

    ror u, #8           ; u = lo(uh*rl + ul*rh) : hi(uh*rl + ul*rh)
    mov u_lo, #0xff     ; u_lo = 0x00              : 0xff
    and u_lo, u         ; u_lo = 0x00              : hi(uh*rl + ul*rh)
    eor u, u_lo         ; u = lo(uh*rl + ul*rh) : 0x00
    add q_lo, u
    adc q, u_lo

    mov pc, link
}

; TODO - 32 bit version of this (gulp)
; 16-bit by 16-bit division with 16-bit quotient and remainder
; Instruction count: 52-63
.math_udiv16fast {
    ; TODO - some of these registers can surely be dual purposed
    alias r0 u
    alias r1 v
    alias r2 q
    alias r2 v1
    alias r3 q_lo
    alias r4 r
    alias r5 m1
    alias r6 m2
    alias r7 m3
    alias r8 m4
    alias r9 n

    ; Calculate estimate of quotient using lookup table.

    ; TODO call subroutine version of clz instead

    ; count leading zeros in v - takes 9-13 instructions
    mov r, #hi(.clz6)
    add r, #lo(.clz6)
    mov n, v
    lsr n, #10
    preq
    bra .clz_mid6
    add n, r
    ldb n, [n]
    bra .clz_done
.clz_mid6
    mov n, v
    lsr n, #4
    preq
    bra .clz_low4
    add n, r
    ldb n, [n]
    add n, #6
    bra .clz_done
.clz_low4
    add r, v
    ldb n, [r]
    add n, #10
.clz_done

    ; shift v1 up until top bit set
    mov v1, v
    lsl v1, n

    lsr v1, #8                      ; get top 8 bits
    lsl v1, #1                      ; convert to table offset
    mov r, #hi(.reciprocal-0x100)   ; correct for bit 8 always being set
    add r, #lo(.reciprocal-0x100)
    add r, v1
    ldw r, [r]
    
    ; TODO call mul16x16 instead of inlining

    ; q = (uint32_t)u * r;           // Q16.16 = U16 * Q16
    mov m1, u
    lsr m1, #8          ; m1 = 0x00:u_hi
    mov m2, #0xff
    and m2, u           ; m2 = 0x00:u_lo

    mov m3, r
    lsr m3, #8          ; m3 = 0x00:r_hi
    mov m4, #0xff
    and m4, r           ; m4 = 0x00:r_lo

    mov q, m1
    mul q, m3           ; q = uh*rh
    mov q_lo, m2
    mul q_lo, m4        ; q_lo = ul*rl

    mul m1, m4          ; m1 = uh*rl
    mul m2, m3          ; m2 = ul*rh
    mov m3, #0x0100     ; tmp
    add m1, m2          ; m1 = uh*rl + ul*rh
    prcs
    add q, m3           ; carry in to bit 24

    ror m1, #8          ; m1 = lo(uh*rl + ul*rh) : hi(uh*rl + ul*rh)
    mov m2, #0xff       ; m2 = 0x00              : 0xff
    and m2, m1          ; m2 = 0x00              : hi(uh*rl + ul*rh)
    eor m1, m2          ; m1 = lo(uh*rl + ul*rh) : 0x00
    add q_lo, m1
    adc q, m2

    ; q  = (uint16_t)(qx >> 16);      // U16 = trunc(Q16.16)
    ; qx is (q:q_lo) above, so we already have q
    
    mov q_lo, #15
    sub q_lo, n
    lsr q, q_lo     ; q >>= 15-n; // Undo normalization of v

    prne            ; if (q > 0) --q; // Adjust guess down to avoid possible overflow
    sub q, #1

    mov n, q        ; u -= q * v; // Calculate remainder to u
    mul n, v
    sub u, n

    ; Final correction of quotient to satisfy division theorem.
    
    cmp u, v        ; if (u >= v) { // Failed to satisfy division theorem?
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

.clz6
    db 6, 5, 4, 4, 3, 3, 3, 3
    db 2, 2, 2, 2, 2, 2, 2, 2
    db 1, 1, 1, 1, 1, 1, 1, 1
    db 1, 1, 1, 1, 1, 1, 1, 1
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0

.reciprocal
    ; 256 bytes
    ; reciprocal[i] = 0x007fffff / (0x80+i)
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

.math_clz {
    ; worst case 20 instructions
    alias r0 x
    alias r1 cnt
    alias r2 ptr

    mov ptr, #hi(.table)
    add ptr, #lo(.table)
    mov cnt, x
    lsr cnt, #10
    preq
    bra .mid6
    add cnt, ptr
    ldb cnt, [cnt]
    mov pc, link
.mid6
    mov cnt, x
    lsr cnt, #4
    preq
    bra .low4
    add cnt, ptr
    ldb cnt, [cnt]
    add cnt, #6
    mov pc, link
.low4
    add ptr, x
    ldb cnt, [ptr]
    add cnt, #10
    mov pc, link
.table
    ; 64 bytes
    db 6, 5, 4, 4, 3, 3, 3, 3
    db 2, 2, 2, 2, 2, 2, 2, 2
    db 1, 1, 1, 1, 1, 1, 1, 1
    db 1, 1, 1, 1, 1, 1, 1, 1
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0
}


