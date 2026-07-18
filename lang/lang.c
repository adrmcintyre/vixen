#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "header.h"

///////////////////////////////////////////////////////////////////////////////
// Utilities
//
void die(const char* msg)
{
    // TODO - all calls to die should be converted
    // to fail the parse instead.
    fprintf(stderr, "%s\n", msg);
    exit(1);
}

void parser_die(const char* msg)
{
    fprintf(stderr, "PROGRAM ERROR: %s\n", msg);
    exit(1);
}

// Gross memory map
u8* mem_base;
u8* heap_base;
u8* code_base;
u8* vm_stack_base;

void mem_init() {
    mem_base = (u8*)malloc(mem_size);
    heap_base = mem_base + mem_heap_offset;
    code_base = mem_base + mem_code_offset;
    vm_stack_base = mem_base + mem_vm_stack_offset;
}

// Return a 15-bit hash.
u16 hash_mem(const u8* p, u16 len)
{
    u16 h = 0;
    while(len--) h = h * 101 + *p++;
    return h & 0x7fff | 0x8000;
}

///////////////////////////////////////////////////////////////////////////////
// Lexing
//
const u8* prog_base;

int main()
{
    mem_init();

    const char* prog =
        "proc blah(arr)\n"
        "   arr[2] = 99\n"
        "end\n"
        "foo = [4,5,6,7,8,9,10,11]\n"
        "blah foo\n"
        "print foo\n"
        "z = \"he\" + \"l\" + \"l\" + \"o\"\n"
        "z = z + \" world\"\n"
        "print z\n"
        "func fu()\n"
        "end\n"
        "print str(Inf)\n"
        "d={\"foo\":123, \"bar\":\"quux\"}\n"
        "print d[\"bar\"]\n"
        "print d[\"foo\"]\n"
        "print d[\"missing\"]\n"
        "stop\n"
    ;

    const u8* p = (u8*) prog;
    prog_base = p;
    input_ptr = p;

    parse_start();
    while(*input_ptr) parse_line();
    parse_finish();

    vm_run(code_base);
}


