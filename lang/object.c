#include "header.h"
#include "object.h"
#include "dict.h"

extern Class* class_new()
{
    Class* klass = (Class*) heap_alloc(sizeof(Class));
    klass->methods = dict_new();
    return klass;
}

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

extern Func* object_get_method(Object* object, Ident* name_id)
{
    Class* klass = (Class*) from_p16(object->klass);
    Value nameval;
    nameval.k = kind_ident;
    nameval.u = to_p16(name_id);
    Value implval = dict_get_item(klass->methods, nameval);
    if (implval.k == kind_fail) {
        return 0;
    }
    Ident* impl_id = (Ident*) from_p16(implval.u);
    return (Func*) from_p16(impl_id->val.u);
}