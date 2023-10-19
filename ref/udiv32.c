#include <stdio.h>
#include <stdlib.h>

typedef unsigned char  u8;
typedef unsigned short u16;
typedef unsigned int   u32;
typedef unsigned long  u64;

/*
void udiv32(
        u16 uh, u16 ul,
        u16 vh, u16 vl,
        u16 *pqh, u16 *pql,
        u16 *prh, u16 *prl
) {
    *pqh = qh;
    *pql = ql;
    *qrh = rh;
    *qrl = rl;
}
*/

u16 hi(u32 w) { return w>>16; }
u16 lo(u32 w) { return (u16)w; }
u32 wd(u16 h, u16 l) { return h<<16 | l; }

int clz32(u32 a) {
    int n = 0;
    while(n<32 && !(a>>31)) {a<<=1; ++n;}
    return n;
}

int clz16(u16 a) {
    int n = 0;
    while(n<16 && !(a>>15)) {a<<=1; ++n;}
    return n;
}

u8 recip_3i_8o[] = {
  0xFF, 0xE3, 0xCC, 0xBA, 0xAA, 0x9D, 0x92, 0x88
};

u16 recip_7i_16o[] = {
    0xFFFF, 0xFE03, 0xFC0F, 0xFA23, 0xF83E, 0xF660, 0xF489, 0xF2B9,
    0xF0F0, 0xEF2E, 0xED73, 0xEBBD, 0xEA0E, 0xE865, 0xE6C2, 0xE525,
    0xE38E, 0xE1FC, 0xE070, 0xDEE9, 0xDD67, 0xDBEB, 0xDA74, 0xD901,
    0xD794, 0xD62B, 0xD4C7, 0xD368, 0xD20D, 0xD0B6, 0xCF64, 0xCE16,
    0xCCCC, 0xCB87, 0xCA45, 0xC907, 0xC7CE, 0xC698, 0xC565, 0xC437,
    0xC30C, 0xC1E4, 0xC0C0, 0xBFA0, 0xBE82, 0xBD69, 0xBC52, 0xBB3E,
    0xBA2E, 0xB921, 0xB817, 0xB70F, 0xB60B, 0xB509, 0xB40B, 0xB30F,
    0xB216, 0xB11F, 0xB02C, 0xAF3A, 0xAE4C, 0xAD60, 0xAC76, 0xAB8F,
    0xAAAA, 0xA9C8, 0xA8E8, 0xA80A, 0xA72F, 0xA655, 0xA57E, 0xA4A9,
    0xA3D7, 0xA306, 0xA237, 0xA16B, 0xA0A0, 0x9FD8, 0x9F11, 0x9E4C,
    0x9D89, 0x9CC8, 0x9C09, 0x9B4C, 0x9A90, 0x99D7, 0x991F, 0x9868,
    0x97B4, 0x9701, 0x964F, 0x95A0, 0x94F2, 0x9445, 0x939A, 0x92F1,
    0x9249, 0x91A2, 0x90FD, 0x905A, 0x8FB8, 0x8F17, 0x8E78, 0x8DDA,
    0x8D3D, 0x8CA2, 0x8C08, 0x8B70, 0x8AD8, 0x8A42, 0x89AE, 0x891A,
    0x8888, 0x87F7, 0x8767, 0x86D9, 0x864B, 0x85BF, 0x8534, 0x84A9,
    0x8421, 0x8399, 0x8312, 0x828C, 0x8208, 0x8184, 0x8102, 0x8080,
};

u16 mul16_hi(a, b)
{
    return (u16)(((u32)a*b) >> 16);
}

void udiv16(u16 u, u16 v, u16 *pq, u16 *pr, int *pk)
{
    int n = clz16(v);

    u16 v2 = v << n;
    int i = (v2 >> 8) - 0x80;
    u16 r = recip_7i_16o[i];   // Q16

    // Calculate quotient estimate and undo normalization.
    u16 q = mul16_hi(u, r);
    q >>= 15-n;

    // ^^^ q must be no more than 2 too low after all this ^^^
    
    // Prevent potential overflow in calculation of remainder;
    // also compensates for quotient "one too high."
    if (q > 0) --q;

    // Calculate remainder to u.
    u -= q*v;

    int k = 0;
    while(u >= v) {
        q += 1;
        u -= v;
        k++;
    }
    *pq = q;
    *pr = u;
    *pk = k;
}

