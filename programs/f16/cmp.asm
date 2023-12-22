; Compares two floating point values, and returns a value indicating their
; relative ordering, as well as setting the processor flags in such a way
; that the unsigned predicates can be used. (Despite the fact that floats
; are signed, the signed predicates prlt, prle, prge, prgt will not work
; as expected).
;
;   a < b    : result = -1, flags = -V -C -Z
;   a == b   : result =  0, flags = -V +C +Z
;   a > b    : result = +1, flags = -V +C -Z
;   unordered: result = +2, flags = +V -C -Z
;
; Unordered will be indicated if either or both arguments are NaN.
;
;   prvs is_unordered
;   prvc !is_unordered
;   prlo <
;   prls <=
;   preq ==
;   prhs >=
;   prhi >
;   prne !=
;
; If unordered is a possibility, prvs/prvc should always be checked first.
;
.f16_cmp {
    alias r0 a
    alias r1 b
    alias r2 result
    alias r3 b_abs

    alias r12 tmp
    alias r14 link
    alias r15 pc

    mov result, a
    mov b_abs, b
    bic result, #.f16_sign_mask
    bic b_abs, #.f16_sign_mask

    ; either NaN?
    mov tmp, #.f16_exp_mask
    cmp result, tmp
    prls
    cmp b_abs, tmp
    prhi
    bra .unordered

    ; both +-zero?
    mov tmp, result
    orr tmp, b_abs
    preq
    bra .eq_zeroes

    asr a, #15
    eor result, a

    asr b, #15
    eor b_abs, b

    sub result, b_abs
    preq
    mov pc, link

    mov result, #0
    prgt
    mov result, #2
    sub result, #1
    mov pc, link

.eq_zeroes
    mov result, #1
    sub result, #1      ; -V +C +Z result=0
    mov pc, link

.unordered
    mov result, #0x9000
    add result, result  ; +V +C -Z result=0x2000
    lsr result, #12     ; +V -C -Z result=2
    mov pc, link
}
