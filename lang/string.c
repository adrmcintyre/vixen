#include "header.h"
#include <string.h>

String* interned_string_empty;
String* interned_string_true;
String* interned_string_false;
String* interned_string_array;
String* interned_string_proc;
String* interned_string_func;
String* interned_string_unknown;

String* string_bucket[256];

void strings_init()
{
    interned_string_empty   = string_from_data((const u8*) "", 0);
    interned_string_true    = string_from_data((const u8*) "True", 4);
    interned_string_false   = string_from_data((const u8*) "False", 5);
    interned_string_array   = string_from_data((const u8*) "<array>", 7);
    interned_string_proc    = string_from_data((const u8*) "<proc>", 6);
    interned_string_func    = string_from_data((const u8*) "<func>", 6);
    interned_string_unknown = string_from_data((const u8*) "<unknown>", 9);

    for(int i=0; i<256; i++) string_bucket[i] = 0;
}

String* string_from_char(u8 ch)
{
    String* str = string_bucket[ch];
    if (str == 0) {
        str = (String*) heap_alloc(sizeof(String) + 1);
        str->hash = 0;
        str->len = 1;
        str->data[0] = ch;
        string_bucket[ch] = str;
    }
    return str;
}

String* string_from_data(const u8* data, u16 len)
{
    if (len == 0) return interned_string_empty;
    if (len == 1) {
        return string_from_char(*data);
    }
    String* str = (String*) heap_alloc(sizeof(String) + len);
    str->hash = 0;
    str->len = len;
    memcpy(str->data, data, len);
    return str;
}


