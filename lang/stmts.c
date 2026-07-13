#include <stdio.h>
#include "header.h"

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

Kind func_kind;
Ident* func_ident;

u8 slot_max = 64;
Ident* slot_stack[64];     // indexed by slot_num of active func

void stmt_init()
{
    control_sp = 0;
    begin_loop_sp = 0;
    end_loop_sp = 0;
    end_loop_count = 0;
    forward_jump_sp = 0;
    func_kind = kind_fail;
    func_ident = 0;
}

// Records the beginning of a control structure.
//
void push_control(Op op)
{
    if (control_sp == 32) parser_die("too many nested control statements");
    control_stack[control_sp++] = op;
}

// Pops and returns the op corresponding to the most recently started
// control structure. Returns fail if not inside a control structure.
//
Op pop_control()
{
    if (control_sp == 0) return fail;
    return control_stack[--control_sp];
}

// Records the beginning of a loop construct.
//
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
// Returns 1 on success, or 0 if not in a loop.
//
u8 emit_end_loop_jump(Op jump_op)
{
    if (end_loop_sp == 0) return 0;
    if (end_loop_sp == end_loop_max) parser_die("control flow is too complicated");
    emit_op(jump_op);
    u16 ref = to_p16(code_ptr);
    *(u16*) &end_loop_stack[end_loop_sp] = ref;
    end_loop_sp += sizeof(u16);
    end_loop_count++;
    emit_word(0);
    return 1;
}

// Emits a backward ref to the given location relative to the
// byte immediately following the emitted ref.
//
void emit_backward_ref(u16 ref)
{
    u16 rel = (u16)(ref - to_p16(code_ptr+2));
    emit_word(rel);
}

// Sets the ref at the given location to point to the current
// code position relative to the byte immediately following the
// updated ref.
//
void patch_forward_ref(u16 ref_ptr)
{
    u16 rel = (u16)(to_p16(code_ptr) - (ref_ptr+2));
    *(u16*) (from_p16(ref_ptr)) = rel;
}

// Emits a jump instruction to repeat the current loop, and
// resolves outstanding forward jumps to the end of the loop.
//
// Returns 1 on success, or 0 if not currently in a loop.
//
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
//
void emit_forward_jump(u8 jump_op)
{
    if (forward_jump_sp == forward_jump_max) parser_die("control flow is too complicated");
    emit_op(jump_op);
    forward_jump_stack[forward_jump_sp++] = to_p16(code_ptr);
    emit_word(0);   // not yet resolved
}

// Resolves the most recent forward jump to the current location.
// Returns 1 on success, or 0 if the forward_jump stack is empty.
//
void resolve_forward_jump()
{
    if (forward_jump_sp == 0) parser_die("not in a control block");
    u16 ref = forward_jump_stack[--forward_jump_sp];
    patch_forward_ref(ref);
}

void parse_func_or_proc(Op op)
{
    if (control_sp != 0) parser_die("func/proc only allowed at top level");

    push_control(op);
    emit_forward_jump(op_jump);

    func_kind = (op==op_func) ? kind_func : kind_proc;

    if (!lex_word()) parser_die("missing name");
    if (lookup_keyword()) parser_die("reserved word cannot be used here");

    // first time we've seen this, or it has only been referenced before
    bool is_new;
    func_ident = intern_ident(&is_new);
    if (is_new || func_ident->val.k == kind_fail) {
        func_ident->val.k = func_kind;
    }
    else {
        parser_die("name already in use");
    }

    u16 func_addr = to_p16(code_ptr);
    func_ident->val.u = func_addr;
    func_ident->args = 0;
    func_ident->slot = 0;

    if (!lex_char('(')) parser_die("missing '('");

    u8 slot_num = 0;
    if (!lex_char(')')) {
        while(1) {
            if (!lex_word()) parser_die("missing parameter name");
            if (lookup_keyword()) parser_die("reserved word cannot be used here");
            Ident* parent_ident = intern_ident(0);
            if (parent_ident->slot != 0xff) parser_die("repeated parameter name");

            if (slot_num >= slot_max) die("too many local variables");

            parent_ident->slot = slot_num;
            slot_stack[slot_num] = parent_ident;
            slot_num += 1;

            if (lex_char(')')) break;
            if (!lex_char(',')) parser_die("missing ','");
        }
    }
    func_ident->args = slot_num;
    func_ident->slot = slot_num;
}

