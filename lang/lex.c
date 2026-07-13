#include "header.h"

const OpData opdata_fail = { .op = fail, .info = 0x0f };

const u8* input_ptr;
const u8* token_ptr;

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
    const bool alpha = (ch >= 'a' && ch <= 'z');
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

