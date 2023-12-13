#include <stdio.h>
#include <math.h>
#include <string.h>

#define numof(a) (sizeof(a)/sizeof((a)[0]))

typedef int bool;
const bool false = 0;
const bool true = 1;
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned u32;
typedef unsigned long long u64;

const int prec = 11;
const int emin = 1;     // biased value
const int emax = 30;    // biased value
const int bias = 15;
//const int sign = 1;
const int ebits = 5;
const int mbits = 10;
const int bits = 1 + ebits + mbits;

const u16 exp_zero_sub = 0;
const u16 exp_nan_inf = (1<<ebits)-1;

const u16 neg_max_nan   = 0xffff;
const u16 neg_min_nan   = 0xfc01;
const u16 neg_inf       = 0xfc00;
const u16 neg_max       = 0xfbff;
const u16 neg_three     = 0xc200;
const u16 neg_two       = 0xc000;
const u16 neg_one_eps   = 0xbc01;
const u16 neg_one       = 0xbc00;
const u16 neg_min_norm  = 0x8400;
const u16 neg_max_sub   = 0x83ff;
const u16 neg_min_sub   = 0x8001;
const u16 neg_zero      = 0x8000;

const u16 pos_zero      = 0x0000;
const u16 pos_min_sub   = 0x0001;
const u16 pos_max_sub   = 0x03ff;
const u16 pos_min_norm  = 0x0400;
const u16 pos_one       = 0x3c00;
const u16 pos_one_eps   = 0x3c01;
const u16 pos_two       = 0x4000;
const u16 pos_three     = 0x4200;
const u16 pos_max       = 0x7bff;
const u16 pos_inf       = 0x7c00;
const u16 pos_min_nan   = 0x7c01;
const u16 pos_max_nan   = 0x7fff;

// NaNs - given the following constraints, bits 7:0 are available for an 8-bit custom payload
const u16 snan          = 0x7d00;   // signalling - highest payload bit is clear, next bit is set to avoid confusion with inf
const u16 qnan          = 0x7e00;   // quiet      - highest payload bit is set

typedef int order;
const order order_lt = -1;
const order order_eq = 0;
const order order_gt = 1;
const order order_un = 2; // unordered

// exp==0,  fra==0 => value = +- 0
// exp==0,  fra!=0 => value = +- 0.fra * 2^-14
// exp==31, fra==0 => value = +- inf
// exp==31, fra!=0 => value = NaN
typedef union
{
    u16 bits;
    struct {
        u16 fra: 10; // bits 0-9
        u16 exp: 5;  // bits 10-14  ; +15 bias: 0=zero_or_sub, 1=-14 ... 15=0 ... 30=+15, 31=inf_or_nan
        u16 sign: 1; // bit  15     ; 0=positive, 1=negative
    };
} f16;

// General operations
bool isSignMinus(f16 x)  { return x.sign == 1; }
bool isSignPlus(f16 x)   { return x.sign == 0; }
bool isNormal(f16 x)     { return x.exp != exp_zero_sub && x.exp != exp_nan_inf; }
bool isFinite(f16 x)     { return x.exp != exp_nan_inf; }
bool isZero(f16 x)       { return x.exp == exp_zero_sub && x.fra == 0; }
bool isSubnormal(f16 x)  { return x.exp == exp_zero_sub && x.fra != 0; }
bool isInfinite(f16 x)   { return x.exp == exp_nan_inf && x.fra == 0; }
bool isNan(f16 x)        { return x.exp == exp_nan_inf && x.fra != 0; }
bool isSignaling(f16 x)  { return false; }
bool isCanonical(f16 x)  { return true; }
int radix(f16 x)         { return 2; }
bool totalOrder(f16 x, f16 y) {
	if (x.sign != y.sign) return x.sign < y.sign;
	return x.bits < y.bits;
}
bool totalOrderMag(f16 x, f16 y) {
    x.sign = 0;
    y.sign = 0;
	return x.bits < y.bits;
}

