#ifndef GUARD_KEYWORD_H
#define GUARD_KEYWORD_H

#include "header.h"

OpData lookup_keyword(const u8* word_ptr, u16 word_len);
OpData opdata_from_value(Value value);
Value opdata_to_value(OpData opdata);

#endif
