#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "header.h"
#include "dict.h"

/*

We need to support the following API:

dict_new() - create an empty dict
dict_literal() - create a dict from some literal keys and values
dict_get() - lookup key and return value or None
dict_set() - insert/update key/value
dict_del() - remove key

some kind of iteration would be useful
*/

//TODO
void heap_free(void* p)
{}

static const u16 sizeof_DictEntry = sizeof(DictEntry);

static const u16 sizeof_DictKeys = sizeof(DictKeys);

static const u16 sizeof_Dict = sizeof(Dict);


#define MINSIZE 8           // must be power of 2
#define PERTURB_SHIFT 5
#define MAX_PRESIZE 1024    // must be power of 2

#define IX_EMPTY ((i16)(-1))
#define IX_DELETED ((i16)(-2))

static inline DictEntry* DK_ENTRIES(DictKeys *keys) {
    u16 index = keys->index_bytes;
    return (DictEntry*)(&keys->indices[index]);
}

static DictKeys empty_dictkeys = {
    0, // mask
    0, // usable (immutable)
    0, // nentries
    0, // index_bytes
    {IX_EMPTY, IX_EMPTY, IX_EMPTY, IX_EMPTY,
        IX_EMPTY, IX_EMPTY, IX_EMPTY, IX_EMPTY}, // indices
};

#define EMPTY_DICT_KEYS &empty_dictkeys

static i16 dictkeys_get_index(DictKeys *keys, u16 i)
{
    u16 mask = keys->mask;
    i8* indices = keys->indices;
    if (mask < 128) {
        return (i16)indices[i];
    }
    return ((i16*)indices)[i];
}

// write to indices.
static void dictkeys_set_index(DictKeys *keys, u16 i, i16 ix)
{
    u16 mask = keys->mask;
    i8* indices = keys->indices;
    if (mask < 128) {
        indices[i] = (i8)ix;
    }
    else {
        ((i16*)indices)[i] = ix;
    }
}

#define USABLE_FRACTION(n) (((n) << 1)/3)

// count leading zeroes (a vixen instruction)
u16 clz(u16 val)
{
    if (!val) return 16;
    u16 i = 0;
    for( ; !(val & 0x8000); val <<= 1) i++;
    return i;
}

// Find the smallest dk_size >= minsize.
static u16 calculate_keysize(u16 minsize)
{
    if (minsize <= 8) {
        return 8;
    }
    return 1<<(16 - clz(minsize));
}

static u8 estimate_keysize(u16 n)
{
    // compute (n*3 + 1) >> 1, being careful to avoid 16-bit overflow
    u16 arg = (n>>1)*3;
    if (n & 1) {
        arg += 2;
    }
    return calculate_keysize(arg);
}

#define GROWTH_RATE(d) ((d)->used*3)

static DictKeys* dictkeys_new(u16 size)
{
    u16 usable = USABLE_FRACTION(size);
    u16 index_bytes = size <= 128 ? size : size*2;

    DictKeys* keys = (DictKeys*) heap_alloc(sizeof_DictKeys
                        + index_bytes
                        + sizeof_DictEntry * usable);
    keys->mask = size-1;
    keys->usable = usable;
    keys->nentries = 0;
    keys->index_bytes = index_bytes;
    memset(&keys->indices[0], 0xff, index_bytes);
    memset(&keys->indices[index_bytes], 0, sizeof_DictEntry * usable);
    return keys;
}

static void dictkeys_free(DictKeys* keys)
{
    //TODO add to a free list?
    heap_free(keys);
    // do not free the entries themselves, as we've
    // just been called from dict_resize which will
    // not be holding onto them instead.
}

static Dict* dict_internal_new(DictKeys *keys, u16 used)
{
    Dict *dict = (Dict*) heap_alloc(sizeof(Dict));
    dict->keys = keys;
    dict->used = used;
    return dict;
}

