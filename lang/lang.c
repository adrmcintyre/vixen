#include "header.h"
#include "parse.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

///////////////////////////////////////////////////////////////////////////////
// Utilities
//

// Print msg generated at run time, and abort the program.
__attribute__((noreturn)) void die(const char* msg)
{
    // TODO - all calls to die should be converted
    // to fail the parse instead.
    fprintf(stderr, "%s\n", msg);
    exit(1);
}

// Print msg generated at compile time, and abort the program.
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

// Initialise the memory map.
void mem_init()
{
    mem_base = (u8*)malloc(mem_size);
    heap_base = mem_base + mem_heap_offset;
    code_base = mem_base + mem_code_offset;
    vm_stack_base = mem_base + mem_vm_stack_offset;
}

// Return a 15-bit hash (top-bit set) of len bytes starting at p.
u16 hash_mem(const u8* p, u16 len)
{
    u16 h = 0;
    while(len--) h = h * 101 + *p++;
    return h | 0x8000;
}

// Default source file to load.
static const char default_program[] = "test.lang";

// Print program usage.
void usage(const char* prog)
{
    printf(
        "Usage: %s [OPTIONS] [PROGRAM]\n"
        "Compile and run PROGRAM, or '%s' if not specified.\n"
        "\n"
        "Options\n"
        "  -h, --help    display this mesage and exit\n"
        "  --trace-emit  enable/disable code generation logging\n"
        "  --trace-vm    enable/disable vm execution logging\n",
        prog,
        default_program
    );
}

// Main entry point.
int main(int argc, char *argv[])
{
    // parse options
    int argi = 1;
    for (; argi < argc; argi++) {
        char *arg = argv[argi];
        if (0 == strcmp(arg, "-h") || 0 == strcmp(arg, "--help")) {
            usage(argv[0]);
            exit(0);
        }
        else if (0 == strcmp(arg, "--trace-emit")) {
            opt_trace_emit = true;
        }
        else if (0 == strcmp(arg, "--trace-vm")) {
            opt_trace_vm = true;
        }
        else if (0 == strcmp(arg, "--")) {
            argi++;
            break;
        }
        else if (*arg == '-') {
            fprintf(stderr, "Unrecognised option: %s\n", arg);
            exit(1);
        }
        else break;
    }

    // check options
    if (argi < argc - 1) {
        die("too many arguments");
    }

    mem_init();

    // load program
    const char *filename = default_program;
    if (argi == argc - 1) {
        filename = argv[argi];
    }

    FILE *fp = fopen(filename, "r");
    if (fp == 0) {
        perror(filename);
        exit(1);
    }

    size_t prog_max = 65536;
    char *prog = malloc(prog_max + 1);
    size_t n = fread(prog, 1, prog_max, fp);
    if (ferror(fp)) {
        perror(filename);
        exit(1);
    }
    fclose(fp);
    // TODO could add an implicit "stop" ?
    prog[n] = '\0';

    // parse and compile program
    const u8 *p = (u8 *)prog;
    prog_base = p;
    input_ptr = p;

    parse_start();
    while (*input_ptr) {
        parse_line();
    }
    parse_finish();

    // execute compiled bytecode
    vm_run(code_base);
}
