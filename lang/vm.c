#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "header.h"
#include "dict.h"
#include "array.h"
#include "object.h"

// TODO? - a top-of-stack register to reduce number of push/pop sequences
// TODO - heap cleanup (e.g. ref counts)

bool opt_trace_vm = false;

Value vm_a;
Value vm_b;

u16 vm_sp;
u16 vm_fp;
u16 vm_pc;

u16 vm_sp_max; // not a register

//------------------------------------------------------------------------------
// Utilities
//

void vm_die(const char* msg)
{
    fprintf(stderr, "RUNTIME ERROR: %s!\n", msg);
    exit(1);
}

extern Value get_value(const u8* p)
{
    return (Value){.k = *p, .u = *(u16*)(p+1)};
}

extern void set_value(u8* p, Value v)
{
    *p = v.k;
    *(u16*)(p+1) = v.u;
}

//------------------------------------------------------------------------------
// Instruction stream
//

u8 fetch_byte()
{
    u8 b = *from_p16(vm_pc);
    vm_pc += 1;
    return b;
}

u16 fetch_word()
{
    u16 w = *(u16*) from_p16(vm_pc);
    vm_pc += sizeof(u16);
    return w;
}

u8* fetch_ptr()
{
    return from_p16(fetch_word());
}

//------------------------------------------------------------------------------
// Stack handling
//

void push_byte(u8 b)
{
    *from_p16(vm_sp) = b;
    vm_sp += 1;
}

void push_word(u16 w)
{
    *(u16*) from_p16(vm_sp) = w;
    vm_sp += sizeof(u16);
}

void push_val(Kind kind, u16 value)
{
    push_byte((u8) kind);
    push_word(value);
}

void push_bool(u16 b)
{
    push_val(kind_bool, (b==0) ? 0 : 1);
}

void push_int(i16 i)
{
    push_val(kind_int, i);
}

void push_f16(u16 f)
{
    push_val(kind_float, f);
}

void push_float(float f)
{
    push_f16(f16_from_float(f));
}

void push_string(String* s)
{
    push_val(kind_string, to_p16(s));
}

void push_array(Array* a)
{
    push_val(kind_array, to_p16(a));
}

void push_dict(Dict* d)
{
    push_val(kind_dict, to_p16(d));
}

void vm_check_stack(u16 n)
{
    if (vm_sp > vm_sp_max-n) vm_die("stack overflow");
}

void push_val_checked(Kind kind, u16 value)
{
    vm_check_stack(sizeof_Value);

    push_val(kind, value);
}

u8 pop_byte()
{
    vm_sp -= 1;
    return *from_p16(vm_sp);
}

u16 pop_word()
{
    vm_sp -= 2;
    return *(u16*) from_p16(vm_sp);
}

void pop_val()
{
    vm_a.u = pop_word();
    vm_a.k = pop_byte();
}

void pop_bool()
{
    pop_val();
    // convert None, False to False, everything else to True
    if (vm_a.k != kind_bool) {
        vm_a.u = vm_a.k != kind_none;
        vm_a.k = kind_bool;
    }
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
        vm_a.f = f16_from_float((float) vm_a.i);
    }
    else {
        vm_b.k = kind_float;
        vm_b.f = f16_from_float((float) vm_b.i);
    }
}

void pop_str()
{
    pop_val();
    if (vm_a.k != kind_string) vm_die("expected string");
}

void pop_array()
{
    pop_val();
    if (vm_a.k != kind_array) vm_die("expected array");
}

void pop_dict()
{
    pop_val();
    if (vm_a.k != kind_dict) vm_die("expected dict");
}

void pop_vals()
{
    pop_val();
    vm_b = vm_a;
    pop_val();

    if (vm_a.k == vm_b.k) return;
    if (vm_a.k == kind_int && vm_b.k == kind_float) {
        vm_a.k = kind_float;
        vm_a.f = f16_from_float((float) vm_a.i);
        return;
    }
    else if (vm_a.k == kind_float && vm_b.k == kind_int) {
        vm_b.k = kind_float;
        vm_b.f = f16_from_float((float) vm_b.i);
        return;
    }

    vm_die("incompatible types");
}

