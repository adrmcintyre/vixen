#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "header.h"

const char* op_names[] = {
    "fail",
    "mark",

    // Arithmetic operators
    "op_neg", "op_mul", "op_div", "op_mod", "op_add", "op_sub",
    
    // Relational operators
    "op_le", "op_lt", "op_gt", "op_ge", "op_eq", "op_ne",

    // Bitwise operators
    "op_bnot", "op_band", "op_bor", "op_beor",

    // Shift operators
    "op_asr", "op_lsr", "op_lsl",
    
    // Logical operators
    "op_lnot", "op_land", "op_lor",

    // Constants
    "op_false", "op_true", "op_nan", "op_inf",

    // Built in functions
    "op_abs", "op_sgn", "op_rnd",
    "op_sqr", "op_int", "op_float",
    "op_asc", "op_chr", "op_str", "op_len",
    "op_left", "op_right", "op_substr",

    // Statements
    "op_print", "op_input", "op_stop",

    // Control structure tokens
    "op_func", "op_proc", "op_return", "op_end",
    "op_if", "op_else", "op_endif",
    "op_repeat", "op_until",
    "op_while", "op_wend",
    "op_break",

    // Internal ops
    "op_ident_get",
    "op_ident_set",
    "op_slot_get",
    "op_slot_set",

    "op_lit_int",
    "op_lit_float",
    "op_lit_string",
    "op_lit_array",

    "op_index",
    "op_slice",
    "op_slice_start",
    "op_slice_end",
    "op_slice_empty",
    "op_ident_set_indexed",
    "op_slot_set_indexed",

    "op_call_proc",
    "op_call_func",
    "op_return_proc",
    "op_return_func",
    "op_return_missing",

    "op_jump",
    "op_jfalse"
};

const char* debug_op_name(u8 op)
{
    if (op & 0x80) return op_names[op-0x80];
    return "<invalid>";
}

// each table should be arranged in ascii order
const u8 keywords_hpx[] = {
    op_print,    info_cmd_any,  'p','r','i','n','t',
    op_proc,     info_control,  'p','r','o','c',
    fail, 0
};
const u8 keywords_aiqy[] = {
    op_inf,      info_const,    'I','n','f',

    op_abs,      info_fn1,      'a','b','s',
    op_asc,      info_fn1,      'a','s','c',

    op_if,       info_control,  'i','f',
    op_input,    info_cmd_any,  'i','n','p','u','t',
    op_int,      info_fn1,      'i','n','t',
    fail, 0
};
const u8 keywords_bjrz[] = {
    op_break,    info_control,  'b','r','e','a','k',
    op_repeat,   info_control,  'r','e','p','e','a','t',
    op_return,   info_control,  'r','e','t','u','r','n',
    op_right,    info_fn2,      'r','i','g','h','t',
    op_rnd,      info_fn0,      'r','n','d',
    fail, 0
};
const u8 keywords_cks[] = {
    op_chr,      info_fn1,      'c','h','r',

    op_sgn,      info_fn1,      's','g','n',
    op_sqr,      info_fn1,      's','q','r',
    op_stop,     info_cmd0,     's','t','o','p',
    op_str,      info_fn1,      's','t','r',
    op_substr,   info_fn3,      's','u','b','s','t','r',
    fail, 0
};
const u8 keywords_dlt[] = {
    op_true,     info_const,    'T','r','u','e',

    op_left,     info_fn2,      'l','e','f','t',
    op_len,      info_fn1,      'l','e','n',
    fail, 0
};
const u8 keywords_emu[] = {
    op_else,     info_control,  'e','l','s','e',
    op_end,      info_control,  'e','n','d',
    op_endif,    info_control,  'e','n','d','i','f',

    op_until,    info_control,  'u','n','t','i','l',
    fail, 0
};
const u8 keywords_fnv[] = {
    op_false,    info_const,    'F','a','l','s','e',
    op_nan,      info_const,    'N','a','N',
    op_float,    info_fn1,      'f','l','o','a','t',
    op_func,     info_control,  'f','u','n','c',
    fail, 0
};
const u8 keywords_gow[] = {
    op_wend,     info_control,  'w','e','n','d',
    op_while,    info_control,  'w','h','i','l','e',
    fail, 0
};

