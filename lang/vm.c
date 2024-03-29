#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "header.h"

typedef short i16;

// TODO? - a top-of-stack register to reduce number of push/pop sequences
// TODO - heap cleanup (e.g. ref counts)

typedef struct
{
    u8 k;
    union {
        u16 u;
        i16 i;
        u16 f;
    };
} value;

value vm_a;
value vm_b;

u16 vm_fp;
u16 vm_sp;
u16 vm_pc;

const u16 stack_max = 1536;
u8 vm_stack[1536];

//------------------------------------------------------------------------------
// Utilities
//

void vm_die(const char* msg)
{
    printf("RUNTIME ERROR: %s!\n", msg);
    exit(1);
}

//------------------------------------------------------------------------------
// Instruction stream
//

u8 fetch_byte()
{
    u8 b = code_base[vm_pc++];
    return b;
}

u16 fetch_word()
{
    u16 w;
    w = code_base[vm_pc++]<<8;
    w |= code_base[vm_pc++]; 
    return w;
}

//------------------------------------------------------------------------------
// Stack handling
//

void push_byte(u8 b)
{
    vm_stack[vm_sp+0] = b;
    vm_sp += 1;
}

void push_word(u16 w)
{
    vm_stack[vm_sp+0] = w>>8;
    vm_stack[vm_sp+1] = w&0xff;
    vm_sp += 2;
}

void push_bool(u16 b)
{
    vm_stack[vm_sp+0] = kind_bool;
    vm_stack[vm_sp+1] = 0;
    vm_stack[vm_sp+2] = (b==0) ? 0 : 1;
    vm_sp += 3;
}

void push_int(i16 i)
{
    vm_stack[vm_sp+0] = kind_int;
    vm_stack[vm_sp+1] = ((u16)i) >> 8;
    vm_stack[vm_sp+2] = ((u16)i) & 0xff;
    vm_sp += 3;
}

void push_f16(u16 f)
{
    vm_stack[vm_sp+0] = kind_float;
    vm_stack[vm_sp+1] = f >> 8;
    vm_stack[vm_sp+2] = f & 0xff;
    vm_sp += 3;
}

void push_float(float f)
{
    u16 u = f16_from_float(f);
    vm_stack[vm_sp+0] = kind_float;
    vm_stack[vm_sp+1] = u>>8;
    vm_stack[vm_sp+2] = u&0xff;
    vm_sp += 3;
}

void push_array(u16 a)
{
    vm_stack[vm_sp+0] = kind_array;
    vm_stack[vm_sp+1] = a>>8;
    vm_stack[vm_sp+2] = a&0xff;
    vm_sp += 3;
}

void push_val(u8 kind, u16 value)
{
    vm_stack[vm_sp+0] = kind;
    vm_stack[vm_sp+1] = value >> 8;
    vm_stack[vm_sp+2] = value & 0xff;
    vm_sp += 3;
}

void vm_check_stack(u16 n)
{
    if (vm_sp > stack_max-n) vm_die("stack overflow");
}

void push_val_checked(u8 kind, u16 value)
{
    vm_check_stack(3);

    push_val(kind, value);
}

u8 pop_byte()
{
    vm_sp -= 1;
    u8 b = vm_stack[vm_sp+0];
    return b;
}

u16 pop_word()
{
    vm_sp -= 2;
    u8 hi = vm_stack[vm_sp+0];
    u8 lo = vm_stack[vm_sp+1];
    u16 w = hi<<8 | lo;
    return w;
}

void pop_val()
{
    vm_sp -= 3;
    u8 k  = vm_stack[vm_sp+0];
    u8 hi = vm_stack[vm_sp+1];
    u8 lo = vm_stack[vm_sp+2];
    vm_a.k = k;
    vm_a.u = (hi<<8) | lo;
}

void pop_bool()
{
    pop_val();
    if (vm_a.k != kind_bool) vm_die("expected boolean");
}

void pop_int()
{
    pop_val();
    if (vm_a.k != kind_int) vm_die("expected integer");
}

void pop_float()
{
    pop_val();
    if (vm_a.k != kind_float) vm_die("expected float");
}