// Parses a control statement.
//
void parse_control_stmt(Op op)
{
    switch(op) {
    case op_if:
        // |if <expr>| ... [else] ... endif
        push_control(op_if);
        parse_expr();
        emit_forward_jump(op_jfalse);
        break;

    case op_else:
        // if <expr> ... |else| ... endif
        if (pop_control() != op_if) parser_die("'else' without 'if'");
        push_control(op_else);

        // account for following jump instruction
        code_ptr += 3;
        resolve_forward_jump();
        code_ptr -= 3;

        emit_forward_jump(op_jump);
        break;

    case op_endif:
        {
            // if <expr> ... [else] ... |endif|
            Op popped = pop_control();
            if (popped != op_if && popped != op_else) parser_die("'endif' without 'if'");

            resolve_forward_jump();
            break;
        }

    case op_while:
        // |while <expr>| ... wend
        push_control(op_while);
        begin_loop();
        parse_expr();
        emit_end_loop_jump(op_jfalse);
        break;

    case op_wend:
        // while <expr> ... |wend|
        if (pop_control() != op_while) parser_die("'wend' without 'while'");
        end_loop(op_jump);
        break;

    case op_repeat:
        // |repeat| ... until <expr>
        push_control(op_repeat);
        begin_loop();
        break;

    case op_until:
        // repeat ... |until <expr>|
        if (pop_control() != op_repeat) parser_die("'until' without 'repeat'");
        parse_expr();
        end_loop(op_jfalse);
        break;

    case op_break:
        // while <expr> ... |break| ... wend
        //
        // repeat ... |break| ... until <expr>
        //
        if (!emit_end_loop_jump(op_jump)) parser_die("'break' is not in a loop");
        break;

    case op_proc:
    case op_func:
        parse_func_or_proc(op);
        break;

    case op_return:
        if (func_kind == kind_fail) parser_die("'return' is not inside a func/proc");
        if (func_kind == kind_proc) {
            if (!lex_peek_stmt_end()) parser_die("a proc cannot return a value");
            emit_op(op_return_proc);
        }
        else {
            parse_expr();
            emit_op(op_return_func);
        }
        break;

    case op_end:
        {
            Op k = pop_control();
            if (k != op_func && k != op_proc) parser_die("'end' not after a func/proc");

            if (func_kind == kind_proc) {
                emit_op(op_return_proc);
            }
            else {
                // TODO - compile error if some path does not end in a return.
                emit_op(op_return_missing);
            }

            // clear slot assignments
            u8 slot_num = func_ident->slot;
            while(slot_num > 0) {
                --slot_num;
                Ident* slot_ident = slot_stack[slot_num];
                slot_ident->slot = 0xff;
            }

            func_ident = 0;
            func_kind = kind_fail;
            resolve_forward_jump();
            break;
        }

    default:
        die("unreachable");
    }
}

// Parses a ',' separated list of 0 or more exprs.
//
// Returns the number of expressions.
//
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

void parse_assign(Ident* ident, u8 is_indexed)
{
    parse_expr();
    if (func_kind == kind_fail) {
        emit_op(is_indexed ? op_ident_set_indexed : op_ident_set);
        emit_ident(ident);
    }
    else {
        u8 slot_num = ident->slot;
        if (slot_num == 0xff) {
            slot_num = func_ident->slot++;
            ident->slot = slot_num;
            slot_stack[slot_num] = ident;
        }
        emit_op(is_indexed ? op_slot_set_indexed : op_slot_set);
        emit_byte(slot_num);
    }
}

void parse_stmt()
{
    if (!lex_word()) parser_die("bad statement");

    if (lookup_keyword()) {
        Op opcode = kw.op;
        if (kw.info == info_cmd0) {
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
    }
    else {
        Ident* ident = intern_ident(0);
        if (lex_char('[')) {
            parse_expr();
            if (!lex_char(']')) parser_die("missing ']'");
            if (!lex_char('=')) parser_die("missing '='");
            parse_assign(ident, 1);
        }
        else if (lex_char('=')) {
            parse_assign(ident, 0);
        }
        else {
            u8 nargs = parse_cmd_args();
            emit_op(op_call_proc);
            emit_byte(nargs);
            emit_ident(ident);
        }
    }
}


