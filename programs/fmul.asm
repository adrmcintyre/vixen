def sign_mask   0x8000
def exp_mask    0x7c00
def quiet_nan   0x7e00
def exp_bias    15
def emax        30
def infinity    0x7c00
def min_norm    0x0400

;; TODO optimise register usage
alias r0 a
alias r1 b
alias r2 r
alias r3 a_sign     ; not used past r_sign
alias r4 b_sign     ; not used past r_sign
alias r5 r_sign
alias r6 r_exp
alias r7 a_fra      ; not used past prod_hi, prod_lo
alias r8 b_fra      ; not used past prod_hi, prod_lo
alias r9 prod_hi    ; alias for r?
alias r10 prod_lo
alias r12 tmp
alias r14 link
alias r15 pc

.entry
    mov r0, #hi(0x262e)
    add r0, #lo(0x262e)
    mov r1, #hi(0x3799)
    add r1, #lo(0x3799)
    bl .math_fmul
    ;; expect 21de as result...!
    hlt

.math_fmul
    ; extract signs and make absolute
    mov tmp, #.sign_mask
    mov a_sign, a
    and a_sign, tmp
    bic a, tmp

    mov b_sign, b
    and b_sign, tmp
    bic b, tmp

    mov r_sign, a_sign      ; multiply signs
    eor r_sign, b_sign

    mov tmp, #.exp_mask

    cmp a, tmp              ; isNan(a) ?
    prls
    bra .a_not_nan
    mov r, a                ; propagate NaN
    mov pc, link

.a_not_nan
    cmp b, tmp              ; isNan(b) ?
    prls
    bra .b_not_nan
    mov r, b                ; propagate NaN
    mov pc, link

.b_not_nan
    and a, a                ; isZero(a) ?
    prne
    bra .a_non_zero
    mov r, r_sign           ; signed zero
    cmp b, tmp              ; isInfinite(b) ?
    preq
    mov r, #.quiet_nan      ; 0 * inf = Nan
    mov pc, link

.ret_signed_zero
    mov pc, link

.a_non_zero
    and b, b                ; isZero(b) ?
    prne
    bra .b_non_zero
    mov r, r_sign           ; signed zero
    cmp a, tmp              ; isInfinite(b) ?
    preq
    mov r, #.quiet_nan      ; inf * 0 = Nan
    mov pc, link

.b_non_zero
    mov r, tmp              ; signed infinity
    orr r, r_sign

    cmp a, tmp              ; isInfinite(a) || isInfinite(b) ?
    prne
    cmp b, tmp
    preq
    mov pc, link            ; return signed infinity

    mov r_exp, tmp
    and r_exp, a            ; extract a.exp
    add r_exp, b            ; add b.exp as well as b.fra
    lsr r_exp, #10          ; shift off the fraction
    sub r_exp, #.exp_bias   ; undo double bias

    mov a_fra, a
    bic a_fra, tmp          ; extract a.fra
    lsl a_fra, #3           ; and move up
    mov b_fra, b
    bic b_fra, tmp          ; extract b.fra
    lsl b_fra, #3           ; and move up

    tst a, tmp              ; isSubnormal(a) ?
    prne
    bra .a_is_normal
    add r_exp, #1           ; adjust exponent

    ; use r as temp
    clz r, a_fra            ; shift a_fra until unit bit[13] is filled
    sub r, #2
    lsl a_fra, r
    sub r_exp, r            ; adjust exponent

;.a_norm_lp
;    lsl a_fra, #1
;    sub r_exp, #1
;    tst a_fra, #bit 13
;    preq
;    bra .a_norm_lp

    bra .a_normed

.a_is_normal
    orr a_fra, #1<<13       ; set unit bit
.a_normed
    tst b, tmp              ; isSubnormal(b) ?
    prne
    bra .b_is_normal
    add r_exp, #1           ; adjust exponent

    ; use r as temp
    clz r, b_fra            ; shift b_fra until unit bit[13] filled
    sub r, #2
    lsl b_fra, r
    sub r_exp, r            ; adjust exponent

;.b_norm_lp
;    lsl b_fra, #1
;    sub r_exp, #1
;    tst b_fra, #bit 13
;    preq
;    bra .b_norm_lp

    bra .b_normed

.b_is_normal
    orr b_fra, #bit 13       ; set unit bit
.b_normed
    mov prod_hi, a_fra
    muh prod_hi, b_fra      ; high part of product
    mov prod_lo, a_fra
    mul prod_lo, b_fra      ; low part of product

    tst prod_hi, #bit 11    ; we just multiplied 1.aaa * 1.bbb: is this >= 2.0 ?
    preq
    bra .endif_carry
    lsr prod_hi, #1         ; shift down to maintain position of unit bit
    rrx prod_lo
    add r_exp, #1           ; adjust exponent

.endif_carry
    tst prod_lo, #bit 15    ; are we >= 0.5 ulp ?
    preq
    bra .endif_round
    add prod_hi, #1         ; round up
    tst prod_hi, #bit 11    ; overflowed?
    preq
    bra .endif_round
    lsr prod_hi, #1         ; maintain unit bit position
    add r_exp, #1           ; adjust exponent

.endif_round
    mov tmp, #.emax
    cmp r_exp, tmp          ; do we exceed emax?
    prle                    ; (signed compare)
    bra .r_not_inf
    mov r, #.infinity       ; return signed infinity
    orr r, r_sign
    mov pc, link

.r_not_inf
    mov tmp, #0             ; subnormal result?
    cmp r_exp, tmp
    prle
    bra .r_norm_lp

    ; return normal result
    mov r, r_exp
    lsl r, #10              ; get exponent into position
    orr r, r_sign           ; apply sign
    lsl prod_hi, #6         ; ditch top 6 bits of product
    lsr prod_hi, #6         ; restore remaining 10 bits to proper position
    orr r, prod_hi          ; apply to result
    mov pc, link

.r_norm_lp
    lsr prod_hi, #1         ; shift down until exponent is 1
    rrx prod_lo
    add r_exp, #1
    prle                    ; (branch taken when r_exp<=0)
    bra .r_norm_lp

    tst prod_lo, #bit 15    ; >= 0.5 ulp?
    preq
    bra .endif_r_round

    add prod_hi, #1         ; round up
    tst prod_hi, #bit 10    ; did we overflow into unit bit?
    preq
    bra .endif_r_round
    
    ;; TODO - can optimise as prod_hi == min_norm at this point
    mov r, #.min_norm       ; smallest possible normal result
    orr r, r_sign
    mov pc, link

.endif_r_round
    lsl prod_hi, #6         ; ditch top 6 bits
    lsr prod_hi, #6         ; restore remaining 10 bits to proper position
    mov r, prod_hi
    orr r, r_sign           ; apply sign
    mov pc, link

