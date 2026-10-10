#ifndef GUARD_HEAP_H
#define GUARD_HEAP_H

#include "header.h"

void heap_init(void);
void* heap_alloc(const char* label, Kind k, u16 n);
void heap_immortalise(void* p);
void heap_release(void* p);
void* rc_inc_ptr(void* p);
Value rc_inc(Value v);
void rc_dec(Value v);
void rc_inc_many(u8* p, i16 n);
void rc_dec_many(u8* p, i16 n);

#endif

