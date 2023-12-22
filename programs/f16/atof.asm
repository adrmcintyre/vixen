; Parses an ASCII string into a float, stopping at the first
; invalid character. E.g. "123.5xyz" will be parsed to 123.5,
; and r0 will be left pointing at the 'x'.
;
; Arguments
;   r0: pointer to input buffer
; 
; Returns
;   r0: points 1 past last valid character
;   r2: value, V=0 -- on success
;   r2: NaN, V=1   -- on parsing "nan"
;   r2: 0, V=1     -- on failure
;
; The following format is recognised.
;
;   <float> ::=
;       <sign>? ( <mantissa> <exponent>? | <inf> ) |
;       <nan>
;
;   <mantissa> ::=
;       <digit>+ |
;       <digit>+ <point> |
;       <digit>* <point> <digit>+
;
;   <exponent> ::= E <sign>? <digit>+
;   <sign> ::= [-+]
;   <digit> ::= [0-9]
;   <point> ::= '.'
;   <inf> ::= [Ii][Nn][Ff]
;   <nan> ::= [Nn][Aa][Nn]
;
.f16_parse
{
    alias r0 buf
    alias r0 pow10_mul_hi

    alias r1 ch
    alias r1 pow10_mul_lo

    alias r2 cmp_buf
    alias r2 z

    alias r3 z_exp
    alias r4 z_sign

    alias r5 z_lo
    alias r6 flags
    alias r7 tmp2
    alias r8 shift
    alias r9 exp_value

    alias r12 tmp
    alias r13 sp
    alias r14 link
    alias r15 pc

    def flag_seen_dp       0
    def flag_saturated     1
    def flag_exp_sign      2
    def flag_missing_exp   3
    def flag_missing_value 4

    mov cmp_buf, #hi(.nan_name)
    add cmp_buf, #lo(.nan_name)

    stw link, [sp]
    bl .casecmp3
    ldw link, [sp]

    preq
    bra .f16_return_nan

    mov z_sign, #0
    ldb ch, [buf]

    mov tmp, #'+'
    cmp ch, tmp
    preq
    bra .got_sign

    mov tmp, #'-'
    cmp ch, tmp
    prne
    bra .parse_value

    mov z_sign, #0x8000

.got_sign
    add buf, #1

.parse_value
    mov cmp_buf, #hi(.inf_name)
    add cmp_buf, #lo(.inf_name)

    stw link, [sp]
    bl .casecmp3
    ldw link, [sp]

    preq
    bra .f16_return_inf

    mov flags, #bit .flag_missing_value
    ldb ch, [buf]
    mov tmp, #'0'

.leading_zeros_loop
    cmp ch, tmp
    prne
    bra .parse_mantissa

    bic flags, #bit .flag_missing_value
    add buf, #1
    ldb ch, [buf]
    bra .leading_zeros_loop

.parse_mantissa
    mov z, #0
    mov z_lo, #0
    mov z_exp, #0

.parse_mantissa_loop
    tst flags, #bit .flag_seen_dp
    prne
    bra .parse_digit

    mov tmp, #'.'
    cmp ch, tmp
    prne
    bra .parse_digit

    orr flags, #bit .flag_seen_dp
    add buf, #1
    ldb ch, [buf]

.parse_digit
    mov tmp, #'9'
    cmp ch, tmp
    prhi
    bra .parse_exponent

    mov tmp, #'0'
    cmp ch, tmp
    prlo
    bra .parse_exponent

    bic flags, #bit .flag_missing_value

    sub ch, tmp
    tst flags, #bit .flag_seen_dp
    prne
    sub z_exp, #1

    tst flags, #bit .flag_saturated
    preq
    bra .not_saturated
    add z_exp, #1
    bra .next_digit

.not_saturated
    mov tmp, #(0x7fff / 10) & 0xff00
    cmp z, tmp
    prls
    bra .accumulate_digit

    mov tmp, #0
    sub ch, #5
    adc z_lo, tmp
    adc z, tmp
    orr flags, #bit .flag_saturated
    add z_exp, #1
    bra .next_digit

.accumulate_digit
    mov tmp, #10
    mul z, tmp
    muh tmp, z_lo
    add z, tmp
    mov tmp, #10
    mul z_lo, tmp
    add z_lo, ch
    prcs
    add z, #1

.next_digit
    add buf, #1
    ldb ch, [buf]
    bra .parse_mantissa_loop

.parse_exponent
    tst flags, #bit .flag_missing_value
    prne
    bra .error

    mov tmp, #'E'
    eor tmp, ch
    bic tmp, #bit 5
    prne
    bra .evaluate

    orr flags, #bit .flag_missing_exp

    add buf, #1
    ldb ch, [buf]

    mov tmp, #'+'
    cmp ch, tmp
    preq
    bra .got_exponent_sign

    mov tmp, #'-'
    cmp ch, tmp
    prne
    bra .parse_exponent_loop

    orr flags, #bit .flag_exp_sign

.got_exponent_sign
    add buf, #1
    ldb ch, [buf]

.parse_exponent_loop
    mov tmp, #'9'
    cmp ch, tmp
    prhi
    bra .evaluate

    mov tmp, #'0'
    cmp ch, tmp
    prlo
    bra .evaluate

    sub ch, tmp
    bic flags, #bit .flag_missing_exp
    mov tmp, #10
    mul exp_value, tmp
    add exp_value, ch
    add buf, #1
    ldb ch, [buf]
    bra .parse_exponent_loop

.evaluate
    tst flags, #bit .flag_missing_exp
    prne
    bra .error

    add buf, #1

    mov tmp, #0
    tst flags, #bit .flag_exp_sign
    prne
    rsb exp_value, tmp
    add z_exp, exp_value

    ;; table is 5 bytes per entry, and valid for z_exp in [-11,4]
    mov tmp, #5
    mul z_exp, tmp
    mov tmp, #hi(.pow10_table + 5*11)
    add tmp, #lo(.pow10_table + 5*11)
    add tmp, z_exp

    ldw pow10_mul_hi, [tmp,#0]
    ldw pow10_mul_lo, [tmp,#2]
    ldb z_exp, [tmp,#4]

    clz shift, z
    tst shift, #16
    preq
    bra .done_clz

    clz shift, z_lo
    add shift, #16

.done_clz
    sub shift, #1   ; we want to shift highest set bit to bit 30

    sub z_exp, shift
    tst shift, #16
    prne
    bra .big_shift

.small_shift
    mov tmp2, z_lo
    lsl z_lo, shift
    lsl z, shift
    mov tmp, #16
    sub tmp, shift
    lsr tmp2, tmp
    orr z, tmp2
    bra .done_shift

.big_shift
    mov z, z_lo
    mov z_lo, #0
    sub shift, #16
    lsl z, shift

.done_shift
    mov tmp, #1<<15
    add z_lo, tmp
    mov tmp, #0
    adc z, tmp
    prpl
    bra .drop16
    lsr z, #1
    rrx z_lo
    add z_exp, #1

.drop16
    mov tmp, z

    muh z, pow10_mul_hi
    muh pow10_mul_lo, tmp
    mul tmp, pow10_mul_hi

    add tmp, pow10_mul_lo
    mov tmp, #0
    prmi                ; test bit 15 of intermediate sum
    mov tmp, #1         ; round up
    adc z, tmp          ; also incorporate carry from intermediate sum

    tst z, #bit 14
    prne
    bra .f16_round_pack

    lsl z, #1
    sub z_exp, #1
    bra .f16_round_pack

.error
    mov r2, #0x8000 
    add r2, r2              ; r2=0 and sets V
    mov pc, link

    ; utility routine
.casecmp3
    ldb ch, [buf]
    ldb tmp, [cmp_buf]
    eor tmp, ch
    bic tmp, #bit 5
    prne
    mov pc, link

    ldb ch, [buf, #1]
    ldb tmp, [cmp_buf, #1]
    eor tmp, ch
    bic tmp, #bit 5
    prne
    mov pc, link

    ldb ch, [buf, #2]
    ldb tmp, [cmp_buf, #2]
    eor tmp, ch
    bic tmp, #bit 5
    prne
    mov pc, link

    add buf, #3
    cmp ch, ch
    mov pc, link

.nan_name
    ds "NAN"

.inf_name
    ds "INF"

; 16 * 5 = 80 bytes
.pow10_table
    ; negative powers are expressed as fractions of 1<<32
    ; -11
    dl 0xafebff0c
    db 44 -36

    ; -10
    dl 0xdbe6fecf
    db 44 -33

    ; -9
    dl 0x89705f41
    db 44 -29

    ; -8
    dl 0xabcc7712
    db 44 -26

    ; -7
    dl 0xd6bf94d6
    db 44 -23

    ; -6
    dl 0x8637bd06
    db 44 -19

    ; -5
    dl 0xa7c5ac48
    db 44 -16

    ; -4
    dl 0xd1b71759
    db 44 -13

    ; -3
    dl 0x83126e98
    db 44 -9

    ; -2
    dl 0xa3d70a3e
    db 44 -6

    ; -1
    dl 0xcccccccd
    db 44 -3

    ; Positive powers are shifted left to get leading bit in bit 31,
    ; with an adjusted shift value to compensate.
    ; 0
    dl 0x80000000
    db 44 +32 -31
    ; 1
    dl 0xa0000000
    db 44 +32 -28
    ; 2
    dl 0xc8000000
    db 44 +32 -25
    ; 3
    dl 0x7d000000
    db 44 +32 -21
    ; 4
    dl 0x9c400000
    db 44 +32 -18

    align
}