order compare(f16 x, f16 y) {
    if (isNan(x) || isNan(y)) return order_un;
    if (isZero(x) && isZero(y)) return order_eq;
    if (x.bits == y.bits) return order_eq;
    if (x.sign != y.sign) return x.sign ? order_lt : order_gt;
    if (x.sign == 0) {
        return x.bits < y.bits ? order_lt : order_gt;
    } else {
        return x.bits < y.bits ? order_gt : order_lt;
    }
}

f16 f16_from_float(float f)
{
    if (isnan(f)) {f16 r; r.bits = qnan; return r;}
    if (isinf(f)) {f16 r; r.bits = f<0 ? neg_inf : pos_inf; return r; }
    if (f==0.0f)  {f16 r; r.bits = signbit(f) ? neg_zero : pos_zero; return r; }

    u32 packed = *(u32*)&f;
    int exp = ((packed >> 23) & 0xff) - 127 + bias;
    if (exp > emax) {f16 r; r.bits = f<0 ? neg_inf : pos_inf; return r; }

    if (exp >= emin) {
        f16 r;
        r.sign = (packed >> 31);
        r.exp = exp;
        r.fra = (u16)((packed & 0x007fffff) >> (23-mbits)); // TODO rounding
        return r;
    }

    // subnormal
    unsigned fra = ((packed & 0x007fffff) | 0x00800000) >> (23-mbits);
    while(exp < emin) {fra >>= 1; exp++; }
    f16 r;
    r.sign = (packed >> 31);
    r.exp = 0;
    r.fra = fra;
    return r;
}

float f16_to_float(f16 a)
{
    u32 packed = 0;
    if (a.sign) packed |= 1u<<31;

    if (a.exp==exp_nan_inf) {
        // infinity or nan
        packed |= 0xffu << 23;
        packed |= ((u32)a.fra) << 13;
    }
    else if (a.exp==0) {
        if (a.fra==0) {
            // zero - nothing to do
        }
        else {
            int exp = -15;
            u32 fra = ((u32)a.fra) << 14;
            while((fra & (1<<23)) == 0) {
                fra <<= 1;
                exp -= 1;
            }
            packed |= ((u32)(exp+127)) << 23;
            packed |= fra & ((1<<23)-1);
        }
    }
    else {
        // normal
        packed |= (a.exp-bias+127) << 23;
        packed |= ((u32)a.fra) << 13;
    }

    return *(float*)&packed;
}

void f16_print(f16 a)
{
    float f = f16_to_float(a);
    printf("%x:%x:%03x = %.9f", a.sign, a.exp, a.fra, f);
//    printf("sign=%s exp=%d fra=%f\n", a.sign?"-":"+", ((int)a.exp)-bias, (a.fra | 1 << mbits) / ((1<<mbits)+0.0));
}

u16 mul16_hi(u16 a, u16 b) 
{
    return (u16)((u32)a*b >> 16);
}

u16 mul16_lo(u16 a, u16 b) 
{
    return (u16)((u32)a*b);
}

