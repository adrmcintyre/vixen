#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "header.h"

// TODO? - a top-of-stack register to reduce number of push/pop sequences
u16 vm_ai;
u16 vm_bi;
float vm_af;
float vm_bf;

u16 vm_fp;
u16 vm_sp;
u16 vm_pc;
u8 vm_stack[1536];

u8 fetch_byte()
{
    u8 b = code_base[vm_pc++];
    fprintf(stderr, "     fetch_byte => %02x\n", b);
    return b;
}

u16 fetch_word()
{
    u16 w;
    w = code_base[vm_pc++]<<8;
    w |= code_base[vm_pc++]; 
    fprintf(stderr, "     fetch_word => %04x\n", w);
    return w;
}

void push_byte(u8 b)
{
    fprintf(stderr, "     push_byte <= %02x\n", b);
    vm_stack[vm_sp+0] = b;
    vm_sp += 1;
}

void push_word(u16 w)
{
    fprintf(stderr, "     push_word <= %04x\n", w);
    vm_stack[vm_sp+0] = w>>8;
    vm_stack[vm_sp+1] = w&0xff;
    vm_sp += 2;
}

void push_bool(u16 b)
{
    fprintf(stderr, "     push_bool <= %s\n", b ? "true" : "false");
    vm_stack[vm_sp+0] = kind_bool;
    vm_stack[vm_sp+1] = 0;
    vm_stack[vm_sp+2] = (b==0) ? 0 : 1;
    vm_sp += 3;
}

void push_int(u16 i)
{
    fprintf(stderr, "     push_int <= %04x\n", i);
    vm_stack[vm_sp+0] = kind_int;
    vm_stack[vm_sp+1] = i>>8;
    vm_stack[vm_sp+2] = i&0xff;
    vm_sp += 3;
}

void push_f16(u16 f)
{
    fprintf(stderr, "     push_f16\n");
    vm_stack[vm_sp+0] = kind_float;
    vm_stack[vm_sp+1] = f>>8;
    vm_stack[vm_sp+2] = f&0xff;
    vm_sp += 3;
}

void push_float(float f)
{
    fprintf(stderr, "     push_float\n");
    u16 u = f16_from_float(f);
    vm_stack[vm_sp+0] = kind_float;
    vm_stack[vm_sp+1] = u>>8;
    vm_stack[vm_sp+2] = u&0xff;
    vm_sp += 3;
}

u8 pop_byte()
{
    vm_sp -= 1;
    u8 b = vm_stack[vm_sp+0];
    fprintf(stderr, "     pop_byte => %02x\n", b);
    return b;
}

u16 pop_word()
{
    vm_sp -= 2;
    u8 hi = vm_stack[vm_sp+0];
    u8 lo = vm_stack[vm_sp+1];
    u16 w = hi<<8 | lo;
    fprintf(stderr, "     pop_word => %04x\n", w);
    return w;
}

void pop_bool()
{
    vm_sp -= 3;
    u8 k  = vm_stack[vm_sp+0];
    u8 hi = vm_stack[vm_sp+1];
    u8 lo = vm_stack[vm_sp+2];
    if (k != kind_bool) die("expected boolean");

    vm_ai = lo ? 1 : 0;
    fprintf(stderr, "     pop_bool => %s\n", vm_ai ? "true" : "false");
}

void pop_int()
{
    vm_sp -= 3;
    u8 k  = vm_stack[vm_sp+0];
    u8 hi = vm_stack[vm_sp+1];
    u8 lo = vm_stack[vm_sp+2];
    if (k != kind_int) die("expected integer");

    vm_ai = (hi<<8) | lo;
    fprintf(stderr, "     pop_int => %04x\n", vm_ai);
}

void pop_float()
{
    vm_sp -= 3;
    u8 k  = vm_stack[vm_sp+0];
    u8 hi = vm_stack[vm_sp+1];
    u8 lo = vm_stack[vm_sp+2];
    if (k != kind_float) die("expected float");

    u16 u = (hi<<8) | lo;

    vm_ai = u;
    vm_af = f16_to_float(u);

    fprintf(stderr, "     pop_float\n");
}

void pop_bools()
{
    pop_bool(); vm_bi = vm_ai;
    pop_bool();
}

void pop_ints()
{
    pop_int(); vm_bi = vm_ai;
    pop_int();
}

