#include "object.h"
#include "header.h"
#include "heap.h"
#include "class.h"
#include "dict.h"

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

    Object* object = (Object*) heap_alloc("object", kind_object, sizeof(Object) + dict_length(klass->slots) * sizeof_Value);
    object->klass = klass;
    u16 iter = dict_iter_init(klass->slots);

    // TODO - a simple memcpy might suffice?
    Value key;
    Value slotval;
    while ((iter = dict_iter_item(klass->slots, iter, &key, &slotval))) {
        Value value = dict_get_item(klass->props, key);
        
        // rc_inc(value) not needed, as dict_get_item bumped it already
        set_value_indexed(object->data, slotval.i, value);
    }

    return object;
}

void object_release(Object* object)
{
    u16 nslots = object->klass->slots->used;
    rc_dec_many(object->data, nslots);
    rc_dec((Value){.k=kind_class, .u=to_p16(object->klass)});
}

// Returns the Value of object's property identified by name.
// Returns fail if the property does not exist.
extern Value object_get_prop_by_name(Object* object, Value name)
{
    Class* klass = object->klass;
    // never a heap object
    Value slotval = dict_get_item(klass->slots, name);
    if (slotval.k != kind_int) {
        return (Value){.k=kind_fail};
    }
    return rc_inc(get_value_indexed(object->data, slotval.i));
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

    u8* p = object->data + slotval.i * sizeof_Value;

    rc_dec(get_value(p));
    rc_inc(value);
    set_value(p, value);

    return true;
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

    rc_inc_ptr(object);
    // funcval already bumped by dict_get_item

    BoundObjectMethod* bom = (BoundObjectMethod*) heap_alloc("bom", kind_bom, sizeof(BoundObjectMethod));
    bom->object = object;
    bom->func = (Func*) from_p16(funcval.u);

    return (Value){.k=kind_bom, .u=to_p16(bom)};
}

extern void bom_release(BoundObjectMethod* bom)
{
    rc_dec((Value){.k=kind_object, .u=to_p16(bom->object)});
    rc_dec((Value){.k=kind_func, .u=to_p16(bom->func)});
}
