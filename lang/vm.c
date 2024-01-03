#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "header.h"

u16 vm_ai;
u16 vm_bi;
float vm_af;
float vm_bf;

const u8 *vm_pc;
u16 vm_sp;
u8 vm_stack[1536];

u8 fetch_byte()
{
    return *vm_pc++;
}

u16 fetch_word()
{
    u16 w;
    w = (*vm_pc++)<<8;
    w |= *vm_pc++; 
    return w;
}

void push_int(u16 i)
{
    trace("push_int");
    vm_stack[vm_sp++] = i>>8;
    vm_stack[vm_sp++] = i&0xff;
    vm_stack[vm_sp++] = kind_int;
}

void push_f16(u16 f)
{
    trace("push_f16");
    vm_stack[vm_sp++] = f>>8;
    vm_stack[vm_sp++] = f&0xff;
    vm_stack[vm_sp++] = kind_float;
}

void push_float(float f)
{
    trace("push_float");
    push_f16(f16_from_float(f));
}

void pop_int()
{
    trace("pop_int");
    vm_sp -= 3;
    u8 hi = vm_stack[vm_sp+0];
    u8 lo = vm_stack[vm_sp+1];
    u8 k  = vm_stack[vm_sp+2];
    if (k != kind_int) die("expected integer");

    vm_ai = (hi<<8) | lo;
}

void pop_float()
{
    trace("pop_float");
    vm_sp -= 3;
    u8 hi = vm_stack[vm_sp+0];
    u8 lo = vm_stack[vm_sp+1];
    u8 k  = vm_stack[vm_sp+2];
    if (k != kind_float) die("expected float");

    u16 u = (hi<<8) | lo;

    vm_ai = u;
    vm_af = f16_to_float(u);
}

void pop_ints()
{
    trace("pop_ints");
    pop_int(); vm_bi = vm_ai;
    pop_int();
}

int pop_num()
{
    trace("pop_num");
    vm_sp -= 3;
    u8 hi = vm_stack[vm_sp+0];
    u8 lo = vm_stack[vm_sp+1];
    u8 k  = vm_stack[vm_sp+2];
    u16 u = (hi<<8) | lo;
    if (k == kind_int) {
    }
    else if (k == kind_float) {
        vm_af = f16_to_float(u);
    }
    else {
        die("expected float or integer");
    }
    vm_ai = u;
    return k;
}

int pop_nums()
{
    trace("pop_nums");
    int k = pop_num();
    if (k == kind_int) {
        vm_bi = vm_ai;
        pop_int();
    } else {
        vm_bi = vm_ai;
        vm_bf = vm_af;
        pop_float();
    }
    return k;
}

void push_val(u8 kind, u16 value)
{
    vm_stack[vm_sp++] = value >> 8;
    vm_stack[vm_sp++] = value & 0xff;
    vm_stack[vm_sp++] = kind;
}

u8 pop_str()
{
    trace("pop_str");
    vm_sp -= 3;
    u8 hi = vm_stack[vm_sp+0];
    u8 lo = vm_stack[vm_sp+1];
    u8 k  = vm_stack[vm_sp+2];
    switch(k) {
        case kind_str_empty:
        case kind_str_char:
        case kind_str_prog:
            break;
        case kind_str_heap:
            die("kind_str_heap: not implemented");
        default:
            die("expected string");
    }

    vm_ai = (hi<<8) | lo;
    fprintf(stderr, "popped str: vm_ai=0x%04x\n", vm_ai);
    return k;
}

u8 str_unescape_char(const u8 *p)
{
    u8 ch = *p;
    if (ch == '\\') {
        ch = *++p;
        if (ch == '"') return '"';
        if (ch == 'n') return '\n';
        if (ch == 't') return '\t';
        if (ch == '\\') return '\\';
    }
    return ch;
}

void fn_asc()
{
    switch(pop_str()) {
        case kind_str_empty: push_int(0); break;
        case kind_str_char:  push_int(vm_ai); break;
        case kind_str_prog:
            push_int(str_unescape_char(prog_base + vm_ai));
            break;
    }
}

void fn_chr()
{
    pop_int();
    push_val(kind_str_char, vm_ai & 0xff);
}

void fn_len()
{
    switch(pop_str()) {
        case kind_str_empty: push_int(0); break;
        case kind_str_char:  push_int(1); break;
        case kind_str_prog:
            {
                u16 len = 0;
                const u8 *p = prog_base + vm_ai;
                char ch = *p++;
                while(ch != '"') {
                    len++;
                    if (ch == '\\') p++;
                    ch = *p++;
                }
                push_int(len);
                break;
            }
    }
}

void cmd_print()
{
    u8 n = fetch_byte();
    vm_sp -= 3*n;
    const u8 *ptr = &vm_stack[vm_sp];
    while(n--) {
        u8 hi = *ptr++;
        u8 lo = *ptr++;
        u8 k  = *ptr++;
        u16 val = (hi<<8) | lo;

        switch(k) {
            case kind_int:
                printf("int:%d\n", val);
                break;
            case kind_float:
                printf("float:%f\n", f16_to_float(val));
                break;
            case kind_str_empty:
                printf("str:\"\"\n");
                break;
            case kind_str_char:
                printf("str:\"%c\"\n", val & 0xff);
                break;
            case kind_str_prog:
                {
                    printf("str:\"");
                    const u8 *p = prog_base + val;
                    u8 ch = *p;
                    while(ch != '"') {
                        if (ch == '\\') {
                            ch = str_unescape_char(p);
                            p++;
                        }
                        putchar(ch);
                        ch = *++p;
                    }
                    printf("\"\n");
                    break;
                }
        }
    }
}

