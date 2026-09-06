#include "header.h"
#include "parse.h"

#include <stdlib.h>

const OpData opdata_fail = { .op = fail, .info = 0x0f };

const u8* prog_base;
const u8* input_ptr;
const u8* token_ptr;
i16 token_len;

// Advances input_ptr past any spaces or tabs.
void lex_space()
{
    while(1) {
        char ch = *input_ptr;
        if (! (ch == ' ' || ch == '\t') ) break;
        input_ptr++;
    }
}

// Looks for a numeric literal in the input.
//
// Returns kind_int if an integer was recognised, or kind_float for a float,
// setting token_ptr and advancing input_ptr.
//
// Returns kind_none if neither recognised, with input_ptr unchanged.
// Returns kind_fail if partially recognised number is badly terminated.
Value lex_number()
{
    const Value VALUE_FAIL = {.k=kind_fail};
    const Value VALUE_NONE = {.k=kind_none};

    lex_space();

    const u8* p = input_ptr;
    bool has_digits = false;
    bool has_dp = false;

    u8 ch = *p;
    if (ch == '+' || ch == '-') ch = *++p;
    while(1) {
        if (ch == '.') {
            if (has_dp) return VALUE_FAIL;
            has_dp = true;
        }
        else if (ch >= '0' && ch <= '9') {
            has_digits = true;
        }
        else if (ch == 'e' || ch == 'E') {
            break;
        }
        else if (ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' || ch == '_') {
            return has_digits ? VALUE_FAIL : VALUE_NONE;
        }
        else {
            break;
        }
        ch = *++p;
    }
    if (!has_digits) return VALUE_NONE;

    bool has_exp_digits = false;
    if (ch == 'e' || ch == 'E') {
        ch = *++p;
        if (ch == '+' || ch == '-') ch = *++p;
        while(1) {
            if (ch >= '0' && ch <= '9') {
                has_exp_digits = true;
                ch = *++p;
            }
            else if (ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' || ch == '_') {
                return VALUE_FAIL;
            }
            else {
                break;
            }
        }
        if (!has_exp_digits) return VALUE_FAIL;    // malformed number
    }

    token_ptr = input_ptr;
    input_ptr = p;
    token_len = input_ptr - token_ptr;

    if (has_dp || has_exp_digits) {
        double f = atof((const char*) token_ptr);
        return (Value){.k=kind_float, .f=f16_from_float(f)};
    }
    else {
        int i = atoi((const char*) token_ptr);
        return (Value){.k=kind_int, .i=(i16)i};
    }
}

// Looks for a string literal in the input.
//
// May return a pointer to an interned string or allocate a new
// string and return a pointer to its heap descriptor.
//
// If no open " is found, returns 0, and input_ptr is left unchanged.
String* lex_string()
{
    lex_space();

    u8 ch = *input_ptr;
    if (ch != '"') return 0;
    input_ptr++;

    const u8* input_ptr0 = input_ptr;
    i16 len = 0;
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
        String* str = interned_char_strings[ch0];
        if (str) {
            return str;
        }
    }

    String* str = string_new_uninited(len);
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
    string_rehash(str);

    if (len == 1) interned_char_strings[ch0] = str;

    return str;
}

// Looks for a word in the input /[_a-zA-z][_a-zA-Z0-9]*/
//
// Returns String* if a word was recognised, setting token_ptr and
// advancing input_ptr.
//
// Otherwise returns 0, leaving input_ptr unchanged.
String* lex_word()
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
    token_len = input_ptr - token_ptr;

    String* name = string_from_token();
    return name;
}

// Resets the input ptr to the start of the last word recognised. 
// Should only be called immediately after a successful call to lex_word().
void unlex_word()
{
    input_ptr = token_ptr;
}

// Looks in the input for one of the operators from the supplied ops table.
//
// Returns hi(result)=opcode, lo(result)=opinfo if an operator
// is recognised, setting token_ptr and advancing input_ptr.
//
// Returns opdata_fail, leaving input_ptr unchanged on failure.
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

// Looks for a unary operator in the input.
//
// Returns hi(result)=op, lo(result)=opinfo if a unary operator
// is recognised, setting token_ptr and advancing input_ptr.
//
// Returns opdata_fail, leaving input_ptr unchanged on failure.
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

// Looks for a binary operator in the input.
//
// Returns hi(result)=op, lo(result)=opinfo if a binary operator
// is recognised, setting token_ptr and advancing input_ptr.
//
// Returns opdata_fail, leaving input_ptr unchanged on failure.
OpData lex_binop()
{
    lex_space();

    return lex_op(binops);
}

// Looks for the character ch in the input.
//
// Returns 1 if the specified character is next in the input stream,
// advancing input_ptr.
//
// Returns 0 if the character is not present, leaving input_ptr unchanged.
bool lex_char(u8 ch)
{
    lex_space();

    if (*input_ptr != ch) return false;

    input_ptr++;

    return true;
}

// Looks for a comment terminated by <newline> or <end-of-input> in the input.
//
// Returns 1 if a comment was found, advancing input_ptr.
// Returns 0 if a comment is not present, leaving input_ptr unchanged.
bool lex_comment()
{
    if (!lex_char('#')) return false;

    while(1) {
        u8 ch = *input_ptr++;
        if (ch == '\0' || ch == '\n') break;
    }
    return true;
}

// Looks for statement end in the input (';', <newline>, <comment>, or <end-of-input>).
//
// Returns 1 if an end of statement was found, advancing input_ptr.
// Returns 0 if an end of statement was not present, leaving input_ptr unchanged.
bool lex_peek_stmt_end()
{
    lex_space();
    u8 ch = *input_ptr;

    if (ch==';' || ch=='\n' || ch=='#' || ch=='\0') return true;
    return false;
}

// Returns 1 if currently at the end of the input stream.
// Returns 0 if there is more to consume.
bool lex_end_of_stream()
{
    lex_space();

    if (*input_ptr != '\0') return false;
    
    return true;
}

