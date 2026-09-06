#ifndef GUARD_DICT_H
#define GUARD_DICT_H

#include "header.h"

typedef struct {
    Value key;
    Value value;
} DictEntry;

typedef struct {
    u16 mask;           // mask used during probing (=size-1)
    u16 usable;         // Number of usable entries in dk_entries.
    u16 nentries;       // Number of used entries in dk_entries.
    // NOTE we could derive index_bytes from mask:
    //  index_bytes = (mask < 0x80) ? (mask+1) : (2*mask+1)
    u16 index_bytes;    // Size of the hash table (indices) by bytes.

    // Actual hash table of dk_size entries. It holds indices into
    // entries, or IX_EMPTY(-1) or IX_DELETED(-2).
    //
    // Indices must be: 0 <= index < USABLE_FRACTION(mask+1).
    //
    // The size in bytes of an index depends on size:
    //
    // * 1 byte if size <= 128 (u8*)
    // * 2 bytes if size > 128 (u16*)
    //
    // Dynamically sized.
    i8 indices[];

    // "DictEntry entries[USABLE_FRACTION(DK_SIZE(keys))];" array follows
} DictKeys;

typedef struct Dict {
    u16 used;
    DictKeys* keys;
} Dict;

extern Dict* dict_new(void);
extern Dict* dict_new_presized(u16 min_used);
extern Value dict_get_item(Dict *dict, Value key);
extern void dict_set_item(Dict* dict, Value key, Value value);
extern int dict_has_item(Dict* dict, Value key);
extern int dict_delete(Dict* dict, Value key);
extern u16 dict_length(Dict* dict);
extern u16 dict_iter_init(Dict* dict);
extern u16 dict_iter_item(Dict* dict, u16 iter, Value* key, Value* value);

#endif