const u8* keywords[] = {
    keywords_hpx,
    keywords_aiqy,
    keywords_bjrz,
    keywords_cks,
    keywords_dlt,
    keywords_emu,
    keywords_fnv,
    keywords_gow
};

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

const OpInfo prec_max  = 0xf;
const OpInfo prec_mark = 0x1;
const OpData opdata_mark = { .op = mark, .info = 0x21 };
const OpData opdata_fail = { .op = fail, .info = 0x0f };

///////////////////////////////////////////////////////////////////////////////
// Utilities
//
void die(const char* msg)
{
    // TODO - all calls to die should be converted
    // to fail the parse instead.
    fprintf(stderr, "%s\n", msg);
    exit(1);
}

void parser_die(const char* msg)
{
    fprintf(stderr, "PROGRAM ERROR: %s\n", msg);
    exit(1);
}


// Gross memory map
const size_t mem_size = 65536;
u8 *mem_base;

const u16 heap_max = 0x1000;
u8* heap_base;

const u16 code_max = 0x1000;
u8* code_base;

const u16 vm_stack_max = 1536;
u8* vm_stack_base;

void mem_init() {
    mem_base = (u8*)malloc(mem_size);
    heap_base = mem_base;
    code_base = mem_base + 0x1000;
    vm_stack_base = mem_base + 0x2000;
}

// Heap
u8* heap_top;
u8* heap_end;

void heap_init() {
    heap_top = heap_base;
    heap_end = heap_base + 0x1000;
}

typedef struct HeapObj HeapObj;

typedef struct HeapObj {
    HeapObj* next;
    u8 data[];
} HeapObj;

u8* heap_alloc(u16 bytes)
{
    if (heap_end-heap_top < bytes+2) die("heap full");

    HeapObj* obj = (HeapObj*) heap_top;
    heap_top += sizeof(HeapObj) + bytes;
    obj->next = (HeapObj*) heap_top;

    return &obj->data[0];
}

// Return a 15-bit hash.
u16 hash_mem(const u8* p, u16 len)
{
    u16 h = 0;
    while(len--) h = h * 101 + *p++;
    return h & 0x7fff;
}

///////////////////////////////////////////////////////////////////////////////
// Lexing
//
const u8* prog_base;
const u8* input_ptr;
const u8* token_ptr;

const u8 ident_bucket_count = 32;
Ident* ident_bucket[ident_bucket_count];

void intern_init()
{
    for(u8 i=0; i<ident_bucket_count; i++) ident_bucket[i] = 0;
}

// Looks up token_ptr..input_ptr in the interned symbol table, creating
// a new entry if not found. On exit, sets ident to the new or existing entry.
// Returns 1 if a new entry was created, or 0 otherwise.
Ident* intern_ident(bool* is_new)
{
    u16 token_len = input_ptr-token_ptr;
    u16 token_hash = hash_mem(token_ptr, token_len);
    u8 buck = token_hash & (ident_bucket_count-1);

    Ident* last_ident = 0;
    Ident* ident = ident_bucket[buck];
    while(ident) {
        u16 hash = ident->hash;
        u16 len = ident->len;
        if (hash != token_hash) { }
        else if (len != token_len) { }
        else if (0 != memcmp(token_ptr, &ident->name, len)) { }
        else {
            if (is_new != 0) *is_new = false;
            return ident;
        }

        last_ident = ident;
        ident = ident->chain;
    }

    // TODO - point to name in program text instead of copying it?
    //
    // TODO - allocate value contiguously in separate part of the heap
    // and store a pointer to it from the ident record instead.
    //
    // During code gen inject the value pointer instead of the ident pointer.
    //
    ident = (Ident*) heap_alloc(sizeof(Ident) + token_len);
    ident->chain = 0;
    ident->hash = token_hash;
    ident->val.k = kind_fail;
    ident->val.u = 0;
    ident->slot = 0xff; // doubles as slot_count for funcs
    ident->args = 0;    // only used for funcs/procs
    ident->len = token_len;
    memcpy(ident->name, token_ptr, token_len);

    if (last_ident == 0) {
        ident_bucket[buck] = ident;
    }
    else {
        last_ident->chain = ident;
    }

    if (is_new != 0) *is_new = true;
    return ident;
}

