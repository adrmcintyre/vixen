;; Adapted from the softfloat library by John R Hauser.
;; See https://github.com/ucb-bar/berkeley-softfloat-3

; Requires f16_internal.asm

; external routine
.f16_add
    mov tmp, a
    eor tmp, b
    prmi
    bra .f16_internal_sub_mags  ; subtract instead if signs are opposite
    ; fall through

; Internal helper
.f16_internal_add_mags
{
    ; working regs
    alias r5 a_exp
    alias r6 b_exp
    alias r7 a_sign
    alias r8 exp_diff
    alias r9 x_hi
    alias r10 y_hi
    alias r11 y_lo

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

    ; From here we know exponents are equal, so we have one of:
    ;   both are zero or subnormal,
    ;   both are inf or nan
    ;   both are normal
    ;
    and a_exp, a_exp
    prne
    bra .neither_subnormal

    ; At this point we know a_exp=b_exp=0, so we can add both as subnormals
    mov z, a
    add z, b    ; if we overflow into bit 10, that's okay as it's then treated as exp=1
    orr z, z_sign
    mov pc, link

.neither_subnormal
    ;  TODO could do >30 instead, so we can reuse for <30 comparison in both_normal
    mov tmp, #0x1f      ; inf or nan?
    cmp a_exp, tmp
    prne
    bra .both_normal

    mov tmp, a          ; any nan bits set in either arg?
    orr tmp, b
    preq
    bra .f16_return_inf ; both must be inf, so inf result
    bra .f16_return_nan

.both_normal
    mov z_exp, a_exp
    mov z, #0x400 * 2
    add z, a
    add z, b

    tst z, #bit 0
    prne
    bra .pad

    mov tmp, #30
    cmp z_exp, tmp
    prhs
    bra .pad

    lsr z, #1
    bra .f16_return

.pad
    lsl z, #3
    bra .f16_round_pack

    ; At this point we know exp_a > exp_b

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
    mov z_exp, a_exp
    mov x_hi, a
    orr x_hi, #0x400
    mov y_hi, b
    and b_exp, b_exp
    preq
    bra .y_is_double_b

    orr y_hi, #0x400
    bra .y_done

.y_is_double_b
    add y_hi, b

.y_done
    mov tmp, #19
    rsb exp_diff, tmp

    ; Now we align and add

    ; 0 < a_exp - b_exp < 13
    ; therefore 19 > exp_diff > 6

    lsl x_hi, #3

    mov tmp, #16
    cmp exp_diff, tmp
    prhs
    bra .align_ge16

    mov y_lo, y_hi
    lsl y_lo, exp_diff
    rsb exp_diff, tmp
    lsr y_hi, tmp
    bra .aligned

.align_ge16
    sub exp_diff, #16
    lsl y_hi, exp_diff
    mov y_lo, #0

    ; addition looks like this:
    ; x : 00xxxxxx:xxxxx000 : 00000000:00000000
    ; y : 000yyyyy:yyyyyy00 : 00000000:00000000, (after << 18 when exp_diff=1)
    ; ... 00000000:000000yy : yyyyyyyy:y0000000, (after << 7  when exp_diff=12)
.aligned
    ; z32 = [y_hi:y_lo]
    add y_hi, x_hi
    mov tmp, #0x4000
    cmp y_hi, tmp
    prhs
    bra .scaled
    sub z_exp, #1
    lsl y_lo, #1        ; [y_hi:y_lo] <<= 1
    adc y_hi, y_hi

.scaled
    mov z, y_hi
    and y_lo, y_lo
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
    bra .f16_return
}

