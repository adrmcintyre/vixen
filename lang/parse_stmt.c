#include "parse.h"
#include "header.h"
#include "dict.h"
#include "object.h"

#include <stdio.h>
#include <string.h>

// TODO convert all of these to arrays

u8 control_sp;
Op control_stack[32];

const u8 begin_loop_max = 32;
u8 begin_loop_sp = 0;                   // nesting depth of loops
u16 begin_loop_stack[begin_loop_max];   // addresses of loop starts

const u8 end_loop_max = 32;
u8 end_loop_sp;
u8 end_loop_stack[end_loop_max];        // addresses and counts of unresolved refs to end of loop
u8 end_loop_count;                      // count of unresolved refs in current loop

// Forward references for conditional branches
const u8 forward_jump_max = 32;
u16 forward_jump_sp = 0;
u16 forward_jump_stack[forward_jump_max];

const u8 unresolved_method_refs_max = 128;
u16 unresolved_method_refs[unresolved_method_refs_max];
u16 unresolved_method_refs_sp;

Dict* global_idents;
Class* active_class;
Func* active_func;

u8 slot_max = 64;

// Initialises the statement parser.
void stmt_init()
{
    control_sp = 0;
    begin_loop_sp = 0;
    end_loop_sp = 0;
    end_loop_count = 0;
    forward_jump_sp = 0;
    active_func = 0;
    active_class = 0;
    unresolved_method_refs_sp = 0;
}

// Records the beginning of a control structure.
void push_control(Op op)
{
    if (control_sp == 32) parser_die("too many nested control statements");
    control_stack[control_sp++] = op;
}

// Pops and returns the op corresponding to the most recently started
// control structure. Returns fail if not inside a control structure.
Op pop_control()
{
    if (control_sp == 0) return fail;
    return control_stack[--control_sp];
}

// Records the beginning of a loop construct.
void begin_loop()
{
    if (begin_loop_sp == begin_loop_max) parser_die("too many nested loops");
    begin_loop_stack[begin_loop_sp++] = to_p16(code_ptr);

    end_loop_stack[end_loop_sp++] = end_loop_count;
    end_loop_count = 0;
}

// Emits a forward jump instruction to exit the current loop,
// recording its location in the end_loop stack for later resolution.
//
// Returns true on success, or false if not in a loop.
bool emit_end_loop_jump(Op jump_op)
{
    if (end_loop_sp == 0) return false;
    if (end_loop_sp == end_loop_max) parser_die("control flow is too complicated");
    emit_op(jump_op);
    u16 ref = to_p16(code_ptr);
    *(u16*) &end_loop_stack[end_loop_sp] = ref;
    end_loop_sp += sizeof(u16);
    end_loop_count++;
    emit_word(0);
    return true;
}

// Emits a backward ref to the given location relative to the
// byte immediately following the emitted ref.
void emit_backward_ref(u16 ref)
{
    u16 rel = (u16)(ref - to_p16(code_ptr+2));
    emit_word(rel);
}

// Sets the ref at the given location to point to the current
// code position relative to the byte immediately following the
// updated ref.
void patch_forward_ref(u16 ref_ptr)
{
    u16 rel = (u16)(to_p16(code_ptr) - (ref_ptr+2));
    *(u16*) (from_p16(ref_ptr)) = rel;
}

// Emits a jump instruction to repeat the current loop, and
// resolves outstanding forward jumps to the end of the loop.
void end_loop(u8 jump_op)
{
    if (begin_loop_sp == 0) parser_die("unexpected end-of-loop statement");

    // TODO - swap following two code blocks and use same stack

    // jump to start of loop
    u16 ref = begin_loop_stack[--begin_loop_sp];
    emit_op(jump_op);
    emit_backward_ref(ref);

    // resolve references to end of loop
    while(end_loop_count) {
        end_loop_sp -= sizeof(u16);
        u16 ref = *(u16*) &end_loop_stack[end_loop_sp];
        patch_forward_ref(ref);
        end_loop_count--;
    }
    end_loop_count = end_loop_stack[--end_loop_sp];
}

