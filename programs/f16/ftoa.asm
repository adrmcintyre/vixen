; Converts the float x to an ascii string placed in memory pointed to
; by buf, which must have sufficient space for the converted string.
;
; On return, buf points to one past the last character written.
;
; A '-' sign is inserted for numbers < 0, but '+' is not used for numbers >= 0.
; A '.' decimal point is only inserted for numbers with a fractional part.
; A leading '0' is always inserted for numbers < 1 in magnitude.
; Exponential notation is not used (i.e. 1000 is converted to "1000" not "1e3").
; +inf is converted to "inf"
; -inf is converted to "-inf"
; NaN is converted to "nan"
; 
.f16_to_ascii
{
    alias r0 x
    alias r1 buf
    alias r2 exp
    alias r3 sign
    alias r4 digit
    alias r5 hulp_hi
    alias r6 hulp_lo
    alias r7 whole
    alias r8 outputting
    alias r9 ptr
    alias r10 trial
    alias r11 x_hi
    alias r12 tmp
    alias r13 sp
    alias r14 link
    alias r15 pc

    ; split into sign, exp and fra
    mov sign, x
    bic x, #.f16_sign_mask
    prne
    bra .non_zero

    mov digit, #'0'
    stw digit, [buf, #0]
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
    ldb digit, [tmp, #0]
    stb digit, [buf, #0]
    ldb digit, [tmp, #1]
    stb digit, [buf, #1]
    ldb digit, [tmp, #2]
    stb digit, [buf, #2]
    add buf, #3
    mov pc, link

.numeric
    bic sign, x
    preq
    bra .positive

    mov digit, #'-'
    stb digit, [buf]
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
    bic x, tmp

    ;; THE MEAT ...

    mov hulp_hi, #0
    mov hulp_lo, #1

    mov tmp, #15
    cmp exp, tmp
    prlt
    bra .fractional

    mov whole, x
    orr whole, #bit 10

    mov tmp, #25
    cmp exp, tmp
    prgt
    bra .huge

    sub tmp, exp        ; 15 <= exp <= 25, so 0 <= tmp <= 10
    lsr whole, tmp

    sub exp, #9         ; 6 <= exp <= 16
    lsl x, exp
    lsl hulp_lo, exp
    adc hulp_hi, hulp_hi
    bra .output_whole

.huge
    sub exp, tmp        ; tmp=25 still
    lsl whole, exp
    mov x, #0

.output_whole
    mov outputting, #0
    mov ptr, #hi(.digit_bit_table)
    add ptr, #lo(.digit_bit_table)

    ldw trial, [ptr]

.whole_digit_loop
    mov digit, #0

.whole_bit_loop
    lsl digit, #1
    cmp whole, trial
    prlo
    bra .whole_next_bit

    sub whole, trial
    orr digit, #1
    mov outputting, #1

.whole_next_bit
    add ptr, #2
    ldw trial, [ptr]
    tst trial, #bit 15
    preq
    bra .whole_bit_loop

    add digit, #'0'
    bic trial, #bit 15
    preq
    bra .whole_done

    and outputting, outputting
    preq
    bra .whole_digit_loop

    stb digit, [buf]
    add buf, #1
    bra .whole_digit_loop

.whole_done
    stb digit, [buf]
    add buf, #1

    ;; [x_hi:x] <<= 12;
    mov x_hi, x
    lsr x_hi, #4
    lsl x, #12

    ;; hulp <<= 11
    mov hulp_hi, hulp_lo
    lsl hulp_lo, #11
    lsr hulp_hi, #5
    bra .output_fraction

.fractional
    and exp, exp
    prne
    bra .normal

    lsl x, #1
    lsl hulp_lo, #1
    bra .widen

.normal
    orr x, #bit 10

.widen
    mov tmp, #'0'
    stb tmp, [buf]
    add buf, #1

    mov tmp, #16
    add exp, #2

    cmp exp, tmp
    prlo
    bra .widen_small

    sub exp, #16
    mov hulp_hi, hulp_lo
    lsl hulp_hi, exp
    mov hulp_lo, #0

    mov x_hi, x
    lsl x_hi, exp
    lsl x_hi, #1
    mov x, #0
    bra .output_fraction

.widen_small
    mov x_hi, x
    lsl x, exp

    mov hulp_hi, hulp_lo
    lsl hulp_lo, exp

    rsb exp, tmp
    lsr hulp_hi, exp
    lsr x_hi, exp

    lsl x, #1
    adc x_hi, x_hi

.output_fraction
    and x, x                            ; if (frac != 0) {
    preq
    and x_hi, x_hi
    preq
    bra .terminate

    mov tmp, #'.'                       ;   *buf++ = '.'
    stb tmp, [buf]
    add buf, #1

.output_frac_loop                       ;   while(1) {
    mov tmp, #10                        ;       hulp *= 10
    mul hulp_hi, tmp
    muh tmp, hulp_lo
    add hulp_hi, tmp
    mov tmp, #10
    mul hulp_lo, tmp

    mul x_hi, tmp                       ;       x *= 10
    muh tmp, x
    add x_hi, tmp
    mov tmp, #10
    mul x, tmp

    mov digit, x_hi                     ;       digit = x>>28
    lsr digit, #(28-16)
    mov tmp, #0xf000                    ;       x &= ~(0xf<<28)
    bic x_hi, tmp

    add digit, #'0'                     ;       *buf++ = '0' + digit
    stb digit, [buf]
    add buf, #1

    tst x_hi, #bit (27-16)              ;       if (x & (1<<27)) {
    preq
    bra .not_roundup

    mov tmp, x                          ;           if ( ((x+hulp) >> 28) >= 1) {
    add tmp, hulp_lo
    mov tmp, x_hi
    adc tmp, hulp_hi
    lsr tmp, #(28-16)
    preq
    bra .output_frac_loop

    mov tmp, #'9'
    mov ptr, buf                        ;               ptr = buf

.inc_nines
    sub ptr, #1
    ldb digit, [ptr]                    ;               while(*--ptr == '9') {
    cmp digit, tmp                      ;
    prne
    bra .inc_nines_done

    sub digit, #'9'-'0'                 ;                   (*ptr) -= '9'-'0'
    stb digit, [ptr]
    bra .inc_nines                      ;               }

.inc_nines_done
    mov tmp, #'.'                       ;               if (*ptr != '.') {
    cmp digit, tmp
    preq
    bra .inc_dp_todo

    add digit, #1                       ;                   (*ptr) += 1;
    stb digit, [ptr]
    bra .terminate                      ;               }

.inc_dp_todo                            ;               else {
    hlt                                 ;                   // TODO
                                        ;               }
.inced_frac                             ;           }
    bra .output_frac_loop_end           ;       }

.not_roundup                            ;       else {
    cmp x_hi, hulp_hi                   ;           if (frac <= hulp) {
    prhi
    bra .output_frac_loop
    prlo
    bra .output_frac_loop_end           ;               break
    cmp x, hulp_lo
    prhi
    bra .output_frac_loop               ;       }

.output_frac_loop_end
    mov ptr, buf
    sub ptr, #1

.terminate
    mov tmp, #0
    stb tmp, [buf]
    add buf, #1
    mov pc, link

.nan_name
    ds "nan"

.inf_name
    ds "inf"
    align

.digit_bit_table
    dw 40000
    dw 20000
    dw 10000
    dw  8000 | 0x8000
    dw  4000
    dw  2000
    dw  1000
    dw   800 | 0x8000
    dw   400
    dw   200
    dw   100
    dw    80 | 0x8000
    dw    40
    dw    20
    dw    10
    dw     8 | 0x8000
    dw     4
    dw     2
    dw     1
    dw     0 | 0x8000
}