// Returns 1 if token_ptr..input_ptr identifies a keyword
// with kw set to op and info.
OpData kw;

bool lookup_keyword()
{
    u8 ch = *token_ptr;
    u16 i = ch & 7;
    const u8 *kwd_ptr = keywords[i];

    kw.op = (Op) *kwd_ptr++;
    while(kw.op != fail) {
        const u8* p = token_ptr;

        kw.info = (OpInfo) *kwd_ptr++;

        u8 kwd_ch;
        while(1) {
            ch = *p;
            kwd_ch = *kwd_ptr++;
            if (kwd_ch & 0x80) {
                if (p != input_ptr) break;
                return true;
            }
            if (kwd_ch > ch) {
                return false;
            }
            if (kwd_ch < ch) {
                // skip until id byte
                while(1) {
                    kwd_ch = *kwd_ptr++;
                    if (kwd_ch & 0x80) break;
                }
                break;
            }
            p++;
        }
        kw.op = (Op) kwd_ch;
    }
    return false;
}

// Advances input_ptr past any spaces.
//
void lex_space()
{
    while(1) {
        char ch = *input_ptr;
        if (! (ch == ' ' || ch == '\t') ) break;
        input_ptr++;
    }
}

// Returns kind_int if an integer was recognised, or kind_float for a float,
// setting token_ptr and advancing input_ptr.
//
// Returns kind_fail if neither recognised, with input_ptr unchanged.
//
Kind lex_number()
{
    lex_space();

    const u8* p = input_ptr;
    u8 digits = 0;
    u8 dp = 0;

    u8 ch = *p;
    if (ch == '+' || ch == '-') ch = *++p;
    while(1) {
        if (ch == '.') {
            if (dp) break;
            dp = 1;
        }
        else {
            if (ch < '0') break;
            if (ch > '9') break;
            digits = 1;
        }
        ch = *++p;
    }
    if (!digits) return kind_fail;

    u8 nexp = 0;
    if (ch == 'e') {
        ch = *++p;
        if (ch == '+' || ch == '-') ch = *++p;
        while(1) {
            if (ch < '0') break;
            if (ch > '9') break;
            nexp = 1;
            ch = *++p;
        }
        if (nexp == 0) parser_die("malformed number");
    }

    token_ptr = input_ptr;
    input_ptr = p;

    return (dp || nexp) ? kind_float : kind_int;
}


String* interned_string_empty;
String* interned_string_true;
String* interned_string_false;
String* interned_string_array;
String* interned_string_proc;
String* interned_string_func;
String* interned_string_unknown;

String* string_bucket[256];

void strings_init()
{
    interned_string_empty   = string_from_data((const u8*) "", 0);
    interned_string_true    = string_from_data((const u8*) "True", 4);
    interned_string_false   = string_from_data((const u8*) "False", 5);
    interned_string_array   = string_from_data((const u8*) "<array>", 7);
    interned_string_proc    = string_from_data((const u8*) "<proc>", 6);
    interned_string_func    = string_from_data((const u8*) "<func>", 6);
    interned_string_unknown = string_from_data((const u8*) "<unknown>", 9);

    for(int i=0; i<256; i++) string_bucket[i] = 0;
}

