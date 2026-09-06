#include "object.h"
#include "header.h"
#include "dict.h"

// Returns a newly allocated class descriptor.
extern Class* class_new(void)
{
    Class* klass = (Class*) heap_alloc(sizeof(Class));
    klass->methods = dict_new();
    klass->slots = dict_new();
    klass->props = dict_new();
    return klass;
}

// Returns the Value of klass's property identified by name.
// Returns fail if the property does not exist.
extern Value class_get_prop_by_name(Class* klass, Value name)
{
    return dict_get_item(klass->props, name);
}

// Returns the func Value of klass's method identified by name.
// Returns fail if the method does not exist.
extern Value class_get_method_by_name(Class* klass, Value name)
{
    return dict_get_item(klass->methods, name);
}

// Returns a newly allocated object with specified class and property count.
// Property values are not initialised.
extern Object* object_new_uninited(Class* klass)
{
    // TODO we should separate compile time and runtime class representation,
    // with the runtime rep something like:
    // struct {
    //      Dict* methods;  // String -> Func - method map
    //      Dict* slots;    // String -> Int - slot map
    //      u8 data[];      // prop values
    // } Class;
    // Then object slot initialisation simply becomes a memcpy of data[].

    Object* object = (Object*) heap_alloc(sizeof(Object) + dict_length(klass->slots) * sizeof_Value);
    object->klass = klass;
    u16 iter = dict_iter_init(klass->slots);
    Value key;
    Value slotval;
    while ((iter = dict_iter_item(klass->slots, iter, &key, &slotval))) {
        Value value = dict_get_item(klass->props, key);
        set_value(object->data + slotval.u * sizeof_Value, value);
    }

    return object;
}

// Returns the Value of object's property identified by name.
// Returns fail if the property does not exist.
extern Value object_get_prop_by_name(Object* object, Value name)
{
    Class* klass = object->klass;
    Value slotval = dict_get_item(klass->slots, name);
    if (slotval.k != kind_int) {
        return (Value){.k=kind_fail};
    }
    return get_value(object->data + slotval.u * sizeof_Value);
}

// Sets object's property identified by name to value.
//
// Returns 1 if the property exists.
// Returns 0 if the property does not exist (and could not be set).
extern bool object_set_prop_by_name(Object* object, Value name, Value value)
{
    Class* klass = object->klass;
    Value slotval = dict_get_item(klass->slots, name);
    if (slotval.k != kind_int) {
        return false;
    }
    set_value(object->data + slotval.u * sizeof_Value, value);
    return true;
}

// Returns a newly allocated bom Value binding object and the func Value of
// object's method identified by name.
//
// Returns fail if the method does not exist.
extern Value object_bind_method_by_name(Object* object, Value name)
{
    Class* klass = object->klass;
    Value funcval = dict_get_item(klass->methods, name);
    if (funcval.k == kind_fail) {
        return funcval;
    }
    BoundObjectMethod* bom = (BoundObjectMethod*) heap_alloc(sizeof(BoundObjectMethod));
    bom->object = object;
    bom->func = (Func*) from_p16(funcval.u);
    return (Value){.k=kind_bom, .u=to_p16(bom)};
}

// Returns the func descriptor of the named method on object.
// Returns 0 if the method does not exist.
extern Func* object_get_method(Object* object, Value name)
{
    Class* klass = object->klass;
    Value funcval = dict_get_item(klass->methods, name);
    if (funcval.k == kind_fail) {
        return 0;
    }
    return (Func*) from_p16(funcval.u);
}
