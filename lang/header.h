#include <stdbool.h>

#define trace(msg) fprintf(stderr,"[trace] %s\n", msg)

typedef unsigned char u8;
typedef unsigned short u16;
typedef signed short i16;

#define to_p16(p) ((u16) ((u8*) (p)-mem_base))
#define from_p16(p) (mem_base+(u16)(p))

typedef enum {
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
} Op;

typedef enum {
    // these entries double as argument counts
    info_fn0 = 0,
    info_fn1 = 1,
    info_fn2 = 2,
    info_fn3 = 3,

    info_const   = 4,
    info_cmd0    = 5,
    info_cmd_any = 6,
    info_control = 7
} OpInfo;

typedef struct {
    Op op;
    OpInfo info;
} OpData;

typedef enum {
    kind_fail   = 0,
    kind_bool   = 1,
    kind_int    = 2,
    kind_float  = 3,
    kind_string = 4,
    kind_array  = 5,
    kind_proc   = 6,
    kind_func   = 7
} Kind;

typedef struct {
    Kind k;
    union {
        u16 u;
        i16 i;
        u16 f;
    };
} Value;

typedef struct Ident Ident;

typedef struct Ident {
    Ident* chain;
    u16 hash;
    Value val;

    // make this a u16 offset into the frame instead
    // to save having to compute * 3 on lookup - also
    // allows possibility of variable sized slots
    //
    // slot index for func local vars/args
    // number of slots (inc args) for func
    u8 slot;

    // number of args for func
    u8 args;
    u8 len;
    u8 name[];
} Ident;

typedef struct {
    u16 hash;
    u16 len;
    u8 data[];
} String;

typedef struct {
    u8 len;
    u8 data[];
} Array;

extern u8* mem_base;
extern const u8* prog_base;
extern u8* code_base;
extern u8* code_ptr;

extern u8 heap[];
extern String* interned_string_empty;
extern String* interned_string_true;
extern String* interned_string_false;
extern String* interned_string_array;
extern String* interned_string_proc;
extern String* interned_string_func;
extern String* interned_string_unknown;
String* string_from_char(u8 ch);
String* string_from_data(const u8* data, u16 len);

void die(const char* msg);

extern u8* vm_stack_base;
const u16 vm_stack_max;
void vm_die(const char* msg);
u16 vm_run(const u8* vm_pc_base);
u16 f16_from_float(float f);
float f16_to_float(u16 u);
const char* debug_op_name(u8 op);

extern bool opt_emit_log;

void emit_op(Op op);
void emit_byte(u8 b);
void emit_word(u16 w);
void emit_ident(Ident* ident);

bool lex_char(u8 ch);
bool lex_word();
bool lex_peek_stmt_end();

extern OpData kw;
bool lookup_keyword();

Ident* intern_ident(bool* is_new);

u8* heap_alloc(u16 n);

u8 control_sp;
void parser_die(const char* msg);
void parse_expr();
void parse_stmt();


Kind func_kind;

void stmt_init();
