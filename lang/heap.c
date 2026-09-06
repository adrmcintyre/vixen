#include "header.h"

typedef struct HeapObj HeapObj;

// A linked list of blocks allocated from the heap.
// TODO is this the best way to handle the heap?
// Should we have a header at the start of each heap object type instead?
// Ref counts etc?
// Block length?
// Link by type?
typedef struct HeapObj {
    HeapObj* next;
    u8 data[];
} HeapObj;

u8* heap_top;
u8* heap_end;

void heap_init(void) {
    heap_top = heap_base;
    heap_end = heap_base + 0x1000;
}

u8* heap_alloc(u16 bytes)
{
    u8* new_heap_top = heap_top + sizeof(HeapObj) + bytes;
    if (new_heap_top > heap_end) die("heap full");

    HeapObj* obj = (HeapObj*) heap_top;
    obj->next = (HeapObj*) new_heap_top;
    heap_top = new_heap_top;

    return &obj->data[0];
}

