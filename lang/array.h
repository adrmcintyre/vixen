#ifndef GUARD_ARRAY_H
#define GUARD_ARRAY_H

#include "header.h"

// Represents a dynamically sized array.
typedef struct {
    i16 len;        // current length of the array in elements
    i16 cap;        // total allocated capacity in elements
    i16 min_cap;    // don't shrink cap below this
    u8* dataptr;    // points to the allocated elements
} Array;

Array* array_new_presized(const char* label, i16 len, i16 cap);
void array_release(Array* array);
void array_append(Array* array, Value v);
Value array_pop(Array* array);
void array_reset(Array *array);
Array *array_concat(Array *arr1, Array *arr2);
Value array_get(Array* array, i16 index);
bool array_set(Array* array, i16 index, Value v);
Array* array_get_slice(Array* array, i16 start, i16 end);
void array_set_slice(Array* dst, i16 start, i16 end, Array* src);

#endif
