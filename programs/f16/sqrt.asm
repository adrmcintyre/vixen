;; Adapted from the softfloat library by John R Hauser.
;; See https://github.com/ucb-bar/berkeley-softfloat-3

; Computes sqrt(a).
;
; Arguments:
;   r0: a
;
; Results:
;   r2: square-root; V=1 on NaN
;
.f16_sqrt
{
    alias r0 a  
    alias r0 r_hi
    alias r1 r_lo
    alias r2 z
    alias r3 z_exp
    alias r4 z_sign
    alias r5 even_exp
    alias r6 ptr
    alias r6 e_hi
    alias r7 e_lo
    alias r7 sigma
    alias r7 neg_rem

    alias r12 tmp
    alias r13 sp
    alias r14 link
    alias r15 pc

    mov z, a
    mov z_sign, #.f16_sign_mask
    and z_sign, z
    bic z, #.f16_sign_mask
    mov z_exp, z
    lsr z_exp, #10
    mov tmp, #.f16_exp_mask
    bic z, tmp

    mov tmp, #31
    cmp z_exp, tmp
    prne
    bra .finite
    
    orr z, z_sign
    preq
    bra .f16_return_inf
    bra .f16_return_nan

.finite
    and z_sign, z_sign
    preq
    bra .positive

    orr z_exp, z
    preq
    bra .f16_return_zero
    bra .f16_return_nan

.positive
    and z_exp, z_exp
    prne
    bra .normal

    and z, z
    preq
    bra .f16_return_zero

    clz tmp, z
    sub tmp, #5
    lsl z, tmp
    mov z_exp, #1
    sub z_exp, tmp

.normal
    mov even_exp, #1
    and even_exp, z_exp

    sub z_exp, #15
    asr z_exp, #1
    add z_exp, #14

    orr z, #bit 10
    mov ptr, z
    lsr ptr, #6
    mov tmp, #14
    and ptr, tmp
    add ptr, even_exp
    lsl ptr, #2

    mov tmp, #hi(.data)
    add tmp, #lo(.data)
    add ptr, tmp
    ldw r_lo, [ptr, #2]
    mov tmp, #0x7f
    and tmp, z

    mov r_hi, r_lo
    muh r_hi, tmp
    mul r_lo, tmp

    lsr r_lo, #11
    lsl r_hi, #5
    orr r_lo, r_hi

    ldw tmp, [ptr, #0]
    rsb r_lo, tmp

    mov e_hi, r_lo
    mov e_lo, r_lo
    muh e_hi, r_lo
    mul e_lo, r_lo
    lsr e_hi, #1
    rrx e_lo

    and even_exp, even_exp
    preq
    bra .no_shift
    lsr e_hi, #1
    rrx e_lo

.no_shift
    mul e_hi, z
    muh e_lo, z
    add e_lo, e_hi

    mvn sigma, e_lo

    muh sigma, r_lo
    lsr sigma, #9
    add sigma, r_lo
    prpl
    mov sigma, #0x8000

    lsl z, #5
    muh z, sigma

    and even_exp, even_exp
    prne
    lsr z, #1

    add z, #1
    mov tmp, #7
    and tmp, z
    prne
    bra .f16_round_pack

    mov neg_rem, neg_rem
    lsr neg_rem, #1

    bic z, #1
    mul neg_rem, neg_rem

    prpl
    bra .else

    orr z, #1
    bra .f16_round_pack

.else
    prne
    sub z, #1
    bra .f16_round_pack

.data
    ;; 1k0s    1k1s
    dw 0xB4C9, 0xA5A5
    dw 0xFFAB, 0xEA42
    dw 0xAA7D, 0x8C21
    dw 0xF11C, 0xC62D
    dw 0xA1C5, 0x788F
    dw 0xE4C7, 0xAA7F
    dw 0x9A43, 0x6928
    dw 0xDA29, 0x94B6
    dw 0x93B5, 0x5CC7
    dw 0xD0E5, 0x8335
    dw 0x8DED, 0x52A6
    dw 0xC8B7, 0x74E2
    dw 0x88C6, 0x4A3E
    dw 0xC16D, 0x68FE
    dw 0x8424, 0x432B
    dw 0xBAE1, 0x5EFD
}