void test_udiv16()
{
    u16 x;
    u16 y;
    u16 q;
    u16 r;
    int k;

    for(x=0xffff; x>=1; x--) {
        printf("[x=%04x]\n", x);
        for(y=0xffff; y>=1; y--) {
            udiv16(x,y, &q,&r, &k);
            if (q != x/y) {
                printf("fail x=%04x y=%04x k=%d\n", x, y, k);
            }
            else if(k>2) {
                printf("succ x=%04x y=%04x k=%d\n", x, y, k);
            }
            else if(k>2) {
                printf("succ y=%04x k=%d\n", y, k);
            }
        }
    }
}
 
u32 mul_hi(u32 a, u32 b) {
  return (u32)(((u64)a * b) >> 32);
}
 
u32 mul_hi_approx(u32 a, u32 b) {
    u16 a1 = (u16)(a>>16);
    u16 a0 = (u16)a;
    u16 b1 = (u16)(b>>16);
    u16 b0 = (u16)b;

    u16 p2_a0_b1 = (u16)(((u32)a0*b1) >> 16);
    u16 p2_a1_b0 = (u16)(((u32)a1*b0) >> 16);
    u16 p3_a1_b1 = (u16)(((u32)a1*b1) >> 16);
    u16 p2_a1_b1 = (u16)(u32)a1*b1;

    u16 p2 =             p2_a0_b1 + p2_a1_b0 + p2_a1_b1;
    u16 c2 = (u16)(((u32)p2_a0_b1 + p2_a1_b0 + p2_a1_b1) >> 16);

    u16 p3 = p3_a1_b1 + c2;

    return (((u32)p3)<<16) | p2;
}
 
u32 mul_hi_approx_bad(u32 a, u32 b) {
    u16 a1 = (u16)(a>>16);
    u16 b1 = (u16)(b>>16);

    u16 p3_a1_b1 = (u16)(((u32)a1*b1) >> 16);
    u16 p2_a1_b1 = (u16)(u32)a1*b1;
    u16 p2 =             p2_a1_b1;
    u16 p3 = p3_a1_b1;

    return (((u32)p3)<<16) | p2;
}
 
void inv32_ref(u32 v, u32 *pr, int *pn)
{
    int n = clz32(v);

    v <<= n;
    u32 i = (v >> 24) - 0x80;
    u32 r1 = recip_7i_16o[i]; // Q16
    r1 <<= 16;            // Q32

    // Newton iterations to refine reciprocal.
    u32 r2 = mul_hi(0u - mul_hi(r1, v), r1) << 1;
    u32 r3 = mul_hi(0u - mul_hi(r2, v), r2) << 1;
    u32 r4 = mul_hi(0u - mul_hi(r3, v), r3) << 1;

    *pr = r4;
    *pn = n;
}

static u8 recip_6i_8o[64] = {
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
    0x84, 0x83, 0x82, 0x81
};

void inv32(u32 v, u32 *pr, int *pn)
{
    u32 i;
    u32 q;
    u32 r;
    int n;

    n = clz32(v);

    v <<= n;
    i = ((v >> 25) - 0x40);
    r = (u16)recip_6i_8o[i];
    r <<= 24;            // Q32

    // Newton iterations to refine reciprocal.
    r = mul_hi_approx_bad(0u - mul_hi_approx_bad(r, v), r) << 1;    // 4 muls
    r = mul_hi_approx(0u - mul_hi_approx(r, v), r) << 1;            // 8 muls
    *pr = r;
    *pn = n;
}

