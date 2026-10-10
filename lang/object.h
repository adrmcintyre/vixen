#ifndef GUARD_OBJECT_H
#define GUARD_OBJECT_H

#include "header.h"
#include "class.h"
#include "dict.h"
#include "func.h"

typedef struct Object {
    Class* klass;
    u8 data[];
} Object;

typedef struct {
    Object* object;
    Func* func;
} BoundObjectMethod;

Object* object_new_uninited(Class* klass);
void object_release(Object* object);
Value object_get_prop_by_name(Object* object, Value name);
bool object_set_prop_by_name(Object* object, Value name, Value value);
Func* object_get_method(Object* object, Value name);

Value object_bind_method_by_name(Object* object, Value name);
extern void bom_release(BoundObjectMethod* bom);

#endif
