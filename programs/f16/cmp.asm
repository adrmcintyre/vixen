; result:
;   -1 = lt
;    0 = eq
;   +1 = gt
;   +2 = unordered

.f16_cmp {
    alias r0 a
    alias r1 b
    alias r2 a_abs ; (result)
    alias r3 b_abs

    mov a_abs, a
    mov b_abs, b
    bic a_abs, #.f16_sign_mask
    bic b_abs, #.f16_sign_mask

    ; either NaN?
    mov tmp, #.f16_exp_mask
    cmp a_abs, tmp
    prls
    cmp b_abs, tmp
    prhi
    bra .unordered

    ; both +-zero?
    mov tmp, a_abs
    orr tmp, b_abs
    preq
    mov pc, link

    asr a, #15
    eor a_abs, a

    asr b, #15
    eor b_abs, b

    sub a_abs, b_abs
    prgt
    bra .gt

    asr a_abs, #15  ; converts 0 to 0, and -N to -1
    mov pc, link

    .gt
    mov a_abs, #1
    mov pc, link

.unordered
    mov a_abs, #2
    mov pc, link
}
