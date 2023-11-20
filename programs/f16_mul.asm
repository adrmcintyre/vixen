;; Adapted from the softfloat library by John R Hauser.
;; See https://github.com/ucb-bar/berkeley-softfloat-3

; Requires f16_internal.asm

.f16_mul {
    alias r5 a_exp
    alias r6 b_exp

    mov tmp, #.f16_sign_mask
    mov z_sign, a
    eor z_sign, b
    and z_sign, tmp         ; calc result sign
    bic a, #.f16_sign_mask  ; a=abs(a)
    bic b, #.f16_sign_mask  ; b=abs(b)

    mov tmp, #.f16_exp_mask ; exponent mask
    mov a_exp, a
    mov b_exp, b
    bic a, tmp              ; isolate fractions
    bic b, tmp
    lsr a_exp, #10          ; extract exponents
    lsr b_exp, #10

    mov tmp, #31
    cmp a_exp, tmp
    prne
    bra .a_finite

    and a, a
    prne
    bra .f16_return_nan

    ; else a is infinite...

    cmp b_exp, tmp
    prne
    bra .a_inf_b_not_nan
    and b, b
    prne
    bra .f16_return_nan

.a_inf_b_not_nan
    orr b, b_exp        ; isZero(b) ?
    preq
    bra .f16_return_nan ; inf * zero     => nan
    bra .f16_return_inf ; inf * non-zero => inf

.a_finite
    cmp b_exp, tmp      ; isFinite(b) ?
    prne
    bra .both_finite

    and b, b
    prne
    bra .f16_return_nan ; finite * nan => nan

    orr a, a_exp        ; isZero(a) ?
    preq
    bra .f16_return_nan ; zero * inf     => nan
    bra .f16_return_inf ; non-zero * inf => inf

.both_finite
    and a_exp, a_exp
    prne
    bra .a_normal

    and a, a
    preq
    bra .f16_return_zero

    clz tmp, a              ; normalise a
    sub tmp, #5
    lsl a, tmp
    mov a_exp, #1
    sub a_exp, tmp

.a_normal
    and b_exp, b_exp
    prne
    bra .b_normal

    and b, b
    preq
    bra .f16_return_zero

    clz tmp, b              ; normalise b
    sub tmp, #5
    lsl b, tmp
    mov b_exp, #1
    sub b_exp, tmp

.b_normal
    mov z_exp, a_exp
    add z_exp, b_exp
    sub z_exp, #15
    orr a, #0x400
    lsl a, #4
    orr b, #0x400
    lsl b, #5

    mov z, a
    muh z, b
    mul a, b    ; lo bits of product
    prne
    orr z, #bit 0
    mov tmp, #0x4000
    cmp z, tmp
    prhs
    bra .f16_round_pack
    sub z_exp, #1
    lsl z, #1
    bra .f16_round_pack
}