void test_inv32()
{
    u32 v;
    u32 r;
    int n;
    u32 r_ref;
    int n_ref;

    for(v = 0x01ffffff; v>0; v--) {
        if((v&0xffff) == 0)printf("[v=0x%08x]\n",v);
        inv32_ref(v, &r_ref, &n_ref);
        inv32(v, &r, &n);
        int delta = r_ref-r;
        if (delta > 2 || delta<-2)
        printf("v=0x%08x r=0x%08x r_ref=0x%08x delta=%d\n", v, r, r_ref, r_ref-r);
    }
}

void udiv32(u32 u, u32 v, u32 *pq, u32* pr)
{
    u32 u0 = u;
    u32 v0 = v;

    u32 r;
    int n;
    inv32(v, &r, &n);

    // Calculate quotient estimate and undo normalization.
    u32 q = mul_hi_approx(u, r);                                // 4 muls
    q >>= 31-n;

    // Prevent potential overflow in calculation of remainder;
    // also compensates for quotient "one too high."
    if (q > 0) --q;

    // Calculate remainder to u.
    u -= q*v;

    int corr = 0;
    while(u >= v) {
        q += 1;
        u -= v;
        corr++;
    }
    // no more than 3 corrections should be needed
    if (corr >= 4) printf("%08x/%08x needed %d corrections\n", u0, v0, corr);

    *pq = q;
    *pr = u;
}


#define HDR(msg) printf("%s\n", msg)
#define TRACE printf(\
        "r0=%04x r1=%04x r2=%04x r3=%04x " \
        "r4=%04x r5=%04x r6=%04x r7=%04x " \
        "r8=%04x r9=%04x r10=%04x r11=%04x r12=%04x\n", \
            (int)uh, (int)ul, (int)vh,  (int)vl, \
            (int)qh, (int)ql, (int)vh0, (int)vl0, \
            (int)rh, (int)rl, (int)n,   (int)th, (int)tl)
    
