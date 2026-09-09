#include "header.h"
#include "array.h"
#include "dict.h"
#include "object.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// TODO? - a top-of-stack register to reduce number of push/pop sequences
// TODO - heap cleanup (e.g. ref counts)

bool opt_trace_vm = false;

Value vm_a;
Value vm_b;

u16 vm_sp;
u16 vm_fp;
u16 vm_pc;

Dict* vm_globals;

u16 vm_sp_max; // not a register

//------------------------------------------------------------------------------
// Utilities
//

// Aborts the program with the specified message.
__attribute__((noreturn)) void vm_die(const char* msg)
{
    fflush(stdout);
    fprintf(stderr, "RUNTIME ERROR: %s!\n", msg);
    exit(1);
}

// Returns the value stored at p.
extern Value get_value(const u8* p)
{
    return (Value){.k = *p, .u = *(u16*)(p+1)};
}

// Stores the value v at p.
extern void set_value(u8* p, Value v)
{
    *p = v.k;
    *(u16*)(p+1) = v.u;
}

//------------------------------------------------------------------------------
// Instruction stream
//

// Fetches a single byte from the instruction stream.
u8 fetch_byte(void)
{
    u8 b = *from_p16(vm_pc);
    vm_pc += 1;
    return b;
}

// Fetches a 16-bit word from the instruction stream.
u16 fetch_word(void)
{
    u16 w = *(u16*) from_p16(vm_pc);
    vm_pc += sizeof(u16);
    return w;
}

// Fetches a 16-bit pointer-to-byte from the instruction stream.
u8* fetch_ptr(void)
{
    return from_p16(fetch_word());
}

//------------------------------------------------------------------------------
// Stack handling
//

// Pushes a single byte to the stack.
// - The stack is not checked for overflow.
void push_byte(u8 b)
{
    *from_p16(vm_sp) = b;
    vm_sp += 1;
}

// Pushes a 16-bit word to the stack.
// - The stack is not checked for overflow.
void push_word(u16 w)
{
    *(u16*) from_p16(vm_sp) = w;
    vm_sp += sizeof(u16);
}

// Pushes a value of the given kind and payload to the stack.
// - The stack is not checked for overflow.
void push_val(Kind kind, u16 value)
{
    push_byte((u8) kind);
    push_word(value);
}

// Pushes the value for True to the stack if b is non-zero, otherwise pushes
// the value for False.
// - The stack is not checked for overflow.
void push_bool(u16 b)
{
    push_val(kind_bool, (b==0) ? 0 : 1);
}

// Pushes the integer Value for i to the stack.
// The stack is not checked for overflow.
void push_int(i16 i)
{
    push_val(kind_int, i);
}

// Pushes the float Value for f to the stack, where f is already
// encoded as an f16.
// - The stack is not checked for overflow.
void push_f16(f16 f)
{
    push_val(kind_float, (u16) f);
}

// Pushes the float Value for f, converting from a host float.
// - The stack is not checked for overflow.
void push_float(float f)
{
    push_f16(f16_from_float(f));
}

// Pushes the string Value for s to the stack.
// - The stack is not checked for overflow.
void push_string(String* s)
{
    push_val(kind_string, to_p16(s));
}

// Pushes the array Value for a to the stack.
// - The stack is not checked for overflow.
void push_array(Array* a)
{
    push_val(kind_array, to_p16(a));
}

// Pushes the dict Value for d to the stack.
// - The stack is not checked for overflow.
void push_dict(Dict* d)
{
    push_val(kind_dict, to_p16(d));
}

// Aborts if the stack has less then n bytes of headroom.
void vm_check_stack(u16 n)
{
    if (vm_sp > vm_sp_max-n) vm_die("stack overflow");
}

// Pushes a value of the specified kind and payload to the stack,
// checking for sufficient headroom.
void push_val_checked(Kind kind, u16 value)
{
    vm_check_stack(sizeof_Value);

    push_val(kind, value);
}

// Pops and returns a single byte from the stack.
u8 pop_byte(void)
{
    vm_sp -= 1;
    return *from_p16(vm_sp);
}

// Pops and returns a 16-bit word from the stack.
u16 pop_word(void)
{
    vm_sp -= 2;
    return *(u16*) from_p16(vm_sp);
}

// Pops a Value of any type from the stack and returns it.
Value pop_val(void)
{
    Value v;
    v.u = pop_word();
    v.k = pop_byte();
    return v;
}

// Pops a Value of any type from the stack, and returns False if it was
// either False or None, otherwise returns True.
Value pop_bool(void)
{
    Value v = pop_val();
    // convert None, False to False, everything else to True
    if (v.k != kind_bool) {
        v.u = v.k != kind_none;
        v.k = kind_bool;
    }
    return v;
}

// Pops an integer Value from the stack and returns it.
// - Aborts if the value was not an integer.
Value pop_int(void)
{
    Value v = pop_val();
    if (v.k == kind_int) return v;
    vm_die("expected integer");
}

// Pops a float Value from the stack and returns it.
// - Aborts if the value was not a float.
Value pop_float(void)
{
    Value v = pop_val();
    if (v.k == kind_float) return v;
    vm_die("expected float");
}

// Pops two Values of any type from the stack, setting vm_b to the top value
// and vm_a to the 2nd from top value, coercing both to bool.
void pop_bools(void)
{
    vm_b = pop_bool();
    vm_a = pop_bool();
}

// Pops two integer Values from the stack, setting vm_b to the top item and
// vm_a to the 2nd from top item.
// - Aborts if either value was not an integer.
void pop_ints(void)
{
    vm_b = pop_int();
    vm_a = pop_int();
}

// Pops a numeric Value (integer or float) from the stack and returns it.
// - Aborts if the value was not an integer or float.
Value pop_num(void)
{
    Value v = pop_val();

    switch(v.k) {
        case kind_int:
        case kind_float:
            return v;
        default:
            vm_die("expected float or integer");
    }
}

// Pops two numeric Values from the stack, setting vm_b to the top value,
// and vm_a to the 2nd from top value. If either value was float, coerces
// the other to float as well.
// - Aborts if either value was not an integer or float.
void pop_nums(void)
{
    vm_b = pop_num();
    vm_a = pop_num();

    if (vm_b.k != vm_a.k) {
        if (vm_b.k == kind_float) {
            vm_a.k = kind_float;
            vm_a.f = f16_from_float((float) vm_a.i);
        }
        else {
            vm_b.k = kind_float;
            vm_b.f = f16_from_float((float) vm_b.i);
        }
    }
}

// Pops a string Value from the stack and returns it.
// - Aborts if the value was not a string.
Value pop_str(void)
{
    Value v = pop_val();
    if (v.k == kind_string) return v;
    vm_die("expected string");
}

// Pops an array Value from the stack and returns it.
// - Aborts if the value was not an array.
Value pop_array(void)
{
    Value v = pop_val();
    if (v.k == kind_array) return v;
    vm_die("expected array");
}

