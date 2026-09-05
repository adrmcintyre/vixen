#ifndef GUARD_ARRAY_H
#define GUARD_ARRAY_H

#include "header.h"

Array* array_new_presized(i16 len, i16 cap);
void array_append(Array* array, Value v);
Value array_pop(Array* array);
void array_reset(Array *array);
Array *array_concat(Array *arr1, Array *arr2);
Value array_get(Array* array, i16 index);
Array* array_get_slice(Array* array, i16 start, i16 end);
void array_set_slice(Array* dst, i16 start, i16 end, Array* src);

#endif