int pop_num()
{
    vm_sp -= 3;
    u8 k  = vm_stack[vm_sp+0];
    u8 hi = vm_stack[vm_sp+1];
    u8 lo = vm_stack[vm_sp+2];
    u16 u = (hi<<8) | lo;
    if (k == kind_int) {
        vm_ai = u;
        fprintf(stderr, "     pop_num => %04x\n", vm_ai);
    }
    else if (k == kind_float) {
        vm_ai = u;
        vm_af = f16_to_float(u);
        fprintf(stderr, "     pop_float => %f\n", vm_af);
    }
    else {
        die("expected float or integer");
    }
    return k;
}

int pop_nums()
{
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

u8 pop_val()
{
    vm_sp -= 3;
    u8 k  = vm_stack[vm_sp+0];
    u8 hi = vm_stack[vm_sp+1];
    u8 lo = vm_stack[vm_sp+2];
    vm_ai = (hi<<8) | lo;
    fprintf(stderr, "     pop_val => k:%02x v=%04x\n", k, vm_ai);
    return k;
}

void push_val(u8 kind, u16 value)
{
    fprintf(stderr, "     push_val <= k:%02x v=%04x\n", kind, value);
    vm_stack[vm_sp+0] = kind;
    vm_stack[vm_sp+1] = value >> 8;
    vm_stack[vm_sp+2] = value & 0xff;
    vm_sp += 3;
}

u8 pop_str()
{
    vm_sp -= 3;
    u8 k  = vm_stack[vm_sp+0];
    u8 hi = vm_stack[vm_sp+1];
    u8 lo = vm_stack[vm_sp+2];
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
    fprintf(stderr, "     pop_str %04x\n", vm_ai);
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
        u8 k  = *(ptr+0);
        u8 hi = *(ptr+1);
        u8 lo = *(ptr+2);
        u16 val = (hi<<8) | lo;
        ptr += 3;

        switch(k) {
            case kind_bool:
                printf(val ? "true" : "false");
                break;
            case kind_int:
                printf("%d", val);
                break;
            case kind_float:
                printf("%f", f16_to_float(val));
                break;
            case kind_str_empty:
                break;
            case kind_str_char:
                printf("%c", val & 0xff);
                break;
            case kind_str_prog:
                {
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
                    break;
                }
            default:
                printf("%02x:%04x", k, val);
                break;
        }
        if (n > 0) printf(" ");
    }
    printf("\n");
}

void vm_ident_set()
{
    u16 id = fetch_word();
    u8 k = pop_val();
    heap[id+ident_kind] = k;
    heap[id+ident_val+0] = vm_ai >> 8;
    heap[id+ident_val+1] = vm_ai & 0xff;
}

void vm_ident_get()
{
    u16 id = fetch_word();
    u8 k  = heap[id+ident_kind];
    u8 hi = heap[id+ident_val+0];
    u8 lo = heap[id+ident_val+1];
    push_val(k, (hi<<8)|lo);
}

void vm_slot_set()
{
    u8 *slot = vm_stack + vm_fp + (u16)fetch_byte() * 3;
    u8 k = pop_val();
    slot[0] = k;
    slot[1] = vm_ai >> 8;
    slot[2] = vm_ai & 0xff;
}

void vm_slot_get()
{
    u8 *slot = vm_stack + vm_fp + (u16)fetch_byte() * 3;
    u8 k  = slot[0];
    u8 hi = slot[1];
    u8 lo = slot[2];
    push_val(k, (hi<<8)|lo);
}

void vm_call(u8 kind)
{
    u8 nargs = fetch_byte();
    u16 id = fetch_word();
    const u8 *func = &heap[id];

    u8 k = func[ident_kind];
    if (k == kind_fail) die("func/proc not defined");
    if (k != kind) die("bad call");

    if (func[ident_arg_count] != nargs) {
        fprintf(stderr, "     want=%d got=%d\n", func[ident_arg_count], nargs);
        die("wrong argument count");
    }

    u16 old_fp = vm_fp;
    u16 old_sp = vm_sp - 3 * nargs;
    vm_fp = vm_sp - 3 * nargs;
    vm_sp = vm_fp + 3 * func[ident_slot_count];

    push_word(old_fp);
    push_word(old_sp);
    push_word(vm_pc);

    vm_pc = func[ident_val+0]<<8 | func[ident_val+1];
}

void vm_return_func()
{
    u8 k = pop_val();

    u16 old_pc = pop_word();
    u16 old_sp = pop_word();
    u16 old_fp = pop_word();

    vm_fp = old_fp;
    vm_sp = old_sp;
    push_val(k, vm_ai);
    vm_pc = old_pc;
}

