#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "header.h"

enum {
    // first entries double as argument counts
    kw_fn0 = 0,
    kw_fn1 = 1,
    kw_fn2 = 2,
    kw_fn3 = 3,

    kw_const   = 4,
    kw_cmd     = 5,
    kw_control = 6
};

const char* op_names[] = {
    "fail",
    "mark",

    "op_neg", "op_bnot", "op_lnot",
    "op_mul", "op_div", "op_mod",
    "op_add", "op_sub",
    "op_asr", "op_lsr", "op_lsl",
    "op_le", "op_lt", "op_gt", "op_ge",
    "op_eq", "op_ne",
    "op_band",
    "op_bor", "op_beor",
    "op_land",
    "op_lor",

    "op_abs", "op_asc", "op_break",
    "op_chr", "op_else", "op_end",
    "op_endif", "op_false", "op_func",
    "op_if", "op_input", "op_int",
    "op_left", "op_len", "op_print",
    "op_repeat", "op_return", "op_right",
    "op_rnd", "op_sgn", "op_sqr",
    "op_stop", "op_str", "op_substr", "op_true",
    "op_until", "op_wend", "op_while",

    "op_index",
    "op_call",
    "op_ident_get",
    "op_ident_set",
    "op_lit_int",
    "op_lit_float",
    "op_lit_str_empty",
    "op_lit_str_char",
    "op_lit_str_prog",
    "op_jump",
    "op_jfalse",
};

