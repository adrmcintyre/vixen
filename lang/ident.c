#include <string.h>
#include <stdio.h>
#include "header.h"
#include "dict.h"

Dict* ident_dict;
Value ident_proxy_key;

extern void ident_init()
{
    ident_dict = dict_new();

    // In practice this could be statically allocated
    ident_proxy_key.k = kind_ident_proxy;
    ident_proxy_key.u = to_p16(heap_alloc(sizeof(IdentProxy)));
}

// Looks up token_ptr..token_ptr+token_len in the interned symbol table, creating
// a new entry if not found. On exit, sets ident to the new or existing entry.
// Returns 1 if a new entry was created, or 0 otherwise.
extern Ident* ident_intern(bool* is_new)
{
    u16 hash = hash_mem(token_ptr, token_len);

    // We reference the token directly from the program text
    // using a buffer that only gets allocated once to avoid
    // a heap allocation on every lookup.
    IdentProxy* ref = (IdentProxy*) from_p16(ident_proxy_key.u);
    ref->hash = hash;
    ref->len = token_len;
    ref->ptr = to_p16(token_ptr);

    Value item = dict_get_item(ident_dict, ident_proxy_key);
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
    Ident* ident = (Ident*) heap_alloc(sizeof(Ident) + token_len);
    ident->hash = hash;
    ident->val.k = kind_fail;
    ident->val.u = 0;
    ident->slot = 0xff;
    ident->len = token_len;
    memcpy(ident->name, token_ptr, token_len);

    item.k = kind_ident;
    item.u = to_p16(ident);
    dict_set_item(ident_dict, item, item);

    if (is_new != 0) *is_new = true;
    return ident;
}

extern int ident_eq(Ident* a, Ident* b)
{
    return 
        (a->hash == b->hash) &&
        (a->len != b->len) &&
        (0 == memcmp(a->name, b->name, a->len));

}

extern int ident_proxy_eq(Ident* ident, IdentProxy* proxy)
{
    if ((ident->hash != proxy->hash) ||
        (ident->len != proxy->len))
    {
        return false;
    }

    const u8* prog_token = prog_base + proxy->ptr;
    return (0 == memcmp(ident->name, prog_token, ident->len));
}