// Emits a forward jump instruction, recording its location
// in the forward_jump stack for later resolution.
void emit_forward_jump(u8 jump_op)
{
    if (forward_jump_sp == forward_jump_max) parser_die("control flow is too complicated");
    emit_op(jump_op);
    forward_jump_stack[forward_jump_sp++] = to_p16(code_ptr);
    emit_word(0);   // not yet resolved
}

// Resolves the most recent forward jump to the current location.
void resolve_forward_jump()
{
    if (forward_jump_sp == 0) parser_die("not in a control block");
    u16 ref = forward_jump_stack[--forward_jump_sp];
    patch_forward_ref(ref);
}

// Emits a speculative global variable lookup for the named identifier,
// and records its location in unresolved_method_refs for possible 
// backpatching if it later turns out this should be a method lookup instead.
void emit_potential_method_ref(String* name)
{
    if (unresolved_method_refs_sp >= unresolved_method_refs_max) {
        die("too many unresolved symbols in class");
    }
    unresolved_method_refs[unresolved_method_refs_sp++] = to_p16(code_ptr);
    emit_op(op_get_global_prop);
    emit_string(name);
}

// Resolves any ambiguous identifier references inside the active
// class's method definitions.
void resolve_potential_method_refs()
{
    u8* saved_code_ptr = code_ptr;
    while (unresolved_method_refs_sp > 0) {
        unresolved_method_refs_sp--;
        code_ptr = from_p16(unresolved_method_refs[unresolved_method_refs_sp]);
        String* name = (String*) from_p16(*(u16*)(code_ptr+1));
        Value nameval = {.k=kind_string, .u=to_p16(name)};
        Value slotval = dict_get_item(active_class->methods, nameval);
        if (slotval.k != kind_fail) {
            // TODO emit correct code
            emit_op(op_lit_method);
            emit_word(slotval.u);
        }
    }
    code_ptr = saved_code_ptr;
}

// Parses a class's name after `class` has been recognised, and emits code to
// register the class at runtime.
//
// Aborts if it is not valid to define a class at this point, or if the name 
// is invalid.
//
// - `/class/ <ident>`
void parse_class()
{
    if (control_sp != 0) parser_die("class only allowed at top level");
    if (active_class != 0) parser_die("class not allowed inside class");
    if (!lex_word()) parser_die("missing name");
    if (lookup_keyword()) parser_die("reserved word cannot be used here");

    String* name = string_from_token();
    Value nameval = {.k=kind_string, .u=to_p16(name)};

    Class* klass = class_new();
    Value klassval = {.k=kind_class, .u=to_p16(klass)};

    // TODO define this op
    emit_op(op_lit_class);
    emit_word(to_p16(klass));

    emit_op(op_set_global_prop);
    emit_string(name);

    active_class = klass;
    unresolved_method_refs_sp = 0;
}

// Returns a newly allocated function descriptor.
Func* func_new()
{
    // TODO could include name field (String)
    Func* func = (Func*) heap_alloc(sizeof(Func));
    func->klass = 0;
    func->nargs = 0;
    func->nslots = 0;
    func->slots = dict_new();
    func->vm_addr = 0;
    return func;
}

