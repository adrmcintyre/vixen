#include "header.h"
#include "object.h"

extern Object* object_new(Class* klass, u8 nargs)
{
    Object* object = (Object*) heap_alloc(sizeof(Object));
    object->klass = to_p16(klass);
    object->props = dict_new_presized(nargs);
    return object;
}

extern Value object_get_prop(Object* object, Value key)
{
    return dict_get_item(object->props, key);
}

extern void object_set_prop(Object* object, Value key, Value value)
{
    dict_set_item(object->props, key, value);
}
