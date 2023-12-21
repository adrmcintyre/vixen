; Returns minimum of a, b.
;
; Returns NaN and sets V if either arg is Nan.
; 
.f16_min {
    alias r0 a
    alias r1 b
    alias r2 result
    alias r2 a_abs
    alias r3 b_abs

    alias r12 tmp
    alias r14 link
    alias r15 pc

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
    bra .f16_return_nan

    mov tmp, a
    asr tmp, #15
    eor a_abs, tmp

    mov tmp, b
    asr tmp, #15
    eor b_abs, tmp

    cmp a_abs, b_abs
    mov result, b
    prlt
    mov result, a
    add result, #0      ; clear V
    mov pc, link
}

; Returns maximum of a, b.
;
; Returns NaN and sets V if either arg is Nan.
; 
.f16_max {
    alias r0 a
    alias r1 b
    alias r2 result
    alias r2 a_abs
    alias r3 b_abs

    alias r12 tmp
    alias r14 link
    alias r15 pc

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
    bra .f16_return_nan

    mov tmp, a
    asr tmp, #15
    eor a_abs, tmp

    mov tmp, b
    asr tmp, #15
    eor b_abs, tmp

    cmp a_abs, b_abs
    mov result, b
    prgt
    mov result, a
    add result, #0      ; clear V
    mov pc, link
}
