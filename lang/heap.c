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

bool opt_trace_heap = false;

typedef struct HeapObj HeapObj;

// TODO is this the best way to handle the heap?
// Should we have a header at the start of each heap object type instead?
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

static u16 heap_free_list[128];

// Initialises the heap.
void heap_init(void)
{
    heap_top = heap_base;
    heap_end = heap_base + 0x2000; // TODO pass in as arg; should be most of memory
}

static const u16 block_size_count = 26;

static u16 block_sizes[block_size_count] = {
        8,     12,
       16,     24,
       32,     48,
       64,     96,
      128,    192,
      256,    384,
      512,    768,
     1024,   1536,
     2048,   3072,
     4096,   6144,
     8192,  12288,
    16384,  24576,
    32768,  49152,
};

static i16 bytes_to_block_index(u16 bytes)
{
    // TODO unroll first few block sizes, and/or use clz
    for (u16 i=0; i < block_size_count; i++) {
        u16 block = block_sizes[i];
        if (block >= bytes) {
            return i;
        }
    }
    return block_size_count;
}

// Allocates a `bytes` sized object from the heap.
// The ref count of the returned object is 1.
void* heap_alloc(const char* label, Kind k, u16 bytes)
{
    // TODO - define a sensible range of sizes, and pick the smallest
    // possible one. When out of heap space, consider other free lists.

    for (i16 entry = bytes_to_block_index(bytes); entry < block_size_count; entry++) {
        bytes = block_sizes[entry];

        HeapObj* obj;
        u16 h = heap_free_list[entry];
        if (h == 0) {
            u8* new_heap_top = heap_top + sizeof_HeapObj + bytes;
            if (new_heap_top > heap_end) {
                if (opt_trace_heap) {
                    printf("[alloc] heap full, trying next block size\n");
                }
                continue;
            }
            obj = (HeapObj*) heap_top;
            heap_top = new_heap_top;
        }
        else {
            obj = (HeapObj*) from_p16(h);
            heap_free_list[entry] = obj->rc;
        }

        obj->bytes = bytes;
        obj->rc = 1;
        obj->debug_label = strdup(label);
        obj->debug_kind = k;

        if (opt_trace_heap) {
            printf("[alloc] %04hx alloc %s %hd bytes\n", to_p16(obj), label, bytes);
        }

        debug_objs[debug_count++] = obj;

        return &obj->data[0];
    }
    die("heap full");
}

void value_print(Value);
void heap_debug_obj(HeapObj* h)
{
    if (opt_trace_heap) {
        printf("%04x %-24s ", to_p16(h), h->debug_label);
    }

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

    if (opt_trace_heap) {
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
}

void heap_debug_dump(void)
{
    if (opt_trace_heap) {
        printf("HEAP\n");
        for (u16 i = 0; i < debug_count; i++) {
            HeapObj* h = debug_objs[i];
            if (h->debug_kind == kind_none) continue;
            printf("  [%d] ", i);
            heap_debug_obj(h);
            printf("\n");
        }
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
    if (opt_trace_heap) {
        printf("[heap] %04hx release\n", to_p16(h));
    }

    u16 entry = bytes_to_block_index(h->bytes);
    u16 old_free = heap_free_list[entry];
    heap_free_list[entry] = to_p16(h);
    h->rc = old_free;
}

void* rc_inc_ptr(void *p)
{
    HeapObj* h = (HeapObj*)(((char*) p) - sizeof_HeapObj);
    // only bump if mortal
    if (h->rc != RC_IMMORTAL) {
        h->rc++;
    }
    if (opt_trace_heap) {
        printf("[rcinc] ");
        heap_debug_obj(h);
        printf("\n");
    }
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
            if (opt_trace_heap) {
                printf("[rcdec] ");
                heap_debug_obj(h);
                printf("\n");
            }
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
