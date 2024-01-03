
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
    op_endif,   op_false,   op_func,
    op_if,      op_input,   op_int,
    op_left,    op_len,     op_print,
    op_repeat,  op_return,  op_right,
    op_rnd,     op_sgn,     op_sqr,
    op_stop,    op_str, op_substr,  op_true,
    op_until,   op_wend,    op_while,

    // internal ops
    op_index,
    op_call,
    op_ident_get,
    op_ident_set,
    op_lit_int,
    op_lit_float,
    op_lit_str_empty,
    op_lit_str_char,
    op_lit_str_prog,
    op_jump,
    op_jfalse
};

enum {
    kind_fail      = 0,
    kind_int       = 1,
    kind_float     = 2,
    kind_str_empty = 3,
    kind_str_char  = 4,
    kind_str_prog  = 5,
    kind_str_heap  = 6
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

extern u8 kwop;
extern u8 kwinfo;
u16 lookup_keyword();

u16 intern_ident();
void parse_expr();
void parse_stmt();

void stmt_init();