void vm_return_proc()
{
    u16 old_pc = pop_word();
    u16 old_sp = pop_word();
    u16 old_fp = pop_word();

    vm_fp = old_fp;
    vm_sp = old_sp;
    vm_pc = old_pc;
}

u16 vm_run(const u8 *vm_pc_base)
{
    fprintf(stderr, "\n");
    fprintf(stderr, "RUNNING\n");

    vm_fp = 0;
    vm_sp = 0;
    vm_pc = (u16)(vm_pc_base - code_base);

    while(1) {
        fprintf(stderr, "pc=%04x fp=%04x sp=%04x\n", vm_pc, vm_fp, vm_sp);
        u8 op = fetch_byte();
        fprintf(stderr, "     %s\n", debug_op_name(op));

        switch(op) {
            // operators
            case op_neg:   pop_int(); push_int(-vm_ai); break;
            case op_bnot:  pop_int(); push_int(~vm_ai); break;
            case op_lnot:  pop_bool(); push_bool(!vm_ai); break;

            case op_mul:   if (pop_nums() == kind_int) push_int(vm_ai * vm_bi); else push_float(vm_af * vm_bf); break;
            case op_div:   if (pop_nums() == kind_int) push_int(vm_ai / vm_bi); else push_float(vm_af / vm_bf); break;
            case op_add:   if (pop_nums() == kind_int) push_int(vm_ai + vm_bi); else push_float(vm_af + vm_bf); break;
            case op_sub:   if (pop_nums() == kind_int) push_int(vm_ai - vm_bi); else push_float(vm_af - vm_bf); break;

            case op_mod:   pop_ints(); push_int(vm_ai % vm_bi); break;

            case op_asr:   die("asr: unimplemented"); break;
            case op_lsr:   pop_ints(); push_int(vm_ai >> vm_bi); break;
            case op_lsl:   pop_ints(); push_int(vm_ai << vm_bi); break;

            // TODO make relationals work for strings too
            case op_le:    pop_ints(); push_bool(vm_ai <= vm_bi); break;
            case op_lt:    pop_ints(); push_bool(vm_ai < vm_bi); break;
            case op_gt:    pop_ints(); push_bool(vm_ai > vm_bi); break;
            case op_ge:    pop_ints(); push_bool(vm_ai >= vm_bi); break;
            case op_eq:    pop_ints(); push_bool(vm_ai == vm_bi); break;
            case op_ne:    pop_ints(); push_bool(vm_ai != vm_bi); break;

            case op_band:  pop_ints(); push_int(vm_ai & vm_bi); break;
            case op_bor:   pop_ints(); push_int(vm_ai | vm_bi); break;
            case op_beor:  pop_ints(); push_int(vm_ai ^ vm_bi); break;

            case op_land:  pop_bools(); push_bool(vm_ai && vm_bi); break;
            case op_lor:   pop_bools(); push_bool(vm_ai || vm_bi); break;

            // constants
            case op_false: push_bool(0); break;
            case op_true:  push_bool(1); break;

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
            case op_stop:  return 1;

            // return
            case op_return_func: vm_return_func(); break;
            case op_return_proc: vm_return_proc(); break;
            case op_return_missing: die("missing return"); break;

            // internal ops
            case op_index:      die("index: unimplemented"); break;
            case op_call_proc:  vm_call(kind_proc); break;
            case op_call_func:  vm_call(kind_func); break;
            case op_ident_get:  vm_ident_get(); break;
            case op_ident_set:  vm_ident_set(); break;
            case op_slot_get:   vm_slot_get(); break;
            case op_slot_set:   vm_slot_set(); break;
            case op_lit_int:    push_int(fetch_word()); break;
            case op_lit_float:  push_f16(fetch_word()); break;
            case op_lit_str_empty: push_val(kind_str_empty, 0); break;
            case op_lit_str_char: push_val(kind_str_char, fetch_byte()); break;
            case op_lit_str_prog: push_val(kind_str_prog, fetch_word()); break;
            case op_jump:
                {
                    u16 tmp = fetch_word();
                    vm_pc += tmp;
                    break;
                }
            case op_jfalse:
                {
                    u16 tmp = fetch_word();
                    pop_bool();
                    if (vm_ai == 0) vm_pc += tmp;
                    break;
                }

            default:
                die("unknown opcode");
                break;
        }
    }
}

