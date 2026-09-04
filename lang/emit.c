#include "header.h"

#include <stdio.h>

///////////////////////////////////////////////////////////////////////////////
// Code generation
//

bool opt_trace_emit = false;

// TODO check code_ptr does not run out of bounds!
u8* code_ptr;
u8* last_op_ptr;

// Emits a single byte to the code stream.
void emit_byte(u8 b)
{
    if (opt_trace_emit) fprintf(stderr, "%04x: emit_byte 0x%02x = %d\n", to_p16(code_ptr), b, b);
    *code_ptr++ = b;
}

// Emits a 16-bit word to the code stream.
void emit_word(u16 w)
{
    if (opt_trace_emit) fprintf(stderr, "%04x: emit_word 0x%04x = %d\n", to_p16(code_ptr), w, w);
    *(u16*) code_ptr = w;
    code_ptr += sizeof(u16);
}

void emit_string(const String* s)
{
    if (opt_trace_emit) {
        fprintf(stderr, "%04x: emit_string \"", to_p16(code_ptr));
        fwrite(s->data, 1, s->len, stderr);
        fprintf(stderr, "\"\n");
    }
    *(u16*) code_ptr = to_p16(s);
    code_ptr += sizeof(u16);
}

// Emits a vm opcode to the code stream.
void emit_op(Op op)
{
    if (opt_trace_emit) fprintf(stderr, "%04x: emit_op %s\n", to_p16(code_ptr), debug_op_name(op));
    last_op_ptr = code_ptr;
    *code_ptr++ = (u8) op;
}
