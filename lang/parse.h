#ifndef GUARD_PARSE_H
#define GUARD_PARSE_H

#include "header.h"
#include "dict.h"
#include "object.h"

// Statement parser
Kind func_kind;
u8 control_sp;
extern Dict* global_idents;
extern Class* active_class;
extern Func* active_func;
void parse_stmt(void);
void stmt_init(void);
void expr_init(void);

// Parser
void parse_start(void);
void parse_line(void);
void parse_finish(void);
void parser_die(const char* msg);
void parse_expr(void);
bool parse_index_arg(void);
void emit_potential_method_ref(String* name);

#endif
