#include <math.h>
#include "header.h"

u16 f16_from_float(float f)
{
    if (isnan(f)) return 0x7e00;

    u16 sign = signbit(f) ? 0x8000:0;
    if (isinf(f)) return sign|0x7c00;
    if (f==0.0f)  return sign|0x0000;

    unsigned long fbits = *(unsigned long*)&f;
    int exp = ((fbits>>23) & 0xff) - 112;
    if (exp > 30) return sign|0x7c00;
    u16 fra = (fbits>>13) & 0x03ff;
    if (exp >= 1) return sign|(exp<<10)|fra;
    fra |= 0x0400;
    for(; exp < 1; exp++) fra >>= 1;
    return sign|fra;
}

float f16_to_float(u16 u)
{
    unsigned long lu = u;
    unsigned long bits = (lu & 0x8000) << 16;
    lu &= 0x7fff;
    if (lu != 0) {
        if (lu >= 0x7c00) bits |= 0x70000000;
        else {
            unsigned long adj = 112;
            while(lu < 0x0200) { lu <<= 1; adj -= 1; }
            lu += adj<<10;
        }
        bits |= lu << 13;
    }
    return *(float*) &bits;
}

