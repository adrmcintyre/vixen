;;
;; This code is based on the softfloat library by John R Hauser
;; at https://github.com/ucb-bar/berkeley-softfloat-3
;;

.f16_div
{
    ; TODO reduce register usage
    alias r0 a
    alias r1 b
    alias r2 z
    alias r3 rem
    alias r4 a_exp
    alias r5 b_exp
    alias r6 z_exp
    alias r7 z_sign
    alias r8 index
    alias r9 recip
    alias r10 deriv_lo
    alias r11 deriv_hi
    alias r12 tmp
    alias r13 sp
    alias r14 link
    alias r15 pc

    def f16_zero      0x0000
    def f16_min_sub   0x0001
    def f16_max_sub   0x03ff
    def f16_min_norm  0x0400
    def f16_one       0x3c00
    def f16_one_eps   0x3c01
    def f16_two       0x4000
    def f16_three     0x4200
    def f16_max       0x7bff
    def f16_inf       0x7c00
    def f16_min_nan   0x7c01
    def f16_qnan      0x7e00
    def f16_max_nan   0x7fff
    def f16_neg       0x8000

    def f16_sign_mask 0x8000
    def f16_exp_mask  0x7c00

    mov tmp, #.f16_sign_mask
    mov z_sign, a
    eor z_sign, b
    and z_sign, tmp         ; calc result sign
    bic a, #.f16_sign_mask  ; a=abs(a)
    bic b, #.f16_sign_mask  ; b=abs(b)

    mov tmp, #.f16_exp_mask ; exponent mask
    mov a_exp, a
    mov b_exp, b
    bic a, tmp              ; isolate fractions
    bic b, tmp
    lsr a_exp, #10          ; extract exponents
    lsr b_exp, #10

    mov tmp, #0x1f          ; inf/nan indicator

    cmp a_exp, tmp          ; isInfOrNan(a) ?
    prne
    bra .a_finite

    and a, a
    prne
    bra .invalid            ; isNan(a) => NaN
    cmp b_exp, tmp
    preq
    bra .invalid            ; isInfOrNan(b) => NaN
                            ;          else => inf
.infinity
    mov z, #.f16_inf
    orr z, z_sign
    mov pc, link

.a_finite
    cmp b_exp, tmp          ; isInfOrNan(b) ?
    prne
    bra .b_finite
    and b, b
    prne
    bra .invalid            ; isNan(b) => NaN
                            ; else     => 0
.zero
    mov z, z_sign
    mov pc, link

.b_finite
    and b_exp, b_exp        ; isSubOrZero(b) ?
    prne
    bra .b_normal
    and b, b                ; isZero(b) ?
    prne
    bra .b_subnormal
    orr a_exp, a
    prne
    bra .infinity           ; !isZero(a) => inf
                            ;       else => NaN
.invalid
    mov z, #.f16_qnan
    mov pc, link

.b_subnormal
    clz tmp, b              ; normalise b
    sub tmp, #5             ; (shift highest 1 bit up to bit 10)
    lsl b, tmp
    mov b_exp, #1
    sub b_exp, tmp

.b_normal
    and a_exp, a_exp        ; isSubOrZero(a) ?
    prne
    bra .a_normal
    and a, a                ; !isZero(a)
    preq
    bra .zero

    clz tmp, a              ; normalise a - max(tmp) = 15
    sub tmp, #5             ;               max(tmp) = 10
    lsl a, tmp
    mov a_exp, #1
    sub a_exp, tmp          ;               min(a_exp) = -9

    ; a and b have both been normalised at this point

.a_normal
    mov z_exp, a_exp        ; compute result exponent with bias
    sub z_exp, b_exp        ;               max(b_exp) = 30, so min(z_exp) = -9-30 = -39
    add z_exp, #14          ;               min(z_exp) = -39+14 = -25

    orr a, #bit 10          ; set implicit ones
    orr b, #bit 10

    cmp a, b                ; a < b ?
    prhs                
    bra .no_double_a
    sub z_exp, #1           ; double a to ensure result >= 1    min(z_exp) = -25-1 = -26
    lsl a, #1
.no_double_a
    lsl a, #4               ; pad a with 4 trailing 0s for accurate rounding

    mov index, b            ; compute table index
    lsr index, #6
    mov tmp, #0xf
    and index, tmp
    lsl index, #2

    mov tmp, #hi(.f16_recip_approx_data)
    add tmp, #lo(.f16_recip_approx_data)
    add index, tmp
    ldw recip, [index]              ; look up recip=1/x
    ldw deriv_lo, [index, #2]       ; and deriv=1/x^2

    mov tmp, #0x3f                  ; scale deriv by low bits of a (the error)
    and tmp, b
    mov deriv_hi, deriv_lo
    mul deriv_lo, tmp
    muh deriv_hi, tmp

    lsl deriv_hi, #6                ; align prior to subtraction
    lsr deriv_lo, #10
    orr deriv_hi, deriv_lo

    sub recip, deriv_hi             ; adjust recip by scaled deriv

    mov z, a                        ; initial quotient
    muh z, recip

    ;; Calculate: u16 rem = (a << 10) - z * b;
    ;;
    ;; NOTE - the remainder will be 16 bits, but the intermediates reach 32,
    ;; though since we truncate the result, it doesn't actually matter if the
    ;; intermediate terms overflow.
    ;; 
    ;; TODO optimisation
    ;;      lsl a, #10
    ;;      mov rem, a
    ;;  then later when recomputing remainder, we just need
    ;;      mov rem, a
    mov rem, a                      ; compute remainder
    lsl rem, #10
    mov tmp, z
    mul tmp, b
    sub rem, tmp                    ; rem = a - z*b

    muh rem, recip
    lsr rem, #10                    ; remainder indicates our quotient is low,
    add z, rem                      ; so boost proportionally (and vice versa)

    add z, #1
    mov tmp, #7
    tst z, tmp
    prne
    bra .round_pack_to_f16

;;  bic z, #bit 0                   ; redundant as bits 2..0 are known to be 000 here

    mov rem, a                      ; recompute remainder
    lsl rem, #10
    mov tmp, z
    mul tmp, a
    sub rem, tmp                    ; rem = a - z'*b

    prpl                            ; if rem < 0 z must be too large
    bra .adjust_elseif
    sub z, #2                       ; so adjust down
    bra .adjust_endif
.adjust_elseif
    prne                            ; elseif rem > 0, z is too small
    orr z, #bit 0                   ; so adjust up
.adjust_endif

    ; apply "round nearest, ties to even" rule
.round_pack_to_f16
    mov tmp, #0x1d
    cmp z_exp, tmp
    prlo
    bra .round_unspecial            ; z_exp >= 0x1d || z_exp < 0 (unsigned cmp) ?

    and z_exp, z_exp                ; z_exp < 0 ?
    prpl
    bra .round_maybe_huge

    ; subnormal case - at this point -26 <= z_exp <= -1

    ; z = shr_sticky32(z, -z_exp)

    mvn z_exp, z_exp
    add z_exp, #1                   ;   z_exp = -z_exp

    tst z_exp, #16                  ;   (this bit test is only valid because we know z_exp < 32)
    prne                            ;   if (z_exp >= 16)
    mov z_exp, #15                  ;       z_exp = 15

    mov tmp, z                      ;   tmp = z
    lsr z, z_exp                    ;   z >>= z_exp
    mvn z_exp, z_exp
    add z_exp, #17                  ;   z_exp = 16-z_exp
    lsl tmp, z_exp
    prne                            ;   if (tmp << (16-z_exp) != 0)
    orr z, #1                       ;       z |= 1

    mov z_exp, #0                   ; z_exp = 0

    bra .round_unspecial

.round_maybe_huge
    prle                            ; z_exp > 0x1D ?
    bra .round_unspecial

    mov tmp, #8         ; z + roundIncrement >= 0x8000
    add tmp, z
    prmi
    bra .infinity       ; return signed-infinity

.round_unspecial
    
    ; repurpose rem to hold rounding bits
    mov rem, #0xf       ; bottom 4 bits for rounding
    and rem, z

    add z, #8           ; round up
    lsr z, #4           ; lose extra precision bits

    mov tmp, #8
    cmp rem, tmp        ; round to even when roundBits == 0x8 by clearing bit 0
    preq
    bic z, #bit 0

    and z, z            ; did we hit zero?
    preq
    mov z_exp, #0       ; ensure correct zero representation

.pack_result
    lsl z_exp, #10      ; shift exponent into place

    ; note: orr would be incorrect here, as bit 10 of z is
    ; used to indicate an increment to the exponent is wanted
    add z, z_exp        ; combine with fraction
    orr z, z_sign       ; set sign
    mov pc, link

; These constants can be generated by the following code.
; (See https://stackoverflow.com/a/32640889):
;
;   for(int i = 0; i < 16; i++) {
;        double x0 = 1.0+i/16.0;       // left endpoint of interval
;        double x1 = 1.0+(i+1)/16.0;   // right endpoint of interval
;        double f0 = 1.0 / x0;
;        double f1 = 1.0 / x1;
;        double df = f0 - f1;
;        double sl = df * 16.0;        // slope across interval
;        double mp = (x0 + x1) / 2.0;  // midpoint of interval
;        double fm = 1.0 / mp;
;        double ic = fm + df / 2.0;    // intercept at start of interval
;
;        printf("dw %04x %04x\n",
;           (int)(ic * 65536.0 - 0.9999),
;           (int)(sl * 65536.0 + 0.9999));
;   }
;
; This yields the 1.15 fixed point equivalent of the following,
; taking x = 1 + i/16
;
;            1       1                        1       slope
;   slope = --- - --------  ;  intercept = -------- + -----
;            x    x + 1/16                 x + 1/32     2
;
; Where `intercept` starts with the value at the midpoint, and is then shifted up
; the slope to the endpoint. This is instead of evaluating the endpoint directly
; because when the error term is applied based on the slope we want to minimise
; the maximum error either side.
;
; When multiplied by the remaining bits unused in looking up the initial estimate
; `slope` provides the error correction to be subtracted. Note that the `slope`
; constants are scaled by a factor of 16 to makes the most of the 16 bits of
; available precision.

.f16_recip_approx_data
    dw 0xFFC4, 0xF0F1
    dw 0xF0BE, 0xD62C
    dw 0xE363, 0xBFA1
    dw 0xD76F, 0xAC77
    dw 0xCCAD, 0x9C0A
    dw 0xC2F0, 0x8DDB
    dw 0xBA16, 0x8185
    dw 0xB201, 0x76BA
    dw 0xAA97, 0x6D3B
    dw 0xA3C6, 0x64D4
    dw 0x9D7A, 0x5D5C
    dw 0x97A6, 0x56B1
    dw 0x923C, 0x50B6
    dw 0x8D32, 0x4B55
    dw 0x887E, 0x4679
    dw 0x8417, 0x4211
}