// Looks for a string literal in the input.
// Creates the string if necessary and returns a pointer to its heap descriptor.
// If no open " is found, returns 0, and input_ptr is left unchanged.
//
String* lex_string()
{
    lex_space();

    u8 ch = *input_ptr;
    if (ch != '"') return 0;
    input_ptr++;

    const u8* input_ptr0 = input_ptr;
    u16 len = 0;
    u8 ch0 = 0;

    // TODO - hex escapes?
    while(1) {
        ch = *input_ptr++;
        if (ch == '"') break;
        ch0 = ch;
        if (ch == '\\') {
            ch = *++input_ptr;
            if      (ch == 't')  {ch0 = '\t';}
            else if (ch == 'n')  {ch0 = '\n';}
            else if (ch == '"')  {}
            else if (ch == '\\') {}
            else parser_die("invalid string escape");
        }
        if (ch == '\0') parser_die("missing double quote \"");
        len++;
    }

    // TODO - intern all literal strings
    if (len == 0) return interned_string_empty;
    if (len == 1) {
        String* str = string_bucket[ch0];
        if (str) return str;
    }

    String* str = (String*) heap_alloc(sizeof(String) + len);
    str->hash = 0;
    str->len = len;

    u8* q = str->data;
    const u8* ptr = input_ptr0;
    while(1) {
        ch = *ptr++;
        if (ch == '"') break;
        if (ch == '\\') {
            ch = *++ptr;
            if      (ch == 't') ch = '\t';
            else if (ch == 'n') ch = '\n';
        }
        *q++ = ch;
    }

    if (len == 1) string_bucket[ch0] = str;

    return str;
}

String* string_from_char(u8 ch)
{
    String* str = string_bucket[ch];
    if (str == 0) {
        str = (String*) heap_alloc(sizeof(String) + 1);
        str->hash = 0;
        str->len = 1;
        str->data[0] = ch;
        string_bucket[ch] = str;
    }
    return str;
}

String* string_from_data(const u8* data, u16 len)
{
    if (len == 0) return interned_string_empty;
    if (len == 1) {
        return string_from_char(*data);
    }
    String* str = (String*) heap_alloc(sizeof(String) + len);
    str->hash = 0;
    str->len = len;
    memcpy(str->data, data, len);
    return str;
}

