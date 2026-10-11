#include "string.h"
#include "header.h"
#include "dict.h"
#include "heap.h"

#include <string.h>

//DEBUG
#include <stdio.h>

static Dict* interned_strings;      // string -> string : a dictionary of interned strings
String* interned_char_strings[256]; // interned strings for single character strings (on-demand)

static Token* last_token; // only ever used for lookups, never stored

// Interned strings for well known values.
String* interned_string_empty; // the empty string
String* interned_string_none;
String* interned_string_true;
String* interned_string_false;
String* interned_string_nan;
String* interned_string_neg_inf;
String* interned_string_pos_inf;

// Interned strings for representations of various types.
String* interned_string_array;
String* interned_string_dict;
String* interned_string_func;
String* interned_string_class;
String* interned_string_object;
String* interned_string_bom;
String* interned_string_unknown;

// forward declarations
static String* immortal_string(const u8* data, i16 len);

// Initialises the strings module.
void strings_init(void)
{
    interned_strings = dict_new("!interned_strings");
    last_token = (Token*) heap_alloc("!last_token", kind_token, sizeof(Token));

    interned_string_empty = string_new_uninited(0);
    string_rehash(interned_string_empty);

    heap_immortalise(interned_string_empty);

    interned_string_none    = immortal_string((const u8*) "None", 4);
    interned_string_true    = immortal_string((const u8*) "True", 4);
    interned_string_false   = immortal_string((const u8*) "False", 5);
    interned_string_nan     = immortal_string((const u8*) "NaN", 3);
    interned_string_pos_inf = immortal_string((const u8*) "Inf", 3);
    interned_string_neg_inf = immortal_string((const u8*) "-Inf", 4);

    interned_string_array   = immortal_string((const u8*) "<array>", 7);
    interned_string_dict    = immortal_string((const u8*) "<dict>", 6);
    interned_string_func    = immortal_string((const u8*) "<func>", 6);
    interned_string_class   = immortal_string((const u8*) "<class>", 7);
    interned_string_object  = immortal_string((const u8*) "<object>", 8);
    interned_string_bom     = immortal_string((const u8*) "<bound-method>", 14);
    interned_string_unknown = immortal_string((const u8*) "<unknown>", 9);

    for(int i=0; i<256; i++) interned_char_strings[i] = 0;
}

// Returns an interned string from a token of program text.
String* string_intern_token(const u8* ptr, i16 len)
{
    if (len == 1) {
        return string_from_char(*ptr);
    }

    // see if already interned without allocating yet
    last_token->hash = hash_mem(ptr, len);
    last_token->len = len;
    last_token->ptr = ptr;

    Value key;
    key.k = kind_token;
    key.u = to_p16(last_token);

    Value strval = dict_get_item(interned_strings, key);
    if (strval.k != kind_fail) {
        rc_dec(strval);
        return (String*) from_p16(strval.u);
    }

    String* string = string_from_data(ptr, len);
    strval.k = kind_string;
    strval.u = to_p16(string);
    dict_set_item(interned_strings, strval, strval);

    return string;
}

// Returns an interned string for the specified character.
String* string_from_char(u8 ch)
{
    String* str = interned_char_strings[ch];
    if (str == 0) {
        str = (String*) heap_alloc("string_from_char", kind_string, sizeof(String) + 1);
        str->len = 1;
        str->data[0] = ch;
        string_rehash(str);
        interned_char_strings[ch] = str;
    }
    return str;
}

// Returns a string containing len bytes of data as provided.
String* string_from_data(const u8* data, i16 len)
{
    if (len == 0) return interned_string_empty;
    if (len == 1) {
        return string_from_char(*data);
    }
    String* str = string_new_uninited(len);
    memcpy(str->data, data, len);
    string_rehash(str);
    return str;
}

static String* immortal_string(const u8* data, i16 len)
{
    String* str = string_new_uninited(len);
    heap_immortalise(str);
    memcpy(str->data, data, len);
    string_rehash(str);
    return str;
}

// Returns a newly allocated string with space for len bytes of data.
// It is the caller's responsibility to initialise the data and hash value.
String* string_new_uninited(i16 len)
{
    String* str = (String*) heap_alloc("string_new_uninited", kind_string, sizeof(String) + len);
    str->len = len;
    return str;
}

// (Re-)computes string's hash field.
void string_rehash(String* string)
{
    u16 h = string->hash;
    if (!h) {
        h = hash_mem(string->data, string->len);
        string->hash = h;
    }
}

// TODO - unused
const char* string_data(u16 s)
{
    String* string = (String*) from_p16(s);
    return (const char*) string->data;
}

// Returns true if the contents of both strings are identical.
bool string_eq(String* s1, String* s2)
{
    return s1->hash == s2->hash &&
        s1->len == s2->len &&
        0 == memcmp(s1->data, s2->data, s1->len);
}

// Returns a string containing the slice of characters from string with
// indexes in the range start' <= index < end', where start' is derived
// from start as follows (and end' is derived from end in the same way):
//
// - if start >= 0: start' = max(0, min(start, len))
// - if start < 0:  start' = max(0, min(start+len, len))
String* string_get_slice(String* string, i16 start, i16 end)
{
    i16 len = slice_adjust(string->len, &start, &end);
    return string_from_data(string->data + start, len);
}

// Returns a string formed from the concatentation of str1 and str2.
String* string_concat(String* str1, String* str2)
{
    if (str2->len == 0) {
        return rc_inc_ptr(str1);
    }

    if (str1->len == 0) {
        return rc_inc_ptr(str2);
    }

    i16 len = str1->len + str2->len;
    String* str = (String*) heap_alloc("string_concat", kind_string, sizeof(String) + len);
    str->len = len;

    u8* ptr = str->data;
    memcpy(ptr, str1->data, str1->len);
    ptr += str1->len;
    memcpy(ptr, str2->data, str2->len);
    string_rehash(str);

    return str;
}

i16 string_compare(String* str1, String* str2)
{
    if (str1 == str2) {
        return 0;
    }

    i16 len1 = str1->len;
    i16 len2 = str2->len;
    i16 prefix_len = len1;
    if (prefix_len > len2) {
        prefix_len = len2;
    }
    int cmp = memcmp(str1->data, str2->data, prefix_len);
    if (cmp < 0) {
        return -1;
    }
    if (cmp > 0) {
        return 1;
    }
    if (len1 == len2) {
        return 0;
    }
    if (len1 < len2) {
        return -1;
    }
    else {
        return 1;
    }
}
