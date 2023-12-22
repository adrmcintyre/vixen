; Converts a 16-bit signed integer to float.
;
; Arguments
;   r0: signed integer to convert
;
; Returns
;   r2: converted float, V=0
;
.f16_itof {
    alias r0  num
    alias r2  z
    alias r3  z_exp
    alias r4  z_sign

    alias r12 tmp
    alias r14 link
    alias r15 pc

    mov z, num
    add z, #0           ; clears V
    preq
    mov pc, link

    mov tmp, #0
    mov z_sign, #.f16_sign_mask
    and z_sign, z
    prmi
    rsb z, tmp
    bra .f16_utof_return
}

; Converts a 16-bit unsigned integer to float.
;
; Arguments
;   r0: unsigned integer to convert
;
; Returns
;   r2: converted float, V=0
;
.f16_utof {
    alias r0  num
    alias r2  z
    alias r3  z_exp
    alias r4  z_sign

    alias r12 tmp
    alias r14 link
    alias r15 pc

    mov z, num
    add z, #0           ; clears V
    preq
    mov pc, link

    mov z_sign, #0
}
.f16_utof_return
    mov z_exp, #30-1    ; account for leading 1 bit
    clz tmp, z
    sub z_exp, tmp
    lsl z, tmp

    lsr z, #1
    prcs
    orr z, #bit 0
    bra .f16_round_pack
}
