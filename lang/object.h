#if !defined GUARD_OBJECT_H
#define GUARD_OBJECT_H

#include "header.h"
#include "dict.h"

typedef struct Class {
    Dict* methods;
} Class;

typedef struct Object {
    u16 klass;
    Dict* props;
} Object;

Class* class_new();

Object* object_new(Class* klass, u8 nargs);
Value object_get_prop(Object* object, Value key);
void object_set_prop(Object* object, Value key, Value value);
Func* object_get_method(Object* object, Ident* method_id);

#endif