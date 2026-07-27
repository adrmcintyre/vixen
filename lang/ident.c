#include <string.h>
#include <stdio.h>
#include "header.h"
#include "dict.h"
#include "object.h"

Dict* ident_dict;

extern void ident_init()
{
    ident_dict = dict_new();
}

// Looks up token_ptr..token_ptr+token_len in the interned symbol table, creating
// a new entry if not found. On exit, sets ident to the new or existing entry.
// Returns 1 if a new entry was created, or 0 otherwise.
extern Ident* ident_intern(Dict* dict, bool* is_new)
{
    if (dict == 0) {
        dict = ident_dict;
    }

    String* name = string_from_token();
    Value key;
    key.k = kind_string;
    key.u = to_p16(name);

    Value item = dict_get_item(dict, key);
    if (item.k != kind_fail) {
        if (is_new != 0) *is_new = false;
        return (Ident*) from_p16(item.u);
    }

    // Ident doesn't exist - now we can allocate it for real.

    // TODO - allocate value contiguously in separate part of the heap
    // and store a pointer to it from the ident record instead.
    //
    // During code gen inject the value pointer instead of the ident pointer.
    //
    Ident* ident = (Ident*) heap_alloc(sizeof(Ident));
    ident->val.k = kind_fail;
    ident->val.u = 0;
    ident->slot = 0xff;
    ident->nameptr = to_p16(name);

    item.k = kind_ident;
    item.u = to_p16(ident);
    dict_set_item(dict, key, item);

    if (is_new != 0) *is_new = true;
    return ident;
}

extern int token_proxy_eq_string(TokenProxy* proxy, String* string)
{
    if ((proxy->hash != string->hash) ||
        (proxy->len != string->len))
    {
        return false;
    }

    const u8* token = prog_base + proxy->ptr;
    return (0 == memcmp(token, string->data, string->len));
}