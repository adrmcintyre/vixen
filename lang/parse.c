#include <stdlib.h>
#include "header.h"

///////////////////////////////////////////////////////////////////////////////
// Expression parsing
//

OpData lex_unop();
OpData lex_binop();

const OpInfo prec_max  = 0xf;
const OpInfo prec_mark = 0x1;

const OpData opdata_mark = { .op = mark, .info = 0x21 };

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

// Parses an atom:
//      <integer>
//      <float>
//      <string>
bool parse_atom()
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

u16 parse_dict()
{
    if (!lex_char('{')) {
        return 0;
    }

    u16 nargs = 0;
    if (!lex_char('}')) {
        pending_ops[pending_ops_sp++] = opdata_mark;
        parse_expr();
        if (!lex_char(':')) parser_die("missing ':'");
        parse_expr();

        nargs += 1;
        while(lex_char(',')) {
            pending_ops[pending_ops_sp++] = opdata_mark;
            parse_expr();
            if (!lex_char(':')) parser_die("missing ':'");
            parse_expr();

            nargs += 1;
        }
        if (!lex_char('}')) {
            parser_die("missing '}'");
        }
    }

    emit_op(op_lit_dict);
    emit_word(nargs);

    return 1;
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

// Parses an index expression in one of these forms, and returns
// a Subscript value indicating which was found.
//
// [index]
// [start:end]
// [start:]
// [:end]
// [:]
//
extern Subscript parse_index_arg()
{
    if (!lex_char('[')) return ss_none;

    if (!lex_char(':')) {
        pending_ops[pending_ops_sp++] = opdata_mark;
        parse_expr();
        if (lex_char(']')) {
            // [index]
            return ss_index;
        }
        else if (!lex_char(':')) {
            parser_die("missing ']'");
        }
        else if (lex_char(']')) {
            // [start:]
            return ss_start;
        }
        else {
            // [start:end]
            pending_ops[pending_ops_sp++] = opdata_mark;
            parse_expr();
            if (!lex_char(']')) parser_die("missing ']'");
            return ss_both;
        }
    }
    else if (lex_char(']')) {
        // [:]
        return ss_empty;
    }
    else {
        // [:end]
        pending_ops[pending_ops_sp++] = opdata_mark;
        parse_expr();
        if (!lex_char(']')) parser_die("missing ']'");
        return ss_end;
    }
    return ss_none;
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

    if (parse_atom()) return;

    if (parse_array()) return;

    if (parse_dict()) return;

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

    switch(parse_index_arg()) {
        case ss_none:  break;
        case ss_index: emit_op(op_get_index); break;
        case ss_empty: emit_op(op_get_slice_empty); break;
        case ss_start: emit_op(op_get_slice_start); break;
        case ss_end:   emit_op(op_get_slice_end); break;
        case ss_both:  emit_op(op_get_slice); break;
        default: die("unreachable");
    }
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
    // TODO should be somewhere better for this...
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