// Parses the function (or method) name and prototype after `func` has been
// recognised, and emits code to register the function at runtime.
//
// Aborts if it is not valid to define a function at this point, the name
// is invalid, or the prototype is misformed.
//
// `/func/ <ident> ()`
// `/func/ <ident> ( <ident>, ... )`
void parse_func()
{
    if (control_sp != 0) parser_die("func only allowed at top level or class level");

    if (!lex_word()) parser_die("missing name");
    if (lookup_keyword()) parser_die("reserved word cannot be used here");

    String* name = string_from_token();
    Value nameval = {.k=kind_string, .u=to_p16(name)};

    Func* func = func_new();
    Dict* func_slots = func->slots;

    // parse arglist
    if (!lex_char('(')) parser_die("missing '('");

    u8 nslots = 0;
    if (active_class != 0) {
        // make room for implicit self arg
        nslots++;
    }
    if (!lex_char(')')) {
        while(1) {
            if (!lex_word()) parser_die("missing parameter name");
            if (lookup_keyword()) parser_die("reserved word cannot be used here");
            String* argname = string_from_token();
            Value argnameval = {.k=kind_string, .u=to_p16(argname)};

            if (dict_has_item(func_slots, argnameval)) {
                parser_die("repeated parameter name");
            }
            if (nslots >= slot_max) die("too many local variables");
            Value slot = {.k=kind_int, .u=nslots};
            dict_set_item(func_slots, argnameval, slot);
            nslots += 1;

            if (lex_char(')')) break;
            if (!lex_char(',')) parser_die("missing ','");
        }
    }
    func->klass = active_class;
    func->nargs = nslots;
    func->nslots = nslots;
    active_func = func;

    if (active_class == 0) {
        emit_op(op_lit_func);
        emit_word(to_p16(func));

        emit_op(op_set_global_prop);
        emit_string(name);
    }
    else {
        // TODO perhaps registration should be at runtime instead?
        Value funcval = {.k=kind_func, .u=to_p16(func)};
        dict_set_item(active_class->methods, nameval, funcval);
    }

    push_control(op_func);
    emit_forward_jump(op_jump);

    func->vm_addr = to_p16(code_ptr);
}

// Parses optional expression after `return` has been recognised, and emits
// the code to return the value of the expression, or None if no expression
// was provided.
//
// Aborts if not currently inside a function definition.
//
// - `/return/`
// - `/return/ <expr>`
void parse_return()
{
    if (active_func == 0) parser_die("'return' is not inside a func");

    if (lex_peek_stmt_end()) {
        emit_op(op_return_none);
    }
    else {
        parse_expr();
        emit_op(op_return);
    }
}
   
// Tidies up at the end of a class or function definition.
//
// - `/end/`
void parse_end()
{
    // end of a class definition?
    if (control_sp == 0 && active_class != 0) {
        resolve_potential_method_refs();
        active_class = 0;
    }
    else {
        // end of a func definition?
        Op k = pop_control();
        if (k != op_func) parser_die("'end' not after a func");

        active_func = 0;

        // return None if we fall off the end
        emit_op(op_return_none);

        // this resolves the jump inserted before the function body
        resolve_forward_jump();
    }
}

// Parses the remainder of an `if` control statement.
//
// `/if/ <expr>`
void parse_if()
{
    push_control(op_if);
    parse_expr();
    emit_forward_jump(op_jfalse);
}

// Parses the remainder of an `else` control statement.
//
// Aborts if an `if` block is not currently active.
//
// `/else/`
void parse_else()
{
    if (pop_control() != op_if) parser_die("'else' without 'if'");
    push_control(op_else);

    // account for following jump instruction
    code_ptr += 3;
    resolve_forward_jump();
    code_ptr -= 3;

    emit_forward_jump(op_jump);
}

// Parses the remainder of an `endif` control statement.
//
// Aborts if an `if` block is not currently active.
//
// `/endif/`
void parse_endif()
{
    Op popped = pop_control();
    if (popped != op_if && popped != op_else) parser_die("'endif' without 'if'");

    resolve_forward_jump();
}

// Parses the remainder of a `while` control statement.
//
// `/while/ <expr>`
void parse_while()
{
    push_control(op_while);
    begin_loop();
    parse_expr();
    emit_end_loop_jump(op_jfalse);
}

// Parses the remainder of a `wend` control statement.
//
// Aborts if a `while` block is not currently active.
//
// `/wend/`
void parse_wend()
{
    if (pop_control() != op_while) parser_die("'wend' without 'while'");
    end_loop(op_jump);
}

// Parses the remainder of a `repeat` control statement.
//
// `/repeat/`
void parse_repeat()
{
    push_control(op_repeat);
    begin_loop();
}

// Parses the remainder of an `until` control statement.
//
// Aborts if a `repeat` block is not currently active.
//
// `/until/ <expr>`
void parse_until()
{
    if (pop_control() != op_repeat) parser_die("'until' without 'repeat'");
    parse_expr();
    end_loop(op_jfalse);
}

