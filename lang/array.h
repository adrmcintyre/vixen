#include "header.h"

Array* array_new_presized(i16 len, i16 cap);
void array_push(Array* array, Value v);
Array* array_append(Array* arr1, Array* arr2);
Array* array_get_slice(Array* array, i16 start, i16 end);
void array_set_slice(Array* dst, i16 start, i16 end, Array* src);