// Pops a dict Value from the stack and returns it.
// - Aborts if the value was not a dict.
Value pop_dict(void)
{
    Value v = pop_val();
    if (v.k == kind_dict) return v;
    vm_die("expected dict");
}

// Pops two Values of any type from the stack, setting vm_b to the top value,
// and vm_a to the 2nd from top value. If one value was float and the other
// integer, coerces the non-integer to float.
//
// - Aborts if the two values' types differ (after coercion).
void pop_vals(void)
{
    vm_b = pop_val();
    vm_a = pop_val();

    if (vm_a.k != vm_b.k) {
        if (vm_a.k == kind_int && vm_b.k == kind_float) {
            vm_a.k = kind_float;
            vm_a.f = f16_from_float((float) vm_a.i);
        }
        else if (vm_a.k == kind_float && vm_b.k == kind_int) {
            vm_b.k = kind_float;
            vm_b.f = f16_from_float((float) vm_b.i);
        }
        else {
            vm_die("incompatible types");
        }
    }
}

//------------------------------------------------------------------------------
// Arithmetic operators
//

// Replaces the numeric Value N with its negation -N, preserving its type.
//
// [..., N:int] => [..., int]
// [..., N:float] => [..., float]
void vm_neg(void)
{
    vm_a = pop_num();
    if (vm_a.k == kind_int) {
        push_int(-vm_a.i);
    }
    else {
        push_f16(vm_a.f ^ 0x8000);
    }
}

// Replaces two numeric Values A, B with their product A*B.
//
// [..., A:int, B:int] => [..., int]
//
// [..., A:float, B:num] => [..., float]
// [..., A:num, B:float] => [..., float]
//
// - if A or B is float, both are coerced to float before multiplying.
void vm_mul(void)
{
    pop_nums();
    if (vm_a.k == kind_int) {
        push_int(vm_a.i * vm_b.i);
    }
    else {
        push_float(f16_to_float(vm_a.f) * f16_to_float(vm_b.f));
    }
}

// Replaces two numeric Values A, B with their quotient A/B.
//
// [..., int, int] => [..., int]
//
// [..., float, num] => [..., float]
// [..., num, float] => [..., float]
//
// - if A or B is float, both are coerced to float before dividing.
void vm_div(void)
{
    pop_nums();
    if (vm_a.k == kind_int) {
        push_int(vm_a.i / vm_b.i);
    }
    else {
        push_float(f16_to_float(vm_a.f) / f16_to_float(vm_b.f));
    }
}

// Replaces two numeric Values A, B with their difference A-B.
//
// [..., int, int] => [..., int]
//
// [..., float, num] => [..., float]
// [..., num, float] => [..., float]
//
// - if A or B is float, both are coerced to float before subtracting.
void vm_sub(void)
{
    pop_nums();
    if (vm_a.k == kind_int) {
        push_int(vm_a.i - vm_b.i);
    }
    else {
        push_float(f16_to_float(vm_a.f) - f16_to_float(vm_b.f));
    }
}

// Replaces two integer Values A, B with their modulus A mod B.
//
// [..., int, int] => [..., int]
void vm_mod(void)
{
    pop_ints();
    i16 r = vm_a.i % vm_b.i;
    if (r != 0 && ((vm_a.u ^ vm_b.u)&0x8000)) {
        // If signs differ, convert result from
        // c99-style remainder to python-style modulo
        r += vm_b.i;
    }
    push_int(r);
}

// Replaces two Values A, B with a combined Value A+B according to their type.
//
// [..., int, int] => [..., int]
// - numeric types are added.
//
// [..., float, num] => [..., float]
// [..., num, float] => [..., float]
// - if A or B is float, both are coerced to float before adding.
//
// [..., string, string] => [..., string]
// - strings are concatenated.
//
// [..., array, array]   => [..., array]
// - arrays are appended.
void vm_add(void)
{
    //TODO - maybe even + and - for dictionaries?
    pop_vals();

    switch (vm_a.k) {
        case kind_int: {
            push_int(vm_a.i + vm_b.i);
            return;
        }
        case kind_float: {
            push_float(f16_to_float(vm_a.f) + f16_to_float(vm_b.f));
            return;
        }
        case kind_string: {
            String* str1 = (String*) from_p16(vm_a.u);
            String* str2 = (String*) from_p16(vm_b.u);

            String* res = string_concat(str1, str2);
            push_val(kind_string, to_p16(res));
            return;
        }
        case kind_array: {
            Array* arr1 = (Array*) from_p16(vm_a.u);
            Array* arr2 = (Array*) from_p16(vm_b.u);
            Array* array = array_concat(arr1, arr2);
            push_array(array);
            return;
        }
        default:
            vm_die("expected numbers or strings or arrays");
    }
}

//------------------------------------------------------------------------------
// Relational operators
//

// Replaces two Values A, B with a bool Value according to their comparison by
// one of the operators op_le, op_lt, op_gt, op_ge, op_eq, or op_ne, indicating
// if the relation is true.
//
// - result is True if A op B holds,
// - otherwise False.
//
// [..., A:int, B:int]       => [..., bool]
// - numbers are compared numerically
//
// [..., A:float, B:num]       => [..., bool]
// [..., A:num, B:float]       => [..., bool]
// - if A or B is float, both are coerced to float before comparison.
//
// [..., A:string, B:string] => [..., bool]
// - strings are compared lexicographically.
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

        case kind_string:
            if (vm_a.u == vm_b.u) {
                cmp = 0;
            }
            else {
                String* str1 = (String*) from_p16(vm_a.u);
                String* str2 = (String*) from_p16(vm_b.u);
                i16 len1 = str1->len;
                i16 len2 = str2->len;
                i16 prefix_len = len1;
                if (prefix_len > len2) {
                    prefix_len = len2;
                }
                cmp = memcmp(str1->data, str2->data, prefix_len);
                if (cmp == 0 && len1 != len2) {
                    cmp = (len1 < len2) ? -1 : 1;
                }
            }
            break;

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

// Replaces numeric Value A with a positive Value of the type and magnitude.
//
// [..., A:num] => [..., num]
void fn_abs(void)
{
    vm_a = pop_num();
    if (vm_a.k == kind_int) {
        push_int((vm_a.i < 0) ? -vm_a.i : vm_a.i);
    }
    else {
        push_val(kind_float, vm_a.f & 0x7fff);
    }
}

// Replaces numeric Value A with an integer Value indicating A's sign.
//
// - result is 1 if A > 0
// - result is 0  if A = 0
// - result is -1 if A < 0
//
// [..., A:num] => [..., int]
void fn_sgn(void)
{
    vm_a = pop_num();
    if (vm_a.k == kind_int) {
        push_int(vm_a.i ? ((vm_a.i < 0) ? -1 : 1) : 0);
    }
    else {
        push_int((vm_a.f & 0x7fff) ? ((vm_a.f & 0x8000) ? -1 : 1) : 0);
    }
}

// Pushes an integer Value chosen uniformly at random from the range 0..32767.
//
// [...] => [..., int]
void fn_rnd(void)
{
    push_int(random() & 0x7fff);
}

