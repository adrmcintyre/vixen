
#define trace(msg) fprintf(stderr,"[trace] %s\n", msg)

typedef unsigned char u8;
typedef unsigned short u16;

enum {
    fail = 0x80,
    mark = 0x81,

    // Operators
    op_neg, op_bnot, op_lnot,
    op_mul, op_div, op_mod,
    op_add, op_sub,
    op_asr, op_lsr, op_lsl,
    op_le, op_lt, op_gt, op_ge,
    op_eq, op_ne,
    op_band,
    op_bor, op_beor,
    op_land,
    op_lor,

    // Other keywords
    op_abs,     op_asc,     op_break,
    op_chr,     op_else,    op_end,
    op_endif,   op_false,   op_float,   op_func,
    op_if,      op_input,   op_int,
    op_left,    op_len,     op_print,   op_proc,
    op_repeat,  op_return,  op_right,
    op_rnd,     op_sgn,     op_sqr,
    op_stop,    op_str,     op_substr,  op_true,
    op_until,   op_wend,    op_while,

    // internal ops
    op_index,
    op_call_proc,
    op_call_func,
    op_ident_get,
    op_ident_set,
    op_slot_get,
    op_slot_set,
    op_lit_int,
    op_lit_float,
    op_lit_str_0,
    op_lit_str_1,
    op_lit_str_n,
    op_jump,
    op_jfalse,
    op_return_func,
    op_return_proc,
    op_return_missing
};

enum {
    kind_fail  = 0,
    kind_bool  = 1,
    kind_int   = 2,
    kind_float = 3,
    kind_str_0 = 4,
    kind_str_1 = 5,
    kind_str_n = 6,
    kind_proc  = 7,
    kind_func  = 8,
};

enum {
    // these entries double as argument counts
    kw_fn0 = 0,
    kw_fn1 = 1,
    kw_fn2 = 2,
    kw_fn3 = 3,

    kw_const   = 4,
    kw_cmd0    = 5,
    kw_cmd_any = 6,
    kw_control = 7
};

extern const u8 *prog_base;
extern u8 *code_base;
extern u8 *code_ptr;

extern u8 heap[];

void die(const char* msg);
u16 vm_run(const u8* vm_pc_base);
u16 f16_from_float(float f);
float f16_to_float(u16 u);
const char* debug_op_name(u8 op);

void emit_op(u8 op);
void emit_byte(u8 b);
void emit_word(u16 w);
void emit_ident(u16 w);

u16 lex_char(u8 ch);
u16 lex_word();
u16 lex_eol();

extern u8 kwop;
extern u8 kwinfo;
u16 lookup_keyword();

enum {
    ident_chain      =  0, // +2
    ident_hash       =  2, // +2
    ident_kind       =  4, // +1
    ident_val        =  5, // +2    // address of code for func

    // make these u16 offsets into the frame instead
    // to save having to compute * 3 on lookup - also
    // allows possibility of variable sized slots
    ident_slot_num   =  7, // +1    // union \ slot index for func local vars/args
    ident_slot_count =  7, // +1    // union / number of slots (inc args) for func

    ident_arg_count  =  8, // +1    // number of args for func
    ident_len        =  9, // +1
    ident_name       = 10  // +len
};

u16 intern_ident();

enum {
    str_len_hi = 0,
    str_len_lo = 1,
    str_data   = 2
};

u16 heap_alloc(u16 n);

void parse_expr();
void parse_stmt();


u8 func_kind;

void stmt_init();
