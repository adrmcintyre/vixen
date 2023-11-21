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

.f16_internal_sub_mags
{
    alias r5 a_exp
    alias r6 b_exp
    alias r7 fra_diff
    alias r8 exp_diff
    alias r9 z_lo
    alias r10 y_lo

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
    preq
    bra .exp_a_gt_b

    mov tmp, #0x1f
    cmp a_exp, tmp
    preq
    bra .f16_return_nan

    mov fra_diff, a
    sub fra_diff, b
    preq
    bra .f16_return_pos_zero

    and a_exp, a_exp
    prne
    sub a_exp, #1

    and fra_diff, fra_diff
    prpl
    bra .pos_fra_diff

    eor z_sign, #.f16_sign_mask
    mov fra_diff, b
    sub fra_diff, a

.pos_fra_diff
    clz exp_diff, fra_diff
    sub exp_diff, #5
    mov z_exp, a_exp
    sub z_exp, exp_diff
    prmi
    bra .subnormal

    mov z, fra_diff
    lsl z, exp_diff
    bra .f16_return

.subnormal
    mov z, fra_diff
    lsl z, a_exp
    orr z, z_sign
    mov pc, link
    
.exp_a_gt_b
    mov tmp, #0x1f
    cmp a_exp, tmp
    prne
    bra .a_finite

    and a, a
    prne
    bra .f16_return_nan
    bra .f16_return_inf     ;; TODO - check return sign is correct

.a_finite
    mov tmp, #13
    cmp exp_diff, tmp
    prlo
    bra .a_non_huge

    mov z, a
    mov z_exp, a_exp
    bra .f16_return         ;; TODO - check return sign is correct

.a_non_huge
    mov z_exp, b_exp
    add z_exp, #19

    mov z_lo, a
    orr z_lo, #0x400

    mov y_lo, b
    and b_exp, b_exp
    preq
    bra .y_is_double_b

    orr y_lo, #0x400
    bra .y_done

.y_is_double_b
    add y_lo, b

.y_done

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
    sub z_exp, exp_diff;

    tst exp_diff, #16
    prne
    bra .big_shift
    mov y_lo, z_lo
    lsl z_lo, exp_diff
    lsl z, exp_diff
    mov tmp, #16
    sub tmp, exp_diff
    lsr y_lo, tmp
    orr z, y_lo
    bra .shifted

.big_shift
    mov z, z_lo
    sub exp_diff, #16
    lsl z, exp_diff
    mov z_lo, #0

.shifted
    and z_lo, z_lo
    preq
    bra .else

    orr z, #bit 0
    bra .f16_round_pack

.else
    mov tmp, #0xf
    tst z, tmp
    prne
    bra .f16_round_pack

    mov tmp, #30
    cmp z_exp, tmp
    prhs
    bra .f16_round_pack

    lsr z, #4

    add z, z_exp
    orr z, z_sign
    mov pc, link
}

