;; Adapted from the softfloat library by John R Hauser.
;; See https://github.com/ucb-bar/berkeley-softfloat-3

; Requires f16_internal.asm

; external routine
.f16_sub
    mov tmp, a
    eor tmp, b
    prmi
    bra .f16_internal_add_mags  ; add instead if signs are opposite
    ; fall through

; Internal helper
.f16_internal_sub_mags
{
    ; working regs
    alias r5 a_exp
    alias r6 b_exp
    alias r7 z_lo
    alias r8 exp_diff
    alias r9 y_lo

    mov z_sign, #.f16_sign_mask
    and z_sign, a

    bic a, #.f16_sign_mask
    bic b, #.f16_sign_mask

    cmp a, b
    prhs
    bra .ordered

    mov tmp, b
    mov b, a
    mov a, tmp
    eor z_sign, #.f16_sign_mask

.ordered
    mov tmp, #.f16_exp_mask
    mov a_exp, a
    mov b_exp, b
    bic a, tmp
    bic b, tmp
    lsr a_exp, #10
    lsr b_exp, #10

    mov exp_diff, a_exp
    sub exp_diff, b_exp
    prne
    bra .exp_a_gt_b

    mov tmp, #31            ; check if args are both inf or NaN
    cmp a_exp, tmp
    preq
    bra .f16_return_nan     ; inf-inf => NaN; either arg is NaN => NaN

    mov z, a
    sub z, b
    preq
    bra .f16_return_pos_zero

    and a_exp, a_exp
    prne
    sub a_exp, #1

    and z, z
    prpl
    bra .pos_diff

    eor z_sign, #.f16_sign_mask
    mov z, b
    sub z, a

.pos_diff
    clz exp_diff, z
    sub exp_diff, #5
    mov z_exp, a_exp
    sub z_exp, exp_diff
    prmi
    bra .both_subnorm

    lsl z, exp_diff
    bra .f16_return

.both_subnorm
    lsl z, a_exp
    orr z, z_sign
    mov pc, link
    
.exp_a_gt_b
    mov tmp, #31
    cmp a_exp, tmp
    prne
    bra .a_finite

    and a, a
    preq
    bra .f16_return_inf
    bra .f16_return_nan

.a_finite
    mov tmp, #13
    cmp exp_diff, tmp
    prlo
    bra .a_non_huge

    lsl a_exp, #10      ; just return a
    mov z, a
    add z, a_exp
    orr z, z_sign
    mov pc, link

.a_non_huge
    mov z_exp, b_exp
    add z_exp, #19

    mov z_lo, a
    orr z_lo, #0x400

    mov y_lo, b
    and b_exp, b_exp
    preq
    bra .b_subnorm

    orr y_lo, #0x400
    bra .b_normalised

.b_subnorm
    add y_lo, b

.b_normalised
    ;; 1 <= exp_diff <= 12
    ;; [z:z_lo] = [0:z_lo] <<= exp_diff
    mov z, z_lo
    lsl z_lo, exp_diff
    mov tmp, #16
    rsb exp_diff, tmp
    lsr z, exp_diff

    sub z_lo, y_lo
    prcc
    sub z, #1

    clz exp_diff, z
    tst exp_diff, #16
    preq
    bra .done_clz

    clz exp_diff, z_lo
    add exp_diff, #16

.done_clz
    sub exp_diff, #1
    sub z_exp, exp_diff

    tst exp_diff, #16
    prne
    bra .big_align
    mov y_lo, z_lo
    lsl z_lo, exp_diff
    lsl z, exp_diff
    mov tmp, #16
    sub tmp, exp_diff
    lsr y_lo, tmp
    orr z, y_lo
    bra .aligned

.big_align
    mov z, z_lo
    sub exp_diff, #16
    lsl z, exp_diff
    mov z_lo, #0

.aligned
    and z_lo, z_lo
    preq
    bra .z_lo_zero

    orr z, #bit 0
    bra .f16_round_pack

.z_lo_zero
    mov tmp, #0xf
    tst z, tmp
    prne
    bra .f16_round_pack

    mov tmp, #30
    cmp z_exp, tmp
    prhs
    bra .f16_round_pack

    lsr z, #4
    bra .f16_return
}

