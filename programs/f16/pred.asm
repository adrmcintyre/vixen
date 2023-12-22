;-------------------------------------------------------------------------------
; These predicate functions all return their results in the same form.
;
;   Z=1, result=1: predicate is true
;   Z=0, result=0: predicate is false
;
; The Z flag is set in such a way that a subsequent preq is taken
; if the predicate was true, and prne is taken if it was false.
;
; E.g.
;   mov a, #0x3c00
;   bl .f16_is_finite
;   preq
;   bra .was_finite
;-------------------------------------------------------------------------------

; Tests if the float "a" is normal, i.e. not 0, subnormal, infinite, or NaN.
.f16_is_normal {
    bic a, #.f16_sign_mask
    sub a, #0x400                   ; we abuse unsigned comparison
    mov tmp, #.f16_exp_mask-0x400
    bra .f16_pred_cmp_lo            ; to effectively test 0x0400 <= a < 0x7c00
}

; Tests if the float "a" is finite, i.e. not infinite or NaN.
.f16_is_finite {
    bic a, #.f16_sign_mask
    mov tmp, #.f16_exp_mask
    bra .f16_pred_cmp_lo            ; test 0 <= a < 0x7c00
}

; Tests if the float "a" is zero, i.e. +0 or -0.
.f16_is_zero {
    mov result, #0
    bic a, #.f16_sign_mask
    preq
    mov result, #1
    mov pc, link
}

; Tests if the float "a" is subnormal, i.e. 0 < magnitude <= 6.1e-5
.f16_is_subnormal {
    mov tmp, #0x0400
    bic a, #.f16_sign_mask
    prne                            ; assert a > 0
    bra .f16_pred_cmp_lo            ; and test a < 0x0400
    mov result, #0                  ; if a == 0, return false
    bra .f16_pred_return
}

; Tests if the float "a" is NaN.
.f16_is_nan {
    mov result, #0
    bic a, #.f16_sign_mask
    mov tmp, #.f16_exp_mask
    cmp a, tmp
    prhi
    mov result, #1
    mov tmp, #1
    cmp result, tmp
    mov pc, link
}

; Tests if the float "a" is infinite, i.e. +inf or -inf.
.f16_is_infinite {
    mov result, #0
    bic a, #.f16_sign_mask
    mov tmp, #.f16_exp_mask
    cmp a, tmp
    preq
    mov result, #1
    mov tmp, #1
    cmp result, tmp
    mov pc, link
}

; Helper stubs

; Returns true iff a < tmp.
.f16_pred_cmp_lo {
    mov result, #0
    cmp a, tmp
    prlo
    mov result, #1
}
.f16_pred_return {
    mov tmp, #1
    cmp result, tmp
    mov pc, link
}


