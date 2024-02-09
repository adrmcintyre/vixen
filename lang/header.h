
#define trace(msg) fprintf(stderr,"[trace] %s\n", msg)

typedef unsigned char u8;
typedef unsigned short u16;

enum {
    fail = 0x80,
    mark = 0x81,

    // Arithmetic operators
    op_neg, op_mul, op_div, op_mod, op_add, op_sub,
    
    // Relational operators
    op_le, op_lt, op_gt, op_ge, op_eq, op_ne,

    // Bitwise operators
    op_bnot, op_band, op_bor, op_beor,

    // Shift operators
    op_asr, op_lsr, op_lsl,
    
    // Logical operators
    op_lnot, op_land, op_lor,

    // Constants
    op_false, op_true, op_nan, op_inf,

    // Built in functions
    op_abs, op_sgn, op_rnd,
    op_sqr, op_int, op_float,
    op_asc, op_chr, op_str, op_len,
    op_left, op_right, op_substr,

    // Statements
    op_print, op_input, op_stop,

    // Control structure tokens
    op_func, op_proc, op_return, op_end,
    op_if, op_else, op_endif,
    op_repeat, op_until,
    op_while, op_wend,
    op_break,

    // Internal ops
    op_ident_get,
    op_ident_set,
    op_slot_get,
    op_slot_set,

    op_lit_int,
    op_lit_float,
    op_lit_string,
    op_lit_array,

    op_index,
    op_slice,
    op_slice_start,
    op_slice_end,
    op_slice_empty,
    op_ident_set_indexed,
    op_slot_set_indexed,

    op_call_proc,
    op_call_func,
    op_return_proc,
    op_return_func,
    op_return_missing,

    op_jump,
    op_jfalse
};

enum {
    kind_fail   = 0,
    kind_bool   = 1,
    kind_int    = 2,
    kind_float  = 3,
    kind_string = 4,
    kind_array  = 5,
    kind_proc   = 6,
    kind_func   = 7
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

static inline u16 ldw(const u8 *p, u16 off) { return *(p+off)<<8 | *(p+off+1); }
static inline void stw(u8 *p, u16 off, u16 w) { *(p+off) = w>>8; *(p+off+1) = w & 0xff; }

extern const u8 *prog_base;
extern u8 *code_base;
extern u8 *code_ptr;

extern u8 heap[];
extern u8 *interned_string_empty;
extern u8 *interned_string_true;
extern u8 *interned_string_false;
extern u8 *interned_string_array;
extern u8 *interned_string_proc;
extern u8 *interned_string_func;
extern u8 *interned_string_unknown;
u8 *string_from_char(u8 ch);
u8 *string_from_data(const u8 *data, u16 len);


void die(const char* msg);

void vm_die(const char* msg);
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
u16 lex_peek_stmt_end();

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
    str_hash   = 0,
    str_len    = 2,
    str_data   = 4
};

enum {
    array_len = 0,
    array_data = 1
};

u16 heap_alloc(u16 n);

u8 control_sp;
void parser_die(const char* msg);
void parse_expr();
void parse_stmt();


u8 func_kind;

void stmt_init();