// Parses the remainder of a `break` statement.
//
// Aborts if a `while` or `until` block is not currently active.
//
// `/break/`
void parse_break()
{
    if (!emit_end_loop_jump(op_jump)) parser_die("'break' is not in a loop");
}


// Parses the remainder of a control statement after the keyword specified
// by op has been recognised, checks validity of the keyword in the current
// context, performs necessary bookkeeping, and emits the code to implement
// the control structure.
void parse_control_stmt(Op op)
{
    switch(op) {
    case op_if: parse_if(); break;
    case op_else: parse_else(); break;
    case op_endif: parse_endif(); break;
    case op_while: parse_while(); break;
    case op_wend: parse_wend(); break;
    case op_repeat: parse_repeat(); break;
    case op_until: parse_until(); break;
    case op_break: parse_break(); break;
    case op_class: parse_class(); break;
    case op_func: parse_func(); break;
    case op_return: parse_return(); break;
    case op_end: parse_end(); break;
    default:
        die("unreachable");
    }
}

// Parses an optional comma-separated list of expressions after a command
// keyword has been recognised, and emits the code to evaluate each expression.
//
// Returns the number of expressions recognised.
//
// `(cmd)`
// `(cmd) <expr>, ...`
u8 parse_cmd_args()
{
    if (lex_peek_stmt_end()) return 0;

    u8 nargs = 0;
    parse_expr();
    nargs += 1;
    while(lex_char(',')) {
        parse_expr();
        nargs += 1;
    }
    return nargs;
}

// Emits code to set the global property specified by name.
//
// `(<ident> = <expr>)`
void emit_assign_at_global_scope(String* name)
{
    emit_op(op_set_global_prop);
    emit_string(name);
}

// Emits code to set the local variable or function argument specified by name,
// creating a new slot if necessary.
//
// `func F(...)
//      ...
//      <ident> = <expr>
//      ...
// end`
void emit_assign_at_func_scope(String* name)
{
    Value nameval = {.k=kind_string, .u=to_p16(name)};
    Value slotval = dict_get_item(active_func->slots, nameval);
    if (slotval.k == kind_fail) {
        u16 slot = dict_length(active_func->slots);
        slotval = (Value){.k=kind_int, .u=slot};
        dict_set_item(active_func->slots, nameval, slotval);
    }
    emit_op(op_set_func_slot);
    emit_word(slotval.u);
}

// Emits code to set the property specified by name on the currently
// active class, creating a new slot on the class if necessary.
//
// `class C
//      <ident> = <expr>
//      func F (...)
//          ...
//      end
//  end`
void emit_assign_at_class_scope(String* name)
{
    Value nameval = {.k=kind_string, .u=to_p16(name)};
    Value slotval = dict_get_item(active_class->slots, nameval);
    if (slotval.k == kind_fail) {
        u16 slot = dict_length(active_class->slots);
        slotval = (Value){.k=kind_int, .u=slot};
        dict_set_item(active_class->slots, nameval, slotval);
    }
    emit_op(op_set_class_prop);
    emit_word(to_p16(active_class));
    emit_string((String*) from_p16(nameval.u));
}

// Emits code to set the value of the identifier with the specified name
// (in order of precedence) as either a local variable, function argument,
// or property on an object of the currently active class. If none of these
// are resolvable, creates a new local variable and uses that.
// 
// `class C
//      ...
//      func F(...)
//          <ident> = <expr>
//          ...
//      end
// end`
void emit_assign_at_method_scope(String* name)
{
    Value nameval = {.k=kind_string, .u=to_p16(name)};
    Value slotval = dict_get_item(active_func->slots, nameval);

    if (slotval.k != kind_fail) {
        emit_op(op_set_func_slot);
    }
    else {
        slotval = dict_get_item(active_class->slots, nameval);
        if (slotval.k != kind_fail) {
            emit_op(op_set_object_slot);
        }
        else {
            u16 slot = dict_length(active_func->slots);
            slotval = (Value){.k=kind_int, .u=slot};
            dict_set_item(active_func->slots, nameval, slotval);
            emit_op(op_set_func_slot);
        }
    }
    emit_word(slotval.u);
}