Dict* dict_new() {
    return dict_internal_new(EMPTY_DICT_KEYS, 0);
}

// Search index of hash table from offset of entry table
static u16 dictkeys_look_index(DictKeys *keys, u16 hash, i16 index)
{
    u16 mask = keys->mask;
    u16 perturb = hash;
    u16 i = hash & mask;

    for (;;) {
        i16 ix = dictkeys_get_index(keys, i);
        if (ix == index) {
            return i;
        }
        if (ix == IX_EMPTY) {
            return IX_EMPTY;
        }
        perturb >>= PERTURB_SHIFT;
        i = mask & (i*5 + perturb + 1);
    }
}

// Requires entry_key and lookup_key to already have had their hashes computed.
static int keys_eq(Value entry_key, Value lookup_key)
{
    if (entry_key.k != lookup_key.k) {
        if (lookup_key.k == kind_token_proxy && entry_key.k == kind_string) {
            TokenProxy* proxy = (TokenProxy*) from_p16(lookup_key.u);
            String* string = (String*) from_p16(entry_key.u);
            return token_proxy_eq_string(proxy, string);
        }
        return 0;
    }
    if (entry_key.u == lookup_key.u) {
        return 1;
    }
    switch (entry_key.k) {
        case kind_none:
        case kind_bool:
        case kind_int:
        case kind_float:
            return 0;
        case kind_string: {
            String* sa = (String*) from_p16(entry_key.u);
            String* sb = (String*) from_p16(lookup_key.u);
            return string_eq(sa, sb);
        }
        default:
            // silence warnings
            die("unhandled key kind");
            return 0;
    }
}

// Returns hash of v.
static u16 key_hash(Value v)
{
    switch (v.k) {
        case kind_none:
        case kind_bool:
        case kind_int:
        case kind_float:
            return v.u;
        case kind_string: {
            String* string = (String*) from_p16(v.u);
            return string->hash;
        }
        case kind_token_proxy: {
            TokenProxy* proxy = (TokenProxy*) from_p16(v.u);
            return proxy->hash;
        }
        default:
            // silence warnings
            die("unhandled key kind");
            return 0;
    }
}

// Return 1 for equality, 0 for disequality.
static int entries_check_lookup(DictEntry* entries, i16 ix, Value key)
{
    DictEntry *entry = &(entries)[ix];
    return keys_eq(entry->key, key);
}

static i16 dictkeys_lookup(DictKeys* keys, Value key, u16 hash)
{
    DictEntry* entries = DK_ENTRIES(keys);
    u16 mask = keys->mask;
    u16 perturb = hash;
    u16 i = hash & mask;
    i16 ix;
    while (1) {
        ix = dictkeys_get_index(keys, i);
        if (ix >= 0) {
            if (entries_check_lookup(entries, ix, key)) {
                return ix;
            }
        }
        else if (ix == IX_EMPTY) {
            return IX_EMPTY;
        }
        perturb >>= PERTURB_SHIFT;
        i = mask & (i*5 + perturb + 1);
    }
}

// The basic lookup function used by all operations.
// This is based on Algorithm D from Knuth Vol. 3, Sec. 6.4.
// Open addressing is preferred over chaining since the link overhead for
// chaining would be substantial (100% with typical malloc overhead).
// 
// The initial probe index is computed as hash mod the table size. Subsequent
// probe indices are computed as explained earlier.
// 
// All arithmetic on hash should ignore overflow.
// 
// When the key isn't found a IX_EMPTY is returned.
static i16 dict_lookup(Dict *dict, Value key, u16 hash, Value *value_addr)
{
    DictKeys* keys = dict->keys;
    i16 ix = dictkeys_lookup(keys, key, hash);

    if (ix >= 0) {
        *value_addr = DK_ENTRIES(keys)[ix].value;
    }
    else {
        (*value_addr).k = kind_fail;
    }

    return ix;
}

