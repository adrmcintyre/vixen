
#include <stdio.h>
#include "header.h"

///////////////////////////////////////////////////////////////////////////////
// Code generation
//

bool opt_trace_emit = false;

// TODO check code_ptr does not run out of bounds!
u8* code_ptr;
u8* last_op_ptr;

// Emits the specifed byte to the code stream.
//
void emit_byte(u8 b)
{
    if (opt_trace_emit) fprintf(stderr, "%04x: emit_byte 0x%02x = %d\n", to_p16(code_ptr), b, b);
    *code_ptr++ = b;
}

// Emits the specified word to the code stream.
//
void emit_word(u16 w)
{
    if (opt_trace_emit) fprintf(stderr, "%04x: emit_word 0x%04x = %d\n", to_p16(code_ptr), w, w);
    *(u16*) code_ptr = w;
    code_ptr += sizeof(u16);
}

// Emits the specified opcode to the code stream.
//
void emit_op(Op op)
{
    if (opt_trace_emit) fprintf(stderr, "%04x: emit_op %s\n", to_p16(code_ptr), debug_op_name(op));
    last_op_ptr = code_ptr;
    *code_ptr++ = (u8) op;
}

void emit_ident(Ident* ident)
{
    if (opt_trace_emit) {
        fprintf(stderr, "%04x: emit_ident %04x = ", to_p16(code_ptr), to_p16(ident));
        fwrite(ident->name, 1, ident->len, stderr);
        putc('\n', stderr);
    }

    *(u16*) code_ptr = to_p16(ident);
    code_ptr += sizeof(u16);
}