//------------------------------------------------------------------------------
// Arithmetic operators
//

void vm_add()
{
    //TODO - maybe even + and - for dictionaries?
    pop_vals();

    switch (vm_a.k) {
        case kind_int: {
            // TODO check overflow?
            push_int(vm_a.i + vm_b.i);
            return;
        }
        case kind_float: {
            push_float(f16_to_float(vm_a.f) + f16_to_float(vm_b.f));
            return;
        }
        case kind_string: {
            String* str1 = (String*) from_p16(vm_a.u);
            if (str1->len == 0) {
                push_val(vm_b.k, vm_b.u);
                return;
            }

            String* str2 = (String*) from_p16(vm_b.u);
            if (str2->len == 0) {
                push_val(vm_a.k, vm_a.u);
                return;
            }

            i16 len = str1->len + str2->len;
            String* str = (String*) heap_alloc(sizeof(String) + len);
            str->len = len;

            u8* ptr = str->data;
            memcpy(ptr, str1->data, str1->len);
            ptr += str1->len;
            memcpy(ptr, str2->data, str2->len);

            push_val(kind_string, to_p16(str));
            return;
        }
        case kind_array: {
            Array* arr1 = (Array*) from_p16(vm_a.u);
            Array* arr2 = (Array*) from_p16(vm_b.u);
            Array* array = array_append(arr1, arr2);
            push_array(array);
            return;
        }
        default:
            die("expected numbers or strings or arrays");
    }
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
        push_float(sqrt((float) vm_a.i));
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
            push_int((i16) f16_to_float(vm_a.f));
            break;

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

void fn_float()
{
    pop_val();

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

void fn_asc()
{
    pop_str();
    String* str = (String*) from_p16(vm_a.u);
    if (str->len == 0) push_int(0);
    else push_int(str->data[0]);
}

void fn_chr()
{
    pop_int();
    u8 ch = vm_a.u & 0xff;
    String* str = string_from_char(ch);
    push_val(kind_string, to_p16(str));
}

void fn_str()
{
    pop_val();
    u8 buf[16];
    u16 len;
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
            return;

        case kind_int:
            len = sprintf((char*) buf, "%d", vm_a.i);
            break;

        case kind_float:
            len = sprintf((char*) buf, "%f", f16_to_float(vm_a.f));
            break;

        case kind_string:
            push_val(vm_a.k, vm_a.u);
            return;

        case kind_array:
            push_val(kind_string, to_p16(interned_string_array));
            return;

        case kind_dict:
            push_val(kind_string, to_p16(interned_string_dict));
            return;

        // TODO - could be friendlier and produce the symbol name
        case kind_func:
            push_val(kind_string, to_p16(interned_string_func));
            return;

        case kind_class:
            push_val(kind_string, to_p16(interned_string_class));
            return;

        case kind_object:
            push_val(kind_string, to_p16(interned_string_object));
            return;

        default:
            push_val(kind_string, to_p16(interned_string_unknown));
            return;
    }

    push_val(kind_string, to_p16(string_from_data(buf, len)));
}

void fn_len()
{
    pop_val();
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
            die("expected string or array or dict");
        }
        push_int(n);
}

// TODO - add push, pop for arrays and slice assignment

// TODO - all of substr, left, right can be done away
// with now that we can slice strings...
void vm_substr(u16 pos, u16 n);
void vm_substr_helper(String* str, u16 pos, u16 n, u16 len);

void fn_left()
{
    pop_int();
    i16 ni = vm_a.i;
    if (ni < 0) vm_die("negative count");

    vm_substr(0, (u16) ni);
}

void fn_right()
{
    pop_int();
    i16 ni = vm_a.i;
    if (ni < 0) vm_die("negative count");
    u16 n = (u16) ni;

    pop_str();

    String* str = (String*) from_p16(vm_a.u);
    u16 len = str->len;
    if (n >= len) {
        n = len;
    }
    u16 pos = len - n;

    return vm_substr_helper(str, pos, n, len);
}

