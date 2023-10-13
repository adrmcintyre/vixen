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
     sub r5, r1
     sbc r4, r0
     hlt
 .expect
     dw 0x6e56,0x08dc

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

; TODO - 32 bit version of this (gulp)
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
    mov r, #hi(.reciprocal-0x100)   ; correct for bit 8 always being set
    add r, #lo(.reciprocal-0x100)
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

