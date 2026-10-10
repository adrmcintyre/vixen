#ifndef GUARD_FUNC_H
#define GUARD_FUNC_H

#include "header.h"
#include "dict.h"

// Describes a function or method.
typedef struct {
    Dict* slots;    // string -> int: maps each arg or local to its slot number
    u8 nslots;      // number of slots (args + locals)
    u8 nargs;       // number of args
    Class* klass;   // 0 for funcs, otherwise points to the associated class
    u16 vm_addr;    // address of compiled vm code
} Func;

Func* func_new(const char* label);
void func_release(Func* func);

#endif