void udiv32_asm_style(u32 u, u32 v, u32 *pq, u32 *pr)
{
    // approx 80 instructions

    u16 uh = hi(u);
    u16 ul = lo(u);
    u16 vh = hi(v); 
    u16 vl = lo(v);
    u16 qh;
    u16 ql;
    u16 vh0 = hi(v);
    u16 vl0 = lo(v);
    u16 n;  // temp
    u16 th; // temp
    u16 tl; // temp
    u16 rh; // reciprocal
    u16 rl; // reciprocal

    // Compute inverse of v
    HDR("Compute inverse of v");

    // n = clz32(v), and v <<= n
    // where v = vh:vl
    HDR("n = clz32(v)");
    n = clz16(vh); TRACE;
    th = 16; TRACE;
    if (n == th) {
        HDR("n==16");
        n = clz16(vl); TRACE;
        vh = vl; TRACE;
        vh <<= n; TRACE;
        vl = 0; TRACE;
        n += th; TRACE;
    }
    else {
        HDR("n!=16");
        vh <<= n; TRACE;
        n = th - n; TRACE;
        tl = vl; TRACE;
        tl >>= n; TRACE;
        vh |= tl; TRACE;
        n = th - n; TRACE;
        vl <<= n; TRACE;
    }

    // recip_0 = approx_recip(vh) = 0x3fff / vh[15:9]
    // where recip_0 = rh:__
    HDR("compute recip_0");
    rh = vh; TRACE;
    rh >>= 9; TRACE;
    rh = (u32)(recip_6i_8o-0x40)[rh]; TRACE;
    rh <<= 8; TRACE;

    // Improve approximation with low precision Newton Raphson
    HDR("first Newton Raphson");
    //
    // temp_0 = mul_hi_approx_bad(recip_0, vh)
    // where temp_0 = th:__
    //       recip_0 = rh:__
    //       v = vh:__
    HDR("mul_hi_approx_bad");
    th = rh; TRACE;
    th = hi((u32) th * vh); TRACE;

    // temp_0 = 0u - temp_0
    HDR("negate");
    rl = 0; TRACE;
    th = rl - th; TRACE;   // used as temp zero

    // recip_1 = mul_hi_approx_bad(recip_0, temp_0)
    // where temp_1 = qh:ql
    //       temp_0 = th:__
    //       recip_0 = rh:__
    HDR("mul_hi_approx_bad");
    qh = th; TRACE;
    qh = hi((u32) qh * rh); TRACE;
    ql = rh; TRACE;
    ql = lo((u32) ql * th); TRACE;

    // recip_1 <<= 1
    // where recip_1 = qh:ql
    HDR("shift");
    qh += qh + hi(ql+ql); TRACE;
    ql += ql; TRACE;

    // Second Newton Raphson iteration, at higher precision
    HDR("second Newton Raphson");

    // temp_1 = mul_hi_approx(recip_1, v)
    // where temp_1 = th:tl
    //       recip_1 = qh:ql
    //       v = vh:vl
    HDR("mul_hi_approx");
    th = qh; TRACE;
    th = hi((u32) th * vh); TRACE;
    tl = ql; TRACE;
    tl = hi((u32) tl * vh); TRACE;
    rh = vh; TRACE;
    rh = lo((u32) rh * qh); TRACE;
    vl = hi((u32) vl * qh); TRACE;

    th += hi(tl+vl); TRACE;
    tl += vl; TRACE;

    th += hi(tl+rh); TRACE;
    tl += rh; TRACE;

    // temp_1 = 0u - temp_1
    // where temp_1 = th:tl
    HDR("negate");
    tl = rl - tl; TRACE;
    th = rl - th - (tl != 0 ? 1 : 0); TRACE;

    // recip_2 = mul_hi_approx(recip_1, temp_1)
    // where
    //      recip_1 = qh:ql
    //      temp_1 = th:tl
    //      recip_2 = rh:rl
    HDR("mul_hi_approx");
    ql = hi((u32) ql * th); TRACE;
    tl = hi((u32) tl * qh); TRACE;
    rh = qh; TRACE;
    rh = hi((u32) rh * th); TRACE;
    qh = lo((u32) qh * th); TRACE;

    th = 0; TRACE;
    rl = qh; TRACE;
    rh += th + hi(rl+tl); TRACE;   // th is zero
    rl += tl; TRACE;
    rh += th + hi(rl+ql); TRACE;   // th is zero
    rl += ql; TRACE;

    // recip_2 <<= 1
    // where recip_2 = rh:rl
    HDR("shift");
    rh += rh + hi(rl+rl); TRACE;
    rl += rl; TRACE;

    // End of Newton-Raphson reciprocal calculation

    // Calculate quotient estimate
    HDR("estimate quotient");
    // q = mul_hi_approx(u, recip_2)
    // where
    //      q = qh:ql
    //      u = uh:ul
    //      recip_2 = rh:rl
    HDR("mul_hi_approx");
    ql = ul; TRACE;
    ql = hi((u32) ql * rh); TRACE;
    rl = hi((u32) rl * uh); TRACE;

    qh = uh; TRACE;
    qh = hi((u32) qh * rh); TRACE;
    rh = lo((u32) rh * uh); TRACE;

    qh += th + hi(ql+rl); TRACE;   // th is zero
    ql += rl; TRACE;
    qh += th + hi(ql+rh); TRACE;   // th is zero
    ql += rh; TRACE;

    // Undo normalisation
    // q >>= (31-n)
    // where q = qh:ql
    HDR("undo normalisation");
    tl = 31; TRACE;
    n = tl - n; TRACE;
    tl = 16; TRACE;

    if (n >= tl) {
        HDR("n >= 16");
        n -= tl; TRACE;
        ql = qh; TRACE;
        qh = 0; TRACE;
        ql >>= n; TRACE;

        // Adjust quotient down to prevent potential overflow,
        // and avoid "one too high" error in prior calculation.
        // if (q>0) q -= 1
        HDR("adjust quotient down");
        if (ql != 0) ql -= 1; TRACE;
    }
    else {
        HDR("n < 16");
        ql >>= n; TRACE;
        n = tl - n; TRACE;
        th = qh; TRACE;
        th <<= n; TRACE;
        n = tl - n; TRACE;
        qh >>= n; TRACE;
        ql |= th; TRACE;

        // Adjust quotient down to prevent potential overflow,
        // and avoid "one too high" error in prior calculation.
        // if (q>0) q -= 1
        HDR("adjust quotient down");
        if (ql == 0) {
            qh -= 1; TRACE;
            if (qh == 0xffff) {
                qh = 0; TRACE;
            }
            else ql -= 1; TRACE;
        } else ql -= 1; TRACE;
    }
    
    // Calculate remainder
    HDR("calculate remainder");
    //
    // Step 1: temp = q * v
    // where
    //      temp = th:tl
    //      q = qh:ql
    //      v = vh:vl
    HDR("temp = q * v");
    vh = vh0; TRACE;
    vl = vl0; TRACE;

    th = ql; TRACE;
    th = hi((u32) th * vl); TRACE;     // hi(ql*vl)
    n = ql; TRACE;
    n = lo((u32) n * vh); TRACE;       // lo(ql*vh)
    th += n; TRACE;
    n = qh; TRACE;
    n = lo((u32) n * vl); TRACE;       // lo(qh*vl)
    th += n; TRACE;
    tl = ql; TRACE;
    tl = lo((u32) tl * vl); TRACE;     // lo(ql*vl)

    // Step 2: u -= temp
    // where
    //      u = uh:ul
    //      temp = th:tl
    HDR("subtract");
    uh -= th + (ul<tl ? 1 : 0); TRACE;
    ul -= tl; TRACE;

    // Quotient may be too low - adjust until correct.
    // Max 3 iterations required.
    HDR("final quotient adjust");
    //
    // while(u >= v) u-=v, q++
    int iter = 0;
    u16 old_uh, old_ul;

    tl = 0;
    while(1) {
        HDR("iteration");
        old_uh = uh, old_ul = ul;
        ul -= vl; TRACE;
        uh -= vh + (old_ul < lo(v) ? 1 : 0); TRACE;

        if (wd(old_uh, old_ul) < v) break;
        ql += 1; TRACE;
        qh += (ql==0) ? 1 : 0; TRACE;

        ++iter;
    }

    HDR("restore");
    uh += vh + hi(ul+vl); TRACE;
    ul += vl; TRACE;
    HDR("done");
    HDR("---------------------------------------");

    if (iter >= 4) printf("%d\n",iter);

    *pq = wd(qh, ql);
    *pr = wd(uh, ul);
}

