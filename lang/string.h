#ifndef GUARD_STRING_H
#define GUARD_STRING_H

#include "header.h"

// Represents a string.
typedef struct String {
    u16 hash;   // hash of the string
    i16 len;    // length of the string in characters
    u8 data[];  // the bytes of the string
} String;

// Strings
extern String* interned_char_strings[];
extern String* interned_string_empty;
extern String* interned_string_none;
extern String* interned_string_true;
extern String* interned_string_false;
extern String* interned_string_nan;
extern String* interned_string_neg_inf;
extern String* interned_string_pos_inf;
extern String* interned_string_array;
extern String* interned_string_dict;
extern String* interned_string_func;
extern String* interned_string_class;
extern String* interned_string_object;
extern String* interned_string_bom;
extern String* interned_string_unknown;

void strings_init(void);
String* string_intern_token(const u8* ptr, i16 len);
String* string_from_char(u8 ch);
String* string_from_data(const u8* data, i16 len);
String* string_new_uninited(i16 len);
void string_rehash(String* string);
bool string_eq(String* s1, String* s2);
String* string_get_slice(String* string, i16 start, i16 end);
String* string_concat(String* str1, String* str2);
i16 string_compare(String* str1, String* str2);

#endif