// each table should be arranged in ascii order
const u8 keywords_hpx[] = {
    op_print,    kw_cmd,        'p','r','i','n','t',
    fail, 0
};
const u8 keywords_aiqy[] = {
    op_abs,      kw_fn1,        'a','b','s',
    op_asc,      kw_fn1,        'a','s','c',

    op_if,       kw_control,    'i','f',
    op_input,    kw_cmd,        'i','n','p','u','t',
    op_int,      kw_fn1,        'i','n','t',
    fail, 0
};
const u8 keywords_bjrz[] = {
    op_break,    kw_control,    'b','r','e','a','k',
    op_repeat,   kw_control,    'r','e','p','e','a','t',
    op_return,   kw_control,    'r','e','t','u','r','n',
    op_right,    kw_fn2,        'r','i','g','h','t',
    op_rnd,      kw_fn0,        'r','n','d',
    fail, 0
};
const u8 keywords_cks[] = {
    op_chr,      kw_fn1,        'c','h','r',

    op_sgn,      kw_fn1,        's','g','n',
    op_sqr,      kw_fn1,        's','q','r',
    op_stop,     kw_cmd,        's','t','o','p',
    op_str,      kw_fn1,        's','t','r',
    op_substr,   kw_fn3,        's','u','b','s','t','r',
    fail, 0
};
const u8 keywords_dlt[] = {
    op_left,     kw_fn2,        'l','e','f','t',
    op_len,      kw_fn1,        'l','e','n',

    op_true,     kw_const,      't','r','u','e',
    fail, 0
};
const u8 keywords_emu[] = {
    op_else,     kw_control,    'e','l','s','e',
    op_end,      kw_control,    'e','n','d',
    op_endif,    kw_control,    'e','n','d','i','f',

    op_until,    kw_control,    'u','n','t','i','l',
    fail, 0
};
const u8 keywords_fnv[] = {
    op_false,    kw_const,      'f','a','l','s','e',
    op_func,     kw_control,    'f','u','n','c',
    fail, 0
};
const u8 keywords_gow[] = {
    op_wend,     kw_control,    'w','e','n','d',
    op_while,    kw_control,    'w','h','i','l','e',
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

const u8 unops[] = {
    op_neg,  0x1b, '-',
    op_bnot, 0x1b, '~',
    op_lnot, 0x1b, 'n','o','t',
    0x00,    0x00
};

const u8 binops[] = {
    op_mul,  0x2a, '*',
    op_div,  0x2a, '/',
    op_mod,  0x2a, '%',

    op_add,  0x29, '+',
    op_sub,  0x29, '-',

    op_asr,  0x28, '>','>','>',
    op_lsr,  0x28, '>','>',
    op_lsl,  0x28, '<','<',

    op_le,   0x27, '<','=',
    op_lt,   0x27, '<',
    op_gt,   0x27, '>',
    op_ge,   0x27, '>','=',

    op_eq,   0x26, '=','=',
    op_ne,   0x26, '<','>',

    op_band, 0x25, '&',
    op_bor,  0x24, '|',
    op_beor, 0x24, '^',

    op_land, 0x23, 'a','n','d',
    op_lor,  0x22, 'o','r',
    0x00,    0x00
};

const u8 prec_max  = 0xf;
const u8 prec_mark = 0x1;
const u16 mark_op = mark<<8 | 0x21;
const u16 fail_op = fail<<8 | 0x0f;

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

u16 f16_from_float(float f)
{
    if (isnan(f)) return 0x7e00;

    u16 sign = signbit(f) ? 0x8000:0;
    if (isinf(f)) return sign|0x7c00;
    if (f==0.0f)  return sign|0x0000;

    unsigned long fbits = *(unsigned long*)&f;
    int exp = ((fbits>>23) & 0xff) - 112;
    if (exp > 30) return sign|0x7c00;
    u16 fra = (fbits>>13) & 0x03ff;
    if (exp >= 1) return sign|(exp<<10)|fra;
    fra |= 0x0400;
    for(; exp < 1; exp++) fra >>= 1;
    return sign|fra;
}

float f16_to_float(u16 u)
{
    unsigned long lu = u;
    unsigned long bits = (lu & 0x8000) << 16;
    lu &= 0x7fff;
    if (lu != 0) {
        if (lu >= 0x7c00) bits |= 0x70000000;
        else {
            unsigned long adj = 112;
            while(lu < 0x0200) { lu <<= 1; adj -= 1; }
            lu += adj<<10;
        }
        bits |= lu << 13;
    }
    return *(float*) &bits;
}

// Heap
u16 heap_top;
u8 heap[4096];

u16 heap_alloc(u16 n)
{
    // TODO check for overflow
    u16 p = heap_top;
    heap_top += n+2;
    heap[p++] = heap_top >> 8;
    heap[p++] = heap_top & 0xff;
    return p;
}

// Return a 16-bit hash.
u16 hash(const u8 *p, u16 len)
{
    u16 h = 0;
    while(len--) h = h * 101 + *p++;
    return h;
}

///////////////////////////////////////////////////////////////////////////////
// Lexing
//
const u8 *prog_base;
const u8 *input_ptr;
const u8 *token_ptr;

// Hash structure:
// 2 chain
// 2 hash
// 1 len
// n ascii
// ...?

const u8 ident_bucket_count = 32;
u16 ident_bucket[ident_bucket_count];

// token_ptr..input_ptr
u16 intern_ident()
{
    u16 token_len = input_ptr-token_ptr;
    u16 h = hash(token_ptr, token_len);
    u8 buck = h & (ident_bucket_count-1);

    u16 last_p = 0;
    u16 p = ident_bucket[buck];
    while(p) {
        u16 h2 = ((u16)heap[p+2]<<8) | heap[p+3];
        u16 len2 = heap[p+4];
        if (h2 == h && len2 == token_len && (0==memcmp(token_ptr, &heap[p+5], len2))) {
            return p;
        }

        last_p = p;
        u16 chain = ((u16)heap[p]<<8) | heap[p+1];
        p = chain;
    }

    p = heap_alloc(token_len + 5);
    heap[p] = 0;
    heap[p+1] = 0;
    heap[p+2] = h >> 8;
    heap[p+3] = h & 0xff;
    heap[p+4] = token_len;
    memcpy(&heap[p+5], token_ptr, token_len);

    if (last_p == 0) {
        ident_bucket[buck] = p;
    } else {
        heap[last_p] = p >> 8;
        heap[last_p+1] = p & 0xff;
    }

    return p;
}

// Returns 1 if token_ptr..input_ptr identifies a keyword
// with kwop, kwinfo set to op and info.
u8 kwop;
u8 kwinfo;

u16 lookup_keyword()
{
    u8 ch = *token_ptr;
    u16 i = ch & 7;
    const u8 *kwd_ptr = keywords[i];

    while(1) {
        const u8 *p = token_ptr;

        kwop   = *kwd_ptr++;
        kwinfo = *kwd_ptr++;
        if (kwop == 0) return 0;

        while(1) {
            u8 ch = *p;
            u8 kwd_ch = *kwd_ptr++;
            if (kwd_ch & 0x80) {
                if (p == input_ptr) return 1;
                break;
            }
            if (kwd_ch > ch) return 0;
            if (kwd_ch < ch) {
                // skip until id byte
                while((*++kwd_ptr & 0x80) == 0);
                break;
            }
            p++;
        }
    }
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
// Returns kind_bottom if neither recognised, with input_ptr unchanged.
//
u8 lex_number()
{
    trace("lex_number");
    // TODO - recognise [+-]Inf / NaN ?
    const u8 *p = input_ptr;
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
    if (!digits) return 0;

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
        if (nexp == 0) die("malformed number");
    }

    token_ptr = input_ptr;
    input_ptr = p;

    return (dp || nexp) ? kind_float : kind_int;
}

// TODO
// Define four types of string:
//
//      empty: ""
//      char:  "c"
//      prog:  "some text in program"
//      heap:  "some text in heap"
//
const u8 *str_ptr;
u8 str_char;

// Looks for a string literal in the input.
// Returns one of the following:
//
// - kind_bottom
//      no open " found, input_ptr is left unchanged
// - kind_str_empty
//      empty string was found
// - kind_str_char
//      (possibly escaped) single character string was found,
//      str_char is set to the (unescaped) character
// - kind_str_prog
//      a multi character string was found, str_ptr points to its first
//      character in the program text (opening quote is skipped)
//
u8 lex_string()
{
    trace("lex_string");
    u8 ch = *input_ptr;
    if (ch != '"') return 0;
    input_ptr++;

    const u8 *ptr = input_ptr;
    str_ptr = ptr;
    u16 len = 0;

    while(1) {
        ch = *ptr++;
        if (ch == '"') break;
        str_char = ch;
        if (ch == '\\') {
            ch = *++ptr;
            if      (ch == 't') str_char = '\t';
            else if (ch == 'n') str_char = '\n';
            else if (ch == '"') str_char = ch;
            else if (ch == '\\') str_char = ch;
            else die("invalid string escape");
        }
        if (ch == '\0') die("missing \"");
        len++;
    }

    input_ptr = ptr;

    if (len == 0) return kind_str_empty;
    if (len == 1) return kind_str_char;
    return kind_str_prog;
}

// Returns 1 if a word was recognised, setting token_ptr and
// advancing input_ptr.
//
// Otherwise returns 0, leaving input_ptr unchanged.
//
u16 lex_word()
{
    const u8 *inp = input_ptr;
    token_ptr = input_ptr;

    char ch = *inp;

    if (! ( (ch == '_') ||
            (ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z')
    )) {
        return 0;
    }

    do {
        ch = *++inp;
    } while((ch == '_') || 
            (ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z') ||
            (ch >= '0' && ch <= '9'));

    input_ptr = inp;
    return 1;
}

// Returns hi(result)=op, lo(result)=opinfo if an operator
// is recognised, setting token_ptr and advancing input_ptr.
//
// Returns fail_op, leaving input_ptr unchanged on failure.
//
u16 lex_op(const u8* ptr)
{
    const u8 *inp;
    u16 op;

candidate_loop:
    inp = input_ptr;
    
    op = (*ptr++) << 8;
    op |= (*ptr++);
    if (op == 0) return fail_op;

    u8 ch = *ptr;
    int alpha = (ch >= 'a' && ch <= 'z');
    while(1) {
        if (ch != *inp++) break;
        ch = *++ptr;
        if (ch & 0x80) {
            if (alpha && ch >= 'a' && ch <= 'z') goto candidate_loop;
            input_ptr = inp;
            return op;
        }
    }

    // skip to next entry
    while((ch & 0x80) == 0) ch = *++ptr;

    if (ch == fail) return fail_op;
    goto candidate_loop;
}

// Returns hi(result)=op, lo(result)=opinfo if a unary operator
// is recognised, setting token_ptr and advancing input_ptr.
//
// Returns fail_op, leaving input_ptr unchanged on failure.
//
u16 lex_unop()
{
    // don't consume '-' or '+' immediately followed by a digit or '.',
    // as we went lex_number to deal with that instead
    u8 ch = *input_ptr;
    if (ch == '-' || ch == '+') {
        ch = *(input_ptr+1);
        if ((ch >= '0' && ch <= '9') || ch == '.') return fail_op;
    }
    return lex_op(unops);
}

// Returns hi(result)=op, lo(result)=opinfo if a binary operator
// is recognised, setting token_ptr and advancing input_ptr.
//
// Returns fail_op, leaving input_ptr unchanged on failure.
//
u16 lex_binop()
{
    return lex_op(binops);
}

// Returns 1 is the specified character is next in the input stream,
// advancing input_ptr.
//
// Returns 0 if the character is not present, leaving input_ptr unchanged.
//
u16 lex_char(u8 ch)
{
    if (*input_ptr != ch) return 0;

    input_ptr++;

    return 1;
}

// Returns 1 if currently at the end of the input stream.
//
// Returns 0 if there is more to consume.
//
u16 lex_eol()
{
    if (*input_ptr != '\0') return 0;
    
    return 1;
}



///////////////////////////////////////////////////////////////////////////////
// Code generation
//

u8 *code_base;
u8 *code_ptr;

// Emits the specifed byte to the code stream.
//
void emit_byte(u8 b)
{
    fprintf(stderr, "emit_byte 0x%02x = %d\n", b, b);
    *code_ptr++ = b;
}

// Emits the specified word to the code stream.
//
void emit_word(u16 w)
{
    fprintf(stderr, "emit_word 0x%04x = %d\n", w, w);
    *code_ptr++ = (w >> 8);
    *code_ptr++ = (w & 0xff);
}

// Emits the specified opcode to the code stream.
//
void emit_op(u8 op)
{
    fprintf(stderr, "emit_op %s\n", op_names[op-0x80]);
    *code_ptr++ = op;
}

// Emits the last recognised ident, interning it if needed.
//
void emit_ident()
{
    u16 id = intern_ident();

    {
        char buf[256];
        memcpy(buf, token_ptr, input_ptr-token_ptr);
        buf[input_ptr-token_ptr] = '\0';
        fprintf(stderr, "emit_ident %04x = %s\n", id, buf);
    }

    *code_ptr++ = (id >> 8);
    *code_ptr++ = (id & 0xff);
}

///////////////////////////////////////////////////////////////////////////////
// Expression parsing
//

const u16 pending_ops_max = 32;
u16 pending_ops[pending_ops_max];
u8 pending_ops_sp;

void parse_expr(); // forward decl

// Parses a sequence of zero or more unary operators and emits their
// opcodes.
//
void parse_unops()
{
    trace("parse_unops");
    while(1) {
        u16 op = lex_unop();
        if ((op>>8) == fail) return;
        pending_ops[pending_ops_sp++] = op;
    }
}

u16 parse_literal()
{
    trace("parse_literal");
    u8 kind = lex_number();
    if (kind == kind_bottom) {
        kind = lex_string();
    }

    switch(kind) {
        case kind_int:
            {
                int i = atoi((const char*)token_ptr);
                emit_op(op_lit_int);
                emit_word(i & 0xffff);
                return 1;
            }
        case kind_float:
            {
                float f = (float)atof((const char*)token_ptr);
                u16 f16 = f16_from_float(f);
                emit_op(op_lit_float);
                emit_word(f16);
                return 1;
            }
        case kind_str_empty:
            emit_op(op_lit_str_empty);
            return 1;
        case kind_str_char:
            emit_op(op_lit_str_char);
            emit_byte(str_char);
            return 1;
        case kind_str_prog:
            emit_op(op_lit_str_prog);
            emit_word((u16)(str_ptr - prog_base));
            return 1;
        default:
            return 0;
    }
}

// Parses a bracketed expression (<expr>), emitting it and returning 1.
// Returns 0 if the input does not start with '('.
//
u16 parse_paren_expr()
{
    trace("parse_paren_expr");
    if (!lex_char('(')) return 0;

    pending_ops[pending_ops_sp++] = mark_op;
    parse_expr();
    if (!lex_char(')')) die("expected ')'");

    return 1;
}

// Parses () or (<expr>, ...), emits the expressions and 
// returns 1 more than the number of argument expressions.
//
// Returns 0 if the input does not start with '('.
//
u16 parse_args()
{
    trace("parse_args");
    if (!lex_char('(')) {
        return 0;
    }

    u16 nargs = 1;
    if (!lex_char(')')) {
        pending_ops[pending_ops_sp++] = mark_op;
        parse_expr();
        nargs += 1;
        while(lex_char(',')) {
            pending_ops[pending_ops_sp++] = mark_op;
            parse_expr();
            nargs += 1;
        }
        if (!lex_char(')')) {
            die("expected ')'");
        }
    }

    return nargs;
}

// Parses [<expr>], emits the expression and an index op
// and returns 1.
//
// Returns 0 if the input does not start with '['.
//
u16 parse_index_arg()
{
    trace("parse_index_arg");
    if (!lex_char('[')) return 0;

    pending_ops[pending_ops_sp++] = mark_op;
    parse_expr();
    if (*input_ptr != ']') die("expected ']'");
    emit_op(op_index);
    
    return 1;
}

// Parses the <expr-list> (if needed) for a recently recognised keyword,
// and emits its opcode.
void parse_keyword_args()
{
    trace("parse_keyword_args");

    if (kwinfo == kw_const) {
        emit_op(kwop);
    }
    else if (kwinfo <= kw_fn3) {
        // parse_args may trample kwop
        u8 op = kwop;
        u16 nargs = parse_args();
        if (nargs == 0) die("expected arguments");
        if (nargs-1 < kwinfo) die("too few arguments");
        if (nargs-1 > kwinfo) die("too many arguments");
        emit_op(op);
    }
    else if (kwinfo == kw_cmd) {
        die("unexpected command");
    }
    else if (kwinfo == kw_control) {
        die("unexpected control statement");
    }
}

// Parses a <terminal>, i.e. one of these forms:
//      (<expr>)
//      <ident>
//      <ident>(<expr-list>)
//      <ident>[<expr>]'
//      <const-kwd>
//      <func-kwd>(<expr-list>)
//      <integer>
//      <float>
//      // TODO <string>
//      // TODO? <char>
//
void parse_terminal()
{
    trace("parse_terminal");
    if (parse_paren_expr()) return;

    if (lex_word()) {
        if (lookup_keyword()) {
            parse_keyword_args();
        }
        else {
            emit_op(op_ident_get);
            emit_ident();
            u16 nargs = parse_args();
            if (nargs) {
                emit_op(op_call);
                emit_byte(nargs-1);
                return;
            }
            if (parse_index_arg()) return;
        }
        return;
    }

    if (parse_literal()) return;

    die("expected ident or literal");
}

// Parses an <expr>, consisting of one or more <terminal>s each preceded 
// by zero or more <unop>s, and separated by <binop>s.
//
void parse_expr()
{
    trace("parse_expr");
    while(1) {
        parse_unops();
        parse_terminal();

        while(1) {
            u16 op = lex_binop();
            u8 prec = op & 0x0f;

            while(pending_ops_sp > 0) {
                u16 p_op = pending_ops[pending_ops_sp-1]; 
                u8 p_prec = p_op & 0x0f;
                if ((prec > p_prec) && (prec < prec_max)) break;

                pending_ops_sp -= 1;

                // is this the mark?
                if (p_prec == prec_mark) break;

                emit_op(p_op>>8);
            }

            if (prec == prec_max) return;

            // check arity
            if ((op & 0xf0) > 0x10) {
                pending_ops[pending_ops_sp++] = op;
                break;
            }
        }
    }
}

int main()
{
    const char prog[] =
    "len(\"hello world\")"
    ;

    code_base = malloc(4096);
    prog_base = (const u8*) prog;

    code_ptr = code_base;
    pending_ops_sp = 0;
    input_ptr = (const u8*) prog;

    parse_expr();
    if (!lex_eol()) {
        fprintf(stderr, "unexpected trailing material: %s\n", input_ptr);
        exit(1);
    }
    emit_op(op_print);
    emit_byte(1);
    emit_op(op_stop);

    vm_run(code_base);
}


