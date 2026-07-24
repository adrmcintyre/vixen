#include "header.h"
#include <string.h>

String* interned_string_empty;
String* interned_string_none;
String* interned_string_true;
String* interned_string_false;
String* interned_string_array;
String* interned_string_dict;
String* interned_string_func;
String* interned_string_class;
String* interned_string_object;
String* interned_string_unknown;

String* string_bucket[256];

void strings_init()
{
    interned_string_empty   = string_from_data((const u8*) "", 0);
    interned_string_none    = string_from_data((const u8*) "None", 4);
    interned_string_true    = string_from_data((const u8*) "True", 4);
    interned_string_false   = string_from_data((const u8*) "False", 5);
    interned_string_array   = string_from_data((const u8*) "<array>", 7);
    interned_string_dict    = string_from_data((const u8*) "<dict>", 6);
    interned_string_func    = string_from_data((const u8*) "<func>", 6);
    interned_string_class   = string_from_data((const u8*) "<class>", 7);
    interned_string_class   = string_from_data((const u8*) "<object>", 8);
    interned_string_unknown = string_from_data((const u8*) "<unknown>", 9);

    for(int i=0; i<256; i++) string_bucket[i] = 0;
}

String* string_from_char(u8 ch)
{
    String* str = string_bucket[ch];
    if (str == 0) {
        str = (String*) heap_alloc(sizeof(String) + 1);
        str->len = 1;
        str->data[0] = ch;
        string_bucket[ch] = str;
        str->hash = hash_mem(str->data, str->len);
    }
    return str;
}

String* string_from_data(const u8* data, i16 len)
{
    if (len == 0) return interned_string_empty;
    if (len == 1) {
        return string_from_char(*data);
    }
    String* str = (String*) heap_alloc(sizeof(String) + len);
    str->len = len;
    memcpy(str->data, data, len);
    str->hash = hash_mem(str->data, str->len);
    return str;
}

u16 string_hash(u16 s)
{
    String* string = (String*)from_p16(s);
    u16 h = string->hash;
    if (!h) {
        h = hash_mem(string->data, string->len);
        string->hash = h;
    }
    return h;
}

const char* string_data(u16 s)
{
    String* string = (String*)from_p16(s);
    return (const char*)string->data;
}

int string_eq(String* s1, String* s2)
{
    return s1->hash == s2->hash &&
        s1->len == s2->len &&
        0 == memcmp(s1->data, s2->data, s1->len);
}

String* string_get_slice(String* string, i16 start, i16 end)
{
    i16 len = string->len;

    slice_adjust(&start, &end, &len);

    String* string2 = (String*) heap_alloc(sizeof(String) + len);
    string2->len = len;
    memcpy(string2->data, string->data + start, len);
    string2->hash = hash_mem(string2->data, string2->len);
    return string2;
}
