#include "header.h"

const char* debug_op_names[] = {
    "fail",
    "mark",

    // Arithmetic operators
    "op_neg", "op_mul", "op_div", "op_mod", "op_add", "op_sub",
    
    // Relational operators
    "op_le", "op_lt", "op_gt", "op_ge", "op_eq", "op_ne",

    // Existence operator
    "op_in",

    // Bitwise operators
    "op_bnot", "op_band", "op_bor", "op_beor",

    // Shift operators
    "op_asr", "op_lsr", "op_lsl",
    
    // Logical operators
    "op_lnot", "op_land", "op_lor",

    // Constants
    "op_none", "op_false", "op_true", "op_nan", "op_inf",

    // Built in functions
    "op_abs", "op_sgn", "op_rnd",
    "op_sqr", "op_int", "op_float",
    "op_asc", "op_chr", "op_str", "op_len", "op_pop",

    // Statements
    "op_print", "op_input", "op_stop",
    "op_append", "op_extend",

    // Control structure tokens
    "op_func", "op_return", "op_end",
    "op_if", "op_else", "op_endif",
    "op_repeat", "op_until",
    "op_while", "op_wend",
    "op_break",
    "op_class",

    // Internal ops
    "op_get_global_prop",
    "op_set_global_prop",
    "op_get_func_slot",
    "op_set_func_slot",
    "op_get_class_prop",
    "op_set_class_prop",
    "op_set_class_method",
    "op_get_object_slot",
    "op_set_object_slot",
    "op_get_method_slot",

    "op_lit_int",
    "op_lit_float",
    "op_lit_string",
    "op_lit_array",
    "op_lit_dict",
    "op_lit_class",
    "op_lit_func",
    "op_lit_method",

    "op_get_index",
    "op_get_slice",
    "op_get_slice_start",
    "op_get_slice_end",
    "op_get_slice_empty",

    "op_set_index",
    "op_set_slice",
    "op_set_slice_start",
    "op_set_slice_end",
    "op_set_slice_empty",

    "op_lit_object",
    "op_get_prop",
    "op_set_prop",
    "op_call_method",

    "op_call",
    "op_return_none",
    "op_drop",

    "op_jump",
    "op_jfalse"
};

// Returns the name of the vm opcode specified by op.
const char* debug_op_name(u8 op)
{
    if (op & 0x80) return debug_op_names[op-0x80];
    return "<invalid>";
}

