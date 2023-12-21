
.f16_is_normal {
    mov result, #0
    bic a, #.f16_sign_mask
    sub a, #0x400
    mov tmp, #.f16_exp_mask-0x400
    cmp a, tmp
    prlo
    mov result, #1
    mov tmp, #1
    cmp result, tmp
    mov pc, link
}

.f16_is_finite {
    mov result, #0
    bic a, #.f16_sign_mask
    mov tmp, #.f16_exp_mask
    cmp a, tmp
    prlo
    mov result, #1
    mov tmp, #1
    cmp result, tmp
    mov pc, link
}

.f16_is_zero {
    mov result, #0
    bic a, #.f16_sign_mask
    preq
    mov result, #1
    mov pc, link
}

.f16_is_subnormal {
    mov result, #0
    bic a, #.f16_sign_mask
    mov tmp, #0x0400
    cmp a, tmp
    prlo
    mov result, #1
    mov tmp, #1
    cmp result, tmp
    mov pc, link
}

.f16_is_nan {
    mov result, #0
    bic a, #.f16_sign_mask
    mov tmp, #.f16_exp_mask
    cmp a, tmp
    prhi
    mov result, #1
    mov tmp, #1
    cmp result, tmp
    mov pc, link
}

.f16_is_infinite {
    mov result, #0
    bic a, #.f16_sign_mask
    mov tmp, #.f16_exp_mask
    cmp a, tmp
    preq
    mov result, #1
    mov tmp, #1
    cmp result, tmp
    mov pc, link
}