void pop_bools()
{
    pop_bool(); vm_b = vm_a;
    pop_bool();
}

void pop_ints()
{
    pop_int(); vm_b = vm_a;
    pop_int();
}

void pop_num()
{
    pop_val();

    switch(vm_a.k) {
        case kind_int:
        case kind_float:
            break;
        default:
            vm_die("expected float or integer");
    }
}

void pop_nums()
{
    pop_num();
    vm_b = vm_a;
    pop_num();

    if (vm_b.k == vm_a.k) return;
    if (vm_b.k == kind_float) {
        vm_a.k = kind_float;
        vm_a.f = f16_from_float((float)vm_a.i);
    }
    else {
        vm_b.k = kind_float;
        vm_b.f = f16_from_float((float)vm_b.i);
    }
}

void pop_str()
{
    pop_val();

    switch(vm_a.k) {
        case kind_str_0:
        case kind_str_1:
        case kind_str_n:
            break;

        default:
            vm_die("expected string");
    }
}

void pop_array()
{
    pop_val();
    if (vm_a.k != kind_array) vm_die("expected array");
}

void pop_vals()
{
    pop_val();
    vm_b = vm_a;
    pop_val();

    if (vm_a.k == vm_b.k) return;
    if (vm_a.k == kind_int && vm_b.k == kind_float) {
        vm_a.k = kind_float;
        vm_a.f = f16_from_float((float)vm_a.i);
        return;
    }
    else if (vm_a.k == kind_float && vm_b.k == kind_int) {
        vm_b.k = kind_float;
        vm_b.f = f16_from_float((float)vm_b.i);
        return;
    }

    u8 isstr1 = (vm_a.k == kind_str_0 || vm_a.k == kind_str_1 || vm_a.k == kind_str_n);
    u8 isstr2 = (vm_b.k == kind_str_0 || vm_b.k == kind_str_1 || vm_b.k == kind_str_n);
    if (isstr1 && isstr2) return;

    vm_die("incompatible types");
}

// Takes:
//      (kind, val) - a string value
//      pch [out] - single char temp buffer
//      len [out] - length of string
//
// Returns a pointer to the string contents and sets len
// to its length. If kind is kind_str_1, the returned pointer
// will equal pch, and *pch will be updated to contain the
// single character.
//
// This allows string operations to treat all three string
// kinds uniformly.
//
const u8* vm_str_buf(u8 kind, u16 val, u8* pch, u16* len)
{
    switch(kind) {
        case kind_str_0:
            *len = 0;
            return pch;

        case kind_str_1:
            *pch = val;
            *len = 1;
            return pch;

        default: {
            const u8 *str = heap + val;
            *len = str[str_len_hi]<<8 | str[str_len_lo];
            return str + str_data;
        }
    }
}

//------------------------------------------------------------------------------
// Arithmetic operators
//

void vm_add()
{
    pop_vals();

    // TODO check overflow?
    if (vm_a.k == kind_int) {
        push_int(vm_a.i + vm_b.i);
        return;
    }
    if (vm_a.k == kind_float) {
        push_float(f16_to_float(vm_a.f) + f16_to_float(vm_b.f));
        return;
    }
    if (vm_a.k == kind_str_0) {
        push_val(vm_b.k, vm_b.u);
        return;
    }
    if (vm_b.k == kind_str_0) {
        push_val(vm_a.k, vm_a.u);
        return;
    }

    u8 ch1, ch2;
    u16 len1, len2;
    const u8 *data1 = vm_str_buf(vm_a.k, vm_a.u, &ch1, &len1);
    const u8 *data2 = vm_str_buf(vm_b.k, vm_b.u, &ch2, &len2);

    u16 len = len1+len2;
    u8 *str = heap+heap_alloc(str_data + len);
    str[str_len_hi] = len >> 8;
    str[str_len_lo] = len & 0xff;

    u8 *p = str + str_data;
    memcpy(p, data1, len1);
    p += len1;
    memcpy(p, data2, len2);
    push_val(kind_str_n, str-heap);
}

//------------------------------------------------------------------------------
// Relational operators
//