void test_udiv32()
{
    u32 u;
    u32 v;
    u32 q;
    u32 r;
    int k=0;
    srand48(1);
    for(u = 0xffffffff; u>=64; ) {
        for(int i = 0; i<128; i++) {
            if (k++==0x100000){k=0; printf("[%08x]\n", u);}
            v = mrand48();
            while(v>1) {
                udiv32_asm_style(u, v, &q, &r);
                if (q != u/v || r!=u%v) printf("%08x/%08x=%08x r%08x, got %08x r%08x\n", u, v, u/v, u%v, q, r);
                v >>= 1;
            }
        }

        u -= 1;
    }
}

void print_test_cases()
{
    srand48(1);
    for(int i=0; i<32; i++) {
        u32 u = mrand48();
        u32 v = 0;
        while(u>v && v<=1u) {
            v = mrand48();
            u32 s = (u32)(mrand48() % 256);
            s = 31-(s*s/2097);
            v >>= mrand48() % s;
        }

        u32 ref_q = u / v;
        u32 ref_r = u % v;
       // printf("dw %04x,%04x, %04x,%04x, %04x,%04x, %04x,%04x\n", hi(u),lo(u), hi(v),lo(v), hi(ref_q),lo(ref_q), hi(ref_r),lo(ref_r));
        u32 q, r;
        udiv32_asm_style(u, v, &q, &r);
        if (q != u/v || r!=u%v) printf("%08x/%08x=%08x r%08x, got %08x r%08x\n", u, v, u/v, u%v, ref_q, ref_r);
    }
}

int main()
{
    u32 q, r;
//  udiv32_asm_style(0xffd09c8e, 0x00037087, &q, &r);
    udiv32_asm_style(0x7d4f995c, 0xe9f8879d, &q, &r);

   // test_udiv32();
}
