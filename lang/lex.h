#ifndef GUARD_LEX_H
#define GUARD_LEX_H

#include "header.h"

extern const u8* input_ptr;
extern const u8* token_ptr;
extern i16 token_len;
bool lex_char(u8 ch);
Value lex_word(void);
String* must_lex_ident(void);
void unlex_word(void);
bool lex_peek_stmt_end(void);
Value lex_number(void);
String* lex_string(void);
bool lex_comment(void);
bool lex_end_of_stream(void);

#endif