void vm_relop(u8 op)
{
    pop_vals();

    int cmp;

    switch(vm_a.k) {
        case kind_int:
            cmp = (vm_a.i == vm_b.i) ? 0 : (vm_a.i < vm_b.i) ? -1 : 1;
            break;

        case kind_float: {
            float af = f16_to_float(vm_a.f);
            float bf = f16_to_float(vm_b.f);
            cmp = (af == bf) ? 0 : (af < bf) ? -1 : 1;
            break;
        }

        case kind_str_0:
        case kind_str_1:
        case kind_str_n: {
            pop_str();

            u8 ch1, ch2;
            u16 len1, len2;
            const u8 *data1 = vm_str_buf(vm_a.k, vm_a.u, &ch1, &len1);
            const u8 *data2 = vm_str_buf(vm_b.k, vm_b.u, &ch2, &len2);
            u16 prefix_len = len1;
            if (len2 < prefix_len) prefix_len = len2;
            cmp = memcmp(data1, data2, prefix_len);
            if (cmp == 0 && len1 != len2) {
                cmp = (len1 < len2) ? -1 : 1;
            }
            break;
        }

        default:
            vm_die("non-comparable");
    }

    u16 b;
    switch(op) {
        case op_le: b = cmp <= 0; break;
        case op_lt: b = cmp <  0; break;
        case op_gt: b = cmp >  0; break;
        case op_ge: b = cmp >= 0; break;
        case op_eq: b = cmp == 0; break;
        case op_ne: b = cmp != 0; break;
    }
    push_bool(b);
}

//------------------------------------------------------------------------------
// Built-in math functions
//

void fn_abs()
{
    pop_num();
    if (vm_a.k == kind_int) {
        push_int((vm_a.i < 0) ? -vm_a.i : vm_a.i);
    }
    else {
        push_val(kind_float, vm_a.f & 0x7fff);
    }
}

void fn_sgn()
{
    pop_num();
    if (vm_a.k == kind_int) {
        push_int(vm_a.i ? ((vm_a.i < 0) ? -1 : 1) : 0);
    }
    else {
        push_int((vm_a.f & 0x7fff) ? ((vm_a.f & 0x8000) ? -1 : 1) : 0);
    }
}

void fn_rnd()
{
    push_int(random() & 0x7fff);
}

void fn_sqr()
{
    pop_num();
    if (vm_a.k == kind_int) {
        push_float(sqrt((float)vm_a.i));
    }
    else {
        push_float(sqrt(f16_to_float(vm_a.f)));
    }
}

void fn_int()
{
    pop_val();
    switch(vm_a.k) {
        case kind_int:
            push_int(vm_a.i);
            break;

        case kind_float:
            push_int((i16)f16_to_float(vm_a.f));
            break;

        case kind_str_0:
        case kind_str_1:
        case kind_str_n: {
            u8 ch;
            u16 len;
            const u8 *data = vm_str_buf(vm_a.k, vm_a.u, &ch, &len);
            // number of digits in "-32768"
            if (len <= 6) {
                char buf[8];
                memcpy(buf, data, len);
                buf[len] = '\0';
                char* endptr;
                long l = strtol(buf, &endptr, 10);
                // if *str is not `\0' but **endptr is `\0' on return, the entire string was valid.
                if (endptr > buf && *endptr == '\0') {
                    if (l >= -32768 && l <= 32767) {
                        push_int(l);
                        return;
                    }
                }
            }
            vm_die("not a valid integer");
        }

        default: vm_die("expected number or string");
    }
}

void fn_float()
{
    pop_val();

    switch(vm_a.k) {
        case kind_int:
            push_float((float)vm_a.i);
            break;

        case kind_float:
            push_f16(vm_a.f);
            break;

        case kind_str_0:
        case kind_str_1:
        case kind_str_n: {
            u8 ch;
            u16 len;
            const u8 *data = vm_str_buf(vm_a.k, vm_a.u, &ch, &len);
            // reasonable upper bound for max digits
            if (len < 32) {
                char buf[32];
                memcpy(buf, data, len);
                buf[len] = '\0';
                char* endptr;
                float f = strtof(buf, &endptr);
                // if *str is not `\0' but **endptr is `\0' on return, the entire string was valid.
                if (endptr > buf && *endptr == '\0') {
                    push_float(f);
                    return;
                }
            }
            vm_die("not a valid number");
        }

        default: vm_die("expected number or string");
    }
}

