#include "class.h"
#include "header.h"
#include "dict.h"
#include "heap.h"

// DEBUG
#include <stdio.h>

// Returns a newly allocated class descriptor.
extern Class* class_new(const char* label)
{
    char* methods_label;
    char* slots_label;
    char* props_label;
    asprintf(&methods_label, "%s.methods", label);
    asprintf(&slots_label, "%s.slots", label);
    asprintf(&props_label, "%s.props", label);

    
    Class* klass = (Class*) heap_alloc(label, kind_class, sizeof(Class));
    klass->methods = dict_new(methods_label);
    klass->slots = dict_new(slots_label);
    klass->props = dict_new(props_label);
    return klass;
}

void class_release(Class* klass)
{
    heap_release(klass->methods);
    heap_release(klass->slots);
    heap_release(klass->props);
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