// Replaces the numeric Value A with its positive square root as a float Value.
//
// - result is NaN if A<0.
//
// [..., A:num] => [..., float]
void fn_sqr(void)
{
    vm_a = pop_num();
    if (vm_a.k == kind_int) {
        push_float(sqrt((float) vm_a.i));
    }
    else {
        push_float(sqrt(f16_to_float(vm_a.f)));
    }
}

// Replaces the Value A with its equivalent as an integer Value.
//
// - Float values are truncated towards zero.
// - Aborts if converted value does not fit valid integer range.
//
// [..., A:int]    => [..., int]
// [..., A:float]  => [..., int]
//
// [..., A:string] => [..., int]
// - Aborts if string does not consist of an optional leading
//   sign followed by 1 or more digits and no other characters.
void fn_int(void)
{
    vm_a = pop_val();
    switch(vm_a.k) {
        case kind_int:
            push_int(vm_a.i);
            break;

        case kind_float: {
            float f = f16_to_float(vm_a.f);
            if (isnan(f)) vm_die("cannot convert NaN to int");
            if (isinf(f)) vm_die("cannot convert Inf to int");
            if (f >= 32767.0 || f < -32768.0) vm_die("overflow");
            push_int((i16) f);
            break;
        }

        case kind_string: {
            const String* str = (String*) from_p16(vm_a.u);
            u16 len = str->len;
            // number of digits in "-32768"
            if (len > 0 && len <= 6) {
                char buf[8];
                memcpy(buf, str->data, len);
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

// Replaces Value A with its equivalent as a float Value.
//
// [..., A:float]  => [..., float]
// [..., A:int]    => [..., float]
// - all numbers convert without error (although precision may be lost)
//
// [..., A:string] => [..., float]
//
// - string conversion aborts if A is not formatted as a valid float:
//   -- optional sign `+|-`
//   -- one or more digits `0-9`
//   -- optional decimal point `.` at start, middle or end
//   -- optional exponent: indicator `e|E`, optional sign `+|-`, one or more digits `0-9`
//   -- no other characters.
void fn_float(void)
{
    vm_a = pop_val();

    switch(vm_a.k) {
        case kind_int:
            push_float((float) vm_a.i);
            break;

        case kind_float:
            push_f16(vm_a.f);
            break;

        case kind_string: {
            String* str = (String*) from_p16(vm_a.u);
            u16 len = str->len;
            // reasonable upper bound for max digits
            if (len > 0 && len < 32) {
                char buf[32];
                memcpy(buf, str->data, len);
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

// Replaces string Value A with integer Value of its first character's
// ASCII ordinal.
//
// - Pushes 0 if A is empty.
//
// [..., A:string]  => [..., int]
//
// - TODO - perhaps abort if len(A) != 1 ?
void fn_asc(void)
{
    vm_a = pop_str();
    String* str = (String*) from_p16(vm_a.u);
    if (str->len == 0) push_int(0);
    else push_int(str->data[0]);
}

// Replaces integer Value A with a string Value whose only character is
// ASCII ordinal A.
//
// - TODO - abort if A is outside 0..255 ?
//
// [..., A:int] => [..., string]
void fn_chr(void)
{
    vm_a = pop_int();
    u8 ch = vm_a.u & 0xff;
    String* str = string_from_char(ch);
    push_val(kind_string, to_p16(str));
}

// Replaces A with its representation as a string Value.
//
// [..., A:any] => [..., string]
void fn_str(void)
{
    vm_a = pop_val();

    switch(vm_a.k) {
        case kind_none:
            push_val(kind_string, to_p16(interned_string_none));
            break;

        case kind_bool:
            if (vm_a.u != 0) {
                push_val(kind_string, to_p16(interned_string_true));
            } else {
                push_val(kind_string, to_p16(interned_string_false));
            }
            break;

        case kind_int: {
            u8 buf[16];
            u16 len = sprintf((char*) buf, "%d", vm_a.i);
            push_val(kind_string, to_p16(string_from_data(buf, len)));
            break;
        }

        case kind_float: {
            float f = f16_to_float(vm_a.f);
            if (isnan(f)) {
                push_val(kind_string, to_p16(interned_string_nan));
            } else if (isinf(f)) {
                push_val(kind_string, to_p16(f >= 0 ? interned_string_pos_inf : interned_string_neg_inf));
            } else {
                u8 buf[16];
                u16 len = snprintf((char*) buf, 16, "%.3g", f);
                push_val(kind_string, to_p16(string_from_data(buf, len)));
            }
            break;
        }

        case kind_string:
            push_val(vm_a.k, vm_a.u);
            break;

        case kind_array:
            push_val(kind_string, to_p16(interned_string_array));
            break;

        case kind_dict:
            push_val(kind_string, to_p16(interned_string_dict));
            break;

        // TODO - could be friendlier and produce the symbol name
        case kind_func:
            push_val(kind_string, to_p16(interned_string_func));
            break;

        case kind_class:
            push_val(kind_string, to_p16(interned_string_class));
            break;

        case kind_object:
            push_val(kind_string, to_p16(interned_string_object));
            break;

        case kind_bom:
            push_val(kind_string, to_p16(interned_string_bom));
            break;

        default:
            push_val(kind_string, to_p16(interned_string_unknown));
            break;
    }
}

// Replaces A with integer Value of how many elements it contains.
//
// [..., A:string] => [..., int] - character count
// [..., A:array]  => [..., int] - element count
// [..., A:dict]   => [..., int] - entry count
void fn_len(void)
{
    vm_a = pop_val();
    i16 n;
    switch (vm_a.k) {
        case kind_string: {
            String* str = (String*) from_p16(vm_a.u);
            n = (i16) str->len;
            break;
        }
        case kind_array: {
            Array* arr = (Array*) from_p16(vm_a.u);
            n = (i16) arr->len;
            break;
        }
        case kind_dict: {
            Dict* dict = (Dict*) from_p16(vm_a.u);
            n = (i16) dict_length(dict);
            break;
        }
        default:
            vm_die("expected string or array or dict");
    }
    push_int(n);
}

// Updates array A by appending the element B.
//
// - Leaves no result.
// - Array A is updated in-place.
//
// [..., A:array, B:any] => [...]
void vm_append(void)
{
    vm_b = pop_val();
    vm_a = pop_array();
    Array* arr = (Array*) from_p16(vm_a.u);
    array_append(arr, vm_b);
}

// Updates array A by append the elements of B.
//
// - Modifies A in-place.
// - Leaves no result.
//
// [..., A:array, B:array] => [...]
void vm_extend(void)
{
    vm_b = pop_array();
    vm_a = pop_array();
    Array* dst = (Array*) from_p16(vm_a.u);
    Array* src = (Array*) from_p16(vm_b.u);
    array_set_slice(dst, dst->len, -1, src);
}

// Removes the last element of array A, and pushes it to the stack in its place.
//
// - Aborts if A is empty.
// - Modifies A in place.
//
// [..., A:array] => [..., any]
void vm_pop(void)
{
    vm_a = pop_array();
    Array* arr = (Array*) from_p16(vm_a.u);
    Value v = array_pop(arr);
    if (v.k == kind_fail) vm_die("array empty");
    push_val(v.k, v.u);
}

//------------------------------------------------------------------------------
// Built-in procedures
//

// Prints a representation of the Value val.
void vm_print(Value val)
{
    switch(val.k) {
        case kind_none:
            printf("None");
            break;

        case kind_bool:
            printf(val.u ? "True" : "False");
            break;

        case kind_int:
            printf("%d", val.i);
            break;

        case kind_float: {
            float f = f16_to_float(val.f);
            if (isnan(f)) {
                printf("NaN");
            } else if (isinf(f)) {
                printf(f < 0 ? "-Inf" : "Inf");
            } else {
                printf("%.3g", f);
            }
            break;
        }

        case kind_string:
        {
            String* str = (String*) from_p16(val.u);
            fwrite(str->data, 1, str->len, stdout);
            break;
        }

        case kind_array:
        {
            Array* array = (Array*) from_p16(val.u);
            u16 len = array->len;
            u8* elt = array->dataptr;
            putchar('[');
            while(len--) {
                vm_print(get_value(elt));
                elt += sizeof_Value;
                if (len) putchar(',');
            }
            putchar(']');
            break;
        }

        case kind_dict:
        {
            Dict* dict = (Dict*) from_p16(val.u);
            Value key, value;
            putchar('{');
            u16 iter = dict_iter_init(dict);
            iter = dict_iter_item(dict, iter, &key, &value);
            if (iter) {
                vm_print(key);
                putchar(':');
                vm_print(value);
                while (0 != (iter = dict_iter_item(dict, iter, &key, &value))) {
                    putchar(',');
                    vm_print(key);
                    putchar(':');
                    vm_print(value);
                }
            }
            putchar('}');
            break;
        }

        // TODO - include func name?
        case kind_func: {
            Func* func = (Func*) from_p16(val.u);
            printf("<func:%04x>", func->vm_addr);
            break;
        }

        // TODO - include class name?
        case kind_class:
            printf("<class:%04x>", val.u);
            break;

        case kind_object:
            printf("<object:%04x>", val.u);
            break;

        case kind_bom:
            printf("<bound-method:%04x>", val.u);
            break;

        default:
            printf("%02x:%04x", val.k, val.u);
            break;
    }
}

// Prints <n> Values A_i of any type separated by <space> and terminated
// by <newline>.
//
// <opcode> <n:byte>
// [..., A_0..A_n-1:any] => [...]
void proc_print(void)
{
    u8 n = fetch_byte();
    vm_sp -= n * sizeof_Value;
    u8* item = from_p16(vm_sp);
    while(n--) {
        vm_print(get_value(item));
        item += sizeof_Value;
        if (n) printf(" ");
    }
    printf("\n");
}

//------------------------------------------------------------------------------
// Accessors
//

// Sets the global variable named <prop> to the Value A.
//
// <opcode> <prop:String*>
// [..., A:any] => [...]
void vm_set_global_prop(void)
{
    vm_a = pop_val();

    Value propval = {.k=kind_string, .u=fetch_word()};
    dict_set_item(vm_globals, propval, vm_a);
}

// Pushes the Value in the global variable <prop> to the stack.
//
// <opcode> <prop:String*>
// [...] => [..., any]
void vm_get_global_prop(void)
{
    vm_check_stack(sizeof_Value);

    Value propval = {.k=kind_string, .u=fetch_word()};
    Value val = dict_get_item(vm_globals, propval);
    // TODO fail check?
    push_val(val.k, val.u);
}

// Sets the current frame's <n>th slot to the Value A.
//
// <opcode> <n:word>
// [..., |frame|, A:any] => [..., |updated_frame|]
void vm_set_func_slot(void)
{
    u16 slot = fetch_word();
    vm_a = pop_val();
    u8* pslot = from_p16(vm_fp + slot * sizeof_Value);
    set_value(pslot, vm_a);
}

// Pushes the Value in the current frame's <n>th slot to the stack.
//
// <opcode> <n:word>
// [... |frame|] => [..., |frame|, any]
void vm_get_func_slot(void)
{
    vm_check_stack(sizeof_Value);

    u16 slot = fetch_word();
    u8* frame = from_p16(vm_fp + slot * sizeof_Value);
    Value item = get_value(frame);
    push_val(item.k, item.u);
}

// Returns the implicit self argument for methods (i.e. slot 0 in the frame).
//
// - Assumes the current frame is due to a method call.
// - The stack is not affected.
Object* get_self(void)
{
    u8* frame = from_p16(vm_fp + 0 * sizeof_Value);
    Value self = get_value(frame);
    return (Object*) from_p16(self.u);
}

// Sets <class>'s property named <prop> to the Value A.
//
// <opcode> <class:Class*> <prop:String*>
// [..., A:any] => [...]
void vm_set_class_prop(void)
{
    Class* klass = (Class*) fetch_ptr();
    String* prop = (String*) fetch_ptr();
    Value propval = {.k=kind_string, .u=to_p16(prop)};
    vm_a = pop_val();

    // TODO - shouldn't we check the prop is actually valid first?
    // NOTE - currently only called at compile time
    dict_set_item(klass->props, propval, vm_a);
}

void vm_get_class_prop(void)
{
    vm_die("UNUSED");
}

// Sets <class>'s method named <method> to the func Value A.
//
// <opcode> <class:Class*> <method:String*>
// [..., A:func] => [...]
void vm_set_class_method(void)
{
    Class* klass = (Class*) fetch_ptr();
    String* method = (String*) fetch_ptr();
    Value methodval = {.k=kind_string, .u=to_p16(method)};
    vm_a = pop_val();

    dict_set_item(klass->methods, methodval, vm_a);
}

// Sets the current object's <n>th slot to the Value A.
// - Assumes the current frame is due to a method call.
//
// <opcode> <n:word>
// [..., |frame|, A:any] => [..., |frame|]
void vm_set_object_slot(void)
{
    vm_a = pop_val();

    u16 slot = fetch_word();
    Object* self = get_self();
    u8* pslot = self->data + slot * sizeof_Value;
    set_value(pslot, vm_a);
}

// Pushes the Value in the <n>th slot of the current object to the stack.
// - Assumes the current frame is due to a method call.
//
// <opcode> <n:word>
// [..., |frame|] => [..., |frame|, any]
// 
void vm_get_object_slot(void)
{
    vm_check_stack(sizeof_Value);

    u16 slot = fetch_word();
    Object* self = get_self();
    u8* pslot = self->data + slot * sizeof_Value;
    Value val = get_value(pslot);
    push_val(val.k, val.u);
}

//------------------------------------------------------------------------------
// Literals
//

// Replaces <n> Values E_i with a newly allocated array Value with the E_i as
// elements.
//
// <opcode> <n:byte>
// [..., E_0..n-1:any] => [..., array]
void vm_lit_array(void)
{
    u8 nargs = fetch_byte();
    Array* array = array_new_presized(nargs, 0);
    u8* elt = array->dataptr + nargs * sizeof_Value;

    while(nargs--) {
        vm_a = pop_val();
        elt -= sizeof_Value;
        set_value(elt, vm_a);
    }

    push_array(array);
}

// Replaces <n> pairs K_i:V_i with a newly allocated dict with the K_i as keys
// and the V_i as their corresponding values.
//
// <opcode> <n:word>
// [..., K_0:key,V_0:any, ..., K_n-1,V_n-1] => [..., dict]
// - key is string|num|bool|none
void vm_lit_dict(void)
{
    u16 nargs = fetch_word();

    Dict *dict = dict_new_presized(nargs);
    vm_sp -= nargs * 2 * sizeof_Value;
    u8 *item = from_p16(vm_sp);

    while (nargs--) {
        Value key = get_value(item);
        item += sizeof_Value;
        switch (key.k) {
            case kind_none:
            case kind_bool:
            case kind_int:
            case kind_float:
            case kind_string:
                break;
            default:
                vm_die("expected string or int or float or bool or none");
        }
        Value value = get_value(item);
        item += sizeof_Value;
     
        dict_set_item(dict, key, value);
    }

    push_dict(dict);
}

// Replaces key Value K and dict Value D, with a bool Value indicating
// if the key K exists in dict D.
//
// [..., K:key, D:dict] => [..., bool]
// - key is string|num|bool|none
void vm_in(void)
{
    vm_b = pop_val();
    vm_a = pop_val();

    switch (vm_b.k) {
        case kind_array: {
            vm_die("'in' operator not implemented for arrays");
            break;
        }
        case kind_dict: {
            switch (vm_a.k) {
                case kind_none: 
                case kind_bool:
                case kind_int:
                case kind_float:
                case kind_string:
                    break;
                default:
                    vm_die("expected string or int or float or bool or none");
            }
            Dict* dict = (Dict*) from_p16(vm_b.u);
            int exists = dict_has_item(dict, vm_a);
            push_bool(exists);
            break;
        }
        default:
            vm_die("expected array or dict");
    }
}

// Replaces container Value A and index Value B with B's element at index A.
//
// [..., A:string, B:int] => [..., any]
// [..., A:array, B:int] => [..., any]
// - If B is negative, it is treated as an offset from the end of A.
// - Aborts if B is not a valid index into A.
//
// [..., A:dict, B:key] => [..., any]
// - key is string|num|bool|none
// - Pushes None if A is not a key of B.
void vm_get_index(void)
{
    vm_b = pop_val();
    vm_a = pop_val();

    switch (vm_a.k) {
        case kind_string: {
            if (vm_b.k != kind_int) {
                vm_die("expected int");
            }
            String* string = (String*)from_p16(vm_a.u);
            i16 len = string->len;
            i16 index = vm_b.i;
            if (index < 0 || index >= len) vm_die("string index out of range");
            u8 ch = string->data[index];
            String* result = string_from_char(ch);
            push_string(result);
            break;
        }
        case kind_array: {
            if (vm_b.k != kind_int) {
                vm_die("expected int");
            }

            Array* array = (Array*) from_p16(vm_a.u);
            Value elt = array_get(array, vm_b.i);
            if (elt.k == kind_fail) vm_die("array index out of range");
            push_val(elt.k, elt.u);
            break;
        }
        case kind_dict: {
            switch (vm_b.k) {
                case kind_none: 
                case kind_bool:
                case kind_int:
                case kind_float:
                case kind_string:
                    break;
                default:
                    vm_die("expected string or int or float or bool or none");
            }

            Dict* dict = (Dict*) from_p16(vm_a.u);
            Value item = dict_get_item(dict, vm_b);
            if (item.k == kind_fail) {
                push_val(kind_none, 0);
            }
            else {
                push_val(item.k, item.u);
            }
            break;
        }
        default:
            vm_die("expected string or array or dict");
    }
}

// Updates an element in collection A at index B with the value C.
//
// [..., A:array, B:int, C:any] => [...]
// - a negative index is treated as an offset from the end of A
// - aborts if B is not a valid index
//
// [..., A:dict, B:key, C:any] => [...]
// - key is string|num|bool|none
// - if C is None, the entry is removed
void vm_set_index(void)
{
    Value vm_c = pop_val();
    vm_b = pop_val();
    vm_a = pop_val();

    switch (vm_a.k) {
        case kind_array: {
            Array* array = (Array*) from_p16(vm_a.u);
            if (vm_b.k != kind_int) vm_die("expected int index");
            if (!array_set(array, vm_b.i, vm_c)) vm_die("index out of range");
            break;
        }
        case kind_dict: {
            Dict* dict = (Dict*) from_p16(vm_a.u);
            switch (vm_b.k) {
                case kind_none: 
                case kind_bool:
                case kind_int:
                case kind_float:
                case kind_string:
                    break;
                default:
                    vm_die("expected string or int or float or bool or none");
            }

            if (vm_c.k == kind_none) {
                // TODO separate del operator
                dict_delete(dict, vm_b);
            } else {
                dict_set_item(dict, vm_b, vm_c);
            }
            break;
        }
        default: vm_die("expected array or dict");
    }
}

// Replaces a class Value K and <n> property/value pairs P_i, V_i with
// a newly instantiated object Value of class K, its properties initialised
// from the corresponding P/V pairs; any properties not provided are
// initialised from their default value defined on K.
//
// <opcode> <n:byte>
// [..., K:class, P_0:string,V_0:any, ..., P_n-1,V_n-1] => [..., object]
void vm_lit_object(void)
{
    u8 nargs = fetch_byte();

    // class is buried under args...
    Value klval = get_value(from_p16(vm_sp - (2*nargs + 1) * sizeof_Value));
    if (klval.k != kind_class) {
        if (klval.k == kind_fail) vm_die("class not defined");
        vm_die("expected class");
    }
    Class* klass = (Class*) from_p16(klval.u);

    Object* object = object_new_uninited(klass);

    while(nargs--) {
        vm_b = pop_val();
        vm_a = pop_val();
        if (!object_set_prop_by_name(object, vm_a, vm_b)) {
            vm_die("property does not exist");
        }
    }
    // discard the buried class
    vm_a = pop_val();
    push_val(kind_object, to_p16(object));
}

// Pushes a bom Value that binds the method described by <func> to the current
// frame's self object. It is assumed that the class of the method and object
// are compatible.
//
// <opcode> <func:Func*>
// [..., |frame|] => [..., |frame|, bom]
void vm_lit_method(void)
{
    Func* func = (Func*) fetch_ptr();

    BoundObjectMethod* bom = (BoundObjectMethod*) heap_alloc(sizeof(BoundObjectMethod));
    bom->object = get_self();
    bom->func = func;

    push_val(kind_bom, to_p16(bom));
}

// Replaces a class or object Value by a property Value or callable.
//
// - Aborts if <name> does not refer to a property or method of A.
//
// <opcode> <name:String*>
//
// [..., A:class] => [..., any]
// [..., A:object] => [..., any]
// - if <name> refers to a property, pushes its value found on the object
//   or class A.
//
// [..., A:class] => [..., func]
// - if <name> refers to a method, pushes the method's func Value defined
//   on the object A.
//
// [..., A:object] => [..., bom]
// - if <name> refers to a method, pushes a bom Value that binds the object A
//   with the method's func Value defined on A's class.
void vm_get_prop(void)
{
    String* prop = (String*) fetch_ptr();
    Value key;
    key.k = kind_string;
    key.u = to_p16(prop);

    vm_a = pop_val();
    switch (vm_a.k) {
        case kind_class: {
            Class* class = (Class*) from_p16(vm_a.u);
            Value v = class_get_prop_by_name(class, key);
            if (v.k == kind_fail) {
                v = class_get_method_by_name(class, key);
                if (v.k == kind_fail) {
                    vm_die("property does not exist");
                }
            }
            push_val(v.k, v.u);
            break;
        }
        case kind_object: {
            Object* object = (Object*) from_p16(vm_a.u);

            Value v = object_get_prop_by_name(object, key);
            if (v.k == kind_fail) {
                v = object_bind_method_by_name(object, key);
                if (v.k == kind_fail) {
                    vm_die("property does not exist");
                }
            }
            push_val(v.k, v.u);
            break;
        }
        default: {
            vm_die("expected class or object");
        }
    }
}

// Sets the property on object A named by <prop> to the Value B.
//
// - Aborts if <prop> does not name a property on A.
//
// <opcode> <prop:String*>
// [..., A:object, B:any] => [...]
void vm_set_prop(void)
{
    String* prop = (String*) fetch_ptr();
    Value key;
    key.k = kind_string;
    key.u = to_p16(prop);

    vm_b = pop_val();
    vm_a = pop_val();

    // NOTE cannot set properties on class
    // NOTE cannot set methods on class / object
    if (vm_a.k != kind_object) vm_die("expected object");
    Object* object = (Object*) from_p16(vm_a.u);
    
    if (!object_set_prop_by_name(object, key, vm_b)) {
        vm_die("property does not exist");
    }
}

// Creates a new stack frame and initiates execution of the method named
// <method> defined on the object obj with <n> parameters P_i, and an extra
// <m> locals L_j as specified by the method's func descriptor.
//
// <opcode> <method:String*> <n:byte>
// [..., obj:object, P_0..n_1:any] =>
// [..., |obj, P_0..n-1, L_0..m-1, old_fp, old_sp, ret_pc|]
void vm_call_method(void)
{
    String* prop = (String*) fetch_ptr();
    u8 nargs = fetch_byte();

    // object is buried under args...
    Value objval = get_value(from_p16(vm_sp-(nargs+1)*sizeof_Value));
    if (objval.k != kind_object) {
        vm_die("method call on non-object");
    }

    Object* object = (Object*) from_p16(objval.u);
    Value propval;
    propval.k = kind_string;
    propval.u = to_p16(prop);
    Func* func = object_get_method(object, propval);
    if (func == 0) vm_die("method does not exist");

    // take into account 'self'
    nargs += 1;
    if (func->nargs != nargs) {
        vm_die("wrong argument count");
    }

    u16 old_fp = vm_fp;
    u16 old_sp = vm_sp - nargs * sizeof_Value;
    vm_fp = vm_sp - nargs * sizeof_Value;
    vm_sp = vm_fp;

    vm_check_stack(3 * sizeof(u16) + func->nslots * sizeof_Value);
    vm_sp = vm_sp + func->nslots * sizeof_Value;

    push_word(old_fp);
    push_word(old_sp);
    push_word(vm_pc);

    vm_pc = func->vm_addr;
}


// Initiates iteration of the collection coll, and leaves the iterator state
// on top of stack.
//
// [..., coll] => [..., coll, iter]
// - coll is an array or dict
// - iter describes the initial iteration state
void vm_iter_init(void)
{
    Value collval = pop_val();
    push_val(collval.k, collval.u);

    switch (collval.k) {
        case kind_array:
            push_int(0);
            break;
        case kind_dict: {
            Dict* dict = (Dict*) from_p16(collval.u);
            u16 it = dict_iter_init(dict);
            push_int(it);
            break;
        }
        // TODO extend to strings?
        default:
            vm_die("expected array or dict");
            break;
    }

}

// Produces the next item from the collection coll as indicated by the
// iterator iter, or indicates iteration has finished.
//
// [..., coll, iter] => [..., coll, next_iter, item, True]
// - if iter identifies an in-bounds item within coll, it is advanced
//   to next_iter, and the item and True are left on the stack.
//
// [..., coll, iter] => [..., coll, invalid, False]
// - if iter has exhausted coll, iter becomes invalid, and False is
//   left on the stack (but no item)
void vm_iter_item(void)
{
    Value itval = pop_val();
    Value collval = pop_val();
    push_val(collval.k, collval.u);

    switch (collval.k) {
        case kind_array: {
            Array* array = (Array*) from_p16(collval.u);
            i16 index = itval.i;
            if (index >= array->len) {
                push_int(0);
                push_bool(0);
            }
            else {
                Value item = array_get(array, index);
                push_int(index+1);
                push_val(item.k, item.u);
                push_bool(1);
            }
            break;
        }
        case kind_dict: {
            Value item;
            Value ignore;
            Dict* dict = (Dict*) from_p16(collval.u);
            u16 next_it = dict_iter_item(dict, itval.u, &item, &ignore);
            if (next_it == 0) {
                push_int(0);
                push_bool(0);
            }
            else {
                push_int(next_it);
                push_val(item.k, item.u);
                push_bool(1);
            }
            break;
        }
        default:
            unreachable();
    }
}
   
// Produces the next key-value pair from the collection coll as indicated
// by the iterator iter, or indicates iteration has finished.
//
// [..., coll, iter] => [..., coll, next_iter, key, value, True]
// - if iter identifies an in-bounds key-value pair within coll, it is
//   advanced to next_iter, and the pair and True are left on the stack.
//
// [..., coll, iter] => [..., coll, invalid, False]
// - if iter has exhausted coll, iter becomes invalid, and False is
//   left on the stack (but no key-value pair)
void vm_iter_kv(void)
{
    Value itval = pop_val();
    Value collval = pop_val();
    push_val(collval.k, collval.u);

    switch (collval.k) {
        case kind_array: {
            Array* array = (Array*) from_p16(collval.u);
            i16 index = itval.i;
            if (index >= array->len) {
                push_int(0);
                push_bool(0);
            }
            else {
                Value item = array_get(array, index);
                push_int(index+1);
                push_int(index);
                push_val(item.k, item.u);
                push_bool(1);
            }
            break;
        }
        case kind_dict: {
            Value key;
            Value value;
            Dict* dict = (Dict*) from_p16(collval.u);
            u16 next_it = dict_iter_item(dict, itval.u, &key, &value);
            if (next_it == 0) {
                push_int(0);
                push_bool(0);
            }
            else {
                push_int(next_it);
                push_val(key.k, key.u);
                push_val(value.k, value.u);
                push_bool(1);
            }
            break;
        }
        default:
            unreachable();
    }

}

// Checks the validity of an index enumerating a range with final value end.
//
// [..., index:int, end:int] => [..., index, end, True]
// - index is <= end, and still valid.
//
// [..., index:int, end:int] => [..., index, end, False]
// - index is > end, and not valid.
void vm_range_check(void)
{
    Value endval = pop_int();
    Value indexval = pop_int();
    push_int(indexval.i);
    push_int(endval.i);
    push_bool(indexval.i <= endval.i);
}

// Produces the current index in the enumeration of a range with final
// value end, and advances to the next index.
//
// [..., index:int, end:int] => [..., next_index, end, index]
void vm_range_next(void)
{
    Value endval = pop_int();
    Value indexval = pop_int();
    push_int(indexval.i + 1);
    push_int(endval.i);
    push_int(indexval.i);
}

// TODO move this to another file
// Adjusts start and indexes to point within the bounds of a len-element
// collection, and returns the length of the adjusted slice interval.
//
// On entry len is the length of some collection, and start and end should
// point to the start and end indexes of the desired slice. Negative indexes
// are treated as offsets from the end of the collection.
//
extern i16 slice_adjust(i16 len, i16 *start, i16 *end)
{
    if (*start < 0) *start += len;
    if (*end < 0) *end += len;

    if (*start < 0) *start = 0;
    else if (*start >= len) *start = len;

    if (*end < *start) *end = *start;
    if (*end >= len) *end = len;

    return *end - *start;
}

// Extracts elements in the range start<=index<end from coll.
// Negative indexes are counted from the end of coll.
// Where coll is either string or array.
//
// [..., coll, start?, end?] => [..., slice]
// - start is present if has_start is true,
// - end is present if has_end is true.
void vm_get_slice(u8 has_start, u8 has_end)
{
    i16 start = 0;
    i16 end = 32767;
    if (has_end) {
        vm_a = pop_int();
        end = vm_a.i;
    }
    if (has_start) {
        vm_a = pop_int();
        start = vm_a.i;
    }
    vm_a = pop_val();

    switch (vm_a.k) {
        case kind_string: {
            String* string = (String*) from_p16(vm_a.u);
            String* string2 = string_get_slice(string, start, end);
            push_string(string2);
            break;
        }
        case kind_array: {
            Array* array = (Array*) from_p16(vm_a.u);
            Array* array2 = array_get_slice(array, start, end);
            push_array(array2);
            break;
        }
        default:
            vm_die("expected string or array");
    }
}

// Elements of dst in the range start<=index<end are replaced with
// all elements from src.
// Negative indexes are counted from the end of coll.
//
// [..., dst, start?, end?, src]
// - dst and src are both strings or both arrays,
// - start is present if has_start is true,
// - end is present if has_end is true.
void vm_set_slice(u8 has_start, u8 has_end)
{
    // for expr, dst[start:end] = src
    // stack is: (tos) src | end | start | dst
    vm_a = pop_array();
    Array* src = (Array*) from_p16(vm_a.u);

    i16 start = 0;
    i16 end = 32767;
    if (has_end) {
        vm_a = pop_int();
        end = vm_a.i;
    }
    if (has_start) {
        vm_a = pop_int();
        start = vm_a.i;
    }

    vm_a = pop_array();
    Array* dst = (Array*) from_p16(vm_a.u);

    array_set_slice(dst, start, end, src);
}

//------------------------------------------------------------------------------
// Call + return handlers
//

// Prepares a new stack frame and initiates execution of <callable>'s
// bytecode with <n> parameters P_i and space for <m> locals L_j as
// specified by the callable's func descriptor.
//
// Aborts if the wrong argument count is supplied for the callable.
// Aborts if a method is called without a compatible self argument.
//
// <opcode> <n:byte>
// [..., callable, P_0..n_1] =>
// [..., |P_0..n-1, L_0..m-1, old_fp, old_sp, ret_pc|]
// - callable is a func, method, or bom
void vm_call(void)
{
    // number of args to supply to the callable
    u8 call_nargs = fetch_byte();

    // func is buried under args...
    u8 op_nargs = call_nargs+1;

    u8* callable = from_p16(vm_sp - op_nargs * sizeof_Value);
    Value callableval = get_value(callable);
    Func* func;
    switch (callableval.k) {
        case kind_func: {
            func = (Func*) from_p16(callableval.u);
            if (func->klass != 0) {
                if (call_nargs == 0) {
                    vm_die("missing 'self' argument");
                }
                Value selfval = get_value(callable+3);
                if (selfval.k != kind_object) {
                    vm_die("'self' argument is not an object");
                }
                Object* self = (Object*) from_p16(selfval.u);
                if (self->klass != func->klass) {
                    vm_die("class of 'self' argument does not match method");
                }
            }
            break;
        }
        case kind_bom: {
            // extract self, and bump arg count
            BoundObjectMethod* bom = (BoundObjectMethod*) from_p16(callableval.u);
            func = bom->func;
            Value objectval = {.k=kind_object, .u=to_p16(bom->object)};
            set_value(callable, objectval);
            call_nargs += 1;
            break;
        }
        default:
            vm_die("not callable");
    }

    if (func->nargs != call_nargs) {
        vm_die("wrong argument count");
    }

    u16 old_fp = vm_fp;
    u16 old_sp = vm_sp - op_nargs * sizeof_Value;
    vm_fp = vm_sp - call_nargs * sizeof_Value;
    vm_sp = vm_fp;

    vm_check_stack(3 * sizeof(u16) + func->nslots * sizeof_Value);
    vm_sp = vm_sp + func->nslots * sizeof_Value;

    push_word(old_fp);
    push_word(old_sp);
    push_word(vm_pc);

    vm_pc = func->vm_addr;
}

// Restores the caller's state and leaves value as the result.
//
// [..., |slots..., old_fp, old_sp, ret_pc|, value:any] =>
// [..., value]
// - fp is restored to old_fp,
// - sp is restored to old_sp,
// - execution continues at ret_pc.
void vm_return(void)
{
    vm_a = pop_val();

    u16 old_pc = pop_word();
    u16 old_sp = pop_word();
    u16 old_fp = pop_word();

    vm_fp = old_fp;
    vm_sp = old_sp;
    push_val(vm_a.k, vm_a.u);
    vm_pc = old_pc;
}

// Restores the caller's state, and leaves None as the result value.
//
// [..., |slots..., old_fp, old_sp, ret_pc|, None] =>
// [..., value]
// - fp is restored to old_fp,
// - sp is restored to old_sp,
// - execution continues at ret_pc.
void vm_return_none(void)
{
    u16 old_pc = pop_word();
    u16 old_sp = pop_word();
    u16 old_fp = pop_word();

    vm_fp = old_fp;
    vm_sp = old_sp;
    push_val(kind_none, 0);
    vm_pc = old_pc;
}

//------------------------------------------------------------------------------
// Entry point
//

// Execute the compiled byte code starting at vm_pc_start.
u16 vm_run(const u8 *vm_pc_start)
{
    if (opt_trace_vm) {
        fprintf(stderr, "\nRUNNING\n");
    }

    vm_sp = to_p16(vm_stack_base);
    vm_sp_max = vm_sp + vm_stack_max;
    vm_fp = vm_sp;
    vm_pc = to_p16(vm_pc_start);
    vm_globals = dict_new();

    while(1) {
        if (opt_trace_vm) {
            fprintf(stderr, "pc=%04x fp=%04x sp=%04x ", vm_pc, vm_fp, vm_sp);
        }
        Op op = (Op) fetch_byte();
        if (opt_trace_vm) {
            fprintf(stderr, "%s\n", debug_op_name(op));
        }

        switch(op) {
            // arithmetic operators
            case op_neg: vm_neg(); break;
            case op_mul: vm_mul(); break;
            case op_div: vm_div(); break;
            case op_add: vm_add(); break;
            case op_sub: vm_sub(); break;
            case op_mod: vm_mod(); break;

            // relational operators
            case op_le:
            case op_lt:
            case op_gt:
            case op_ge:
            case op_eq:
            case op_ne:
                vm_relop(op);
                break;

            // existence
            case op_in: vm_in(); break;

            // bitwise operators
            case op_bnot:   vm_a = pop_int(); push_int(~vm_a.i); break;
            case op_band:   pop_ints(); push_int(vm_a.u & vm_b.u); break;
            case op_bor:    pop_ints(); push_int(vm_a.u | vm_b.u); break;
            case op_beor:   pop_ints(); push_int(vm_a.u ^ vm_b.u); break;

            // shift operators
            case op_lsr:
                pop_ints();
                if (vm_b.i >= 0) {
                    push_int(vm_b.i < 16 ? (vm_a.u >> vm_b.i) : 0);
                } else {
                    vm_b.i = -vm_b.i;
                    push_int(vm_b.i < 16 ? (vm_a.u << vm_b.i) : 0);
                }
                break;

            case op_lsl:
                pop_ints();
                if (vm_b.i >= 0) {
                    push_int(vm_b.i < 16 ? (vm_a.u << vm_b.i) : 0);
                } else {
                    vm_b.i = -vm_b.i;
                    push_int(vm_b.i < 16 ? (vm_a.u >> vm_b.i) : 0);
                }
                break;

            // logical operators
            case op_lnot: 
                vm_a = pop_bool();
                push_bool(!vm_a.u);
                break;

            case op_land: 
                vm_b = pop_val();
                vm_a = pop_val();
                if (vm_a.k == kind_none || (vm_a.k == kind_bool && !vm_a.u)) {
                    push_val(vm_a.k, vm_a.u); 
                }
                else {
                    push_val(vm_b.k, vm_b.u); 
                }
                break;

            case op_lor:
                vm_b = pop_val(); 
                vm_a = pop_val();
                if (vm_a.k == kind_none || (vm_a.k == kind_bool && !vm_a.u)) {
                    push_val(vm_b.k, vm_b.u); 
                }
                else {
                    push_val(vm_a.k, vm_a.u); 
                }
                break;

            // constants
            case op_none:   push_val_checked(kind_none, 0); break;
            case op_false:  push_val_checked(kind_bool, 0); break;
            case op_true:   push_val_checked(kind_bool, 1); break;
            case op_inf:    push_val_checked(kind_float, f16_from_float(1.0 / 0.0)); break;
            case op_nan:    push_val_checked(kind_float, f16_from_float(0.0 / 0.0)); break;

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

            // array functions
            case op_append: vm_append(); break;
            case op_pop:    vm_pop(); break;
            case op_extend: vm_extend(); break;

            // built-in procedures
            case op_print:  proc_print(); break;
            case op_input:  vm_die("input: unimplemented"); break;
            case op_stop:   return 1;

            // accessors
            case op_get_global_prop:  vm_get_global_prop(); break;
            case op_set_global_prop:  vm_set_global_prop(); break;
            case op_get_func_slot:    vm_get_func_slot(); break;
            case op_set_func_slot:    vm_set_func_slot(); break;
            case op_get_class_prop:   vm_get_class_prop(); break; // TODO unused?
            case op_set_class_prop:   vm_set_class_prop(); break;
            case op_set_class_method: vm_set_class_method(); break;
            case op_get_object_slot:  vm_get_object_slot(); break;
            case op_set_object_slot:  vm_set_object_slot(); break;

            case op_lit_int:    push_val_checked(kind_int, fetch_word()); break;
            case op_lit_float:  push_val_checked(kind_float, fetch_word()); break;
            case op_lit_string: push_val_checked(kind_string, fetch_word()); break;
            case op_lit_array:  vm_lit_array(); break;
            case op_lit_dict:   vm_lit_dict(); break;
            case op_lit_object: vm_lit_object(); break;
            case op_lit_class:  push_val_checked(kind_class, fetch_word()); break;
            case op_lit_func:   push_val_checked(kind_func, fetch_word()); break;
            case op_lit_method: vm_lit_method(); break;

            case op_get_index:          vm_get_index(); break;
            case op_get_slice:          vm_get_slice(1, 1); break;
            case op_get_slice_start:    vm_get_slice(1, 0); break;
            case op_get_slice_end:      vm_get_slice(0, 1); break;
            case op_get_slice_empty:    vm_get_slice(0, 0); break;

            case op_set_index:          vm_set_index(); break;
            case op_set_slice:          vm_set_slice(1, 1); break;
            case op_set_slice_start:    vm_set_slice(1, 0); break;
            case op_set_slice_end:      vm_set_slice(0, 1); break;
            case op_set_slice_empty:    vm_set_slice(0, 0); break;
            
            case op_get_prop:           vm_get_prop(); break;
            case op_set_prop:           vm_set_prop(); break;
            case op_call_method:        vm_call_method(); break;

            case op_iter_init:          vm_iter_init(); break;
            case op_iter_item:          vm_iter_item(); break;
            case op_iter_kv:            vm_iter_kv(); break;
            case op_range_check:        vm_range_check(); break;
            case op_range_next:         vm_range_next(); break;

            // call + return
            case op_call:           vm_call(); break;
            case op_return:         vm_return(); break;
            case op_return_none:    vm_return_none(); break;
            case op_drop:           pop_val(); break;
            case op_drop2:          pop_val(); pop_val(); break;

            // jumps
            case op_jump: {
                u16 tmp = fetch_word();
                vm_pc += tmp;
                break;
            }
            case op_jfalse: {
                u16 tmp = fetch_word();
                vm_a = pop_bool();
                if (vm_a.u == 0) vm_pc += tmp;
                break;
            }

            default:
                fprintf(stderr, "opcode=0x%02x\n", op);
                vm_die("unknown opcode");
                break;
        }
    }
}