f16 f16_mul(f16 a, f16 b)
{
    if (isNan(a)) return a;
    if (isNan(b)) return b;

    u16 r_sign = a.sign ^ b.sign;

    if (isZero(a)) {
        if (isInfinite(b)) a.bits = qnan;
        return a;
    }
    if (isZero(b)) {
        if (isInfinite(a)) b.bits = qnan;
        return b;
    }

    if (isInfinite(a)) { a.sign = r_sign; return a; }
    if (isInfinite(b)) { b.sign = r_sign; return b; }

    int r_exp = a.exp + b.exp - bias;

    // bits[12:3]=fra[9:0]
    // 000f:ffff:ffff:f000
    u16 a_fra = a.fra << 3;
    u16 b_fra = b.fra << 3;

    if (isSubnormal(a)) {
        r_exp += 1;
        // Shift subnormal up until leading bit at implicit unit position (13)
        // e.g.    0000:001f:ffff:f000
        // becomes 001f:ffff:f000:0000
        do { a_fra <<= 1; r_exp -= 1; } while((a_fra & (1<<13)) == 0);
    }
    else {
        // Normal number - make implicit unit bit explicit
        // e.g.    000f:ffff:ffff:f000
        // becomes 001f:ffff:ffff:f000
        a_fra |= (u16)1 << (mbits+3);
    }

    if (isSubnormal(b)) {
        r_exp += 1;
        do { b_fra <<= 1; r_exp -= 1; } while((b_fra & (1<<13)) == 0);
    }
    else {
        // set implicit unit bit
        b_fra |= (u16)1 << (mbits+3);
    }

    // prod_hi:prod_lo - PP.p{20} P=leading integer, p=trailing fraction
    // 0000:PPpp:pppp:pppp : pppp:pppp:pp00:0000
    u16 prod_hi = mul16_hi(a_fra, b_fra);
    u16 prod_lo = mul16_lo(a_fra, b_fra);
    // is PP > 1 ?
    if (prod_hi & (1<<(27-16))) {
        // divide by 2 so we have only 1 unit bit again
        // e.g.    0000:1Ppp:pppp:pppp : pppp:pppp:pp00:0000
        // becomes 0000:01Pp:pppp:pppp : pppp:pppp:ppp0:0000
        prod_lo = (prod_lo>>1) | (prod_hi<<15);
        prod_hi >>= 1;
        r_exp += 1;
    }
    // Round to nearest - do we have >= 0.5 ulp?
    if (prod_lo & (1<<15)) {
        // so round up
        prod_hi += 1;
        // shift again in case we overflow
        if (prod_hi & (1<<(27-16))) {
            prod_hi >>= 1;
            r_exp += 1;
        }
    }

    if (r_exp > emax) {
        f16 r;
        r.bits = r.sign ? neg_inf : pos_inf;
        return r;
    }
    else if (r_exp > 0) {
        // result frac will be in bits [26:0] of prod_hi:prod_lo,
        // i.e. [10:0] of prod_hi - so mask out unit bit at [10]
        f16 r;
        r.sign = r_sign;
        r.exp = r_exp;
        r.fra = prod_hi & 0x3ff;
        return r;
    }

    // Result is a subnormal...
    //
    // NOTE value of a subnormal is 2**-14 * 0.ffffffffff
    //
    // If we have r_exp==0, the value of the product
    // is 2**-15 * 1.ppp... = 2**-14 * 0.1ppp...
    // Therefore at least 1 shift is always required.
    //
    // If r_exp==-1, value is 2**-16 * 1.ppp... = 2**-14 * 0.01ppp...
    // i.e. two shifts needed.
    //
    // Etc.

    // shift right until subnormal has required valued
    do {
        prod_lo = (prod_hi<<15) | (prod_lo>>1);
        prod_hi >>= 1;
        r_exp += 1;
    } while(r_exp <= 0);

    // round up on 0.5ulp
    if (prod_lo & (1<<15)) {
        prod_hi += 1;
        // if we overflow into leading unit position, we've now
        // got the smallest representable normal, so return that
        if (prod_hi & (1<<(26-16))) {
            f16 r; r.bits = r.sign ? neg_min_norm : pos_min_norm;
            return r;
        }
    }

    f16 r;
    r.sign = r_sign;
    r.exp = 0;
    r.fra = prod_hi & 0x03ff;
    return r;
}