//------------------------------------------------------------------------------
// Built-in string functions
//

void fn_asc()
{
    pop_str();
    switch(vm_a.k) {
        case kind_str_0:
            // TODO - return -1 instead? error?
            push_int(0);
            return;

        case kind_str_1:
            push_int(vm_a.u);
            return;

        default: {
            u8 *str = heap + vm_a.u;
            u16 len = str[str_len_hi]<<8 | str[str_len_lo];
            if (len == 0) push_int(0);
            else push_int(str[str_data+0]);
            return;
        }
    }
}

void fn_chr()
{
    pop_int();
    push_val(kind_str_1, vm_a.u & 0xff);
}

void fn_str()
{
    pop_val();
    char buf[16];
    const char *q;
    u16 len;
    switch(vm_a.k) {
        case kind_bool:
            // TODO - it would make sense to put these on the heap
            // at program start to avoid repeated reallocations
            if (vm_a.u != 0) {
                len = 4;
                q = "true";
            }
            else {
                len = 5;
                q = "false";
            }
            break;

        case kind_int:
            len = sprintf(buf, "%d", vm_a.i);
            q = buf;
            break;

        case kind_float:
            len = sprintf(buf, "%f", f16_to_float(vm_a.f));
            q = buf;
            break;

        case kind_str_0:
        case kind_str_1: 
        case kind_str_n:
            push_val(vm_a.k, vm_a.u);
            return;

        // TODO - it would make sense to put these on the heap
        // at program start to avoid repeated reallocations
        case kind_proc:
            len = 6;
            q = "<proc>";
            break;

        case kind_func:
            len = 6;
            q = "<func>";
            break;

        default:
            len = 9;
            q = "<unknown>";
            break;
    }

    if (len == 1) {
        push_val(kind_str_1, q[0]);
        return;
    }

    u8 *str = heap+heap_alloc(str_data + len);
    str[str_len_hi] = len >> 8;
    str[str_len_lo] = len & 0xff;

    u8 *p = str + str_data;
    memcpy(p, q, len);
    push_val(kind_str_n, str-heap);
}

void fn_len()
{
    pop_str();
    switch(vm_a.k) {
        case kind_str_0:
            push_int(0);
            return;

        case kind_str_1:
            push_int(1);
            return;

        default: {
            u8 *str = heap + vm_a.i;
            u16 len = str[str_len_hi]<<8 | str[str_len_lo];
            push_int((i16) len);
            return;
        }
    }
}

void vm_substr(u16 pos, u16 n);
void vm_substr_cont(const u8 *str, u16 pos, u16 n, u16 len);

void fn_left()
{
    pop_int();
    i16 ni = vm_a.i;
    if (ni < 0) vm_die("negative count");

    vm_substr(0, (u16)ni);
}

void fn_right()
{
    pop_int();
    i16 ni = vm_a.i;
    if (ni < 0) vm_die("negative count");
    u16 n = (u16) ni;

    pop_str();
    if (n == 0 || vm_a.k == kind_str_0) {
        push_val(kind_str_0, 0);
        return;
    }

    if (vm_a.k == kind_str_1) {
        if (n >= 1) push_val(kind_str_1, vm_a.u);
        else push_val(kind_str_0, 0);
        return;
    }

    const u8 *str = heap + vm_a.u;
    u16 len = str[str_len_hi]<<8 | str[str_len_lo];
    if (n >= len) {
        n = len;
    }
    u16 pos = len - n;

    return vm_substr_cont(str, pos, n, len);
}

void fn_substr()
{
    pop_int();
    i16 ni = vm_a.i;
    if (ni < 0) vm_die("negative count");

    pop_int();
    i16 posi = vm_a.i;
    if (posi < 0) vm_die("negative offset");

    vm_substr((u16)posi, (u16)ni);
}

