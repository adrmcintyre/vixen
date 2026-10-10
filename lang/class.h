#ifndef GUARD_CLASS_H
#define GUARD_CLASS_H

#include "header.h"
#include "dict.h"

typedef struct Class {
    Dict* methods; // String -> Func  - maps method names to func descriptors
    Dict* slots;   // String -> Int   - maps prop names to object slot offsets
    Dict* props;   // String -> Value - maps prop names to runtime values
} Class;

Class* class_new(const char* label);
void class_release(Class* class);
Value class_get_prop_by_name(Class* klass, Value name);
Value class_get_method_by_name(Class* klass, Value name);

#endif