// Returns 1 if a word was recognised, setting token_ptr and
// advancing input_ptr.
//
// Otherwise returns 0, leaving input_ptr unchanged.
//
bool lex_word()
{
    lex_space();

    const u8* inp = input_ptr;
    token_ptr = input_ptr;

    char ch = *inp;

    if (! ( (ch == '_') ||
            (ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z')
    )) {
        return false;
    }

    do {
        ch = *++inp;
    } while((ch == '_') || 
            (ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z') ||
            (ch >= '0' && ch <= '9'));

    input_ptr = inp;

    return true;
}

// Returns hi(result)=opcode, lo(result)=opinfo if an operator
// is recognised, setting token_ptr and advancing input_ptr.
//
// Returns opdata_fail, leaving input_ptr unchanged on failure.
//
OpData lex_op(const u8* ops)
{
    const u8* inp;
    OpData opdata;

candidate_loop:
    inp = input_ptr;
    
    opdata.op   = (Op) *ops++;
    opdata.info = (OpInfo) *ops++;

    if (opdata.info == 0) return opdata_fail;

    u8 ch = *ops;
    int alpha = (ch >= 'a' && ch <= 'z');
    while(1) {
        if (ch != *inp++) break;
        ch = *++ops;
        if (ch & 0x80) {
            if (alpha) {
                const u8 next = *inp | 0x20;
                if (next >= 'a' && next <= 'z') break;
            }
            input_ptr = inp;
            return opdata;
        }
    }

    // skip to next entry
    while((ch & 0x80) == 0) ch = *++ops;

    if ((Op) ch == fail) return opdata_fail;
    goto candidate_loop;
}

// Returns hi(result)=op, lo(result)=opinfo if a unary operator
// is recognised, setting token_ptr and advancing input_ptr.
//
// Returns opdata_fail, leaving input_ptr unchanged on failure.
//
OpData lex_unop()
{
    lex_space();

    // don't consume '-' or '+' immediately followed by a digit or '.',
    // as we went lex_number to deal with that instead
    u8 ch = *input_ptr;
    if (ch == '-' || ch == '+') {
        ch = *(input_ptr+1);
        if ((ch >= '0' && ch <= '9') || ch == '.') {
            return opdata_fail;
        }
    }
    return lex_op(unops);
}

// Returns hi(result)=op, lo(result)=opinfo if a binary operator
// is recognised, setting token_ptr and advancing input_ptr.
//
// Returns opdata_fail, leaving input_ptr unchanged on failure.
//
OpData lex_binop()
{
    lex_space();

    return lex_op(binops);
}

// Returns 1 if the specified character is next in the input stream,
// advancing input_ptr.
//
// Returns 0 if the character is not present, leaving input_ptr unchanged.
//
bool lex_char(u8 ch)
{
    lex_space();

    if (*input_ptr != ch) return false;

    input_ptr++;

    return true;
}

bool lex_comment()
{
    if (!lex_char('#')) return false;

    while(1) {
        u8 ch = *input_ptr++;
        if (ch == '\0' || ch == '\n') break;
    }
    return true;
}

bool lex_peek_stmt_end()
{
    lex_space();
    u8 ch = *input_ptr;

    if (ch==';' || ch=='\n' || ch=='#' || ch=='\0') return true;
    return false;
}

// Returns 1 if currently at the end of the input stream.
//
// Returns 0 if there is more to consume.
//
bool lex_end_of_stream()
{
    lex_space();

    if (*input_ptr != '\0') return false;
    
    return true;
}



///////////////////////////////////////////////////////////////////////////////
// Code generation
//

bool opt_emit_log = true;

// TODO check code_ptr does not run out of bounds!
u8* code_ptr;

// Emits the specifed byte to the code stream.
//
void emit_byte(u8 b)
{
    if (opt_emit_log) fprintf(stderr, "%04x: emit_byte 0x%02x = %d\n", to_p16(code_ptr), b, b);
    *code_ptr++ = b;
}

// Emits the specified word to the code stream.
//
void emit_word(u16 w)
{
    if (opt_emit_log) fprintf(stderr, "%04x: emit_word 0x%04x = %d\n", to_p16(code_ptr), w, w);
    *(u16*) code_ptr = w;
    code_ptr += sizeof(u16);
}

// Emits the specified opcode to the code stream.
//
void emit_op(Op op)
{
    if (opt_emit_log) fprintf(stderr, "%04x: emit_op %s\n", to_p16(code_ptr), debug_op_name(op));
    *code_ptr++ = (u8) op;
}

void emit_ident(Ident* ident)
{
    if (opt_emit_log) {
        fprintf(stderr, "%04x: emit_ident %04x = ", to_p16(code_ptr), to_p16(ident));
        fwrite(ident->name, 1, ident->len, stderr);
        putc('\n', stderr);
    }

    *(u16*) code_ptr = to_p16(ident);
    code_ptr += sizeof(u16);
}

///////////////////////////////////////////////////////////////////////////////
// Expression parsing
//

const u8 pending_ops_max = 32;
OpData pending_ops[pending_ops_max];
u8 pending_ops_sp;

void expr_init()
{
    pending_ops_sp = 0;
}

void parse_expr(); // forward decl

// Parses a sequence of zero or more unary operators and emits their
// opcodes.
//
void parse_unops()
{
    while(1) {
        OpData opdata = lex_unop();
        if (opdata.op == fail) return;
        // TODO check for stack overflow
        pending_ops[pending_ops_sp++] = opdata;
    }
}

// Parses a literal:
//      <integer>
//      <float>
//      <string>
bool parse_literal()
{
    // TODO - maybe parse true/false literals here
    Kind kind = lex_number();

    if (kind == kind_int) {
        int i = atoi((const char*) token_ptr);
        emit_op(op_lit_int);
        emit_word(i & 0xffff);
        return true;
    }
    if (kind == kind_float) {
        float f = (float) atof((const char*) token_ptr);
        u16 f16 = f16_from_float(f);
        emit_op(op_lit_float);
        emit_word(f16);
        return true;
    }

    const String* str = lex_string();
    if (str) {
        emit_op(op_lit_string);
        emit_word(to_p16(str));
        return true;
    }

    return false;
}

// Parses an array literal [] or [<expr>, ...], emits the expressions and 
// operator to construct the array.
//
// Returns 0 if the input does not start with '['.
//
bool parse_array()
{
    if (!lex_char('[')) {
        return false;
    }

    u16 nargs = 0;
    if (!lex_char(']')) {
        pending_ops[pending_ops_sp++] = opdata_mark;
        parse_expr();
        nargs += 1;
        while(lex_char(',')) {
            pending_ops[pending_ops_sp++] = opdata_mark;
            parse_expr();
            nargs += 1;
        }
        if (!lex_char(']')) {
            parser_die("missing ']'");
        }
    }

    emit_op(op_lit_array);
    emit_byte(nargs);

    return true;
}

// Parses a bracketed expression (<expr>), emitting it and returning 1.
// Returns 0 if the input does not start with '('.
//
bool parse_paren_expr()
{
    if (!lex_char('(')) return false;

    pending_ops[pending_ops_sp++] = opdata_mark;
    parse_expr();
    if (!lex_char(')')) parser_die("missing ')'");

    return true;
}

// Parses () or (<expr>, ...), emits the expressions and 
// returns 1 more than the number of argument expressions.
//
// Returns 0 if the input does not start with '('.
//
u16 parse_args()
{
    if (!lex_char('(')) {
        return 0;
    }

    u16 nargs = 1;
    if (!lex_char(')')) {
        pending_ops[pending_ops_sp++] = opdata_mark;
        parse_expr();
        nargs += 1;
        while(lex_char(',')) {
            pending_ops[pending_ops_sp++] = opdata_mark;
            parse_expr();
            nargs += 1;
        }
        if (!lex_char(')')) {
            parser_die("missing ')'");
        }
    }

    return nargs;
}

// Parses and index expression in one of these forms, and returns 1.
//
// [index]
// [start:end]
// [start:]
// [:end]
// [:]
//
// Returns 0 if the input does not start with '['.
//
bool parse_index_arg()
{
    if (!lex_char('[')) return false;

    if (!lex_char(':')) {
        pending_ops[pending_ops_sp++] = opdata_mark;
        parse_expr();
        if (lex_char(']')) {
            // [index]
            emit_op(op_index);
            return true;
        }
        else if (!lex_char(':')) {
            parser_die("missing ']'");
        }
        else if (lex_char(']')) {
            // [start:]
            emit_op(op_slice_start);
            return true;
        }
        else {
            // [start:end]
            pending_ops[pending_ops_sp++] = opdata_mark;
            parse_expr();
            emit_op(op_slice);
        }
    }
    else if (lex_char(']')) {
        // [:]
        emit_op(op_slice_empty);
        return true;
    }
    else {
        // [:end]
        pending_ops[pending_ops_sp++] = opdata_mark;
        parse_expr();
        emit_op(op_slice_end);
    }

    if (!lex_char(']')) parser_die("missing ']'");
    
    return true;
}

// Parses the <expr-list> (if needed) for a recently recognised keyword,
// and emits its opcode.
void parse_keyword_args()
{
    if (kw.info == info_const) {
        emit_op(kw.op);
    }
    else if (kw.info <= info_fn3) {
        // parse_args may trample kw
        OpData save = kw;
        u16 nargs = parse_args();
        kw = save;
        if (nargs == 0) parser_die("missing arguments '(...)'");
        if (nargs-1 < kw.info) parser_die("too few arguments");
        if (nargs-1 > kw.info) parser_die("too many arguments");
        emit_op(kw.op);
    }
    else if (kw.info >= info_cmd0 && kw.info <= info_cmd_any) {
        parser_die("command not allowed here");
    }
    else if (kw.info == info_control) {
        parser_die("control statement not allowed here");
    }
}

// Parses a <terminal>, i.e. one of these forms:
//      (<expr>)
//      <ident>
//      <ident>(<expr-list>)
//      <ident>[<expr>]'
//      <const-kwd>
//      <func-kwd>(<expr-list>)
//      <literal>
//
void parse_terminal()
{
    if (parse_paren_expr()) return;

    if (parse_literal()) return;

    if (parse_array()) return;

    if (!lex_word()) parser_die("expecting identifier or value");

    if (lookup_keyword()) {
        parse_keyword_args();
        return;
    }

    Ident* ident = intern_ident(0);

    u16 nargs = parse_args();
    if (nargs) {
        // function call: always lookup symbol in global scope
        emit_op(op_call_func);
        emit_byte(nargs-1);
        emit_ident(ident);
        return;
    }

    if (func_kind == kind_fail) {
        // if we're at global scope, all symbol lookups are global
        emit_op(op_ident_get);
        emit_ident(ident);
    }
    else {
        // we're in a function...
        u8 slot_num = ident->slot;
        if (slot_num == 0xff) {
            // get from global scope if no slot defined
            emit_op(op_ident_get);
            emit_ident(ident);
        }
        else {
            // get from the slot
            emit_op(op_slot_get);
            emit_byte(slot_num);
        }
    }

    parse_index_arg();
}

// Parses an <expr>, consisting of one or more <terminal>s each preceded 
// by zero or more <unop>s, and separated by <binop>s.
//
void parse_expr()
{
    while(1) {
        parse_unops();
        parse_terminal();

        while(1) {
            OpData opdata = lex_binop();
            u8 prec = opdata.info & 0x0f;

            while(pending_ops_sp > 0) {
                OpData prev_opdata = pending_ops[pending_ops_sp-1]; 
                u8 prev_prec = prev_opdata.info & 0x0f;
                if ((prec > prev_prec) && (prec < prec_max)) break;

                pending_ops_sp -= 1;

                // is this the mark?
                if (prev_prec == prec_mark) break;

                emit_op(prev_opdata.op);
            }

            if (prec == prec_max) return;

            // check arity
            if ((opdata.info & 0xf0) > 0x10) {
                pending_ops[pending_ops_sp++] = opdata;
                break;
            }
        }
    }
}

void parse_start()
{
    heap_init();
    intern_init();
    strings_init();
    stmt_init();

    code_ptr = code_base;
}

void parse_line()
{
    expr_init();

    if (lex_char('\n')) return;
    if (lex_comment()) return;

    parse_stmt();

    if (lex_comment()) return;
    if (lex_char(';')) return;
    if (lex_char('\n')) return;

    parser_die("missing ';' or <end-of-line>");
}

void parse_finish()
{
    if (!lex_end_of_stream()) parser_die("unexpected characters at end of line");

    if (control_sp != 0) parser_die("unfinished control block");
}

int main()
{
    mem_init();

    const char* prog =
        "proc blah(arr)\n"
        "   arr[2] = 99\n"
        "end\n"
        "foo = [4,5,6,7,8,9,10,11]\n"
        "blah foo\n"
        "print foo\n"
        "z = \"he\" + \"l\" + \"l\" + \"o\"\n"
        "z = z + \" world\"\n"
        "print z\n"
        "func fu()\n"
        "end\n"
        "print str(Inf)\n"
        "stop\n"
    ;

    const u8* p = (u8*) prog;
    prog_base = p;
    input_ptr = p;

    parse_start();
    while(*input_ptr) parse_line();
    parse_finish();

    vm_run(code_base);
}