void vm_substr(u16 pos, u16 n)
{
    pop_str();

    if (n == 0 || vm_a.k == kind_str_0) {
        push_val(kind_str_0, 0);
        return;
    }

    if (vm_a.k == kind_str_1) {
        if (pos == 0) push_val(kind_str_1, vm_a.u);
        else push_val(kind_str_0, 0);
        return;
    }

    const u8 *str = heap + vm_a.u;
    u16 len = str[str_len_hi]<<8 | str[str_len_lo];

    if (pos >= len) {
        push_val(kind_str_0, 0);
        return;
    }

    vm_substr_cont(str, pos, n, len);
}

void vm_substr_cont(const u8 *str, u16 pos, u16 n, u16 len)
{
    if (pos == 0 && n >= len) {
        push_val(kind_str_n, vm_a.u);
        return;
    }

    const u8 *data = str + str_data;

    if (n == 1 || pos == len-1) {
        push_val(kind_str_1, data[pos]);
        return;
    }

    u16 len2 = len-pos;
    if (n < len2) len2 = n;

    u8 *str2 = heap + heap_alloc(str_data + len2);
    str2[str_len_hi] = len2 >> 8;
    str2[str_len_lo] = len2 & 0xff;
    memcpy(str2+str_data, data+pos, len2);
    push_val(kind_str_n, str2-heap);
}

//------------------------------------------------------------------------------
// Built-in procedures
//

void vm_print(value val)
{
    switch(val.k) {
        case kind_bool:
            printf(val.u ? "true" : "false");
            break;

        case kind_int:
            printf("%d", val.i);
            break;

        case kind_float:
            printf("%f", f16_to_float(val.f));
            break;

        case kind_str_0:
            break;

        case kind_str_1:
            printf("%c", val.u & 0xff);
            break;

        case kind_str_n:
        {
            const u8 *str = heap + val.u;
            u16 len = str[str_len_hi]<<8 | str[str_len_lo];
            fwrite(str + str_data, 1, len, stdout);
            break;
        }

        case kind_array:
        {
            const u8 *array = heap + val.u;
            u8 len = array[array_len];
            const u8 *p = &array[array_data];
            putchar('[');
            while(len > 0) {
                value elt;
                elt.k = p[0];
                elt.u = p[1]<<8 | p[2];
                vm_print(elt);
                p += 3;
                len -= 1;
                if (len > 0) putchar(',');
            }
            putchar(']');
            break;
        }

        default:
            printf("%02x:%04x", val.k, val.u);
            break;
    }
}

void proc_print()
{
    u8 n = fetch_byte();
    vm_sp -= 3*n;
    const u8 *p = &vm_stack[vm_sp];
    while(n--) {
        value val;
        val.k = p[0];
        val.u = p[1]<<8 | p[2];
        p += 3;

        vm_print(val);

        if (n > 0) printf(" ");
    }
    printf("\n");
}

//------------------------------------------------------------------------------
// Accessors
//

void vm_ident_set()
{
    u16 id = fetch_word();
    pop_val();
    heap[id+ident_kind] = vm_a.k;
    heap[id+ident_val+0] = vm_a.u >> 8;
    heap[id+ident_val+1] = vm_a.u & 0xff;
}

void vm_ident_get()
{
    vm_check_stack(3);

    u16 id = fetch_word();
    u8 k  = heap[id+ident_kind];
    u8 hi = heap[id+ident_val+0];
    u8 lo = heap[id+ident_val+1];
    push_val(k, (hi<<8)|lo);
}

void vm_slot_set()
{
    u8 *slot = vm_stack + vm_fp + (u16)fetch_byte() * 3;
    pop_val();
    slot[0] = vm_a.k;
    slot[1] = vm_a.u >> 8;
    slot[2] = vm_a.u & 0xff;
}

void vm_slot_get()
{
    vm_check_stack(3);

    u8 *slot = vm_stack + vm_fp + (u16)fetch_byte() * 3;
    u8 k  = slot[0];
    u8 hi = slot[1];
    u8 lo = slot[2];
    push_val(k, (hi<<8)|lo);
}

