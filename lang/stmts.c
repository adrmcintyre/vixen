#include <stdio.h>
#include "header.h"

u8 control_sp;
u8 control_stack[32];

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

void stmt_init()
{
    control_sp = 0;
    begin_loop_sp = 0;
    end_loop_sp = 0;
    end_loop_count = 0;
    forward_jump_sp = 0;
}

// Records the beginning of a control structure.
//
void push_control(u8 op)
{
    if (control_sp == 32) die("too many nested control statements");
    control_stack[control_sp++] = op;
}

// Pops and returns the op corresponding to the most recently started
// control structure. Returns fail if not inside a control structure.
//
u8 pop_control()
{
    if (control_sp == 0) return fail;
    return control_stack[--control_sp];
}

// Records the beginning of a loop construct.
//
void begin_loop()
{
    if (begin_loop_sp == begin_loop_max) die("too many nested loops");
    begin_loop_stack[begin_loop_sp++] = (u16)(code_ptr-code_base);

    end_loop_stack[end_loop_sp++] = end_loop_count;
    end_loop_count = 0;
}

// Emits a forward jump instruction to exit the current loop,
// recording its location in the end_loop stack for later resolution.
//
// Returns 1 on success, or 0 if not in a loop.
//
u16 emit_end_loop_jump(u8 jump_op)
{
    if (end_loop_sp == 0) return 0;
    if (end_loop_sp == end_loop_max) die("control too complex");
    emit_op(jump_op);
    u16 ref = (u16)(code_ptr - code_base);
    end_loop_stack[end_loop_sp++] = ref >> 8;
    end_loop_stack[end_loop_sp++] = ref & 0xff;
    end_loop_count++;
    emit_word(0);
    return 1;
}

// Emits a backward ref to the given location relative to the
// byte immediately following the emitted ref.
//
void emit_backward_ref(u8 *ref_ptr)
{
    u16 rel = (u16)(ref_ptr - (code_ptr+2));
    emit_word(rel);
}

// Sets the ref at the given location to point to the current
// code position relative to the byte immediately following the
// updated ref.
//
void patch_forward_ref(u8 *ref_ptr)
{
    u16 rel = (u16)(code_ptr - (ref_ptr+2));
    *(ref_ptr+0) = rel >> 8;
    *(ref_ptr+1) = rel & 0xff;
}

// Emits a jump instruction to repeat the current loop, and
// resolves outstanding forward jumps to the end of the loop.
//
// Returns 1 on success, or 0 if not currently in a loop.
//
void end_loop(u8 jump_op)
{
    if (begin_loop_sp == 0) die("not in a loop");

    // TODO - swap following two code blocks and use same stack

    // jump to start of loop
    u16 ref = begin_loop_stack[--begin_loop_sp];
    emit_op(jump_op);
    emit_backward_ref(code_base + ref);

    // resolve references to end of loop
    while(end_loop_count) {
        end_loop_sp -= 2;
        u8 ref_hi = end_loop_stack[end_loop_sp+0];
        u8 ref_lo = end_loop_stack[end_loop_sp+1];
        u16 ref = (ref_hi<<8) | ref_lo;
        patch_forward_ref(code_base + ref);
        end_loop_count--;
    }
    end_loop_count = end_loop_stack[--end_loop_sp];
}

// Emits a forward jump instruction, recording its location
// in the forward_jump stack for later resolution.
//
void emit_forward_jump(u8 jump_op)
{
    if (forward_jump_sp == forward_jump_max) die("control too complex");
    emit_op(jump_op);
    forward_jump_stack[forward_jump_sp++] = (u16)(code_ptr - code_base);
    emit_word(0);   // not yet resolved
}

// Resolves the most recent forward jump to the current location.
// Returns 1 on success, or 0 if the forward_jump stack is empty.
//
void resolve_forward_jump()
{
    if (forward_jump_sp == 0) die("not in a control structure");
    u16 ref = forward_jump_stack[--forward_jump_sp];
    patch_forward_ref(code_base + ref);
}

// Parses a control statement.
//
void parse_control_stmt(u8 op)
{
    trace("parse_control_stmt");

    switch(op) {
    case op_if:
        // |if <expr>| ... [else] ... endif
        push_control(op_if);
        parse_expr();
        emit_forward_jump(op_jfalse);
        break;

    case op_else:
        // if <expr> ... |else| ... endif
        if (pop_control() != op_if) die("else without if");
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
            u8 popped = pop_control();
            if (popped != op_if && popped != op_else) die("endif without if");

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
        if (pop_control() != op_while) die("wend without while");
        end_loop(op_jump);
        break;

    case op_repeat:
        // |repeat| ... until <expr>
        push_control(op_repeat);
        begin_loop();
        break;

    case op_until:
        // repeat ... |until <expr>|
        if (pop_control() != op_repeat) die("until without repeat");
        parse_expr();
        end_loop(op_jfalse);
        break;

    case op_break:
        // while <expr> ... |break| ... wend
        //
        // repeat ... |break| ... until <expr>
        //
        if (!emit_end_loop_jump(op_jump)) die("break not in a loop");
        break;


  //case op_func:
  //case op_return:
  //    if (!maybe_expr()) return 0;
  //    emit_op(op_return);
  //    return 1;
  //case op_end:
    }
}

// Parses a ',' separated list of 1 or more exprs.
//
// Returns 1 more than the number of expressions.
//
u16 parse_exprs()
{
    trace("parse_expr");

    u16 nargs = 0;
    parse_expr();
    nargs += 1;
    while(lex_char(',')) {
        parse_expr();
        nargs += 1;
    }
    return nargs;
}

void parse_stmt()
{
    trace("parse_stmt");
    if (!lex_word()) die("expected statement");

    if (lookup_keyword()) {
        fprintf(stderr, "kwop=%02x kwinfo=%02x\n",kwop,kwinfo);
        u8 opcode = kwop;
        if (kwinfo == kw_cmd0) {
            emit_op(opcode);
        }
        else if (kwinfo == kw_cmd_any) {
            // TODO check arg counts
            u16 nargs = parse_exprs();
            emit_op(opcode);
            emit_byte(nargs);
        }
        else if (kwinfo == kw_control) {
            parse_control_stmt(opcode);
        }
        else {
            die("expected command or control statement");
        }
    }
    else {
        u16 id = intern_ident();
        if (!lex_char('=')) die("missing =");
        parse_expr();
        emit_op(op_ident_set);
        emit_ident(id);
    }
}


