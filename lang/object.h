#ifndef GUARD_OBJECT_H
#define GUARD_OBJECT_H

#include "header.h"
#include "dict.h"

typedef struct Class {
    Dict* methods; // String -> Func  - maps method names to func descriptors
    Dict* slots;   // String -> Int   - maps prop names to object slot offsets
    Dict* props;   // String -> Value - maps prop names to runtime values
} Class;

typedef struct Object {
    Class* klass;
    u8 data[];
} Object;

typedef struct {
    Object* object;
    Func* func;
} BoundObjectMethod;

Class* class_new();
Value class_get_prop_by_name(Class* klass, Value name);
Value class_get_method_by_name(Class* klass, Value name);

Object* object_new_uninited(Class* klass);
Value object_get_prop_by_name(Object* object, Value name);
bool object_set_prop_by_name(Object* object, Value name, Value value);
Value object_bind_method_by_name(Object* object, Value name);
Func* object_get_method(Object* object, Value name);

#endif