// Parses an expression after the lhs of an assignment to a bare identifier
// with the specified name has been recognised, and emits the code to perform
// the assignment.
//
// - `(<name> =) <expr>`
void parse_assign(String* name)
{
    parse_expr();

    if (active_class == 0) {
        if (active_func == 0) {
            emit_assign_at_global_scope(name);
        }
        else {
            emit_assign_at_func_scope(name);
        }
    }
    else {
        if (active_func == 0) {
            emit_assign_at_class_scope(name);
        }
        else {
            emit_assign_at_method_scope(name);
        }
    }
}

// Parses a statement, and emits the code to execute it.
//
// - `<command>`
// - `<command> <expr>, ...`
// - `<control-stmt>`
// - `<ident> = <expr>`
// - `<expr> = <expr>`
void parse_stmt()
{
    if (lex_word()) {
        if (lookup_keyword()) {
            Op opcode = kw.op;
            if (kw.info >= info_cmd0 && kw.info < info_cmd_any) {
                OpData save = kw;
                u16 nargs = parse_cmd_args();
                kw = save;
                u16 want = kw.info-info_cmd0;
                if (nargs < want) parser_die("too few arguments");
                if (nargs > want) parser_die("too many arguments");
                emit_op(opcode);
            }
            else if (kw.info == info_cmd_any) {
                // TODO check arg counts
                u8 nargs = parse_cmd_args();
                emit_op(opcode);
                emit_byte(nargs);
            }
            else if (kw.info == info_control) {
                parse_control_stmt(opcode);
            }
            else {
                parser_die("expected a command or control statement");
            }
            return;
        }

        // <name> = <expr>
        if (lex_char('=')) {
            String* name = string_from_token();
            parse_assign(name);
            return;
        }
    }

    unlex_word();
    parse_expr();

    // <expr> = <expr>
    if (lex_char('=')) {
        // TODO ensure correctly sized for max op length
        u8 last_op_and_args[4];
        u8 last_op_len = code_ptr - last_op_ptr;
        memcpy(last_op_and_args, last_op_ptr, last_op_len);
        code_ptr = last_op_ptr;

        parse_expr();

        switch (last_op_and_args[0]) {
            case op_get_global_prop:
                emit_op(op_set_global_prop);
                break;
            case op_get_func_slot:
                emit_op(op_set_func_slot);
                break;
            case op_get_class_prop:
                emit_op(op_set_class_prop);
                break;
            case op_get_object_slot:
                emit_op(op_set_object_slot);
                break;
            case op_get_index:
                emit_op(op_set_index);
                break;
            case op_get_slice_empty:
                emit_op(op_set_slice_empty);
                break;
            case op_get_slice_end:
                emit_op(op_set_slice_end);
                break;
            case op_get_slice_start:
                emit_op(op_set_slice_start);
                break;
            case op_get_slice:
                emit_op(op_set_slice);
                break;
            case op_get_prop:
                emit_op(op_set_prop);
                break;
            default:
                die("invalid asssignment");
        }
        memcpy(code_ptr, last_op_and_args+1, last_op_len-1);
        code_ptr += last_op_len-1;
    }
    else {
        // value of <expr> will be top-of-stack - discard it
        emit_op(op_drop);
    }
}

// Initialises the parser.
void parse_start()
{
    // TODO should be somewhere better for this...
    heap_init();
    strings_init();
    stmt_init();

    code_ptr = code_base;
}

// Parses an optional statement, and emits the code to execute it.
//
// Aborts if the statement is not terminated by a comment, ';', or <newline>.
//
// - `<stmt> # comment text`
// - `<stmt> ;`
// - `<stmt> <newline>`
// - `# comment text`
// - `;`
// - `<newline>`
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

// Wraps up parsing a program.
//
// Aborts if input has not been exhausted, or there are unclosed control blocks.
void parse_finish()
{
    if (!lex_end_of_stream()) parser_die("unexpected characters at end of line");

    if (control_sp != 0) parser_die("unfinished control block");
}


