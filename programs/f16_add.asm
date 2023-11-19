
.f16_add
{
    alias r0 a
    alias r1 b
    alias r2 z
    alias r3 a_exp
    alias r4 b_exp
    alias r5 z_exp
    alias r6 a_sign
    alias r7 z_sign
    alias r8 exp_diff
    alias r9 x
    alias r10 y
    alias r11 y_lo
    alias r12 tmp
    alias r14 link
    alias r15 pc

    def f16_sign_mask 0x8000
    def f16_exp_mask  0x7c00
    def f16_qnan      0x7e00
    def f16_inf       0x7c00


    ;; TODO - branch for add vs sub
    mov tmp, #.f16_sign_mask
    bic a, #.f16_sign_mask
    bic b, #.f16_sign_mask

    ; ...

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
    bra .exp_a_greater_b

    ; from here we know exponents are equal, so we have one of:
    ;   both are zero or subnormal,
    ;   both are inf or nan
    ;   both are normal
    ;
    and a_exp, a_exp
    prne
    bra .both_not_sub

    ; at this point we know a_exp=b_exp=0, so we can add both as subnormals
    mov z_exp, #0
    mov z, a
    add z, b    ; if we overflow into bit 10, that's okay as it's then treated as exp=1
    bra .return_uiz

.both_not_sub
    ;  TODO could do >30 instead, so we can reuse for <30 comparison in both_normal
    mov tmp, #0x1f      ; inf or nan?
    cmp a_exp, tmp
    prne
    bra .both_normal

    mov tmp, a          ; any nan bits set in either arg?
    orr tmp, b
    preq
    bra .both_inf

.return_nan
    mov z, #.f16_qnan
    mov pc, link

.return_inf
    mov z, #.f16_inf
    orr z, a_sign
    mov pc, link

.both_inf
    mov z, #.f16_inf    ; both must be inf, so inf result
    orr z, a_sign
    mov pc, link

.both_normal
    mov z_sign, a_sign
    mov z_exp, a_exp
    mov z, #0x400 * 2
    add z, a
    add z, b

    tst z, #bit 0
    prne
    bra .drop3

    mov tmp, #30
    cmp z_exp, tmp
    prhs
    bra .drop3

    lsr z, #1
    bra .pack

.drop3
    lsr z, #3
    bra .round_pack_to_f16

    ;;; At this point we know exp_a > exp_b

.exp_a_greater_b
    mov tmp, #31
    cmp a_exp, tmp
    prne
    bra .a_finite

    and a, a
    preq
    bra .return_inf
    bra .return_nan

.a_finite
    mov tmp, #13
    cmp exp_diff, tmp
    prlo
    bra .a_non_huge

    mov z, a_exp    ; just return a
    lsl z, #10
    add z, a
    orr z, a_sign
    mov pc, link

.a_non_huge
    mov z_exp, a_exp
    mov x, a
    orr x, #0x400
    mov y, b
    and b_exp, b_exp
    preq
    bra .y_is_double_b

    orr y, #0x400
    bra .y_done

.y_is_double_b
    add y, b

.y_done
    mov tmp, #19
    rsb exp_diff, tmp

    ;; align and add

    ; 0 < a_exp - b_exp < 13
    ; therefore 19 > exp_diff > 6

    lsl x, #3

    mov tmp, #16
    cmp exp_diff, tmp
    prhs
    bra .align_ge16

    mov y_lo, y
    lsl y_lo, exp_diff
    rsb exp_diff, tmp
    lsr y, tmp
    bra .aligned

.align_ge16
    sub exp_diff, #16
    lsl y, exp_diff
    mov y_lo, #0

.aligned

    ; addition looks like this:
    ; 00xxxxxx:xxxxx000 : 00000000:00000000
    ; 000yyyyy:yyyyyy00 : 00000000:00000000, after << 18 : expDiff=1
    ; 00000000:000000yy : yyyyyyyy:y0000000, after << 7  : expDiff=12

    ; z32 = [y:y_lo]
    add y, x
    mov tmp, #0x4000
    cmp y, tmp
    prhs
    bra .scaled
    sub z_exp, #1
    lsl y_lo, #1    ; [y:y_lo] <<= 1
    adc y, y

.scaled
    mov z, y        ; TODO possibility to fuse register usage?
    and y_lo, y_lo
    preq
    bra .else
    orr z, #bit 0
    bra .round_pack_to_f16

.else
    mov tmp, #0xf
    tst z, tmp
    prne
    bra .round_pack_to_f16
    mov tmp, #30
    cmp z_exp, tmp
    prhs
    bra .round_pack_to_f16
    lsr z, #4
    bra .pack

.round_pack_to_f16  ; TODO
.return_uiz         ; TODO
.pack               ; TODO
}


