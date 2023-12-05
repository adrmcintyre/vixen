
;; TODO - stack discipline
;; check *buf++ now we have refactored NaN / Inf parse

.f16_parse
{
    alias r0 buf
    alias r1 ch
    alias r2 buf2
    alias r2 mantissa
    alias r3 exponent
    alias r4 sign

    alias r5 mantissa_lo
    alias r6 full
    alias r7 seen_dp
    alias r8 tmp2
    alias r9 shift

    mov buf2, #hi(nan_name)
    add buf2, #lo(nan_name)
    bl .no_case_cmp3
    preq
    bra .f16_return_nan

.parse_sign
    mov sign, #0
    mov tmp, #'+'
    cmp ch, tmp
    preq
    bra .skip_sign

.parse_sign_minus
    mov tmp, #'-'
    cmp ch, tmp
    prne
    bra .parse_inf

    mov sign, #1
.skip_sign
    ldb ch, [buf]
    add buf, #1

.parse_inf
    mov buf2, #hi(inf_name)
    add buf2, #lo(inf_name)
    bl .no_case_cmp3
    preq
    bra .f16_return_inf

.leading_zeroes
    mov tmp, #'0'
.leading_zeros_loop
    cmp ch, tmp
    prne
    bra .parse_mantissa
    ldb ch, [buf]
    add buf, #1
    bra .leading_zeros_loop

.parse_mantissa
    mov mantissa, #0
    mov mantissa_lo, #0
    mov exponent, #0
    ;; TODO combine into a single flags registers
    mov full, #0
    mov seen_dp, #0
    mov sign, #0

.parse_mantissa_loop
    and ch, ch
    preq
    bra .parse_exponent

    mov tmp, #'.'
    cmp ch, tmp
    prne
    bra .parse_digit

    and seen_dp, seen_dp
    prne
    bra .parse_digit
    mov seen_dp, #1
    ldb ch, [buf]
    add buf, #1
    bra .parse_mantissa

.parse_digit
    mov tmp, #'9'
    cmp ch, tmp
    prhi
    bra .parse_exponent

    mov tmp, #'0'
    cmp ch, tmp
    prlo
    bra .parse_exponent

    sub ch, tmp
    sub exponent, seen_dp
    add exponent, full
    and full, full
    prne
    bra .next_digit

    mov tmp, #0x7f / 10
    cmp mantissa, tmp
    prls
    bra .accept_digit

    mov tmp, #0
    sub ch, #5
    adc mantissa_lo, tmp
    adc mantissa, tmp
    mov full, #1
    add exponent, #1
    bra .next_digit

.accept_digit
    mov tmp, #10
    mul mantissa, tmp
    muh tmp, mantissa_lo
    add mantissa, tmp
    mov tmp, #10
    mul mantissa_lo, tmp
    add mantissa_lo, digit
    prcs
    add mantissa, #1

.next_digit
    ldb ch, [buf]
    add buf, #1
    bra .parse_mantissa_loop

.parse_exponent
    mov exp_sign, #0
    mov tmp, #'E'
    cmp ch, tmp
    prne
    bra .evaluate

    ldb ch, [buf]
    add buf, #1
    mov tmp, #'+'
    cmp ch, tmp
    preq
    bra .parse_exponent_digits_pre

    mov tmp, #'-'
    cmp ch, tmp
    prne
    bra .parse_exponent_loop
    mov exp_sign, #1
    bra .parse_exponent_digits_pre

.parse_exponent_digits_pre
    ldb ch, [buf]
    add buf, #1

.parse_exponent_loop
    mov tmp, #'9'
    cmp ch, tmp
    prhi
    bra .evaluate
    mov tmp, #'0'
    cmp ch, tmp
    prlo
    bra .evaluate
    mov get_exp_value, #1   ;; TODO do something useful with this
    mov tmp, #10
    mul exp_value, tmp
    add exp_value, ch
    ldb ch, [buf]
    add buf, #1
    bra .parse_exponent_loop

.evaluate
    mov tmp, #0
    and exp_sign, exp_sign
    prne
    rsb exp_value, tmp
    add exponent, exp_value

    ;; table is 5 bytes per entry, and valid for exponent in [-11,4]
    mov tmp, #5
    mul exponent, tmp
    mov tmp, #hi(.pow10_table + 5*11)
    add tmp, #lo(.pow10_table + 5*11)
    add tmp, exponent
    
    ldw pow10_mul_hi, [tmp,#0]
    ldw pow10_mul_lo, [tmp,#2]
    ldb exponent, [tmp,#4]

    clz shift, mantissa
    tst shift, #16
    preq
    bra .done_clz

    clz shift, mantissa_lo
    add shift, #16

.done_clz
    sub shift, #1   ; we want to shift highest set bit to bit 30

    sub exponent, shift
    tst shift, #16
    prne
    bra .big_shift

.small_shift
    mov tmp2, mantissa_lo
    lsl mantissa_lo, shift
    lsl mantissa, shift
    mov tmp, #16
    sub tmp, shift
    lsr tmp2, tmp
    orr mantissa, tmp2
    bra .done_shift

.big_shift
    mov mantissa, mantissa_lo
    mov mantissa_lo, #0
    sub shift, #16
    lsl mantissa, shift

.done_shift
    mov tmp, #0
    add mantissa_lo, #1<<15
    adc mantissa, tmp
    prpl
    bra .drop16
    lsr mantissa, #1
    rrx mantissa_lo, #1
    add exponent, #1

.drop16
    mov tmp, mantissa

    muh mantissa, pow10_mul_hi
    muh pow10_mul_lo, tmp
    mul tmp, pow10_mul_hi

    add tmp, pow10_mul_lo
    mov tmp, #0
    prmi                ; test bit 15 of intermediate sum
    mov tmp, #1         ; round up
    adc mantissa, tmp   ; incorporate carry from intermediate sum
    
    tst mantissa, #bit 14
    prne
    bra .normalised

    lsl mantissa, #1
    sub exponent, #1
    bra .f16_round_pack

    ; utility routine
.no_case_cmp3
    ldb ch, [buf]
    bic ch, #bit 5
    ldb tmp, [buf2]
    cmp ch, tmp
    prne
    mov pc, link
    ldb ch, [buf, #1]
    bic ch, #bit 5
    ldb tmp, [buf2, #1]
    cmp ch, tmp
    prne
    mov pc, link
    ldb ch, [buf, #2]
    bic ch, #bit 5
    ldb tmp, [buf2, #2]
    cmp ch, tmp
    mov pc, link

.nan_name
    ds "nan"

.inf_name
    ds "inf"

; 16 * 5 = 80 bytes
.pow10_table
    ; negative powers are expressed as fractions of 1<<32
    ; -11
    dl 0xafe0ff0c
    db 16 +15 +14 -36 

    ; -10
    dl 0xdbe0fecf
    db 16 +15 +14 -33 

    ; -9
    dl 0x89705f41
    db 16 +15 +14 -29 

    ; -8
    dl 0xabc07712
    db 16 +15 +14 -26 

    ; -7
    dl 0xd6b094d6
    db 16 +15 +14 -23 

    ; -6
    dl 0x8630bd06
    db 16 +15 +14 -19 

    ; -5
    dl 0xa7c0ac48
    db 16 +15 +14 -16 

    ; -4
    dl 0xd1b01759
    db 16 +15 +14 -13 

    ; -3
    dl 0x83106e98
    db 16 +15 +14 -9  

    ; -2
    dl 0xa3d00a3e
    db 16 +15 +14 -6  

    ; -1
    dl 0xccc0cccd
    db 16 +15 +14 -4  

    ; Positive powers are shifted left to get leading bit in bit 31,
    ; with an adjusted shift value to compensate.
    ; 0
    dl 0x80000000  
    db 16 +15 +45 -31 
    ; 1
    dl 0xa0000000  
    db 16 +15 +45 -28 
    ; 2
    dl 0xc8000000  
    db 16 +15 +45 -25 
    ; 3
    dl 0x7d000000  
    db 16 +15 +45 -21 
    ; 4
    dl 0x9c400000  
    db 16 +15 +45 -18 
}

