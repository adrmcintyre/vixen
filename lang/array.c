#include "array.h"
#include "header.h"

#include <string.h>

// TODO add a min_cap field (or possibly no_shrink flag).

// Returns a newly allocated array with specified length and capacity.
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
    array->min_cap = 16;    // TODO expose this
    array->dataptr = data;
    return array;
}

// Reallocates array's data to ensure it has the appropriate capacity for len elements.
// The array's cap and len are updated. No elements are copied.
// Returns 1 if reallocation occurred, otherwise 0.
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

    // do not shrink below min_cap
    if (newcap < array->cap && newcap < array->min_cap) {
        return 0;
    }

    u8* newdata = 0;
    if (newcap > 0) newdata = heap_alloc(newcap * sizeof_Value);

    array->dataptr = newdata;
    array->cap = newcap;

    return 1;
}

// Appends a single value to array.
void array_append(Array* array, Value v)
{
    i16 len = array->len;
    i16 newlen = len + 1;

    u8* olddata = array->dataptr;
    if (array_resize(array, newlen)) {
        memcpy(array->dataptr, olddata, len * sizeof_Value);
    }

    set_value(array->dataptr + len * sizeof_Value, v);
}

// Removes and returns the last value from array.
// Returns fail if array is empty.
Value array_pop(Array* array)
{
    i16 len = array->len;
    if (len == 0) {
        return (Value){.k=kind_fail};
    }
    u8* olddata = array->dataptr;
    i16 newlen = len - 1;
    Value v = get_value(olddata + newlen * sizeof_Value);

    if (array_resize(array, newlen)) {
        memcpy(array->dataptr, olddata, newlen * sizeof_Value);
    }
    return v;
}

// Removes all elements from array.
void array_reset(Array* array)
{
    array_resize(array, 0);
}

// Returns a newly allocated array from the concatenation of src1 and src2.
Array* array_concat(Array* src1, Array* src2)
{
    u16 len = src1->len + src2->len;
    Array* dst = array_new_presized(len, len);

    memcpy(dst->dataptr, src1->dataptr, src1->len * sizeof_Value);
    memcpy(
        dst->dataptr + src1->len * sizeof_Value,
        src2->dataptr,
        src2->len * sizeof_Value);

    return dst;
}

// Returns the element of array at index. Negative indexes are treated
// as an offset from the end of the array (e.g. -1 is the last element).
// Returns a kind_fail value if the index is invalid.
Value array_get(Array* array, i16 index)
{
    if (index < 0) index += array->len;
    if (index < 0 || index >= array->len) return (Value){.k=kind_fail};
    u8* p = array->dataptr + index * sizeof_Value;
    return get_value(p);
}

// Returns a newly allocated array from the elements of src at indexes in the
// range start <= index < end.
Array* array_get_slice(Array* src, i16 start, i16 end)
{
    i16 len = (i16) src->len;
    slice_adjust(&start, &end, &len);

    Array* dst = array_new_presized(len, 0);

    memcpy(dst->dataptr, src->dataptr + start*sizeof_Value, len * sizeof_Value);

    return dst;
}

// Removes elements of dst at indexes in the range start <= index < end, and
// inserts all elements from src in their place. The length of src need not
// match the size of the destination range.
void array_set_slice(Array* dst, i16 start, i16 end, Array* src)
{
    i16 slicelen = (i16) dst->len; // num elems to replace
    slice_adjust(&start, &end, &slicelen);

    u8* srcdata = src->dataptr;
    u8* olddata = dst->dataptr;

    // beware, if dst == src, after array_resize reading src->len returns newlen,
    // so we read it now.
    i16 oldlen = dst->len;
    i16 srclen = src->len;
    i16 newlen = oldlen - slicelen + srclen;

    if (array_resize(dst, newlen)) {
        u8* newdata = dst->dataptr;

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
        memmove(
            olddata + start * sizeof_Value,
            srcdata,
            srclen * sizeof_Value);
    }
}
