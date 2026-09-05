#include "parse.h"
#include "header.h"
#include "array.h"
#include "dict.h"
#include "object.h"

#include <stdlib.h>

///////////////////////////////////////////////////////////////////////////////
// Expression parsing
//

OpData lex_unop();
OpData lex_binop();

const OpInfo prec_max  = 0xf;
const OpInfo prec_mark = 0x1;

const OpData opdata_mark = { .op = mark, .info = 0x21 };

Array* pending_ops;
const u16 default_pending_ops_cap = 16;

void parse_expr();

// Initialises the state of the expression parser.
void expr_init()
{
    // TODO need separate init for this
    if (pending_ops == 0) {
        pending_ops = array_new_presized(0, default_pending_ops_cap);
    }
    else {
        array_reset(pending_ops);
    }
}

void push_opdata(OpData opdata)
{
    Value v;
    v.k = kind_int;
    v.u = ((u16)opdata.op) << 8 | ((u16)opdata.info);
    array_append(pending_ops, v);
}

OpData peek_opdata()
{
    Value v = array_get(pending_ops, -1);
    return (OpData){.op = v.u>>8, .info = v.u & 0xff};
}

void drop_opdata()
{
    array_pop(pending_ops);
}

// Parses a sequence of zero or more unary operators and emits their
// opcodes.
//
// - e.g. `not - - ~`
void parse_unops()
{
    while(1) {
        OpData opdata = lex_unop();
        if (opdata.op == fail) return;
        push_opdata(opdata);
    }
}

// Parses an atom and emits the corresponding literal op.
//
// Returns true on success.
// Returns false if no atom was recognised, leaving input_ptr unchanged.
//
// - `<integer>`
// - `<float>`
// - `<string>`
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
        emit_string(str);
        return true;
    }

    return false;
}

