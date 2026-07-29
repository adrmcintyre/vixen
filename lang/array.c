#include <string.h>
#include "header.h"
#include "array.h"

// Allocate a new array with specified length and capacity.
// The actual capacity allocated will be at least max(len, cap).
Array* array_new_presized(i16 len, i16 cap)
{
    if (len > cap) {
        cap = len;
    }

    Array* array = (Array*) heap_alloc(sizeof(Array));
    u8* data = 0;
    if (cap != 0) data = (u8*) heap_alloc(cap * sizeof_Value);
    
    array->len = len;
    array->cap = cap;
    array->dataptr = to_p16(data);
    return array;
}

// Reallocate an array's data to ensure it has the appropriate capacity for len elements.
// Returns 1 if reallocation occurred. The array's cap and len are updated. No elements are copied.
static int array_resize(Array* array, i16 len)
{
    array->len = len;

    // do not reallocate if utilisation would be >= 50%
    if ((array->cap>>1) <= len && len <= array->cap) {
        return 0;
    }

    i16 newcap = len + (len>>3);
    if (len > 0) newcap += 3;
    if (len >= 9) newcap += 3;

    u16 newdata = 0;
    if (newcap > 0) newdata = to_p16(heap_alloc(newcap * sizeof_Value));

    array->dataptr = newdata;
    array->cap = newcap;

    return 1;
}

// Append a single value to an array.
void array_append(Array* array, Value v)
{
    i16 len = array->len;
    i16 newlen = len + 1;

    u16 olddata = array->dataptr;
    if (array_resize(array, newlen)) {
        memcpy(from_p16(array->dataptr), from_p16(olddata), len * sizeof_Value);
    }

    set_value(from_p16(array->dataptr + len * sizeof_Value), v);
}

// Remove the last value from an array.
Value array_pop(Array* array)
{
    i16 len = array->len;
    if (len == 0) {
        Value v;
        v.k = kind_fail;
        return v;
    }
    u16 olddata = array->dataptr;
    i16 newlen = len - 1;
    Value v = get_value(from_p16(olddata + newlen * sizeof_Value));

    if (array_resize(array, newlen)) {
        memcpy(
            from_p16(array->dataptr),
            from_p16(olddata),
            newlen * sizeof_Value);
    }
    return v;
}

// Return a new array from the concatenation of src1 and src2.
Array* array_concat(Array* src1, Array* src2)
{
    u16 len = src1->len + src2->len;
    Array* dst = array_new_presized(len, len);

    memcpy(
        from_p16(dst->dataptr),
        from_p16(src1->dataptr),
        src1->len * sizeof_Value);

    memcpy(
        from_p16(dst->dataptr + src1->len * sizeof_Value),
        from_p16(src2->dataptr),
        src2->len * sizeof_Value);

    return dst;
}

// Return a new array from elements of src with indexes in the half-open range [start,end).
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

// Replace elements of dst with indexes in the half-open range [start,end) with
// all elements from src. The number of elements in src need not match the size
// of the destination range.
void array_set_slice(Array* dst, i16 start, i16 end, Array* src)
{
    i16 slicelen = (i16) dst->len; // num elems to replace
    slice_adjust(&start, &end, &slicelen);

    u8* srcdata = from_p16(src->dataptr);
    u8* olddata = from_p16(dst->dataptr);

    // beware, if dst == src, after array_resize reading src->len returns newlen,
    // so we read it now.
    i16 oldlen = dst->len;
    i16 srclen = src->len;
    i16 newlen = oldlen - slicelen + srclen;

    if (array_resize(dst, newlen)) {
        u8* newdata = from_p16(dst->dataptr);

        u16 bytes = start * sizeof_Value;
        memcpy(newdata, olddata, bytes);
        newdata += bytes;

        bytes = srclen * sizeof_Value;
        memcpy(newdata, srcdata, bytes);
        newdata += bytes;

        bytes = (oldlen-end) * sizeof_Value;
        memcpy(newdata, olddata + end*sizeof_Value, bytes);
    }
    else {
        // no reallocation, so olddata[0:start] needs no copying
        //

        // TODO verify that we can't accidentally overwrite any elements before copying...
        // (when src and dst arrays are the same).
        memmove(
            olddata + (start + srclen) * sizeof_Value,
            olddata + end * sizeof_Value,
            (oldlen - end) * sizeof_Value);
        memmove(olddata + start * sizeof_Value, srcdata, srclen * sizeof_Value);
    }
}
