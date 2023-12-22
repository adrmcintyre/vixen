; Converts a float to a 16-bit unsigned integer, truncating towards zero.
;
; Arguments
;   r0: float to convert
;
; Returns
;   r2: value, V=0  -- successful conversion
;   r2: 0x0000, V=1 -- input was < 0.0, -Inf, or NaN
;   r2: 0xffff, V=1 -- input was +Inf
;
.f16_ftou {
    alias r0 a
    alias r1 info
    alias r2 num

    alias r13 sp
    alias r14 link
    alias r15 pc

    stw link, [sp]
    bl .f16_ftomag

    and info, info
    preq
    ldw pc, [sp]

    mov num, #0

    tst info, #.f16_info_nan
    prne
    bra .set_overflow

    tst info, #.f16_info_negative
    preq
    sub num, #1

.set_overflow
    mov info, #0x8000
    add info, info
    ldw pc, [sp]
}


; Converts the float in "a" to a 16-bit signed integer, truncating towards zero.
;
; Return values:
;   V is clear, num=integer part of a
;   V is set, num=0x0000: a was NaN
;   V is set, num=0x7fff: a was >= 32768.0, or +Inf
;   V is set, num=0x8000: a was <= 32769.0, or -Inf
;
.f16_ftoi {
    alias r0 a
    alias r1 info
    alias r2 num

    alias r13 sp
    alias r14 link
    alias r15 pc

    stw link, [sp]
    bl .f16_ftomag

    tst info, #.f16_info_non_finite
    prne
    bra .non_finite

    tst num, #0x8000
    prne
    bra .maybe_overflow

    asr info, #15
    eor num, info
    sub num, info   ; will clear V
    ldw pc, [sp]

.non_finite
    tst info, #.f16_info_nan
    prne
    bra .nan

    bic info, #.f16_info_non_finite
    mov num, #0xf000

.maybe_overflow
    tst info, #.f16_info_negative
    preq
    bra .pos_overflow
    cmp num, info
    preq            ; V will be clear from cmp
    ldw pc, [sp]

    ; return 0x8000 and set overflow
    mov num, #0
    sub num, info   ; info is still 0x8000 here
    ldw pc, [sp]

.pos_overflow
    ; return 0x7fff and set overflow
    mov num, #0x8000
    sub num, #1
    ldw pc, [sp]

.nan
    ; return 0 and set overflow
    mov num, #0x8000
    add num, num
    ldw pc, [sp]
}


; Converts a float to a 16-bit unsigned integer magnitude (truncating towards 0),
; and separate negative/Inf/NaN indicators.
;
; Arguments
;   r0: float to convert
;
; Returns
;   r1 & f16_info_negative   -- argument is negative
;   r1 & f16_info_non_finite -- argument is +Inf, -Inf, or NaN
;   r1 & f16_info_nan        -- argument is NaN
;   r2: magnitude            -- argument is finite
;   r2: 0                    -- argument is NaN or infinite
;
def f16_info_negative   0x8000
def f16_info_non_finite 0x4000
def f16_info_nan        0x2000

.f16_ftomag {
    alias r0 a
    alias r1 info
    alias r2 num
    alias r3 exp

    alias r12 tmp
    alias r14 link
    alias r15 pc

    mov info, #.f16_sign_mask
    and info, a
    bic a, #.f16_sign_mask

    mov tmp, #.f16_one
    cmp a, tmp
    prlo
    bra .zero

    mov tmp, #.f16_exp_mask
    cmp a, tmp
    prhs
    bra .non_finite

    mov exp, a
    lsr exp, #10

    bic a, tmp
    orr a, #bit 10

    mov num, a

    mov tmp, #25
    cmp exp, tmp
    prhi
    bra .big

    sub tmp, exp
    lsr num, tmp
    mov pc, link

.big
    rsb tmp, exp
    lsl num, tmp
    mov pc, link

.zero
    mov num, #0
    mov info, #0
    mov pc, link

.non_finite
    orr info, #.f16_info_non_finite
    mov num, #0
    cmp a, tmp
    prne
    orr info, #.f16_info_nan
    mov pc, link
}
