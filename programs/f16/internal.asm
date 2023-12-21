;; Adapted from the softfloat library by John R Hauser.
;; See https://github.com/ucb-bar/berkeley-softfloat-3

; common fp regs
alias r0 a
alias r1 b
alias r2 z
alias r3 z_exp
alias r4 z_sign

alias r12 tmp
alias r13 sp
alias r14 link
alias r15 pc

; well known values
def f16_zero      0x0000    ; 0
def f16_min_sub   0x0001    ; smallest subnormal
def f16_max_sub   0x03ff    ; largest subnormal
def f16_min_norm  0x0400    ; smallest normal
def f16_one       0x3c00    ; 1
def f16_one_eps   0x3c01    ; 1+epsilon
def f16_two       0x4000    ; 2
def f16_three     0x4200    ; 3
def f16_max_fin   0x7bff    ; largest finite number
def f16_inf       0x7c00    ; infinity
def f16_min_nan   0x7c01    ; smallest valid NaN
def f16_qnan      0x7e00    ; smallest quiet NaN
def f16_max_nan   0x7fff    ; largest valid NaN
def f16_neg       0x8000    ; negative sign bit

def f16_sign_mask 0x8000    ; mask for sign bit
def f16_exp_mask  0x7c00    ; mask for exponent

.f16_round_pack
{
    ; working register
    alias r6 round_bits

    ; apply "round nearest, ties to even" rule
    mov tmp, #0x1d
    cmp z_exp, tmp
    prlo
    bra .round_unspecial            ; z_exp >= 0x1d || z_exp < 0 (unsigned cmp) ?

    and z_exp, z_exp                ; z_exp < 0 ?
    prpl
    bra .round_maybe_huge

    mvn z_exp, z_exp
    add z_exp, #1                   ;   z_exp = -z_exp

    ; z = (u16) shiftRightJam32(z, z_exp)
    ; which expands to:
    ; (dist < 31) ? a>>dist | ((uint32_t) (a<<(-dist & 31)) != 0) : (a != 0);

.shift_right_jam {
    mov tmp, #15
    cmp z_exp, tmp
    prhs
    bra .big_shift
    mov tmp, z
    lsr z, z_exp
    mvn z_exp, z_exp
    add z_exp, #17
    lsl tmp, z_exp
    prne
    orr z, #bit 0
    bra .endif
.big_shift
    and z, z
    prne
    mov z, #1
.endif
}

    mov z_exp, #0                   ; z_exp = 0
    bra .round_unspecial

.round_maybe_huge
    cmp z_exp, tmp
    prgt                            ; z_exp > 0x1D ?
    bra .f16_return_inf

    mov tmp, #8         ; z + roundIncrement >= 0x8000
    add tmp, z
    prmi
    bra .f16_return_inf ; return signed-infinity

.round_unspecial
    mov round_bits, #0xf ; bottom 4 bits for rounding
    and round_bits, z

    add z, #8           ; round up
    lsr z, #4           ; lose extra precision bits

    mov tmp, #8
    cmp round_bits, tmp ; round to even when roundBits == 0x8 by clearing bit 0
    preq
    bic z, #bit 0

    and z, z            ; did we hit zero?
    preq
    mov z_exp, #0       ; ensure correct zero representation
}

.f16_return
    lsl z_exp, #10      ; shift exponent into place

    ; note: orr would be incorrect here, as bit 10 of z is
    ; used to indicate an increment to the exponent is wanted
    add z, z_exp        ; combine with fraction
    orr z, z_sign       ; set sign
    mov pc, link

.f16_return_inf
    mov z, #.f16_inf
    orr z, z_sign
    add z, #0           ; clear V
    mov pc, link

.f16_return_nan
    mov z, #0x8000 | (.f16_qnan>>1)
    add z, z            ; z = f16_qnan, with V set
    mov pc, link

.f16_return_zero
    mov z, z_sign
    add z, #0           ; clear V
    mov pc, link

.f16_return_pos_zero
    mov z, #0
    add z, #0           ; clear V
    mov pc, link