// recip_6i_8o[i] = 0x3fff / (0x40+i)
u8 recip_6i_8o[] = {
    0xFF, 0xFC, 0xF8, 0xF4,
    0xF0, 0xED, 0xEA, 0xE6,
    0xE3, 0xE0, 0xDD, 0xDA,
    0xD7, 0xD4, 0xD2, 0xCF,
    0xCC, 0xCA, 0xC7, 0xC5,
    0xC3, 0xC0, 0xBE, 0xBC,
    0xBA, 0xB8, 0xB6, 0xB4,
    0xB2, 0xB0, 0xAE, 0xAC,
    0xAA, 0xA8, 0xA7, 0xA5,
    0xA3, 0xA2, 0xA0, 0x9F,
    0x9D, 0x9C, 0x9A, 0x99,
    0x97, 0x96, 0x94, 0x93,
    0x92, 0x90, 0x8F, 0x8E,
    0x8D, 0x8C, 0x8A, 0x89,
    0x88, 0x87, 0x86, 0x85,
    0x84, 0x83, 0x82, 0x81,
};

f16 f16_div(f16 a, f16 b)
{
    if (isNan(a)) return a;
    if (isNan(b)) return b;

    bool q_sign = a.sign ^ b.sign;

    if (isZero(a))     {f16 q; q.bits = isZero(b)     ? qnan : q_sign ? neg_zero : pos_zero; return q; }
    if (isInfinite(a)) {f16 q; q.bits = isInfinite(b) ? qnan : q_sign ? neg_inf  : pos_inf;  return q; }
    if (isZero(b))     {f16 q; q.bits =                        q_sign ? neg_inf  : pos_inf;  return q; }
    if (isInfinite(b)) {f16 q; q.bits =                        q_sign ? neg_zero : pos_zero; return q; }

    int q_exp = bias + a.exp - b.exp-1;

    u16 a_fra = a.fra << 5;
    u16 b_fra = b.fra << 5;

    // shift and set implicit top bit
    if (isSubnormal(a)) {
        q_exp -= 1;
        while((a_fra & (1<<15)) == 0) { q_exp -= 1; a_fra <<= 1; }
    } else {
        a_fra |= 1<<15;
    }

    // shift and set implicit top bit
    if (isSubnormal(b)) {
        q_exp += 1;
        while((b_fra & (1<<15)) == 0) { q_exp += 1; b_fra <<= 1; }
    } else {
        b_fra |= 1<<15;
    }

    // get 6 leading bits
    u16 index = b.fra >> 4;

    // rough inverse
    // inv0 = 0x3fff / (0x40 + index)
    u16 inv0 = (u16)recip_6i_8o[index] << 8;

    // Newton-Raphson gets 12 bits accuracy
    u16 p0 = mul16_hi(inv0, b_fra);
    p0 = 0u-p0;
    u16 inv1 = mul16_hi(p0, inv0);
//  inv1 <<= 1;

    // final quotient
    u32 q_fra = mul16_hi(a_fra, inv1);
    q_fra <<= 1;
    if (q_fra & 0x8000) {
        q_fra >>= 1;
        q_exp += 1;
    }
    q_fra += 0x0008;
    q_fra >>= 4;

    // TODO - adjust quotient (use last 4 bits for rounding?)
    // TODO - subnormals, inf, nan, zero
//  printf("q_fra=%08x\n", q_fra);

    f16 q;
    q.sign = q_sign;
    q.exp = q_exp;
    q.fra = q_fra & 0x3ff;
    return q;
}

