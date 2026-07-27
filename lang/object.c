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

extern Value object_get_prop(Object* object, Value name)
{
    return dict_get_item(object->props, name);
}

extern void object_set_prop(Object* object, Value name, Value value)
{
    dict_set_item(object->props, name, value);
}

extern Func* object_get_method(Object* object, Value name)
{
    Class* klass = (Class*) from_p16(object->klass);
    Value impl_val = dict_get_item(klass->methods, name);
    if (impl_val.k == kind_fail) {
        return 0;
    }
    // TODO FIXME
    Ident* impl_ident = (Ident*) from_p16(impl_val.u);
    return (Func*) from_p16(impl_ident->val.u);
}