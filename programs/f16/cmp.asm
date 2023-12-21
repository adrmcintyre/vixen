; Result:
;   less_than:    result = -1, flags = -V -C -Z
;   equal_to:     result =  0, flags = -V +C +Z
;   greater_than: result = +1, flags = -V +C -Z
;   unordered:    result = +2, flags = +V -C -Z

.f16_cmp {
    alias r0 a
    alias r1 b
    alias r2 result
    alias r3 b_abs

    alias r12 tmp
    alias r14 link
    alias r15 pc

    mov result, a
    mov b_abs, b
    bic result, #.f16_sign_mask
    bic b_abs, #.f16_sign_mask

    ; either NaN?
    mov tmp, #.f16_exp_mask
    cmp result, tmp
    prls
    cmp b_abs, tmp
    prhi
    bra .unordered

    ; both +-zero?
    mov tmp, result
    orr tmp, b_abs
    preq
    bra .eq_zeroes

    asr a, #15
    eor result, a

    asr b, #15
    eor b_abs, b

    sub result, b_abs
    preq
    mov pc, link

    mov result, #0
    prgt
    mov result, #2
    sub result, #1
    mov pc, link

.eq_zeroes
    mov result, #1
    sub result, #1      ; -V +C +Z result=0
    mov pc, link

.unordered
    mov result, #0x9000
    add result, result  ; +V +C -Z result=0x2000
    lsr result, #12     ; +V -C -Z result=2
    mov pc, link
}
