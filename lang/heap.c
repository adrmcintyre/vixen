#include "heap.h"
#include "header.h"
#include "array.h"
#include "class.h"
#include "dict.h"
#include "func.h"
#include "object.h"

// DEBUG
#include <stdio.h>
#include <string.h>

typedef struct HeapObj HeapObj;

// A linked list of blocks allocated from the heap.
// TODO is this the best way to handle the heap?
// Should we have a header at the start of each heap object type instead?
// Block length?
// Link by type?
typedef struct HeapObj {
    u16 bytes;
    u16 rc;     // reference count, or RC_IMMORTAL if immortal
    Kind debug_kind;
    const char* debug_label;
    u8 data[];
} HeapObj;

static const u16 RC_IMMORTAL = (u16) 0xffff;
static const size_t sizeof_HeapObj = offsetof(HeapObj, data);

u8* heap_top;
u8* heap_end;

static void rc_dec_descendants(Value v);
static void heapobj_release(HeapObj* h);

static HeapObj* debug_objs[65536];
static u16 debug_count = 0;

// Initialises the heap.
void heap_init(void)
{
    heap_top = heap_base;
    heap_end = heap_base + 0x1000;
}

// Allocates a `bytes` sized object from the heap.
// The ref count of the returned object is 1.
void* heap_alloc(const char* label, Kind k, u16 bytes)
{
    u8* new_heap_top = heap_top + sizeof_HeapObj + bytes; // DEBUG
    if (new_heap_top > heap_end) die("heap full");

    HeapObj* obj = (HeapObj*) heap_top;
    obj->bytes = bytes;
    obj->rc = 1;
    obj->debug_label = strdup(label);
    obj->debug_kind = k;
    heap_top = new_heap_top;

    printf("[alloc] %04hx alloc %s %hd bytes\n", to_p16(obj), label, bytes);

    debug_objs[debug_count++] = obj;

    return &obj->data[0];
}

void value_print(Value);
void heap_debug_obj(HeapObj* h)
{
    printf("%04x %-24s ", to_p16(h), h->debug_label);
    const char* ks;
    switch (h->debug_kind) {
        case kind_array: ks = "array"; break;
        case kind_dict: ks = "dict"; break;
        case kind_bom: ks = "bom"; break;
        case kind_class: ks = "class"; break;
        case kind_object: ks = "object"; break;
        case kind_func: ks = "func"; break;
        case kind_string: ks = "string"; break;
        case kind_token: ks = "token"; break;
        case kind_none: ks = "bytes"; break;
        default: ks = "other"; break;
    }
    if (h->rc == RC_IMMORTAL) {
        printf("IMMORTAL value=%s:", ks);
    } else if (h->rc == 0) {
        printf("DEAD value=%s:", ks);
    } else {
        printf("rc=%d value=%s:", h->rc, ks);
    }
    if (h->debug_kind != kind_none) {
        value_print((Value){.k=h->debug_kind, .u=to_p16(&h->data[0])});
    } else {
        printf("...");
    }
    printf(" len=%d", h->bytes);
}

void heap_debug_dump(void)
{
    printf("HEAP\n");
    for (u16 i = 0; i < debug_count; i++) {
        HeapObj* h = debug_objs[i];
        if (h->debug_kind == kind_none) continue;
        printf("  [%d] ", i);
        heap_debug_obj(h);
        printf("\n");
    }
}

// Returns an unreferenced object to the heap.
//
// It is the caller's responsibility to decrement reference counts
// or release any objects owned by this object.
void heap_release(void* p)
{
    HeapObj* h = (HeapObj*)(((char*) p) - sizeof_HeapObj);
    heapobj_release(h);
}

// Internal function to return a raw HeapObj to the heap.
static void heapobj_release(HeapObj* h)
{
    printf("[heap] %04hx release\n", to_p16(h)+(u16)sizeof_HeapObj);
    // TODO - stick the returned object on a free list.
    (void) h;
}

void* rc_inc_ptr(void *p)
{
    HeapObj* h = (HeapObj*)(((char*) p) - sizeof_HeapObj);
    // only bump if mortal
    if (h->rc != RC_IMMORTAL) {
        h->rc++;
    }
    printf("[rcinc] "); heap_debug_obj(h); printf("\n");
    return p;
}

// If `v` refers to a heap object (and it's not immortal),
// increments its reference count.
Value rc_inc(Value v)
{
    switch (v.k) {
        case kind_array:
        case kind_dict:
        case kind_func:
        case kind_bom:
        case kind_string:
        case kind_object:
        case kind_class:
            rc_inc_ptr(from_p16(v.u));
            break;
        default:
            break;
    }
    return v;
}

// Marks the object at p so that it will never be released.
void heap_immortalise(void* p)
{
    HeapObj* h = (HeapObj*)(((char*) p) - sizeof_HeapObj);
    // zero indicates immortality
    h->rc = RC_IMMORTAL;
}

// If `v` refers to a heap object (and it's not immortal), decrements
// its reference count, and releases it if no references remain.
void rc_dec(Value v)
{
    switch (v.k) {
        case kind_string:
        case kind_array:
        case kind_dict:
        case kind_func:
        case kind_class:
        case kind_object:
        case kind_bom: {
            void *p = from_p16(v.u);
            HeapObj* h = (HeapObj*)(((char*) p) - sizeof_HeapObj);
            bool alive = h->rc == RC_IMMORTAL || --h->rc;
            printf("[rcdec] "); heap_debug_obj(h); printf("\n");
            if (!alive) {
                // NOTE - cpython cleverly adds deallocated object
                // to a queue (linked list) when stack space gets low.
                heapobj_release(h);
                rc_dec_descendants(v);
            }
            break;
        }
        default:
            break;
    }
}

// Internal function to decrement reference counts of any objects
// owned by `v`.
static void rc_dec_descendants(Value v)
{
    switch (v.k) {
        case kind_string:
            break;
        case kind_array:
            array_release((Array*) from_p16(v.u));
            break;
        case kind_dict:
            dict_release((Dict*) from_p16(v.u));
            break;
        case kind_func: 
            func_release((Func*) from_p16(v.u));
            break;
        case kind_class:
            class_release((Class*) from_p16(v.u));
            break;
        case kind_object:
            object_release((Object*) from_p16(v.u));
            break;
        case kind_bom:
            bom_release((BoundObjectMethod*) from_p16(v.u));
            break;
        default:
            break;
    }
}

void rc_inc_many(u8* p, i16 n)
{
    while (n--) {
        rc_inc(get_value(p));
        p += sizeof_Value;
    }
}

void rc_dec_many(u8* p, i16 n)
{
    while (n--) {
        rc_dec(get_value(p));
        p += sizeof_Value;
    }
}