void fn_substr()
{
    pop_int();
    i16 ni = vm_a.i;
    if (ni < 0) vm_die("negative count");

    pop_int();
    i16 posi = vm_a.i;
    if (posi < 0) vm_die("negative offset");

    vm_substr((u16) posi, (u16) ni);
}

void vm_substr(u16 pos, u16 n)
{
    pop_str();

    String* str = (String*) from_p16(vm_a.u);

    vm_substr_helper(str, pos, n, str->len);
}

void vm_substr_helper(String* str, u16 pos, u16 n, u16 len)
{
    if (pos == 0 && n >= len) {
        push_val(kind_string, vm_a.u);
        return;
    }

    u16 len2 = len-pos;
    if (n < len2) len2 = n;

    String* str2 = string_from_data(str->data+pos, len2);
    push_val(kind_string, to_p16(str2));
}

//------------------------------------------------------------------------------
// Built-in procedures
//

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

        case kind_float:
            printf("%f", f16_to_float(val.f));
            break;

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
            u8* elt = from_p16(array->dataptr);
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
            printf("<func:%04x>", func->addr);
            break;
        }

        // TODO - include class name?
        case kind_class:
            printf("<class:%04x>", val.u);
            break;

        case kind_object:
            printf("<object:%04x>", val.u);
            break;

        case kind_ident: {
            Ident* ident = (Ident*) from_p16(val.u);
            String* name = (String*) from_p16(ident->nameptr);
            printf("<ident:%.*s>", name->len, name->data);
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

void vm_ident_set()
{
    Ident* ident = (Ident*) fetch_ptr();
    pop_val();
    ident->val = vm_a;
}

void vm_ident_get()
{
    vm_check_stack(sizeof_Value);

    Ident* ident = (Ident*) fetch_ptr();
    push_val(ident->val.k, ident->val.u);
}

void vm_slot_set()
{
    u8 slot = fetch_byte();
    pop_val();
    u8* pslot = from_p16(vm_fp + slot * sizeof_Value);
    set_value(pslot, vm_a);
}


///////////////!!!!!!!!!!!!!!!!////////////////
//
void vm_slot_get()
{
    vm_check_stack(sizeof_Value);

    u8 slot = fetch_byte();
    u8* frame = from_p16(vm_fp + slot * sizeof_Value);
    Value item = get_value(frame);
    push_val(item.k, item.u);
}

void vm_lit_array()
{
    u8 nargs = fetch_byte();
    Array* array = array_new_presized(nargs, 0);
    u8* elt = from_p16(array->dataptr + nargs * sizeof_Value);

    while(nargs--) {
        pop_val();
        elt -= sizeof_Value;
        set_value(elt, vm_a);
    }

    push_array(array);
}

void vm_lit_dict()
{
    u16 nargs = fetch_word();

    Dict *dict = dict_new_presized(nargs);
    vm_sp -= nargs * 2 * sizeof_Value;
    u8 *item = from_p16(vm_sp);

    while (nargs--) {
        Value key = get_value(item);
        item += sizeof_Value;
        Value value = get_value(item);
        item += sizeof_Value;
     
        dict_set_item(dict, key, value);
    }

    push_dict(dict);
}

void vm_in()
{
    pop_val();
    vm_b = vm_a;
    pop_val();

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
                    die("expected string or int or float or bool or none");
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

void vm_get_index()
{
    pop_val();
    vm_b = vm_a;
    pop_val();

    switch (vm_a.k) {
        case kind_string: {
            if (vm_b.k != kind_int) {
                die("expected int");
            }
            String* string = (String*)from_p16(vm_a.u);
            i16 len = string->len;
            i16 index = vm_b.i;
            if (index < 0 || index >= len) die("string index out of range");
            u8 ch = string->data[index];
            String* result = string_from_char(ch);
            push_string(result);
            break;
        }
        case kind_array: {
            if (vm_b.k != kind_int) {
                die("expected int");
            }

            Array* array = (Array*) from_p16(vm_a.u);
            i16 len = (i16) array->len;

            i16 index = vm_b.i;
            if (index < 0) index += len;
            if (index < 0 || index >= len) die("array index out of range");

            Value elt = get_value(from_p16(array->dataptr + index * sizeof_Value));
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
                    die("expected string or int or float or bool or none");
            }

            Dict* dict = (Dict*) from_p16(vm_a.u);
            Value item = dict_get_item(dict, vm_b);
            if (item.k == kind_fail) {
                push_bool(0);
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

void vm_set_index()
{
    // stack is (tos) value | index | container
    pop_val();
    Value vm_c = vm_a;

    pop_val();
    vm_b = vm_a;

    pop_val();

    switch (vm_a.k) {
        case kind_array: {
            Array* array = (Array*) from_p16(vm_a.u);
            if (vm_b.k != kind_int) die("expected int index");
            i16 len = array->len;
            i16 index = vm_b.i;
            if (index < 0) index += len;
            if (index < 0 || index >= len) vm_die("index out of range");

            set_value(from_p16(array->dataptr + index * sizeof_Value), vm_c);
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
                    die("expected string or int or float or bool or none");
            }

            if (vm_c.k == kind_none) {
                // TODO separate del operator
                dict_delete(dict, vm_b);
            } else {
                dict_set_item(dict, vm_b, vm_c);
            }
            break;
        }
        default: die("expected array or dict");
    }
}

void vm_lit_object()
{
    u8 nargs = fetch_byte();

    // class is buried under args...
    Value klval = get_value(from_p16(vm_sp - (2*nargs + 1) * sizeof_Value));
    if (klval.k != kind_class) {
        if (klval.k == kind_fail) die("class not defined");
        die("expected class");
    }
    Class* klass = (Class*) from_p16(klval.u);

    Object* object = object_new(klass, nargs);

    while(nargs--) {
        pop_val();
        vm_b = vm_a;
        pop_val();
        object_set_prop(object, vm_a, vm_b);
    }
    // discard the buried class
    pop_val();
    push_val(kind_object, to_p16(object));
}

void vm_get_prop()
{
    String* name = (String*) fetch_ptr();
    Value key;
    key.k = kind_string;
    key.u = to_p16(name);

    pop_val();
    if (vm_a.k != kind_object) die("expected object");
    Object* object = (Object*) from_p16(vm_a.u);

    Value v = object_get_prop(object, key);
    if (v.k == kind_fail) die("property does not exist");

    push_val(v.k, v.u);
}

void vm_set_prop()
{
    String* name = (String*) fetch_ptr();
    Value key;
    key.k = kind_string;
    key.u = to_p16(name);

    pop_val();
    vm_b = vm_a;

    pop_val();
    if (vm_a.k != kind_object) die("expected object");
    Object* object = (Object*) from_p16(vm_a.u);
    
    object_set_prop(object, key, vm_b);
}

void vm_call_method()
{
    String* name = (String*) fetch_ptr();
    u8 nargs = fetch_byte();

    // object is buried under args...
    Value objval = get_value(from_p16(vm_sp-(nargs+1)*sizeof_Value));
    if (objval.k != kind_object) {
        die("method call on non-object");
    }

    Object* object = (Object*) from_p16(objval.u);
    Value name_val;
    name_val.k = kind_string;
    name_val.u = to_p16(name);
    Func* func = object_get_method(object, name_val);
    if (func == 0) die("method does not exist");

    // take into account 'self'
    nargs += 1;
    if (func->args != nargs) {
        vm_die("wrong argument count");
    }

    u16 old_fp = vm_fp;
    u16 old_sp = vm_sp - nargs * sizeof_Value;
    vm_fp = vm_sp - nargs * sizeof_Value;
    vm_sp = vm_fp;

    vm_check_stack(3 * sizeof(u16) + func->slots * sizeof_Value);
    vm_sp = vm_sp + func->slots * sizeof_Value;

    push_word(old_fp);
    push_word(old_sp);
    push_word(vm_pc);

    vm_pc = func->addr;
}

extern void slice_adjust(i16 *start, i16 *end, i16 *len)
{
    if (*start < 0) *start += *len;
    if (*end < 0) *end += *len;

    if (*start < 0) *start = 0;
    else if (*start >= *len) *start = *len;

    if (*end < *start) *end = *start;
    if (*end >= *len) *end = *len;

    *len = *end - *start;
}

void vm_get_slice(u8 has_start, u8 has_end)
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
    pop_val();

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
            die("expected string or array");
    }
}

void vm_set_slice(u8 has_start, u8 has_end)
{
    // for expr, dst[start:end] = src
    // stack is: (tos) src | end | start | dst
    pop_array();
    Array* src = (Array*) from_p16(vm_a.u);

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
    Array* dst = (Array*) from_p16(vm_a.u);

    array_set_slice(dst, start, end, src);
}

//------------------------------------------------------------------------------
// Call + return handlers
//

void vm_call()
{
    u8 nargs = fetch_byte();

    // func is buried under args...
    Value funval = get_value(from_p16(vm_sp - (nargs+1) * sizeof_Value));
    if (funval.k != kind_func) {
        if (funval.k == kind_fail) die("func/proc not defined");
        die("bad call");
    }
    Func* func = (Func*) from_p16(funval.u);

    if (func->args != nargs) {
        vm_die("wrong argument count");
    }

    u16 old_fp = vm_fp;
    u16 old_sp = vm_sp - (nargs+1) * sizeof_Value;
    vm_fp = vm_sp - nargs * sizeof_Value;
    vm_sp = vm_fp;

    vm_check_stack(3 * sizeof(u16) + func->slots * sizeof_Value);
    vm_sp = vm_sp + func->slots * sizeof_Value;

    push_word(old_fp);
    push_word(old_sp);
    push_word(vm_pc);

    vm_pc = func->addr;
}

void vm_return()
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

void vm_return_none()
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

u16 vm_run(const u8 *vm_pc_start)
{
    if (opt_trace_vm) {
        fprintf(stderr, "\nRUNNING\n");
    }

    vm_sp = to_p16(vm_stack_base);
    vm_sp_max = vm_sp + vm_stack_max;
    vm_fp = vm_sp;
    vm_pc = to_p16(vm_pc_start);

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

            // existence
            case op_in: vm_in(); break;

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
            case op_lnot: 
                pop_bool();
                push_bool(!vm_a.u);
                break;

            case op_land: 
                pop_val();
                vm_b = vm_a;
                pop_val();
                if (vm_a.k == kind_none || vm_a.k == kind_bool && !vm_a.u) {
                    push_val(vm_a.k, vm_a.u); 
                }
                else {
                    push_val(vm_b.k, vm_b.u); 
                }
                break;

            case op_lor:
                pop_val(); 
                vm_b = vm_a;
                pop_val();
                if (vm_a.k == kind_bool && !vm_a.u || vm_a.k == kind_none) {
                    push_val(vm_b.k, vm_b.u); 
                }
                else {
                    push_val(vm_a.k, vm_a.u); 
                }
                break;

            // constants
            case op_none:   push_val(kind_none, 0); break;
            case op_false:  push_bool(0); break;
            case op_true:   push_bool(1); break;
            case op_inf:    push_float(1.0 / 0.0); break;
            case op_nan:    push_float(0.0/ 0.0); break;

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
            case op_lit_string: push_val_checked(kind_string, fetch_word()); break;
            case op_lit_array:  vm_lit_array(); break;
            case op_lit_dict:   vm_lit_dict(); break;
            case op_lit_ident:  push_val_checked(kind_ident, fetch_word()); break;
            case op_lit_object: vm_lit_object(); break;

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

            // call + return
            case op_call:           vm_call(); break;
            case op_return:         vm_return(); break;
            case op_return_none:    vm_return_none(); break;

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
                fprintf(stderr, "opcode=0x%02x\n", op);
                vm_die("unknown opcode");
                break;
        }
    }
}