// Parses an array literal, and emits the code to construct it.
//
// Returns true on success.
// Returns false if input does not start with '['.
// Aborts if the literal was malformed.
//
// - `[ ]`
// - `[ <expr> , ... ]`
bool parse_lit_array()
{
    if (!lex_char('[')) {
        return false;
    }

    u16 nargs = 0;
    if (!lex_char(']')) {
        push_opdata(opdata_mark);
        parse_expr();
        nargs += 1;
        while(lex_char(',')) {
            push_opdata(opdata_mark);
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

// Parses a dictionary literal and emits the code to construct it.
//
// Returns true on success.
// Returns false if input does not start with '{', leaving input_ptr unchanged.
// Aborts if the literal was malformed.
//
// - `{ }`
// - `{ <ident> : <expr> , ... }`
bool parse_lit_dict()
{
    if (!lex_char('{')) {
        return false;
    }

    u16 nargs = 0;
    if (!lex_char('}')) {
        push_opdata(opdata_mark);
        parse_expr();
        if (!lex_char(':')) parser_die("missing ':'");
        push_opdata(opdata_mark);
        parse_expr();

        nargs += 1;
        while(lex_char(',')) {
            push_opdata(opdata_mark);
            parse_expr();
            if (!lex_char(':')) parser_die("missing ':'");
            push_opdata(opdata_mark);
            parse_expr();

            nargs += 1;
        }
        if (!lex_char('}')) {
            parser_die("missing '}'");
        }
    }

    emit_op(op_lit_dict);
    emit_word(nargs);

    return true;
}

// Parses a bracketed expression and emits the code to evaluate it.
//
// Returns true if parse succeeded.
// Returns false if input does not start with '(', leaving input_ptr unchanged.
// Aborts if expression is malformed.
//
// `( <expr> )`
bool parse_paren_expr()
{
    if (!lex_char('(')) return false;

    push_opdata(opdata_mark);
    parse_expr();
    if (!lex_char(')')) parser_die("missing ')'");

    return true;
}

// Parses a bracketed expression list and emits the code to evaluate each
// expression.
//
// Returns 1 more than the number of expressions parsed.
// Returns 0 if the input does not start with '('.
// Aborts if the expression list is malformed.
//
// - `( )`
// - `( <expr> , ... )`
u16 parse_args()
{
    if (!lex_char('(')) {
        return 0;
    }

    u16 nargs = 1;
    if (!lex_char(')')) {
        push_opdata(opdata_mark);
        parse_expr();
        nargs += 1;
        while(lex_char(',')) {
            push_opdata(opdata_mark);
            parse_expr();
            nargs += 1;
        }
        if (!lex_char(')')) {
            parser_die("missing ')'");
        }
    }

    return nargs;
}

// Parses an index expression and emits code to operate on the prior expression.
//
// Returns true if parse succeeded.
// Returns false if input does not start with '['.
// Aborts if index expression is malformed.
//
// Element index expression:
// - `[ <expr> ]`
//
// Slice expressions:
// - `[ <expr> : <expr> ]`
// - `[ <expr> : ]`
// - `[ : <expr> ]`
// - `[ : ]`
bool parse_index_arg()
{
    if (!lex_char('[')) return false;

    if (!lex_char(':')) {
        push_opdata(opdata_mark);
        parse_expr();
        if (lex_char(']')) {
            // [index]
            emit_op(op_get_index);
        }
        else if (!lex_char(':')) {
            parser_die("missing ']'");
        }
        else if (lex_char(']')) {
            // [start:]
            emit_op(op_get_slice_start);
        }
        else {
            // [start:end]
            push_opdata(opdata_mark);
            parse_expr();
            if (!lex_char(']')) parser_die("missing ']'");
            emit_op(op_get_slice);
        }
    }
    else if (lex_char(']')) {
        // [:]
        emit_op(op_get_slice_empty);
    }
    else {
        // [:end]
        push_opdata(opdata_mark);
        parse_expr();
        if (!lex_char(']')) parser_die("missing ']'");
        emit_op(op_get_slice_end);
    }
    return true;
}

// Parses the bracketed arguments (if required) for a previously recognised
// keyword, and emits code to evaluate them and then invoke the keyword.
//
// No argument list is parsed if the keyword is a constant.
// Aborts if the wrong number of arguments is found.
// Aborts if the keyword is not valid in an expression context.
//
// - <empty>
// - `()`
// - `( <expr> , ... )`
void parse_keyword_args()
{
    if (kw.info == info_const) {
    }
    else if (kw.info >= info_fn0 && kw.info <= info_fn3) {
        // parse_args may trample kw
        OpData save = kw;
        u16 nargs = parse_args();
        kw = save;
        if (nargs == 0) parser_die("missing arguments '(...)'");
        u16 want = kw.info-info_fn0;
        if (nargs-1 < want) parser_die("too few arguments");
        if (nargs-1 > want) parser_die("too many arguments");
    }
    else if (kw.info >= info_cmd0 && kw.info <= info_cmd_any) {
        parser_die("command not allowed here");
    }
    else if (kw.info == info_control) {
        parser_die("control statement not allowed here");
    }
    emit_op(kw.op);
}

// Emits code to look up the named identifier at global scope,
// i.e. as a global identifier.
void emit_ident_at_global_scope(String* name)
{
    emit_op(op_get_global_prop);
    emit_string(name);
}

// Emits code to look up the named identifier at function scope,
// that is as an argument, local, or global identifier, i.e.
//
// `func F(...)
//      ...
//      <name>
//      ...
// end`
void emit_ident_at_func_scope(String* name)
{
    Value nameval = {.k=kind_string, .u=to_p16(name)};
    Value slotval = dict_get_item(active_func->slots, nameval);
    if (slotval.k != kind_fail) {
        emit_op(op_get_func_slot);
        emit_word(slotval.u);
    }
    else {
        emit_ident_at_global_scope(name);
    }
}

// Emits code to look up the named identifier at class scope, but
// outside method scope, i.e.
//
// `class C
//      ... <name> ...
//      func F(...)
//          ...
//      end
//  end`
void emit_ident_at_class_scope(String* name)
{
    // TODO - previously defined class props (+methods) should be in scope too?
    emit_ident_at_global_scope(name);
}

// Emits code to look up the named identifier at method scope, i.e.
//
// `class C
//      ...
//      func F(...)
//          ... <name> ...
//      end
// end`
void emit_ident_at_method_scope(String* name)
{
    Value nameval = {.k=kind_string, .u=to_p16(name)};
    Value slotval = dict_get_item(active_func->slots, nameval);
    if (slotval.k != kind_fail) {
        emit_op(op_get_func_slot);
        emit_word(slotval.u);
    }
    else {
        slotval = dict_get_item(active_class->slots, nameval);
        if (slotval.k != kind_fail) {
            emit_op(op_get_object_slot);
            emit_word(slotval.u);
        }
        else {
            emit_potential_method_ref(name);
        }
    }
}

// Emits code to look up the named identifier according to the current scope.
void emit_ident(String* name)
{
    if (active_class == 0) {
        if (active_func == 0) {
            emit_ident_at_global_scope(name);
        }
        else {
            emit_ident_at_func_scope(name);
        }
    }
    else {
        if (active_func == 0) {
            emit_ident_at_class_scope(name);
        }
        else {
            emit_ident_at_method_scope(name);
        }
    }
}

// Parses a terminal expression, stopping before any possible index operation,
// and emits the code to evaluate the expression.
//
// Aborts if the expression is malformed.
//
// - `( <expr> )`
// - `<integer> | <string> | <float>`
// - `<array-literal>`
// - `<dict-literal>`
// - `<ident>`
// - `<const-keyword>`
// - `<func-keyword> ( ... )`
void parse_terminal_unindexed()
{
    if (parse_paren_expr()) return;

    if (parse_atom()) return;

    if (parse_lit_array()) return;

    if (parse_lit_dict()) return;

    if (!lex_word()) {
        parser_die("expecting identifier or value");
    }

    if (lookup_keyword()) {
        parse_keyword_args();
        return;
    }

    String* name = string_from_token();

    emit_ident(name);
}

// Parses a property or method reference or invocation, and emits
// the code for the look up / invocation.
//
// Returns true if a property/method reference/invocation was recognised.
// Returns false if input does not start with '.'.
// Aborts if the expression is malformed.
//
// - `.<ident>`
// - `.<ident> ( ... )`
bool parse_dot()
{
    if (!lex_char('.')) return false;

    if (!lex_word()) die("expected method or property name");
    String* name = string_from_token();

    u16 nargs = parse_args();
    if (nargs > 0) {
        emit_op(op_call_method);
        emit_string(name);
        emit_byte(nargs-1);
    }
    else {
        emit_op(op_get_prop);
        emit_string(name);
    }
    return true;
}

// Parses an object constructor and emits the code to construct it,
// expecting a class reference to already have been parsed.
//
// Returns true if an object literal was recognised.
// Returns false if input does not start with '{'.
// Aborts if the literal is malformed.
//
// - `{}`
// - `{ <ident> : <expr> , ... }
bool parse_lit_object()
{
    if (!lex_char('{')) return false;

    u16 nargs = 0;
    String* key;
    if (!lex_char('}')) {
        push_opdata(opdata_mark);
        if (!lex_word()) die("missing property");
        key = string_from_token();
        emit_op(op_lit_string);
        emit_string(key);

        if (!lex_char(':')) parser_die("missing ':'");
        parse_expr();

        nargs += 1;
        while(lex_char(',')) {
            push_opdata(opdata_mark);
            if (!lex_word()) die("missing property");
            key = string_from_token();
            emit_op(op_lit_string);
            emit_string(key);

            if (!lex_char(':')) parser_die("missing ':'");
            parse_expr();

            nargs += 1;
        }
        if (!lex_char('}')) {
            parser_die("missing '}'");
        }
    }

    emit_op(op_lit_object);
    emit_byte(nargs);

    return true;
}

// Parses a <terminal> and emits the code to evaluate it.
//
// - `<terminal-unindexed>`
// - `<terminal> [ ... ]`
// - `<terminal> ( ... )`
// - `<terminal> .<ident>`
// - `<terminal> .<ident> ( ... )`
// - `<terminal> { ... }`
void parse_terminal()
{
    parse_terminal_unindexed();

    while (1) {
        if (parse_index_arg()) {
            continue;
        }
        u16 nargs = parse_args(); // foo.bar(...) foo(...)(...) | foo[1](...) | foo(...)
        if (nargs != 0) {
            emit_op(op_call);
            emit_byte(nargs-1);
            continue;
        }
        if (parse_dot()) {
            continue;
        }
        if (parse_lit_object()) {
            continue;
        }
        break;
    }
}

// Parses an <expr>, consisting of one or more <terminal>s each preceded 
// by zero or more <unop>s, and separated by <binop>s. Emits the code
// to evaluate the expression while respecting operator precedences.
//
// - `<terminal>`
// - `<unop> <expr>`
// - `<expr> <binop> <expr>`
void parse_expr()
{
    while(1) {
        parse_unops();
        parse_terminal();

        while(1) {
            OpData opdata = lex_binop();
            u8 prec = opdata.info & 0x0f;

            while (pending_ops->len > 0) {
                OpData prev_opdata = peek_opdata();
                u8 prev_prec = prev_opdata.info & 0x0f;
                if ((prec > prev_prec) && (prec < prec_max)) break;

                drop_opdata();

                // is this the mark?
                if (prev_prec == prec_mark) break;

                emit_op(prev_opdata.op);
            }

            if (prec == prec_max) return;

            // check arity
            if ((opdata.info & 0xf0) > 0x10) {
                push_opdata(opdata);
                break;
            }
        }
    }
}