int dict_has_item(Dict* dict, Value key)
{
    u16 hash = key_hash(key);
    DictKeys* keys = dict->keys;
    i16 ix = dictkeys_lookup(keys, key, hash);
    return ix >= 0;
}

// Internal function to find slot for an item from its hash
// when it is known that the key is not present in the dict.
static u16 dictkeys_find_empty_slot(DictKeys *keys, u16 hash)
{
    u16 mask = keys->mask;
    u16 i = hash & mask;
    i16 ix = dictkeys_get_index(keys, i);
    for (u16 perturb = hash; ix >= 0;) {
        perturb >>= PERTURB_SHIFT;
        i = (i*5 + perturb + 1) & mask;
        ix = dictkeys_get_index(keys, i);
    }
    return i;
}

// Initialises indices of a fresh DictKeys object from n consecutive
// DictEntry items starting at entry.
static void dictkeys_build_indices(DictKeys *keys, DictEntry *entry, u16 n)
{
    u16 mask = keys->mask;
    for (i16 ix = 0; ix != n; ix++, entry++) {
        u16 hash = key_hash(entry->key);
        u16 i = hash & mask;
        for (u16 perturb = hash; dictkeys_get_index(keys, i) != IX_EMPTY;) {
            perturb >>= PERTURB_SHIFT;
            i = mask & (i*5 + perturb + 1);
        }
        dictkeys_set_index(keys, i, ix);
    }
}

// Restructure the table by allocating a new table and reinserting
// all items again.  When entries have been deleted, the new table
// may actually be smaller than the old one.
static void dict_resize(Dict *dict, u16 newsize)
{
    DictKeys *oldkeys = dict->keys;

    // Allocate a new table.
    dict->keys = dictkeys_new(newsize);

    u16 numentries = dict->used;

    DictEntry *oldentries = DK_ENTRIES(oldkeys);
    DictEntry *newentries = DK_ENTRIES(dict->keys);
    if (oldkeys->nentries == numentries) {
        memcpy(newentries, oldentries, numentries * sizeof_DictEntry);
    }
    else {
        DictEntry *entry = oldentries;
        for (u16 i = 0; i < numentries; i++) {
            while (entry->value.k == kind_fail)
                entry++;
            newentries[i] = *entry++;
        }
    }
    dictkeys_build_indices(dict->keys, newentries, numentries);

    if (oldkeys != EMPTY_DICT_KEYS) {
        dictkeys_free(oldkeys);
    }

    dict->keys->usable -= numentries;
    dict->keys->nentries = numentries;
}

static void dict_insert_resize(Dict *dict)
{
    dict_resize(dict, calculate_keysize(GROWTH_RATE(dict)));
}

// Internal routine to insert a new item into the table.
// Used both by the internal resize routine and by the public insert routine.
static void dict_insert(Dict *dict, Value key, u16 hash, Value value)
{
    Value old_value;
    i16 ix = dict_lookup(dict, key, hash, &old_value);

    if (ix == IX_EMPTY) {
        // Insert into new slot.
        if (dict->keys->usable <= 0) {
            // Need to resize.
            dict_insert_resize(dict);
        }

        u16 hashpos = dictkeys_find_empty_slot(dict->keys, hash);
        dictkeys_set_index(dict->keys, hashpos, dict->keys->nentries);

        DictEntry* entry = &DK_ENTRIES(dict->keys)[dict->keys->nentries];
        entry->key = key;
        entry->value = value;
        
        dict->used++;
        dict->keys->usable--;
        dict->keys->nentries++;
    }
    else if (! (old_value.k == value.k && old_value.u == value.u)) {
        // TODO
        // dec_ref(old_value);
        DK_ENTRIES(dict->keys)[ix].value = value;
    }
}