f16 f16_add(f16 a, f16 b)
{
    // TODO - apply correct rules for sum and difference of Zeros

    if (isNan(a)) return a;
    if (isNan(b)) return b;

    bool subtract = (a.sign != b.sign);
    if (subtract) {
        if (isZero(b)) { return a; }
        if (isZero(a)) { b.sign ^= 1; return b; }
        if (isInfinite(a)) {
            if (isInfinite(b)) a.bits = qnan;
            return a;
        }
        if (isInfinite(b)) { b.sign ^= 1; return b; }
    }
    else {
        if (isInfinite(a)) return a;
        if (isInfinite(b)) return b;
        if (isZero(a)) return b;
        if (isZero(b)) return a;
    }

    if (a.exp < b.exp) {
        f16 t = a;
        a = b;
        b = t;
    }

    u16 a_fra = a.fra;
    u16 b_fra = b.fra;
    int a_exp = a.exp;
    int b_exp = b.exp;

    if (a_exp > 0) {
        a_fra |= 1<<10;
    }
    else {
        a_exp += 1;
        do { a_fra <<= 1; a_exp -= 1; } while((a_fra & (1<<10)) == 0);
    }

    if (b_exp > 0) {
        b_fra |= 1<<10;
    }
    else {
        b_exp += 1;
        do { b_fra <<= 1; b_exp -= 1; } while((b_fra & (1<<10)) == 0);
    }

    int dexp = a_exp - b_exp;
    a_fra <<= 4;
    b_fra <<= 4;
    b_fra >>= dexp;

    int r_exp = a_exp;
    u16 r_sign = a.sign;
    u16 r_fra;

    if (subtract) {
        if (dexp == 0) {
            if (a_fra < b_fra) {
                u16 t = a_fra;
                a_fra = b_fra;
                b_fra = t;
                r_sign = ~r_sign;
            }
        }
        printf("a_fra=%x b_fra=%x\n", a_fra, b_fra);
        r_fra = a_fra - b_fra;
        if (r_fra == 0) {f16 r; r.bits = pos_zero; return r; } // TODO - handle zeroes correctly
        while((r_fra & (1<<14)) == 0) {
            r_fra <<= 1;
            r_exp -= 1;
        }
    }
    else {
        r_sign = a.sign;
        r_fra = a_fra + b_fra;
    }

    // convert to subnormal if necessary
    if (r_exp <= 0) {
        r_fra >>= 1-r_exp;
        r_exp = 0;
    }

    // TODO - rounding

    // adjust
    if (r_fra & 1<<15) {
        r_fra >>= 1;
        r_exp += 1;
    }
    r_fra ^= 1<<14;
    r_fra >>= 4;

    f16 r;
    if (r_exp > emax) {r.bits = r_sign ? neg_inf : pos_inf; return r;}
    r.sign = r_sign;
    r.exp = (u16)r_exp;
    r.fra = r_fra;
    return r;
}

void test_compare()
{
    struct s_test { f16 x; f16 y; order expect_xy, expect_yx; };
    struct s_test tests[] = {
        {neg_max_nan,   neg_inf,        order_un, order_un},
        {neg_min_nan,   neg_max_nan,    order_un, order_un},
        {neg_one,       neg_max_nan,    order_un, order_un},
        {neg_max,       neg_inf,        order_gt, order_lt},
        {neg_max_sub,   neg_min_norm,   order_gt, order_lt},
        {neg_min_sub,   neg_max_sub,    order_gt, order_lt},
        {neg_one,       neg_two,        order_gt, order_lt},
        {neg_one,       neg_one_eps,    order_gt, order_lt},
        {neg_one,       pos_one,        order_lt, order_gt},
        {neg_zero,      neg_inf,        order_gt, order_lt},
        {neg_zero,      neg_one,        order_gt, order_lt},
        {neg_zero,      neg_zero,       order_eq, order_eq},
        {pos_zero,      neg_zero,       order_eq, order_eq},
        {pos_zero,      pos_zero,       order_eq, order_eq},
        {pos_zero,      pos_one,        order_lt, order_gt},
        {pos_zero,      pos_inf,        order_lt, order_gt},
        {pos_one,       pos_one_eps,    order_lt, order_gt},
        {pos_one,       pos_two,        order_lt, order_gt},
        {pos_min_sub,   pos_max_sub,    order_lt, order_gt},
        {pos_max_sub,   pos_min_norm,   order_lt, order_gt},
        {pos_max,       pos_inf,        order_lt, order_gt},
        {pos_one,       pos_max_nan,    order_un, order_un},
        {pos_min_nan,   pos_max_nan,    order_un, order_un},
        {pos_max_nan,   pos_inf,        order_un, order_un},
        {neg_inf,       pos_inf,        order_lt, order_gt},
    };
    for(int i=0; i < numof(tests); i++) {
        struct s_test *t = &tests[i];
        order got_xy = compare(t->x, t->y);
        order got_yx = compare(t->y, t->x);
        printf("%s - test_compare[%d], xy[expect=%d got=%d] yx[expect=%d got=%d]\n",
                got_xy == t->expect_xy && got_yx == t->expect_yx ? "pass" : "fail",
                i,
                t->expect_xy, got_xy,
                t->expect_yx, got_yx);
    }
}