u16 vm_run(const u8 *vm_pc_base)
{
    vm_pc = vm_pc_base;
    vm_sp = 0;

    while(1) {
        u8 op = fetch_byte();
        fprintf(stderr, "dispatching opcode %02x\n", op);

        switch(op) {
            // operators
            case op_neg:   pop_int(); push_int(-vm_ai); break;
            case op_bnot:  pop_int(); push_int(~vm_ai); break;
            case op_lnot:  pop_int(); push_int(!vm_ai); break;

            case op_mul:   if (pop_nums() == kind_int) push_int(vm_ai * vm_bi); else push_float(vm_af * vm_bf); break;
            case op_div:   if (pop_nums() == kind_int) push_int(vm_ai / vm_bi); else push_float(vm_af / vm_bf); break;
            case op_add:   if (pop_nums() == kind_int) push_int(vm_ai + vm_bi); else push_float(vm_af + vm_bf); break;
            case op_sub:   if (pop_nums() == kind_int) push_int(vm_ai - vm_bi); else push_float(vm_af - vm_bf); break;

            case op_mod:   pop_ints(); push_int(vm_ai % vm_bi); break;

            case op_asr:   die("asr: unimplemented"); break;
            case op_lsr:   pop_ints(); push_int(vm_ai >> vm_bi); break;
            case op_lsl:   pop_ints(); push_int(vm_ai << vm_bi); break;

            case op_le:    pop_ints(); push_int(vm_ai <= vm_bi); break;
            case op_lt:    pop_ints(); push_int(vm_ai < vm_bi); break;
            case op_gt:    pop_ints(); push_int(vm_ai > vm_bi); break;
            case op_ge:    pop_ints(); push_int(vm_ai >= vm_bi); break;

            case op_eq:    pop_ints(); push_int(vm_ai == vm_bi); break;
            case op_ne:    pop_ints(); push_int(vm_ai != vm_bi); break;
            case op_band:  pop_ints(); push_int(vm_ai & vm_bi); break;
            case op_bor:   pop_ints(); push_int(vm_ai | vm_bi); break;
            case op_beor:  pop_ints(); push_int(vm_ai ^ vm_bi); break;

            case op_land:  pop_ints(); push_int(vm_ai && vm_bi); break;
            case op_lor:   pop_ints(); push_int(vm_ai || vm_bi); break;

            // constants
            case op_false: push_int(0); break;
            case op_true:  push_int(1); break;

            // built-in functions
            case op_abs:
                if (pop_num() == kind_int) {
                    push_int((vm_ai & 0x8000) ? -vm_ai : vm_ai);
                } else {
                    push_float((vm_af < 0) ? -vm_af : (vm_af > 0) ? vm_af : 0);
                }
                break;

            case op_sgn:
                if (pop_num() == kind_int) {
                    push_int((vm_ai & 0x8000) ? 0xffff : (vm_ai==0) ? 0 : 1); 
                } else {
                    push_int((vm_af < 0) ? -1 : (vm_af > 0) ? 1 : 0);
                }
                break;

            case op_rnd:    push_int(random() & 0xffff); break;
            case op_sqr:    pop_float(); push_float(sqrt(vm_af)); break;
            case op_int:    die("int: unimplemented"); break;
            case op_asc:    fn_asc(); break;
            case op_chr:    fn_chr(); break;
            case op_left:   die("left: unimplemented"); break;
            case op_len:    fn_len(); break;
            case op_right:  die("right: unimplemented"); break;
            case op_str:    die("str: unimplemented"); break;
            case op_substr: die("substr: unimplemented"); break;

            // build-in procedures
            case op_print: cmd_print(); break;
            case op_input: die("input: unimplemented"); break;

            // control
            case op_stop:   return 1;
            case op_return: die("return: unimplemented"); break;

            // internal ops
            case op_index:      die("index: unimplemented"); break;
            case op_call:       die("call: unimplemented"); break;
            case op_ident_get:  die("ident_get: unimplemented"); break;
            case op_ident_set:  die("ident_set: unimplemented"); break;
            case op_lit_int:    push_int(fetch_word()); break;
            case op_lit_float:  push_f16(fetch_word()); break;
            case op_lit_str_empty: push_val(kind_str_empty, 0); break;
            case op_lit_str_char: push_val(kind_str_char, fetch_byte()); break;
            case op_lit_str_prog: push_val(kind_str_prog, fetch_word()); break;
            case op_jump:       vm_pc = vm_pc_base + fetch_word(); break;
            case op_jfalse:
                {
                    u16 tmp = fetch_word();
                    pop_int();
                    if (vm_ai == 0) vm_pc = vm_pc_base + tmp;
                    break;
                }

            // Structural (not executed)
            case op_func:
            case op_break:
            case op_else:
            case op_end:
            case op_endif:
            case op_if:
            case op_repeat:
            case op_until:
            case op_wend:
            case op_while:
            default:
                die("unknown opcode");
                break;
        }
    }
}