void vm_lit_array()
{
    u8 nargs = fetch_byte();
    u16 array = heap_alloc(array_data + nargs * 3);
    u8 *p = heap+array;
    p[array_len] = nargs;
    p += array_data;
    p += nargs*3;

    while(nargs > 0) {
        --nargs;
        p -= 3;
        pop_val();
        p[0] = vm_a.k;
        p[1] = vm_a.u >> 8;
        p[2] = vm_a.u & 0xff;
    }

    push_array(array);
}

// TODO allow indexing of strings
void vm_index()
{
    pop_int();
    vm_b = vm_a;
    pop_array();

    u8 *p = heap+vm_a.u;
    // TODO - 16 bit array lengths
    u8 len = p[array_len];
    p += array_data;

    i16 index = vm_b.i;
    if (index < 0) index += len;
    if (index < 0 || index >= len) die("array index out of range");

    p += 3 * index;
    
    u8 k = p[0];
    u16 val = p[1]<<8 | p[2];
    push_val(k, val);
}

// TODO allow slicing of strings
void vm_slice(u8 has_start, u8 has_end)
{
    i16 start = 0;
    i16 end = 32767;
    if (has_end) {
        pop_int();
        end = vm_a.i;
    }
    if (has_start) {
        pop_int();
        start = vm_a.i;
    }
    pop_array();

    u8 *p = heap+vm_a.u;
    u8 len = p[array_len];
    p += array_data;

    if (start < 0) start += len;
    if (end < 0) end += len;

    if (start < 0) start = 0;
    else if (start >= len) start = len;

    if (end < start) end = start;
    if (end >= len) end = len;

    u16 len2 = end-start;

    u16 array2 = heap_alloc(array_data + len2 * 3);
    u8 *q = heap+array2;
    q[array_len] = len2;
    q += array_data;

    memcpy(q, p + start*3, len2*3);

    push_array(array2);
}

//------------------------------------------------------------------------------
// Call + return handlers
//

void vm_call(u8 kind)
{
    u8 nargs = fetch_byte();
    u16 id = fetch_word();
    const u8 *func = &heap[id];

    u8 k = func[ident_kind];
    if (k == kind_fail) vm_die("func/proc not defined");
    if (k != kind) vm_die("bad call");

    if (func[ident_arg_count] != nargs) {
        vm_die("wrong argument count");
    }

    u16 old_fp = vm_fp;
    u16 old_sp = vm_sp - 3 * nargs;
    vm_fp = vm_sp - 3 * nargs;
    vm_sp = vm_fp;

    vm_check_stack(6 + 3 * func[ident_slot_count]);
    vm_sp = vm_sp + 3 * func[ident_slot_count];

    push_word(old_fp);
    push_word(old_sp);
    push_word(vm_pc);

    vm_pc = func[ident_val+0]<<8 | func[ident_val+1];
}

