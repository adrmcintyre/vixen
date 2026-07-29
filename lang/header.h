#if !defined GUARD_HEADER_H
#define GUARD_HEADER_H

#include <stdbool.h>
#include <stddef.h>

typedef signed char i8;
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

    // existence operator
    op_in,

    // Bitwise operators
    op_bnot, op_band, op_bor, op_beor,

    // Shift operators
    op_asr, op_lsr, op_lsl,
    
    // Logical operators
    op_lnot, op_land, op_lor,

    // Constants
    op_none, op_false, op_true, op_nan, op_inf,

    // Built in functions
    op_abs, op_sgn, op_rnd,
    op_sqr, op_int, op_float,
    op_asc, op_chr, op_str, op_len, op_pop,

    // Statements
    op_print, op_input, op_stop,
    op_append, op_extend,

    // Control structure tokens
    op_func, op_return, op_end,
    op_if, op_else, op_endif,
    op_repeat, op_until,
    op_while, op_wend,
    op_break,
    op_class,

    // Internal ops
    op_ident_get,
    op_ident_set,
    op_slot_get,
    op_slot_set,

    op_lit_int,
    op_lit_float,
    op_lit_string,
    op_lit_array,
    op_lit_dict,
    op_lit_ident,

    op_get_index,
    op_get_slice,
    op_get_slice_start,
    op_get_slice_end,
    op_get_slice_empty,

    op_set_index,
    op_set_slice,
    op_set_slice_start,
    op_set_slice_end,
    op_set_slice_empty,

    op_lit_object,
    op_get_prop,
    op_set_prop,
    op_call_method,

    op_call,
    op_return_none,

    op_jump,
    op_jfalse
} Op;

typedef enum {
    // these entries double as argument counts
    info_fn0,
    info_fn1,
    info_fn2,
    info_fn3,

    info_const,
    info_cmd0,
    info_cmd1,
    info_cmd2,
    info_cmd_any,
    info_control,
} OpInfo;

typedef struct {
    Op op;
    OpInfo info;
} OpData;

typedef enum {
    kind_fail,
    kind_none,
    kind_bool,
    kind_int,
    kind_float,
    kind_string,
    kind_array,
    kind_dict,
    kind_token_proxy,
    kind_ident,
    kind_func,
    kind_class,
    kind_object,
} Kind;

typedef struct {
    Kind k;
    union {
        u16 u;
        i16 i;
        u16 f;
    };
} Value;

static const size_t sizeof_Value = 3;

typedef struct {
    u16 hash;
    i16 len;
    u16 ptr;
} TokenProxy;

typedef struct {
    Value val;

    // make this a u16 offset into the frame instead
    // to save having to compute * 3 on lookup - also
    // allows possibility of variable sized slots
    //
    // slot index for func local vars/args
    // number of slots (inc args) for func
    u8 slot;

    u16 nameptr;
} Ident;

typedef struct {
    u8 slots;
    u8 args;
    u16 addr;
} Func;

typedef struct {
    u16 hash;
    i16 len;
    u8 data[];
} String;

typedef struct {
    i16 len;
    u16 cap;
    u16 dataptr;
} Array;

// Gross memory map
static const size_t mem_size = 65536;
static const u16 heap_max = 0x1000;
static const u16 code_max = 0x1000;
static const u16 vm_stack_max = 1536;

static const size_t mem_heap_offset = 0x0000;
static const size_t mem_code_offset = 0x1000;
static const size_t mem_vm_stack_offset = 0x2000;

extern u8* mem_base;
extern u8* heap_base;
extern u8* vm_stack_base;

extern const u8* prog_base;

// Utils
void die(const char* msg);
u16 hash_mem(const u8* p, u16 len);

// Keywords
extern OpData kw;
bool lookup_keyword();

// Operators
extern const u8 binops[];
extern const u8 unops[];

// Heap
void heap_init();
u8* heap_alloc(u16 n);

// Identifiers
typedef struct Dict Dict;
void ident_init();
Ident* ident_intern(Dict* scope_dict, bool* is_new);
int token_proxy_eq_string(TokenProxy* proxy, String* string);

// Strings
extern String* string_bucket[];
extern String* interned_string_empty;
extern String* interned_string_none;
extern String* interned_string_true;
extern String* interned_string_false;
extern String* interned_string_array;
extern String* interned_string_dict;
extern String* interned_string_func;
extern String* interned_string_class;
extern String* interned_string_object;
extern String* interned_string_unknown;
void strings_init();
String* string_from_token();
String* string_from_char(u8 ch);
String* string_from_data(const u8* data, i16 len);
int string_eq(String* s1, String* s2);
String* string_get_slice(String* string, i16 start, i16 end);

// Lexer
extern const u8* input_ptr;
extern const u8* token_ptr;
extern i16 token_len;
bool lex_char(u8 ch);
bool lex_word();
void unlex_word();
bool lex_peek_stmt_end();
Kind lex_number();
String* lex_string();
bool lex_comment();
bool lex_end_of_stream();

// Code generation
extern bool opt_trace_emit;
extern u8* code_base;
extern u8* code_ptr;
extern u8* last_op_ptr;
void emit_op(Op op);
void emit_byte(u8 b);
void emit_word(u16 w);
void emit_ident(Ident* ident);

// Statement parser
Kind func_kind;
u8 control_sp;
void parse_stmt();
void stmt_init();

// Parser
void parse_start();
void parse_line();
void parse_finish();
void parser_die(const char* msg);
void parse_expr();
bool parse_index_arg();

// Virtual machine
extern bool opt_trace_vm;
void vm_die(const char* msg);
u16 vm_run(const u8* vm_pc_base);
u16 f16_from_float(float f);
float f16_to_float(u16 u);
const char* debug_op_name(u8 op);
Value get_value(const u8* p);
void set_value(u8* p, Value v);
void slice_adjust(i16 *start, i16 *end, i16 *len);

#endif