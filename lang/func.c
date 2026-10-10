#include "func.h"
#include "header.h"
#include "dict.h"
#include "heap.h"

//DEBUG
#include <stdio.h>

// Returns a newly allocated function descriptor.
Func* func_new(const char* label)
{
    char *label_slots;
    asprintf(&label_slots, "%s.slots", label);

    // TODO could include name field (String)
    Func* func = (Func*) heap_alloc(label, kind_func, sizeof(Func));
    func->klass = 0;
    func->nargs = 0;
    func->nslots = 0;
    func->slots = dict_new(label_slots);
    func->vm_addr = 0;
    return func;
}

void func_release(Func* func)
{
    heap_release(func->slots);
    rc_dec((Value){.k=kind_class, .u=to_p16(func->klass)});
    // TODO - what about func->vm_addr bytecode?
}
