#ifndef GUARD_HEADER_H
#define GUARD_HEADER_H

#include <stdbool.h>
#include <stddef.h>

typedef signed char i8;
typedef unsigned char u8;
typedef unsigned short u16;
typedef signed short i16;

typedef struct Dict Dict;
typedef struct Class Class;

// Converts a host pointer to a 16-bit vm pointer.
#define to_p16(p) ((u16) ((u8*) (p)-mem_base))

// Converts a 16-bit vm pointer to a host pointer.
#define from_p16(p) (mem_base+(u16)(p))

// Enumerates all vm opcodes.
typedef enum {
    fail = 0x80, // TODO - doc this
    mark = 0x81, // TODO - doc this

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
    op_for, op_next,
    op_break, op_continue,
    op_class,

    op_iter_init, op_iter_item, op_iter_kv,
    op_range_check, op_range_next,

    // Internal ops
    op_get_global_prop,
    op_set_global_prop,
    op_get_func_slot,
    op_set_func_slot,
    op_get_class_prop,
    op_set_class_prop,
    op_set_class_method,
    op_get_object_slot,
    op_set_object_slot,
    op_get_method_slot,

    op_lit_int,
    op_lit_float,
    op_lit_string,
    op_lit_array,
    op_lit_dict,
    op_lit_class,
    op_lit_func,
    op_lit_method,

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
    op_drop,
    op_drop2,

    op_jump,
    op_jfalse
} Op;

// Enumerates keyword categories.
typedef enum {
    // these entries double as argument counts
    info_fn0,       // function of 0 args
    info_fn1,       // function of 1 arg
    info_fn2,       // function of 2 args
    info_fn3,       // function of 3 args

    info_const,     // constant
    info_cmd0,      // command of 0 args
    info_cmd1,      // command of 1 arg
    info_cmd2,      // command of 2 arg
    info_cmd_any,   // command with an unspecified number of arguments
    info_control,   // a control statement (if, while, etc.)
} OpInfo;

// TODO doc
typedef struct {
    Op op;
    OpInfo info;
} OpData;

// Enumerates each value type.
typedef enum {
    kind_fail,      // an internal failure
    kind_none,      // None - value is ignored
    kind_bool,      // True or False
    kind_int,       // an integer
    kind_float,     // an f16 float
    kind_string,    // a String*
    kind_array,     // an Array*
    kind_dict,      // a Dict*
    kind_token,     // a token in the program text
    kind_func,      // a Func*
    kind_class,     // a Class*
    kind_object,    // an Object*
    kind_bom,       // a BoundObjectMethod*
} Kind;

// A vm value (1-byte type and 2-byte payload).
typedef struct {
    Kind k;     // the type
    // convenience accessors for the payload
    // TODO perhaps should use 'f16 f' instead of 'u16 f'.
    // TODO maybe add 'u16 p' for pointers.
    union {         
        u16 u;
        i16 i;
        u16 f;
    };
} Value;

static const size_t sizeof_Value = 3;

// Points to a token in the program text.
typedef struct {
    u16 hash;
    i16 len;
    const u8* ptr;
} Token;

// Describes a function or method.
typedef struct {
    Dict* slots;    // string -> int: maps each arg or local to its slot number
    u8 nslots;      // number of slots (args + locals)
    u8 nargs;       // number of args
    Class* klass;   // 0 for funcs, otherwise points to the associated class
    u16 vm_addr;    // address of compiled vm code
} Func;

// Represents a string.
typedef struct {
    u16 hash;   // hash of the string
    i16 len;    // length of the string in characters
    u8 data[];  // the bytes of the string
} String;

// Represents a dynamically sized array.
typedef struct {
    i16 len;        // current length of the array in elements
    i16 cap;        // total allocated capacity in elements
    i16 min_cap;    // don't shrink cap below this
    u8* dataptr;    // points to the allocated elements
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
__attribute__((noreturn)) void die(const char* msg);
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
bool token_string_eq(Token* token, String* string);

// Strings
extern String* interned_char_strings[];
extern String* interned_string_empty;
extern String* interned_string_none;
extern String* interned_string_true;
extern String* interned_string_false;
extern String* interned_string_nan;
extern String* interned_string_neg_inf;
extern String* interned_string_pos_inf;
extern String* interned_string_array;
extern String* interned_string_dict;
extern String* interned_string_func;
extern String* interned_string_class;
extern String* interned_string_object;
extern String* interned_string_bom;
extern String* interned_string_unknown;
void strings_init();
String* string_from_token();
String* string_from_char(u8 ch);
String* string_from_data(const u8* data, i16 len);
String* string_new_uninited(i16 len);
void string_rehash(String* string);
bool string_eq(String* s1, String* s2);
String* string_get_slice(String* string, i16 start, i16 end);
String* string_concat(String* str1, String* str2);

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
void emit_string(const String* s);

// Virtual machine
extern bool opt_trace_vm;
__attribute__((noreturn)) void vm_die(const char* msg);
u16 vm_run(const u8* vm_pc_base);
u16 f16_from_float(float f);
float f16_to_float(u16 u);
const char* debug_op_name(u8 op);
Value get_value(const u8* p);
void set_value(u8* p, Value v);
void slice_adjust(i16 *start, i16 *end, i16 *len);

#endif