void print_consts()
{
    struct s_test { char* label; u16 bits; };
    struct s_test tests[] = {
        { "-max_nan",  neg_max_nan },
        { "-min_nan",  neg_min_nan },
        { "-inf",      neg_inf },
        { "-max",      neg_max },
        { "-3",        neg_three },
        { "-2",        neg_two },
        { "-1-epsilon",neg_one_eps },
        { "-1",        neg_one },
        { "-min_norm", neg_min_norm },
        { "-max_sub",  neg_max_sub },
        { "-min_sub",  neg_min_sub },
        { "-0",        neg_zero },
        { "+0",        pos_zero },
        { "+min_sub",  pos_min_sub },
        { "+max_sub",  pos_max_sub },
        { "+min_norm", pos_min_norm },
        { "+1",        pos_one },
        { "+1+epsilon",pos_one_eps },
        { "+2",        pos_two },
        { "+3",        pos_three },
        { "+max",      pos_max },
        { "+inf",      pos_inf },
        { "+min_nan",  pos_min_nan },
        { "+max_nan",  pos_max_nan },
    };
    for(size_t i=0; i < numof(tests); i++) {
        struct s_test *t = &tests[i];
        f16 x;
        x.bits = t->bits;
        float value = f16_to_float(x);

        printf("%-10s value=%20.12f bits=%04x f16=", t->label, (double)value, x.bits); f16_print(x); printf("\n");
    }
}

u16 pow10_table[] = {
                40000, 20000, 10000,
0x8000 | 8000,  4000,  2000,  1000,
0x8000 | 800,   400,   200,   100,
0x8000 | 80,    40,    20,    10,
0x8000 | 8,     4,     2,     1,
0x8000 | 0
};

void f16_to_ascii(f16 x, char *buf)
{
    if (isNan(x)) {
        strcpy(buf, "NaN");
        return;
    }
    if (isZero(x)) {
        strcpy(buf, "0");
        return;
    }
    if (isSignMinus(x)) {
        *buf++ = '-';
    }
    if (isInfinite(x)) {
        strcpy(buf, "Inf");
        return;
    }

    int exp = x.exp;

    u32 frac;
    u32 hulp = 1;

    // is value >= 1.0 ?
    if (exp >= 15) {
        u16 whole = x.fra | (1<<10);
        
        // exp counts how many bits of fra are the integer part
        if (exp <= 25) {
            whole >>= (25-exp);
            // move leading fractional bit to bit 15
            frac = (u32)x.fra << (exp-9);
            frac &= 0xffff;
            hulp <<= (exp-9);
        }
        else {
            whole <<= (exp-25);
            frac = 0;
        }

        char outputting = 0;

        u16 trial;
        char digit;
        u16 *ptr = pow10_table;

        trial = *ptr;

        do {
            digit = 0;
            do {
                digit <<= 1;
                if (whole >= trial) {
                    whole -= trial;
                    digit |= 1;
                    outputting = 1;
                }
                trial = *++ptr;
            } while((trial & 0x8000) == 0);
            digit += '0';
            trial &= ~0x8000;
            if (trial == 0) break;

            if (outputting) {
                *buf++ = digit;
            }
        } while(1);

        *buf++ = digit;

        frac <<= 12; // move leading bit (15) up to bit 27
        hulp <<= 11;
    }
    else {
        // exp < 15, thus value is < 1.0
        //
        // Possible thresholds for switching from scientific to fixed notation
        // 0x068e = 0.0001
        // 0x1419 = 0.001

        frac = x.fra;
        if (exp == 0) {
            frac <<= 1;
            hulp <<= 1;
        }
        else {
            frac |= 0x400;
        }

        *buf++ = '0';

        // shift up so that exp=15 would correspond to the implicit
        // bit at 28, thus when multiplied by 10 each leading fractional
        // digit will appear at bits 31..28
        //
        // 15+3+10 = 28
        frac <<= exp + 3;
        hulp <<= exp + 2;
    }

    if (frac != 0) {
        *buf++ = '.';

        while(1) {
            hulp *= 10;
            frac *= 10;
            u16 digit = frac >> 28;
            frac &= ~(0xf<<28);

            *buf++ = '0' + digit;

            // TODO deal with exponent boundaries
            if (frac & (1<<27)) {
                if (frac + hulp >= (1<<28)) {
                    char *ptr = buf;

                    // TODO in practice this condition is never true! can we prove why?!
                    while(*--ptr == '9') *ptr = '0';

                    if (*ptr != '.') {
                        (*ptr)++;
                    }
                    else {
                        // TODO - only need to to worry about this,
                        // if we allow fixed precision formatting.
                    }
                    break;
                }
            } else {
                if (frac <= hulp) {
                    break;
                }
            }
        }
    }

    *buf++ = '\0';
}

