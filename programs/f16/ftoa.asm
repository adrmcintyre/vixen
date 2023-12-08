
mov r0, #0x3c00
bl .f16_to_ascii
hlt

.f16_to_ascii
{
    alias r0 x
    alias r1 buf
    alias r2 exp
    alias r3 sign
    alias r4 ch
    alias r12 tmp
    alias r13 sp
    alias r14 link
    alias r15 pc

    ; split into sign, exp and fra
    mov sign, x
    bic x, #.f16_sign_mask
    prne
    bra .non_zero

    mov ch, #'0'
    stw ch, [buf, #0]
    add buf, #1
    mov pc, link

.non_zero
    mov tmp, #.f16_exp_mask
    cmp x, tmp
    prls
    bra .numeric

    mov tmp, #hi(.nan_name)
    add tmp, #lo(.nan_name)

.copy3
    ldb ch, [tmp, #0]
    stb ch, [buf, #0]
    ldb ch, [tmp, #1]
    stb ch, [buf, #1]
    ldb ch, [tmp, #2]
    stb ch, [buf, #2]
    add buf, #3
    mov pc, link

.numeric
    bic sign, x
    preq
    bra .positive

    mov ch, #'-'
    stb ch, [buf]
    add buf, #1

.positive
    cmp x, tmp
    prne
    bra .finite

    mov tmp, #hi(.inf_name)
    add tmp, #lo(.inf_name)
    bra .copy3

.finite
    mov exp, x
    lsr exp, #10

    ;; THE MEAT ...

    mov pc, link

.nan_name
    ds "nan"

.inf_name
    ds "inf"
    align
}
