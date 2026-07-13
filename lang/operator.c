#include "header.h"

// Note: the lexer expects operators with common prefixes
// to occur with the longest prefix first in these tables.
const u8 unops[] = {
    op_neg,  0x1b, '-',
    op_bnot, 0x1b, '~',
    op_lnot, 0x1b, 'n','o','t',
    fail,    0x00
};

// see note for unops
const u8 binops[] = {
    op_mul,  0x2a, '*',
    op_div,  0x2a, '/',
    op_mod,  0x2a, '%',

    op_add,  0x29, '+',
    op_sub,  0x29, '-',

    op_asr,  0x28, '>','>','>',
    op_lsr,  0x28, '>','>',
    op_ge,   0x27, '>','=',
    op_gt,   0x27, '>',

    op_lsl,  0x28, '<','<',
    op_ne,   0x26, '<','>',
    op_le,   0x27, '<','=',
    op_lt,   0x27, '<',

    op_eq,   0x26, '=','=',

    op_band, 0x25, '&',
    op_bor,  0x24, '|',
    op_beor, 0x24, '^',

    op_land, 0x23, 'a','n','d',
    op_lor,  0x22, 'o','r',
    fail,    0x00
};
