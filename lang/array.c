#include <string.h>
#include "header.h"
#include "array.h"

Array* array_new_presized(i16 len, i16 cap)
{
    if (len > cap) {
        cap = len;
    }
    Array* array = (Array*) heap_alloc(sizeof(Array));
    u8* data = (u8*) heap_alloc(cap * sizeof_Value);
    
    array->len = len;
    array->cap = cap;
    array->dataptr = to_p16(data);
    return array;
}

void array_push(Array* dst, Value v)
{
    i16 len = dst->len;
    i16 cap = dst->cap;
    i16 newlen = len + 1;
    if (newlen > cap) {
        i16 newcap = (cap >> 1) * 3;
        if (cap & 1) {
            newcap += 2;
        }
        if (newcap < newlen) {
            newcap = newlen;
        }
        u8* olddata = from_p16(dst->dataptr);
        u8* newdata = (u8*) heap_alloc(newcap * sizeof_Value);

        memcpy(newdata, olddata, len * sizeof_Value);
        dst->len = newlen;
        dst->cap = newcap;
        dst->dataptr = to_p16(newdata);
    }
    set_value(from_p16(dst->dataptr + len * sizeof_Value), v);
    dst->len = newlen;
}

// TODO array_extend

Array* array_append(Array* src1, Array* src2)
{
    u16 len = src1->len + src2->len;
    Array* dst = array_new_presized(len, len);
    memcpy(from_p16(dst->dataptr), from_p16(src1->dataptr), src1->len * sizeof_Value);
    memcpy(from_p16(dst->dataptr + src1->len * sizeof_Value), from_p16(src2->dataptr), src2->len * sizeof_Value);
    return dst;
}

Array* array_get_slice(Array* src, i16 start, i16 end)
{
    i16 len = (i16) src->len;
    slice_adjust(&start, &end, &len);

    Array* dst = array_new_presized(len, 0);
    memcpy(
        from_p16(dst->dataptr),
        from_p16(src->dataptr + start*sizeof_Value),
        len * sizeof_Value);
    return dst;
}

void array_set_slice(Array* dst, i16 start, i16 end, Array* src)
{
    i16 slicelen = (i16) dst->len; // num elems to replace
    i16 cap = (i16) dst->cap;
    slice_adjust(&start, &end, &slicelen);

    u8* srcdata = from_p16(src->dataptr);
    u8* olddata = from_p16(dst->dataptr);

    i16 newlen = dst->len - slicelen + src->len;
    if (newlen > dst->cap) {
        u16 newcap = (cap >> 1) * 3;
        if (cap & 1) {
            newcap += 2;
        }
        u8* newdata = (u8*) heap_alloc(newcap * sizeof_Value);

        // newarr = dst[0:start]
        memcpy(newdata, olddata, start * sizeof_Value);

        // newarr += src
        memcpy(newdata + start * sizeof_Value, srcdata, src->len * sizeof_Value);

        // newarr += dst[end:len(dst)]
        memcpy(
            newdata + (start+src->len) * sizeof_Value,
            olddata + end * sizeof_Value,
            (dst->len - end) * sizeof_Value);
        
        dst->len = newlen;
        dst->cap = newcap;
        dst->dataptr = to_p16(newdata);
    }
    else {
        memmove(
            olddata + (start + src->len) * sizeof_Value,
            olddata + end * sizeof_Value,
            (dst->len - end) * sizeof_Value);
        memmove(olddata + start * sizeof_Value, srcdata, src->len * sizeof_Value);
        dst->len = newlen;
    }
}