void vm_return_func()
{
    pop_val();

    u16 old_pc = pop_word();
    u16 old_sp = pop_word();
    u16 old_fp = pop_word();

    vm_fp = old_fp;
    vm_sp = old_sp;
    push_val(vm_a.k, vm_a.u);
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

//------------------------------------------------------------------------------
// Entry point
//

u16 vm_run(const u8 *vm_pc_base)
{
    fprintf(stderr, "\n");
    fprintf(stderr, "RUNNING\n");

    vm_fp = 0;
    vm_sp = 0;
    vm_pc = (u16)(vm_pc_base - code_base);

    while(1) {
        fprintf(stderr, "pc=%04x fp=%04x sp=%04x ", vm_pc, vm_fp, vm_sp);
        u8 op = fetch_byte();
        fprintf(stderr, "%s\n", debug_op_name(op));

        switch(op) {
            // arithmetic operators
            case op_neg:    pop_num(); if (vm_a.k == kind_int) push_int(-vm_a.i); else push_f16(vm_a.f ^ 0x8000); break;
            case op_mul:    pop_nums(); if (vm_a.k == kind_int) push_int(vm_a.i * vm_b.i); else push_float(f16_to_float(vm_a.f) * f16_to_float(vm_b.f)); break;
            case op_div:    pop_nums(); if (vm_a.k == kind_int) push_int(vm_a.i / vm_b.i); else push_float(f16_to_float(vm_a.f) / f16_to_float(vm_b.f)); break;
            case op_add:    vm_add(); break;
            case op_sub:    pop_nums(); if (vm_a.k == kind_int) push_int(vm_a.i - vm_b.i); else push_float(f16_to_float(vm_a.f) - f16_to_float(vm_b.f)); break;
            case op_mod:    pop_ints(); push_int(vm_a.i % vm_b.i); break;

            // relational operators
            case op_le:
            case op_lt:
            case op_gt:
            case op_ge:
            case op_eq:
            case op_ne:
                vm_relop(op);
                break;

            // bitwise operators
            case op_bnot:   pop_int(); push_int(~vm_a.i); break;
            case op_band:   pop_ints(); push_int(vm_a.u & vm_b.u); break;
            case op_bor:    pop_ints(); push_int(vm_a.u | vm_b.u); break;
            case op_beor:   pop_ints(); push_int(vm_a.u ^ vm_b.u); break;

            // shift operators
            case op_asr:    vm_die("asr: unimplemented"); break;
            case op_lsr:    pop_ints(); push_int(vm_a.u >> vm_b.i); break;   // TODO special treatment for -ve / +ve shifts?
            case op_lsl:    pop_ints(); push_int(vm_a.u << vm_b.i); break;   // TODO special treatment for -ve / +ve shifts?

            // logical operators
            case op_lnot:   pop_bool(); push_bool(!vm_a.i); break;
            case op_land:   pop_bools(); push_bool(vm_a.u && vm_b.u); break;
            case op_lor:    pop_bools(); push_bool(vm_a.u || vm_b.u); break;

            // constants
            case op_false:  push_bool(0); break;
            case op_true:   push_bool(1); break;

            // built-in math functions
            case op_abs:    fn_abs(); break;
            case op_sgn:    fn_sgn(); break;
            case op_rnd:    fn_rnd(); break;
            case op_sqr:    fn_sqr(); break;
            case op_int:    fn_int(); break;
            case op_float:  fn_float(); break;

            // built-in string functions
            case op_asc:    fn_asc(); break;
            case op_chr:    fn_chr(); break;
            case op_str:    fn_str(); break;
            case op_len:    fn_len(); break;
            case op_left:   fn_left(); break;
            case op_right:  fn_right(); break;
            case op_substr: fn_substr(); break;

            // built-in procedures
            case op_print:  proc_print(); break;
            case op_input:  vm_die("input: unimplemented"); break;
            case op_stop:   return 1;

            // accessors
            case op_ident_get:  vm_ident_get(); break;
            case op_ident_set:  vm_ident_set(); break;
            case op_slot_get:   vm_slot_get(); break;
            case op_slot_set:   vm_slot_set(); break;
            case op_lit_int:    push_val_checked(kind_int, fetch_word()); break;
            case op_lit_float:  push_val_checked(kind_float, fetch_word()); break;
            case op_lit_str_0:  push_val_checked(kind_str_0, 0); break;
            case op_lit_str_1:  push_val_checked(kind_str_1, fetch_byte()); break;
            case op_lit_str_n:  push_val_checked(kind_str_n, fetch_word()); break;

            case op_lit_array:      vm_lit_array(); break;
            case op_index:          vm_index(); break;
            case op_slice:          vm_slice(1, 1); break;
            case op_slice_start:    vm_slice(1, 0); break;
            case op_slice_end:      vm_slice(0, 1); break;
            case op_slice_empty:    vm_slice(0, 0); break;

            // call + return
            case op_call_proc:      vm_call(kind_proc); break;
            case op_call_func:      vm_call(kind_func); break;
            case op_return_func:    vm_return_func(); break;
            case op_return_proc:    vm_return_proc(); break;
            case op_return_missing: vm_die("missing return"); break;

            // jumps
            case op_jump: {
                u16 tmp = fetch_word();
                vm_pc += tmp;
                break;
            }
            case op_jfalse: {
                u16 tmp = fetch_word();
                pop_bool();
                if (vm_a.u == 0) vm_pc += tmp;
                break;
            }

            default:
                vm_die("unknown opcode");
                break;
        }
    }
}

