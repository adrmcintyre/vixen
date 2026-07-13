#include <string.h>
#include "header.h"

const u8 ident_bucket_count = 32;
Ident* ident_bucket[ident_bucket_count];

void intern_init()
{
    for(u8 i=0; i<ident_bucket_count; i++) ident_bucket[i] = 0;
}

// Looks up token_ptr..input_ptr in the interned symbol table, creating
// a new entry if not found. On exit, sets ident to the new or existing entry.
// Returns 1 if a new entry was created, or 0 otherwise.
Ident* intern_ident(bool* is_new)
{
    u16 token_len = input_ptr-token_ptr;
    u16 token_hash = hash_mem(token_ptr, token_len);
    u8 buck = token_hash & (ident_bucket_count-1);

    Ident* last_ident = 0;
    Ident* ident = ident_bucket[buck];
    while(ident) {
        u16 hash = ident->hash;
        u16 len = ident->len;
        if (hash != token_hash) { }
        else if (len != token_len) { }
        else if (0 != memcmp(token_ptr, &ident->name, len)) { }
        else {
            if (is_new != 0) *is_new = false;
            return ident;
        }

        last_ident = ident;
        ident = ident->chain;
    }

    // TODO - point to name in program text instead of copying it?
    //
    // TODO - allocate value contiguously in separate part of the heap
    // and store a pointer to it from the ident record instead.
    //
    // During code gen inject the value pointer instead of the ident pointer.
    //
    ident = (Ident*) heap_alloc(sizeof(Ident) + token_len);
    ident->chain = 0;
    ident->hash = token_hash;
    ident->val.k = kind_fail;
    ident->val.u = 0;
    ident->slot = 0xff; // doubles as slot_count for funcs
    ident->args = 0;    // only used for funcs/procs
    ident->len = token_len;
    memcpy(ident->name, token_ptr, token_len);

    if (last_ident == 0) {
        ident_bucket[buck] = ident;
    }
    else {
        last_ident->chain = ident;
    }

    if (is_new != 0) *is_new = true;
    return ident;
}
