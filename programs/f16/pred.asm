;-------------------------------------------------------------------------------
; These predicate functions all have the same signature:
;
; Arguments
;   r0: float to be tested
;
; Returns
;   r2: 1, Z=1 -- predicate is true
;   r2: 0, Z=0 -- predicate is false
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

; Tests if its argument is normal, i.e. not zero, subnormal, infinite, or NaN.
.f16_is_normal {
    alias r0 a
    alias r12 tmp

    bic a, #.f16_sign_mask
    mov tmp, #0x0400
    sub a, tmp                      ; we abuse unsigned comparison
    mov tmp, #.f16_exp_mask-0x400
    bra .f16_pred_cmp_lo            ; to effectively test 0x0400 <= a < 0x7c00
}

; Tests if its argument is finite, i.e. not infinite or NaN.
.f16_is_finite {
    alias r0 a
    alias r12 tmp

    bic a, #.f16_sign_mask
    mov tmp, #.f16_exp_mask
    bra .f16_pred_cmp_lo            ; test 0 <= a < 0x7c00
}

; Tests if its argument is zero, i.e. +0 or -0.
.f16_is_zero {
    alias r0 a
    alias r2 result
    alias r12 tmp
    alias r14 link
    alias r15 pc

    mov result, #0
    bic a, #.f16_sign_mask
    preq
    mov result, #1
    mov pc, link
}

; Tests if its argument is subnormal, i.e. 0 < magnitude <= 6.1e-5
.f16_is_subnormal {
    alias r0 a
    alias r2 result
    alias r12 tmp

    mov tmp, #0x0400
    bic a, #.f16_sign_mask
    prne                            ; assert a > 0
    bra .f16_pred_cmp_lo            ; and test a < 0x0400
    mov result, #0                  ; if a == 0, return false
    bra .f16_pred_return
}

; Tests if its argument is a NaN.
.f16_is_nan {
    alias r0 a
    alias r2 result
    alias r12 tmp
    alias r14 link
    alias r15 pc

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

; Tests if its argument is infinite, i.e. +Inf or -Inf.
.f16_is_infinite {
    alias r0 a
    alias r2 result
    alias r12 tmp
    alias r14 link
    alias r15 pc

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
    alias r0 a
    alias r2 result
    alias r12 tmp

    mov result, #0
    cmp a, tmp
    prlo
    mov result, #1
}
.f16_pred_return {
    alias r2 result
    alias r12 tmp
    alias r14 link
    alias r15 pc

    mov tmp, #1
    cmp result, tmp
    mov pc, link
}


