#include "softfloat.h"
#include <stdio.h>
#include <stdlib.h>

#define OPERATION f16_sub
#define QUOTED_OP "f16_sub"

const uint16_t f16_zero      = 0x0000; // 0
const uint16_t f16_min_sub   = 0x0001; // smallest subnormal
const uint16_t f16_max_sub   = 0x03ff; // largest subnormal
const uint16_t f16_min_norm  = 0x0400; // smallest normal
const uint16_t f16_one       = 0x3c00; // 1
const uint16_t f16_one_eps   = 0x3c01; // 1+epsilon
const uint16_t f16_two       = 0x4000; // 2
const uint16_t f16_three     = 0x4200; // 3
const uint16_t f16_max       = 0x7bff; // largest finite number
const uint16_t f16_inf       = 0x7c00; // infinity
const uint16_t f16_min_nan   = 0x7c01; // smallest valid NaN
const uint16_t f16_qnan      = 0x7e00; // smallest quiet NaN
const uint16_t f16_max_nan   = 0x7fff; // largest valid NaN
const uint16_t f16_neg       = 0x8000; // negative sign bit

struct {
    const char *label;
    uint16_t value;
} values[26] = {
    {"+zero",     f16_zero    },  
    {"+min_sub",  f16_min_sub },  
    {"+max_sub",  f16_max_sub },  
    {"+min_norm", f16_min_norm},  
    {"+one",      f16_one     },  
    {"+one_eps",  f16_one_eps },  
    {"+two",      f16_two     },  
    {"+three",    f16_three   },  
    {"+max",      f16_max     },  
    {"+inf",      f16_inf     },  
    {"+min_nan",  f16_min_nan },  
    {"+qnan",     f16_qnan    },  
    {"+max_nan",  f16_max_nan },  

    {"-zero",     f16_neg|f16_zero    },
    {"-min_sub",  f16_neg|f16_min_sub },
    {"-max_sub",  f16_neg|f16_max_sub },
    {"-min_norm", f16_neg|f16_min_norm},
    {"-one",      f16_neg|f16_one     },
    {"-one_eps",  f16_neg|f16_one_eps },
    {"-two",      f16_neg|f16_two     },
    {"-three",    f16_neg|f16_three   },
    {"-max",      f16_neg|f16_max     },
    {"-inf",      f16_neg|f16_inf     },
    {"-min_nan",  f16_neg|f16_min_nan },
    {"-qnan",     f16_neg|f16_qnan    },
    {"-max_nan",  f16_neg|f16_max_nan }
};

int main()
{
    softfloat_roundingMode = softfloat_round_near_even;
    softfloat_exceptionFlags = 0;
    softfloat_detectTininess = softfloat_tininess_beforeRounding;

    srandom(11111);

    float16_t a, b, z;
    uint16_t label = 0;

    //
    // Generate a total of 2000 test cases
    //
    printf(".unit_test_data\n");
    printf("    dw ." QUOTED_OP "\n");

    printf("\n");
    printf("    ; Special values\n");
    for(int i=0; i<26; i++) {
        for(int j=0; j<26; j++) {
            a.v = values[i].value;
            b.v = values[j].value;
            z = OPERATION(a, b);
            if (!f16_eq(z, z)) z.v = f16_qnan;    // convert any NaN to lowest quiet NaN
            printf("    dw 0x%04x, 0x%04x, 0x%04x, 0x%04x   ;   %-10s %s\n", label++, a.v, b.v, z.v, values[i].label, values[j].label);
        }
    }

    printf("\n");
    printf("    ; Random values\n");
    for(int i=0; i<1324; i++) {
        uint16_t r, s;
        do r = (uint16_t) random(); while((r & ~f16_neg) >= f16_inf);
        do s = (uint16_t) random(); while((s & ~f16_neg) >= f16_inf);
        a.v = r;
        b.v = s;
        z = OPERATION(a, b);
        if (!f16_eq(z, z)) z.v = f16_qnan;    // convert any NaN to lowest quiet NaN
        printf("    dw 0x%04x, 0x%04x, 0x%04x, 0x%04x\n", label++, a.v, b.v, z.v);
    }

    printf(".unit_test_end\n");

    return 0;
}