// Same as dict_insert, but specialized for keys = EMPTY_KEYS.
static void dict_insert_empty(Dict *dict, Value key, u16 hash, Value value)
{
    DictKeys *newkeys = dictkeys_new(MINSIZE);
    dict->keys = newkeys;

    u16 hashpos = hash & (MINSIZE-1);
    dictkeys_set_index(dict->keys, hashpos, 0);
    DictEntry *entry = DK_ENTRIES(dict->keys);
    entry->key = key;
    entry->value = value;
    dict->used++;
    dict->keys->usable--;
    dict->keys->nentries++;
}

Value dict_get_item(Dict *dict, Value key)
{
    u16 hash = key_hash(key);
    Value value;
    i16 ix = dict_lookup(dict, key, hash, &value);
    (void)ix;

    return value;
}

void dict_set_item(Dict* dict, Value key, Value value)
{
    u16 hash = key_hash(key);
    if (dict->keys == EMPTY_DICT_KEYS) {
        dict_insert_empty(dict, key, hash, value);
    } else {
        // dict_insert() handles any resizing that might be necessary
        dict_insert(dict, key, hash, value);
    }
}

Dict* dict_new_presized(u16 min_used)
{
    u16 newsize;

    if (min_used <= USABLE_FRACTION(MINSIZE)) {
        return dict_new();
    }
    // There is no strict guarantee that returned dict can contain min_used
    // items without resize.  So we create medium size dict instead of very
    // large dict or MemoryError.
    if (min_used > USABLE_FRACTION(MAX_PRESIZE)) {
        newsize = MAX_PRESIZE;
    }
    else {
        newsize = estimate_keysize(min_used);
    }

    DictKeys* new_keys = dictkeys_new(newsize);
    return dict_internal_new(new_keys, 0);
}

Dict* dict_new_from_items(Value* keys_and_values, u16 length)
{
    Value* kvs = keys_and_values;

    for (u16 i = 0; i < length; i++) {
        if (kvs->k != kind_string) {
            die("string keys only please!");
        }
        kvs += 2;
    }

    Dict *dict = dict_new_presized(length);

    kvs = keys_and_values;

    for (u16 i = 0; i < length; i++) {
        Value key = *kvs;
        kvs++;

        Value value = *kvs;
        kvs++;

        dict_set_item(dict, key, value);
    }

    return dict;
}

static void dict_delete_common(
    Dict *dict,
    u16 hash,
    i16 ix,
    Value old_value)
{
    u16 hashpos = dictkeys_look_index(dict->keys, hash, ix);

    dict->used--;
    dictkeys_set_index(dict->keys, hashpos, IX_DELETED);
    DictEntry *entry = &DK_ENTRIES(dict->keys)[ix];
    // TODO
    // dec_ref(entry->value);
    entry->key.k = kind_fail;
    entry->value.k = kind_fail;
}

// Returns 1 on deletion, 0 on key not present.
int dict_delete(Dict* dict, Value key)
{
    u16 hash = key_hash(key);
    Value old_value;
    i16 ix = dict_lookup(dict, key, hash, &old_value);
    if (ix == IX_EMPTY || old_value.k == kind_fail) {
        return 0;
    }

    dict_delete_common(dict, hash, ix, old_value);
    return 1;
}

u16 dict_length(Dict* dict)
{
    return dict->used;
}

u16 dict_iter_init(Dict* dict)
{
    return 0;
}

u16 dict_iter_item(Dict* dict, u16 iter, Value* key, Value* value)
{
    DictKeys *keys = dict->keys;
    while (1) {
        if (iter >= keys->nentries) {
            return 0;
        }

        DictEntry* entry = DK_ENTRIES(keys) + iter;
        iter += 1;
        // skip deleted entries
        if (entry->value.k == kind_fail) {
            continue;
        }

        key->k = entry->key.k;
        key->u = entry->key.u;
        value->k = entry->value.k;
        value->u = entry->value.u;
        break;
    }
    return iter;
}


// Pop also useful - delete, but return value of deleted key.
// Maybe also keys() and values().
