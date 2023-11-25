;; Adapted from the softfloat library by John R Hauser.
;; See https://github.com/ucb-bar/berkeley-softfloat-3

; Requires f16_internal.asm

; external routine
.f16_sub
{
    alias r9 subtract

    mov tmp, a
    eor tmp, b
    mov subtract, #bit 15
    prmi
    mov subtract, #0
    bra .f16_internal_add_sub
}

.f16_add
{
    alias r9 subtract

    mov tmp, a
    eor tmp, b
    mov subtract, #0
    prmi
    mov subtract, #bit 15
    ; fall through
}

; Internal helper
.f16_internal_add_sub
{
    ; working regs
    alias r5 a_exp
    alias r6 b_exp
    alias r7 z_lo
    alias r8 exp_diff
    alias r9 subtract

    mov z_sign, #.f16_sign_mask         ; assume result has same sign as leading argument
    and z_sign, a

    bic a, #.f16_sign_mask              ; clear signs
    bic b, #.f16_sign_mask

    cmp a, b                            ; compare magnitudes
    prhs
    bra .ordered

.unordered
    mov tmp, b                          ; sort larger number into a, smaller into b
    mov b, a
    mov a, tmp
    eor z_sign, subtract                ; invert sign of result if we're subtracting: (a-b) = -(b-a)

    ; from this point we know a >= b

.ordered
    mov tmp, #.f16_exp_mask             ; extract exponents
    mov a_exp, a
    mov b_exp, b
    lsr a_exp, #10
    lsr b_exp, #10

    bic a, tmp                          ; isolate fractions
    bic b, tmp

    mov exp_diff, a_exp                 ; exponent difference - i.e. how much
    sub exp_diff, b_exp                 ; to shift to align the fractions
    preq
    bra .equal_exponents

.unequal_exponents
    mov tmp, #31                        ; do we have one or more NaN/inf ?
    cmp a_exp, tmp
    prne
    bra .finite

    and a, a                            ; remember, bitwise a>=b - if a is inf, b cannot be NaN
    preq
    bra .f16_return_inf                 ; a is inf, so return inf
    bra .f16_return_nan                 ; otherwise we're dealing with at least one NaN

.finite
    mov tmp, #13                        ; is the difference in exponents so great that the
    cmp exp_diff, tmp                   ; smaller argument will have no effect on the larger,
    prlo                                ; even accounting for the extra rounding bits?
    bra .non_tiny_delta

.tiny_delta
    lsl a_exp, #10                      ; b is so small compared to a, we can just return a
    mov z, a
    add z, a_exp
    orr z, z_sign
    mov pc, link

.equal_exponents
    tst subtract, #bit 15               ; dispatch to subtraction?
    prne
    bra .equal_exponents_sub

    ; We have one of:
    ;   both are zero or subnormal,
    ;   both are inf or nan
    ;   both are normal
.equal_exponents_add
{
    and a_exp, a_exp                    ; check for subnormals
    prne
    bra .neither_subnormal

    .both_subnormal
    ; At this point we know a_exp=b_exp=0, so we can add both as subnormals
    ; (no alignment is required).
    ;
    ; Note: if the sum overflows into bit 10, that's okay as the carry becomes
    ; an implicit 1 bit, and the 1 is instead treated as exp=1.
    ;
    ; Example:
    ;  a = 0 00000 1100000000 + |  0.75 * 2^-14 +
    ;  b = 0 00000 1000000000   |  0.50 * 2^-14
    ;      ------------------ = |  ------------ =
    ;  z = 0 00001 0100000000   |  1.25 * 2^-14
    ;      | |___| |________| 
    ;   sign  exp   fraction
    ;
    ; Interpreting the result as a valid float16, we have
    ; sign=+ exp=1 fra=0.25, so value = (1).25 * 2^(1-15) = 1.25 * 2^-14
    ;
    mov z, a
    add z, b
    orr z, z_sign
    mov pc, link

    .neither_subnormal
    mov tmp, #30                        ; are both args inf/NaN ?
    cmp a_exp, tmp
    prls
    bra .both_normal
    
    ; TODO could re-use earlier inf/nan detection
    and a,a                             ; any nan bits set in either arg?
    preq
    bra .f16_return_inf                 ; both must be inf, so inf result
    bra .f16_return_nan

.both_normal
    mov z_exp, a_exp                    ; prepare result exponent
    mov z, #0x400 * 2                   ; account for a and b's implicit bits
    add z, a                            ; i.e. z = 1.a + 1.b
    add z, b                            ; result will be 10.z or 11.z in binary

    tst z, #bit 0                       ; if trailing bit is zero, we can safely
    preq                                ; shift it off to normalise without
    bra .no_rounding                    ; having to deal with rounding

    ; f16_round_pack wants 4 additional trailing bits - we're already shifted
    ; up by 1 due to the oversized fraction, so we just need to append 000
    lsl z, #3                           
    bra .f16_round_pack                 

.no_rounding
    cmp z_exp, tmp                      ; if exponent would exceed its max after
    prhs                                ; normalisation due to the currently
    bra .f16_return_inf                 ; oversized fraction, return inf

    ; Normalise:
    ;     10.z => 1.0z
    ;     11.z => 1.1z
    ;             ^
    ; The leading 1 will be added to the exponent by f16_return,
    ; so there's no need for us to adjust it here.
    lsr z, #1                           
    bra .f16_return
}

.non_tiny_delta
    ; We have differing exponents, and the delta (in b) is large
    ; enough to have an effect when added/subtracted from a.

    tst subtract, #bit 15               ; select subtract path if indicated
    prne
    bra .unequal_exponents_sub

.unequal_exponents_add
{
    mov z_exp, a_exp                    ; prepare result's exponent
    orr a, #0x400                       ; make larger arg's leading bit explicit

    mov z, b                            ; smaller arg into result accumulator

    and b_exp, b_exp                    ; is b normal?
    prne
    bra .b_is_normal

    lsl z, #1                           ; if subnormal, shift its highest
    bra .b_has_leading_bit              ; bit into the leading bit position

.b_is_normal
    orr z, #0x400                       ; if normal, make leading bit explicit

.b_has_leading_bit
    ; Now we align and add

    mov tmp, #19                        ; we know 1 <= exp_diff <= 12
    rsb exp_diff, tmp                   ; so now  7 <= exp_diff <= 18

    lsl a, #3                           ; shift a left by 16+3 bits
                                        ; (we treat a as the top 16 bits of a
                                        ; a two word pair).

    mov tmp, #16                        ; are we going to have to shift our copy
    cmp exp_diff, tmp                   ; of b by more than a 16-bit word?
    prhs
    bra .big_align

    mov z_lo, z                         ; it's just a small shift
    lsl z_lo, exp_diff                  ; - apply it to the low word

    rsb exp_diff, tmp                   ; get the bits shifted off
    lsr z, exp_diff                     ; the top into the high word
    bra .aligned

.big_align                              ; for a large shift
    sub exp_diff, #16                   ; account for z already being the top 16
    lsl z, exp_diff                     ; and apply the rest of the shift
    mov z_lo, #0                        ; the lo word is filled with 16 zeroes

    ; addition looks like this:
    ;  [a:0]    = 00aaaaaaaaaaa000 : 0000000000000000 +
    ;  [z:z_lo] = 000bbbbbbbbbbb00 : 0000000000000000   (z<<18 @ exp_diff=1)
    ;  [z:z_lo] = 00000000000000bb : bbbbbbbbb0000000   (z<<7  @ exp_diff=12)
    ;             ---------------- - ---------------- =
    ;  [z:z_lo] = 0zzzzzzzzzzzzzzz : zzzzzzzzz0000000
    ;              |
    ;          possible carry at bit 30 (bit 14 of z)
.aligned
    ; we only add the high words as the low word of a is implicitly zero
    add z, a
    tst z, #bit 14                      ; did we generate a carry?
    prne
    bra .unequal_exponents_exit

    ; no carry was generated

    ; shift [z:z_lo] up 1 bit to get the msb into bit 14, bringing a single bit
    ; from z_lo into the lsb of z, avoiding loss of precision
    sub z_exp, #1                       ; compensate for the shift
    lsl z_lo, #1                        ; get msb of z_lo into carry
    adc z, z                            ; shift it into z
    bra .unequal_exponents_exit
}

.equal_exponents_sub
{
    mov tmp, #31                        ; are both args inf/NaN?
    cmp a_exp, tmp
    preq                                ; any subtraction involving a NaN is
    bra .f16_return_nan                 ; defined as NaN, as well as inf-inf

.finite
    ; perform the subtraction
    ;
    ; If we get zero, the result is always +0.
    ;
    ; IEEE754 defines "-0 - +0 => -0", but f16_sub converts that case
    ; to the addition "-0 + -0", so we never have to deal with it.
    mov z, a
    sub z, b                            ; do the subtraction                            
    preq
    bra .f16_return_pos_zero            ; if 0 return +0 

    ; The leading 1 bit will soon be present at bit 10 of the fraction after
    ; it has been shifted, causing the exponent field to be incremented when
    ; the result is packed, so we reduce the exponent now in anticipation,
    ; but not for a subnormal as it will have no leading 1.
    and a_exp, a_exp                    ; subnormals?
    prne
    sub a_exp, #1

    and z, z                            ; positive result?
    prpl
    bra .positive

    mov z, b                            ; otherwise reverse subtract
    sub z, a                            ; to get a positive magnitude
    eor z_sign, #.f16_sign_mask         ; and flip the result sign

.positive
    ; the subtraction is now definitely positive:
    ;
    ; a = 0 00000 aaaaaaaaaa -
    ; b = 0 00000 bbbbbbbbbb
    ;     ------------------ =
    ; z = 0 00000 zzzzzzzzzz
    ;     | |___| |________|
    ;    15 14 10 9        0
    ;  sign  exp|  fraction 
    ;           |
    ;  implicit bit (same position as lowest bit of exp)

    ; Count the number of leading zeroes, discounting the sign and all but
    ; one of the exponent bits (1+5-1 = 5), so that when we later shift the
    ; fraction up its leading 1 will occupy the first bit of the exponent.
    clz exp_diff, z                     
    sub exp_diff, #5                    

    ; The test for subnormal here is < 0 rather than <= 0 because the exponent
    ; was decremented earlier in anticipation of the explicit leading 1 bit of
    ; a normal being added into the exponent field by f16_return.
    mov z_exp, a_exp
    sub z_exp, exp_diff                 ; adjust the exponent
    prmi
    bra .subnormal

.normal
    lsl z, exp_diff                     ; bring the leading bit up to bit 10
    bra .f16_return                     ; it will get added into the exponent

.subnormal
    lsl z, a_exp                        ; no adjustment needed for subnormal
    orr z, z_sign
    mov pc, link
}

.unequal_exponents_sub
{
    mov z_exp, b_exp                    ; 
    add z_exp, #19                      ; TODO - why 19?

    mov z_lo, a
    orr z_lo, #0x400                    ; make leading 1 explicit

    and b_exp, b_exp                    ; is be normal?
    prne
    bra .b_normal

    lsl b, #1                           ; if subnormal, shift its highest
    bra .b_normalised                   ; bit into the leading bit position
                                                                               
.b_normal                                                                      
    orr b, #0x400                       ; if normal, make leading bit explicit

.b_normalised
    ; On entry here:
    ;
    ; [z:z_lo] = 0000000000000000:00000 aaaaaaaaaaa
    ;                                   |
    ;                                  10 - leading bit
    ; and we know 1 <= exp_diff <= 12

    mov z, z_lo                         ; Shift [z:z_lo] (i.e. a) up
    lsl z_lo, exp_diff                  ; by exp_diff so its relative
    mov tmp, #16                        ; alignment with b is correct
    rsb exp_diff, tmp
    lsr z, exp_diff
    
    ; Now we're ready to subtract, things look like this:
    ;
    ; [z:z_lo] = 000000000 0000000:0000aaaaaaaaaaa0 after <<= 1
    ; [z:z_lo] = 000000000 aaaaaaa:aaaa000000000000 after <<= 12
    ;                      |______________________|
    ;                     22                      0
    ;
    ; [0:b]    = 000000000 0000000:00000bbbbbbbbbbb
    ;                                   |
    ;                                  10 - leading bit

    sub z_lo, b                         ; [z:z_lo] -= [0:b]
    prcc
    sub z, #1                           ; account for possible borrow

    ; Result looks like this:
    ;
    ; [z:z_lo] = 000000000 zzzzzzz:zzzzzzzzzzzzzzzz
    ;                      |______________________|
    ;                     22                      0
    ;
    ; Note: some number of leading bits of z will be zero due to cancellation.
    ; Count how many leading zeroes there are
    
    ; exp_diff = clz(z:z_lo)
    clz exp_diff, z                     ; count how many leading zeroes
    tst exp_diff, #16                   ; (i.e. where's the first 1 bit?)
    preq
    bra .done_clz

    clz exp_diff, z_lo                  ; count low word
    add exp_diff, #16                   ; if all 16 high bits were clear

.done_clz
    ; Prepare to shift the leading 1 into position 30 (i.e. bit 14 of z).
    ;
    ; After the shift is applied, we will have the following:
    ;
    ; [z:z_lo] = 0 1 zzzzzzzzzz rrrr:rrrrrrrr 00000000
    ;            | | |________| |___:_______| |______|
    ;       unused |  fraction    rounding     unused 
    ;              |
    ;          leading 1    
    ;             
    ; This helps line things up as expected for rounding later.
    ;
    sub exp_diff, #1
    sub z_exp, exp_diff                 ; correct the exponent before we shift

    ; Remainder of block performs [z:z_lo] <<= exp_diff
    tst exp_diff, #16
    prne
    bra .big_align

.small_align
    mov b, z_lo
    lsl z_lo, exp_diff
    lsl z, exp_diff
    mov tmp, #16
    sub tmp, exp_diff
    lsr b, tmp
    orr z, b

    bra .unequal_exponents_exit         ; round and return result

.big_align
    ; at least a 16 bit shift
    mov z, z_lo                         ; shift 16 zeroes into [z:z_lo]
    mov z_lo, #0
    sub exp_diff, #16                   ; apply the remaining shift
    lsl z, exp_diff

    bra .unequal_exponents_exit         ; round and return result
}

.unequal_exponents_exit
    ; On entry here the final result is in [z:z_lo]
    ;
    ; [z:z_lo] = 0 zzzzzzzzzzz rrrr : rrrrrrrrr 0000000
    ;            | |_________| |__|   |_______| |_____|
    ;           15 14        4 3  0   15      7 6     0
    ;       unused <-fraction> <---rounding---> <unused>
    ;
    ; Treated as a 32-bit quantity, bits 19..0 are used for rounding
    ; (although 7..0 will never be non-zero).
    ; 
    and z_lo, z_lo                      ; are any bits set in the lower word?
    preq
    bra .z_lo_is_zero

    orr z, #bit 0                       ; set z's sticky bit
    bra .f16_round_pack

.z_lo_is_zero
    ; the low word of the result was zero, but...
    mov tmp, #0xf                       ; any rounding bits set in the high word?
    tst z, tmp
    prne
    bra .f16_round_pack                 ; then rounding will be required

    mov tmp, #30                        ; TODO
    cmp z_exp, tmp
    prhs
    bra .f16_round_pack

    lsr z, #4                           ; safe to drop the rounding bits
    bra .f16_return
}

