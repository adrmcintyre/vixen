#include "header.h"

#include <string.h>

extern bool token_string_eq(Token* token, String* string)
{
    if ((token->hash != string->hash) ||
        (token->len != string->len))
    {
        return false;
    }

    return (0 == memcmp(token->ptr, string->data, string->len));
}