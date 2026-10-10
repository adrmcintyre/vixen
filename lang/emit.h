#ifndef GUARD_EMIT_H
#define GUARD_EMIT_H

#include "header.h"

// Code generation
extern bool opt_trace_emit;
extern u8* code_base;
extern u8* code_ptr;
extern u8* last_op_ptr;
void emit_op(Op op);
void emit_byte(u8 b);
void emit_word(u16 w);
void emit_string(const String* s);

#endif

