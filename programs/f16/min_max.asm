; Computes the minimum of two floats.
;
; Arguments
;   r0: a
;   r1: b
;
; Returns
;   r2: minimum, V=0 -- a and b are both valid
;   r2: NaN, V=1     -- a or b are NaN
;
; Note that -0 < +0, so min(+0,-0) = -0
; 
.f16_min {
    alias r0 a
    alias r1 b
    alias r2 result
    alias r2 a_prime
    alias r3 b_prime

    alias r12 tmp
    alias r14 link
    alias r15 pc

    mov a_prime, a
    mov b_prime, b
    bic a_prime, #.f16_sign_mask    ; a_prime = abs(a)
    bic b_prime, #.f16_sign_mask    ; b_prime = abs(b)

    ; either NaN?
    mov tmp, #.f16_exp_mask
    cmp a_prime, tmp
    prls
    cmp b_prime, tmp
    prhi
    bra .f16_return_nan

    mov tmp, a
    asr tmp, #15
    eor a_prime, tmp                ; a_prime = two's complement form of a

    mov tmp, b
    asr tmp, #15
    eor b_prime, tmp                ; b_prime = two's complement form of b

    cmp a_prime, b_prime
    mov result, b
    prlt
    mov result, a
    add result, #0      ; clear V
    mov pc, link
}

; Computes the maximum of two floats.
;
; Arguments
;   r0: a
;   r1: b
;
; Returns
;   r2: maximum, V=0 -- a and b are both valid
;   r2: NaN, V=1     -- a or b are NaN
;
; Note that -0 < +0, so max(+0,-0) = +0
; 
.f16_max {
    alias r0 a
    alias r1 b
    alias r2 result
    alias r2 a_prime
    alias r3 b_prime

    alias r12 tmp
    alias r14 link
    alias r15 pc

    mov a_prime, a
    mov b_prime, b
    bic a_prime, #.f16_sign_mask
    bic b_prime, #.f16_sign_mask

    ; either NaN?
    mov tmp, #.f16_exp_mask
    cmp a_prime, tmp
    prls
    cmp b_prime, tmp
    prhi
    bra .f16_return_nan

    mov tmp, a
    asr tmp, #15
    eor a_prime, tmp

    mov tmp, b
    asr tmp, #15
    eor b_prime, tmp

    cmp a_prime, b_prime
    mov result, b
    prgt
    mov result, a
    add result, #0      ; clear V
    mov pc, link
}
