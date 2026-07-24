#include "header.h"
#include "dict.h"

typedef struct {
    Dict methods;
} Class;

typedef struct {
    u16 klass;
    Dict* props;
} Object;

Object* object_new(Class* klass, u8 nargs);
Value object_get_prop(Object* object, Value key);
void object_set_prop(Object* object, Value key, Value value);