// Input conversion
//
// TODO analyse necessary precision
// TODO tests / roundtrip tests
//
f16 f16_from_ascii(char *buf)
{
    struct mul_shift { u32 mul; int shift; };

    struct mul_shift pow10_table[] = {
        // negative powers are expressed as fractions of 1<<32
        {0xafebff0c, 44 -36}, // -11
        {0xdbe6fecf, 44 -33}, // -10
        {0x89705f41, 44 -29}, // -9
        {0xabcc7712, 44 -26}, // -8
        {0xd6bf94d6, 44 -23}, // -7
        {0x8637bd06, 44 -19}, // -6
        {0xa7c5ac48, 44 -16}, // -5
        {0xd1b71759, 44 -13}, // -4
        {0x83126e98, 44 -9 }, // -3
        {0xa3d70a3e, 44 -6 }, // -2
        {0xcccccccd, 44 -3 }, // -1

        // Positive powers are shifted left to get leading bit in bit 31,
        // with an adjusted shift value to compensate.
        {0x80000000, 44 +32 -31}, // 0
        {0xa0000000, 44 +32 -28}, // 1
        {0xc8000000, 44 +32 -25}, // 2
        {0x7d000000, 44 +32 -21}, // 3
        {0x9c400000, 44 +32 -18}  // 4
    };

    char ch;
    u32 dec_mantissa = 0;
    int dec_exponent = 0;
    bool full = 0;
    bool seen_dp = 0;
    bool sign = 0;

    // TODO error
    ch = *buf++;
    if (ch=='n' || ch=='N') {
        ch = *buf++;
        if (ch=='a' || ch=='A') {
            ch = *buf++;
            if (ch=='n' || ch=='N') {
                f16 r;
                r.sign = 0;
                r.exp = 0x1f;
                r.fra = 0x200;
                return r;
            }
        }
    }

    if (ch=='-' || ch=='+') {
        sign = ch=='-';
        ch = *buf++;
    }

    // TODO error
    if (ch=='i' || ch=='I') {
        ch = *buf++;
        if (ch=='n' || ch=='N') {
            ch = *buf++;
            if (ch=='f' || ch=='F') {
                f16 r;
                r.sign = sign;
                r.exp = 0x1f;
                r.fra = 0;
                return r;
            }
        }
    }

    while(ch == '0') ch = *buf++;

    while(1) {
        if (ch == '\0') break;
        if (ch == '.') {
            if (seen_dp) break;
            seen_dp = 1;
            ch = *buf++;
            continue;
        }
        if (! (ch>='0' && ch<='9') ) break;

        if (seen_dp) {
            dec_exponent--;
        }

        u16 digit = ch-'0';
        if (full) {
            dec_exponent++;
        }
        // NOTE:
        // this check does not need to be exact,
        // and we could use a lower constant
        else if (dec_mantissa > (0x7fffffffu-9) / 10) {
            if (digit >= 5) dec_mantissa++;
            full = 1;
            dec_exponent++;
        }
        else {
            dec_mantissa = (dec_mantissa*10) + digit;
        }
        ch = *buf++;
    }
    bool exp_sign = 0;
    u16 exp_value = 0;
    if (ch == 'e' || ch == 'E') {
        ch = *buf++;
        if ((ch=='+' || ch=='-')) {
            exp_sign = ch=='-';
            ch = *buf++;
        }
        while((ch>='0' && ch<='9')) {
            exp_value = exp_value*10 + (ch-'0');
            ch = *buf++;
        }
    }
    if (exp_sign)
        dec_exponent -= exp_value;
    else
        dec_exponent += exp_value;

    // TODO prove or check dec_exponent in range [-11..4]
    u32 pow10_mul = pow10_table[dec_exponent+11].mul;
    int bin_exponent = pow10_table[dec_exponent+11].shift;
//  printf("dec_exponent=%d => pow10_mul=%08x bin_exponent=%d\n", dec_exponent, pow10_mul, bin_exponent);

    // normalise so bit 30 is set (leave 31 clear for possible carry out later)
    while((dec_mantissa & (1<<30)) == 0) {
        dec_mantissa <<= 1;
        bin_exponent--;
    }

    // round to 16 bits (well, 15)
    dec_mantissa += 1<<15;
    if (dec_mantissa & (1<<31)) {
        dec_mantissa >>= 1;
        bin_exponent += 1;
    }
    dec_mantissa >>= 16;

    // scale - this gets us our mantissa expressed as a 47 bit integer
    u64 bin_mantissa64 = ((u64) pow10_mul * dec_mantissa);

    // round to 32 bits (only the lower 15 are used)
    bin_mantissa64 += 1<<31;
    u16 bin_mantissa = bin_mantissa64 >> 32;

    // normalise
    if ((bin_mantissa & (1<<14)) == 0) {
        bin_mantissa <<= 1;
        bin_exponent--;
    }

    // Rest of this code corresponds to f16_round_pack
    if (bin_exponent >= 0 && bin_exponent < 29) {
    }
    else if (bin_exponent >= 0) {
        // round_maybe_huge
        if (bin_exponent > 29 || bin_mantissa + 8 >= 0x8000) {
            // TODO - should be an error instead
            f16 r; r.bits = sign ? neg_inf : pos_inf; return r;
        }
    }
    else {
        u16 dist = -bin_exponent;
        u32 a = bin_exponent;
        bin_mantissa = (dist<31) ? a>>dist | ((u32) (a<<(-dist & 31)) != 0) : (a != 0);
        bin_exponent = 0;
    }

    // round_unspecial
    u16 round_bits = bin_mantissa & 0xf;
    bin_mantissa += 1<<3;
    bin_mantissa >>= 4;
    if (round_bits == 8) bin_mantissa &= ~1;

    // f16_return
    f16 r;
    if (bin_mantissa == 0) {
        bin_exponent = 0;
    }
    r.sign = sign;
    r.exp = bin_exponent + ((bin_mantissa & 0x400) ? 1 : 0);
    r.fra = bin_mantissa & 0x3ff;
    return r;
}

int main() {
    char buf[100];
    for(u16 i = 0x0000; i <= 0x07600; i++) {
        f16 u; u.bits = i;
        f16_to_ascii(u, buf);
        printf("%04x => %s => ", i, buf);
        f16_print(u);
        printf("\n");
    }
}



