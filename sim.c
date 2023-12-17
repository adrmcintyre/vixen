#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/errno.h>

typedef unsigned char bool;
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned long u32;

                            // light dark
const u8 white   = 0x00;    //  67      
const u8 red     = 0x01;    //  61     1
const u8 green   = 0x02;    //  62     2
const u8 yellow  = 0x03;    //  63     3
const u8 blue    = 0x04;    //  64     4
const u8 magenta = 0x05;    //  65     5
const u8 cyan    = 0x06;    //  66     6
const u8 grey    = 0x07;    //  7     60
const u8 black   = 0x08;    //         0

const u8 dark      = 0x08;
const u8 bg        = 0x10;
const u8 bold      = 0x20;
const u8 underline = 0x40;
const u8 inverse   = 0x80;

bool enable_color = 1;
bool enable_ascii = 0;

bool mode_post = 0;

char *attr_cache[256] = {};

char *mk_attr(u8 code) {
    if (!enable_color) {
        return "";
    }
    u8 color = code & 0x7;
    switch(color) {
        case white: color =  (code & dark) ? 0 : 67; break; // black vs white
        case grey:  color =  (code & dark) ? 60 : 7; break; // dark grey vs light grey
        default:    color += (code & dark) ? 0 : 60; break; // dark vs light
    }
    color += (code & bg) ? 40 : 30;
    asprintf(&attr_cache[code], "\033[%d%s%s%sm",
            color,
            (code & bold)      ? ";1" : "",
            (code & underline) ? ";4" : "",
            (code & inverse)   ? ";7" : "");
    return attr_cache[code];
}

static inline char *attr(u8 code) {
    char *res = attr_cache[code];
    return res ? res : mk_attr(code);
}

#define attr_reset  (enable_color ? "\033[0m" : "")
#define attr_strike (enable_color ? "\033[9m" : "")

bool trace_read = 0;
bool trace_write = 0;
int header_counter = 0;
int header_every = 20;
const char* asm_file = 0;

const char* asm_labels[65536] = {};
const char* asm_text[65536] = {};

char disasm[32];

u16 mem[0x8000];
u16 r[16], prev_r[16];
u16 special_regs[4], prev_special_regs[4];

const int FLAGS      = 0;
const int USER_FLAGS = 1;
const int USER_R13   = 2;
const int USER_R14   = 3;

const u16 FLAG_N = 1<<15;
const u16 FLAG_Z = 1<<14;
const u16 FLAG_C = 1<<13;
const u16 FLAG_V = 1<<12;
const u16 FLAG_I = 1<<0;

const int SS_NOP        = 0;
const int SS_ALU        = 1;
const int SS_LOAD       = 2;
const int SS_STORE      = 3;
const int SS_RD_FLAGS   = 4;
const int SS_WR_FLAGS   = 5;
const int SS_RD_SPECIAL = 6;
const int SS_WR_SPECIAL = 7;
const int SS_SWI        = 8;
const int SS_RTU        = 9;
const int SS_BRANCH     = 10;
const int SS_PRED       = 11;
const int SS_HALT       = 12;
const int SS_TRAP       = 13;

const u8 TOUCH_RD = 1;
const u8 TOUCH_WR = 2;

u8 touched_reg[16] = {};
bool touched_skip = 0;

u16 rd(int i)
{
    touched_reg[i] |= TOUCH_RD;
    return r[i];
}

void wr(int i, u16 value)
{
    touched_reg[i] |= TOUCH_WR;
    r[i] = value;
}

void touch_skip()
{
    touched_skip = 1;
}

void untouch_all()
{
    for(int i=0; i<16; i++) touched_reg[i] = 0;
    touched_skip = 0;
}

u16 mem_rd(u16 addr, bool wide)
{
    u16 addr_hi = addr >> 1;
    u16 addr_lo = (addr+1) >> 1;
    bool aligned = (addr & 1) == 0;

    if (wide) {
        if (aligned) {
            return mem[addr_hi];
        } else {
            return mem[addr_hi] << 8 | mem[addr_lo] >> 8;
        }
    }
    else {
        if (aligned) {
            return mem[addr_hi] >> 8;
        } else {
            return mem[addr_hi] & 0xff;
        }
    }
}

void mem_wr(u16 addr, bool wide, u16 data)
{
    u16 addr_hi = addr >> 1;
    u16 addr_lo = (addr+1) >> 1;
    bool aligned = (addr & 1) == 0;

    if (wide) {
        if (aligned) {
            mem[addr_hi] = data;
        } else {
            mem[addr_hi] = (mem[addr_hi] & 0xff00) | (data >> 8);
            mem[addr_lo] = (mem[addr_lo] & 0x00ff) | (data << 8);
        }
    }
    else {
        if (aligned) {
            mem[addr_hi] = (mem[addr_hi] & 0x00ff) | (data << 8);
        } else {
            mem[addr_hi] = (mem[addr_hi] & 0xff00) | (data & 0xff);
        }
    }
}

u16 clz(u16 val)
{
    if (!val) return 16;
    u16 i = 0;
    for( ; !(val & 0x8000); val <<= 1) i++;
    return i;
}

void trap()
{
    printf("TRAP\n");
    exit(0);
}

#define t(args...) sprintf(disasm, args)

void execute(u16 op)
{
    u8 dst          = (op >> 0)  & 0x0f;
    u8 src          = (op >> 4)  & 0x0f;
    u8 num4         = (op >> 4)  & 0x0f;
    u8 num5         = (op >> 8)  & 0x1f;
    u8 num8         = (op >> 4)  & 0xff;
    u8 sign         = (op >> 12) & 0x1;
    u8 major_cat    = (op >> 14) & 0x3;
    u8 arithlog_cat = (op >> 8)  & 0x3f;
    u8 mov8_br      = (op >> 12) & 0x3;
    u8 ldst_wide    = (op >> 13) & 0x1;
    u8 ldst_base    = (op >> 4)  & 0xf;
    u8 ldst_target  = (op >> 0)  & 0xf;
    u8 pred_cond    = (op >> 4)  & 0xf;
    u16 br_offset   = (op >> 0)  & 0xfff;
    u8 special_reg  = (op >> 4)  & 0xf;

    u16 cin = (special_regs[FLAGS] & FLAG_C) != 0;
    u16 cout;
    u32 res;

    int substate = SS_TRAP;

    bool mov_op   = 0;
    bool sub_op   = 0;
    bool add_op   = 0;
    bool trap_op  = 0;
    bool logic_op = 0;
    bool cmp_op   = 0;
    bool shift_op = 0;
    bool tst_op   = 0;
    bool signs_ne = 0;

    u16 ldst_addr = 0;

    bool br_link = 0;
    u16 br_addr = 0;

    bool pred_true = 0;

    bool flag_n = (special_regs[FLAGS] & FLAG_N) != 0;
    bool flag_z = (special_regs[FLAGS] & FLAG_Z) != 0;
    bool flag_c = (special_regs[FLAGS] & FLAG_C) != 0;
    bool flag_v = (special_regs[FLAGS] & FLAG_V) != 0;

    u8 special_special = 0;

    if (major_cat == 0x00) {
        substate = SS_ALU;
        signs_ne = (r[dst] ^ r[src]) >> 15;
        switch(arithlog_cat) {
            case 0x00: t("mov r%d, r%d", dst, src); mov_op = 1; res = rd(src); break;
            case 0x01: t("mvn r%d, r%d", dst, src); mov_op = 1; res = (u16)~rd(src); break;
            case 0x02: t("adc r%d, r%d", dst, src); add_op = 1; res = (u32)rd(dst) + rd(src) + cin; break;
            case 0x03: t("sbc r%d, r%d", dst, src); sub_op = 1; res = (u32)rd(dst) + (u16)~rd(src) + cin; break;
            case 0x04: t("add r%d, r%d", dst, src); add_op = 1; res = (u32)rd(dst) + rd(src); break;
            case 0x05: t("sub r%d, r%d", dst, src); sub_op = 1; res = (u32)rd(dst) + (u16)~rd(src) + 1u; break;
            case 0x06: t("rsc r%d, r%d", dst, src); sub_op = 1; res = (u32)rd(src) + (u16)~rd(dst) + cin; break;
            case 0x07: t("rsb r%d, r%d", dst, src); sub_op = 1; res = (u32)rd(src) + (u16)~rd(dst) + 1u; break;

            case 0x08: t("clz r%d, r%d", dst, src); mov_op = 1; res = clz(rd(src)); break;
            case 0x09: t("???");                    substate = SS_TRAP; break;
            case 0x0a: t("mul r%d, r%d", dst, src); logic_op = 1; res = ((u32)rd(dst) * rd(src)) & 0xffff; break;
            case 0x0b: t("muh r%d, r%d", dst, src); logic_op = 1; res = ((u32)rd(dst) * rd(src)) >> 16; break;
            case 0x0c: t("and r%d, r%d", dst, src); logic_op = 1; res = rd(dst) & rd(src); break;
            case 0x0d: t("cmp r%d, r%d", dst, src); cmp_op = 1; res = (u32)rd(dst) + (u16)~rd(src) + 1u; break;
            case 0x0e: t("cmn r%d, r%d", dst, src); cmp_op = 1; res = (u32)rd(dst) + rd(src); break;
            case 0x0f: t("???");                    substate = SS_TRAP; break;

            // ROR
            case 0x10:
                t("ror r%d, r%d", dst, src);
                if ((rd(src) & 0xf)==0) {
                    logic_op = 1;
                    res = rd(dst);
                } else {
                    shift_op = 1;
                    res = rd(dst) << (16u-(rd(src) & 0xf)) |
                        rd(dst) >>      (rd(src) & 0xf);
                    cout = (rd(dst) >> ((rd(src)-1u) & 0xf)) & 1;
                }
                break;
            // LSL
            case 0x11:
                t("lsl r%d, r%d", dst, src);
                shift_op = 1;
                if (rd(src) > 0u) {
                    res = rd(dst) << rd(src);
                    cout = (rd(src) <= 16u) && ((rd(dst) >> (16u-rd(src))) & 1);
                } else {
                    res = rd(dst);
                    cout = 0;
                }
                break;
            // LSR
            case 0x12:
                t("lsr r%d, r%d", dst, src);
                shift_op = 1;
                if (rd(src) > 0u) {
                    res = rd(dst) >> rd(src);
                    cout = (rd(dst) >> (rd(src)-1u)) & 1;
                } else {
                    res = rd(dst);
                    cout = 0;
                }
                break;
            // ASR
            case 0x13:
                t("asr r%d, r%d", dst, src);
                shift_op = 1;
                if (rd(src) > 0u) {
                    res = rd(dst) >> rd(src);
                    if (rd(dst) & 0x8000) res |= (~0) << (16u-rd(src));
                    cout = (rd(dst) >> (rd(src)-1u)) & 1;
                } else {
                    res = rd(dst);
                    cout = 0;
                }
                break;

            case 0x14: t("orr r%d, r%d", dst, src); logic_op = 1; res = rd(dst) | rd(src); break;
            case 0x15: t("eor r%d, r%d", dst, src); logic_op = 1; res = rd(dst) ^ rd(src); break;
            case 0x16: t("bic r%d, r%d", dst, src); logic_op = 1; res = rd(dst) & ~rd(src); break;
            case 0x17: t("tst r%d, r%d", dst, src); tst_op = 1;   res = rd(dst) & rd(src); break;

            // RRX / ROR#
            case 0x18:
                shift_op = 1;
                if (num4 == 0) {
                    t("rrx r%d", dst);
                    res = (cin ? 0x8000 : 0) | (rd(dst) >> 1);
                    cout = rd(dst) & 1;
                } else {
                    t("ror r%d, #%d", dst, num4);
                    shift_op = 1;
                    res = rd(dst) << (16u-num4) |
                        rd(dst) >>      num4;
                    cout = (rd(dst) >> (num4-1u)) & 1;
                }
                break;

            case 0x19:
                t("lsl r%d, #%d", dst, num4);
                shift_op = 1;
                if (num4 > 0u) {
                    res = rd(dst) << num4;
                    cout = (rd(dst) >> (16u-num4)) & 1;
                } else {
                    res = rd(dst);
                    cout = 0;
                }
                break;
            case 0x1a:
                t("lsr r%d, #%d", dst, num4);
                shift_op = 1;
                if (num4 > 0u) {
                    res = rd(dst) >> num4;
                    cout = (rd(dst) >> (num4-1u)) & 1;
                } else {
                    res = rd(dst);
                    cout = 0;
                }
                break;
            case 0x1b:
                t("asr r%d, #%d", dst, num4);
                shift_op = 1;
                if (num4 > 0u) {
                    res = rd(dst) >> num4;
                    if (rd(dst) & 0x8000) res |= (~0) << (16u-num4);
                    cout = (rd(dst) >> (num4-1u)) & 1;
                } else {
                    res = rd(dst);
                    cout = 0;
                }
                break;

            case 0x1c: t("orr r%d, #bit %d", dst, num4); logic_op = 1; res = rd(dst) | (1<<num4); break;
            case 0x1d: t("eor r%d, #bit %d", dst, num4); logic_op = 1; res = rd(dst) ^ (1<<num4); break;
            case 0x1e: t("bic r%d, #bit %d", dst, num4); logic_op = 1; res = rd(dst) & ~(1<<num4); break;
            case 0x1f: t("tst r%d, #bit %d", dst, num4); tst_op = 1;   res = rd(dst) & (1<<num4); break;

            default:
                if (dst != 0xf) {
                    add_op = 1;
                    signs_ne = (rd(dst)>>15) != sign;
                    if (sign == 0) {
                        t("add r%d, #0x%02x", dst, num8);
                        res = (u32)rd(dst) + num8;
                    } else {
                        u16 delta = (u16)num8 | 0xff00;
                        t("sub r%d, #0x%02x", dst, -(signed short)delta);
                        res = (u32)rd(dst) + delta;
                    }
                }
                else if ((op>>8 & 0x1f) == 0x1f) {
                    substate = SS_PRED;
                    switch(pred_cond) {
                        case 0x0: t("preq"); pred_true = flag_z; break;
                        case 0x1: t("prne"); pred_true = !flag_z; break;
                        case 0x2: t("prcs"); pred_true = flag_c; break;
                        case 0x3: t("prcc"); pred_true = !flag_c; break;
                        case 0x4: t("prmi"); pred_true = flag_n; break;
                        case 0x5: t("prpl"); pred_true = !flag_n; break;
                        case 0x6: t("prvs"); pred_true = flag_v; break;
                        case 0x7: t("prvc"); pred_true = !flag_v; break;
                        case 0x8: t("prhi"); pred_true = flag_c && !flag_z; break;
                        case 0x9: t("prls"); pred_true = !flag_c || flag_z; break;
                        case 0xa: t("prge"); pred_true = flag_n == flag_v; break;
                        case 0xb: t("prlt"); pred_true = flag_n != flag_v; break;
                        case 0xc: t("prgt"); pred_true = !flag_z && (flag_n == flag_v); break;
                        case 0xd: t("prle"); pred_true = flag_z || (flag_n ^ flag_v); break;
                        case 0xe: t("nop"); substate = SS_NOP; break;
                        case 0xf: t("hlt"); substate = SS_HALT; break;
                    }
                }
                else if ((op & 0xf00f) == 0x200f) {
                    t("swi #%d", num8);
                    substate = SS_SWI;
                }
                else switch(op & 0xff0f) {
                    case 0x300f: t("mrs r%d, flags", special_reg); substate = SS_RD_FLAGS; break;
                    case 0x310f: t("msr flags, r%d", special_reg); substate = SS_WR_FLAGS; break;
                    case 0x320f: t("mrs r%d, uflags", special_reg); substate = SS_RD_SPECIAL; special_special = USER_FLAGS; break;
                    case 0x330f: t("msr uflags, r%d", special_reg); substate = SS_WR_SPECIAL; special_special = USER_FLAGS; break;
                    case 0x340f: t("mrs r%d, u13", special_reg); substate = SS_RD_SPECIAL; special_special = USER_R13; break;
                    case 0x350f: t("msr u13, r%d", special_reg); substate = SS_WR_SPECIAL; special_special = USER_R13; break;
                    case 0x360f: t("mrs r%d, u14", special_reg); substate = SS_RD_SPECIAL; special_special = USER_R14; break;
                    case 0x370f: t("msr u14, r%d", special_reg); substate = SS_WR_SPECIAL; special_special = USER_R14; break;
                    case 0x380f: t("rtu r%d", special_reg); substate = SS_RTU; break;
                    default: t("???"); substate = SS_TRAP; break;
                }
                break;
        }
    }
    else if (major_cat == 0x01) {
        if (ldst_wide) {
            t("ldw r%d, [r%d, #%d]", ldst_target, ldst_base, num5);
        } else {
            t("ldb r%d, [r%d, #%d]", ldst_target, ldst_base, num5);
        }
        substate = SS_LOAD;
        ldst_addr = rd(ldst_base) + num5;
    }
    else if (major_cat == 0x02) {
        if (ldst_wide) {
            t("stw r%d, [r%d, #%d]", ldst_target, ldst_base, num5);
        } else {
            t("stb r%d, [r%d, #%d]", ldst_target, ldst_base, num5);
        }
        substate = SS_STORE;
        ldst_addr = rd(ldst_base) + num5;
    }
    else if (major_cat == 0x03) {
        switch(mov8_br) {
            case 0x0: t("mov r%d, #0x00%02x", dst, num8); substate = SS_ALU; mov_op = 1; res = (u16)num8; break;
            case 0x1: t("mov r%d, #0x%02x00", dst, num8); substate = SS_ALU; mov_op = 1; res = (u16)num8 << 8; break;
            default:
                substate = SS_BRANCH;
                br_link = mov8_br == 0x3;
                if (br_offset & 0x800) {
                    br_addr = r[15] + (br_offset<<1 | 0xf000);
                } else {
                    br_addr = r[15] + (br_offset<<1);
                }
                if (br_link) {
                    t("bl 0x%04x", br_addr);
                } else {
                    t("bra 0x%04x", br_addr);
                }
                break;
        }
    }

    if (add_op | sub_op | cmp_op) cout = (res >> 16) & 1;

    bool wr_reg = add_op | sub_op          | shift_op | logic_op | mov_op ;
    bool wr_nz  = add_op | sub_op | cmp_op | shift_op | logic_op | tst_op ;
    bool wr_c   = add_op | sub_op | cmp_op | shift_op                     ;
    bool wr_v   = add_op | sub_op | cmp_op                                ;
    bool nout = (res >> 15) & 1;
    bool zout = (res & 0xffff) == 0;
    bool vout = nout ^ signs_ne ^ cout ^ (sub_op | cmp_op);

    switch(substate) {
        case SS_NOP:
            break;
        case SS_ALU:
            if (wr_reg) {
                wr(dst, res);
            }
            u16 fl = special_regs[FLAGS];
            if (wr_nz) { fl &= ~FLAG_N; fl |= (nout ? FLAG_N : 0); }
            if (wr_nz) { fl &= ~FLAG_Z; fl |= (zout ? FLAG_Z : 0); }
            if (wr_c)  { fl &= ~FLAG_C; fl |= (cout ? FLAG_C : 0); }
            if (wr_v)  { fl &= ~FLAG_V; fl |= (vout ? FLAG_V : 0); }
            special_regs[FLAGS] = fl;
            break;

        case SS_LOAD:
            wr(ldst_target, mem_rd(ldst_addr, ldst_wide));
            if (trace_read) {
                printf("READ %s [%04x] => %04x\n", ldst_wide ? "WORD" : "BYTE", ldst_addr, r[ldst_target]);
            }
            break;
        case SS_STORE:
            if (trace_write) {
                printf("WRITE %s [%04x] <= %04x\n", ldst_wide ? "WORD" : "BYTE", ldst_addr, r[ldst_target]);
            }
            mem_wr(ldst_addr, ldst_wide, r[ldst_target]);
            break;
        case SS_RD_FLAGS:
            wr(special_reg, special_regs[FLAGS]);
            break;
        case SS_WR_FLAGS:
            special_regs[FLAGS] = rd(special_reg);
            break;
        case SS_BRANCH:
            if (br_link) {
                wr(14, r[15]);
            }
            r[15] = br_addr;
            break;
        case SS_PRED:
            if (!pred_true) {
                touch_skip();
                r[15] += 2;
            }
            break;
        case SS_RD_SPECIAL:
            wr(special_reg, special_regs[special_special]);
            break;
        case SS_WR_SPECIAL:
            special_regs[special_special] = rd(special_reg);
            break;
        case SS_SWI:
        case SS_RTU:
        case SS_HALT:
        case SS_TRAP:
            trap();
            break;
    }
}

void trace_headers()
{
    if (header_every == 0) {
        return;
    }
    if (header_counter == 0) {
        printf("\n");
        printf("%s", attr(bold|blue));
        if (enable_ascii) {
            printf("flag   r0    r1    r2    r3    r4    r5    r6    r7    r8    r9    r10   r11   r12   r13   r14   pc\n");
        } else {
            printf("flag  r0   r1   r2   r3   r4   r5   r6   r7   r8   r9   r10  r11  r12  r13  r14  pc\n");
        }
        printf("%s", attr_reset);
    }
    header_counter++;
    if (header_counter == header_every) {
        header_counter = 0;
    }
}

void trace_flags()
{
    struct {
        u16 mask;
        const char* off;
        const char* on;
    } info[4] = {
        { FLAG_N, " ", "N"},
        { FLAG_Z, " ", "Z"},
        { FLAG_C, " ", "C"},
        { FLAG_V, " ", "V"}
    };
    for(int i=0; i<4; i++) {
        u16 pre = prev_special_regs[FLAGS] & info[i].mask;
        u16 now = special_regs[FLAGS] & info[i].mask;
        printf("%s%s%s",
                (now == pre) ? "" : attr(dark|red),
                now ? info[i].on : info[i].off,
                (now == pre) ? "" : attr_reset);
    }
    printf(" ");
}

void trace_regs()
{
    if (enable_ascii) {
        bool old_diff = 0;
        for(int i=0; i<16; i++) {
            u8 touch = touched_reg[i];
            if (touch & TOUCH_WR) {
                printf("[%04x]", r[i]);
            }
            else if (touch & TOUCH_RD) {
                printf(" %04x ", r[i]);
            }
            else {
                printf(" %04x ", r[i]);
            }
        }
    }
    else {
        printf("%s", attr(grey));

        u8 old_touch = 0;
        for(int i=0; i<16; i++) {
            if (i>0) printf(" ");

            u8 touch = touched_reg[i];
            if (touch != old_touch) {
                if (touch & TOUCH_WR) {
                    printf("%s", attr(dark|red));
                }
                else if (touch & TOUCH_RD) {
                    printf("%s", attr(dark|green));
                }
                else {
                    printf("%s", attr(grey));
                }
            }
            printf("%04x", r[i]);
            old_touch = touch;
        }
        printf("%s", attr_reset);
    }
}

void dw(u16 addr, u16 data)
{
    mem[addr>>1] = data;
}

void load_prog()
{
    const char *hi_file = "out/mem.bin.0";
    const char *lo_file = "out/mem.bin.1";
    FILE* hi_fp = fopen(hi_file, "r");
    FILE* lo_fp = fopen(lo_file, "r");
    if (hi_fp == 0 || lo_fp == 0) {
        fclose(hi_fp);
        fclose(lo_fp);
        fprintf(stderr, "could not load %s, %s\n", hi_file, lo_file);
        exit(1);
    }
    for(int i=0; i<0x8000; i++) {
        u8 hi, lo;
        fscanf(hi_fp, "%hhx", &hi);
        fscanf(lo_fp, "%hhx", &lo);
        mem[i] = (u16)hi<<8 | lo;
    }
    fclose(hi_fp);
    fclose(lo_fp);
}

void load_asm()
{
    if (asm_file == 0) {
        return;
    }

    u16 org = 0x0000;
    u16 opcode;

    FILE *fp = fopen(asm_file, "r");
    if (fp == 0) {
        fprintf(stderr, "could not load %s\n", asm_file);
        exit(1);
    }
    int lineno = 0;
    char buf[1024];
    while(fgets(buf, sizeof(buf), fp)) {
        lineno++;
        char *end = strchr(buf, '\n');
        if (end) *end = '\0';

        if (buf[0] == '.') {
            // TODO - label should actually refer to next org read in?
            asm_labels[org+2] = strdup(buf+1);
        }
        else if (2 == sscanf(buf, "%hx %hx ; ", &org, &opcode)) {
            asm_text[org] = strdup(buf+12);
        }
        else if (buf[0] == ';') {
            // ignore comment
        }
        else {
            fprintf(stderr, "%s:%d: syntax error\n", asm_file, lineno);
            exit(1);
        }
    }

    if (ferror(fp)) {
        fprintf(stderr, "%s:%d: while reading: %s\n", asm_file, lineno, strerror(errno));
        exit(1);
    }

    fclose(fp);
}

typedef struct
{
    const char* prog;   // name of program
    const char* opt;    // current option
    const char** v;     // v[0] is next arg
    int c;              // count of remaining args
} args;

typedef struct
{
    char *short_opt;
    char *long_opt;
    char *arg_opt;
    char *msg;
    void (*fn)(args*);
} option;

void opt_trace_write(args *args)
{
    trace_write = 1;
}

void opt_trace_read(args *args)
{
    trace_read = 1;
}

const char *arg_value(args *args)
{
    if (--args->c == 0) {
        fprintf(stderr, "%s: missing value\n", args->opt);
        exit(1);
    }
    return *++args->v;
}

void opt_header_every(args *args)
{
    const char *arg = arg_value(args);
    char *endptr = 0;
    long val = (int)strtol(arg, &endptr, 0);
    if (val < 0 || val > 255 || *endptr) {
        fprintf(stderr, "%s: invalid value %s\n", args->opt, arg);
        exit(1);
    }
    header_every = (int)val;
}

void opt_asm(args *args)
{
    asm_file = arg_value(args);
}

void opt_color(args *args)
{
    enable_color = 1;
    enable_ascii = 0;
}

void opt_plain(args *args)
{
    enable_color = 0;
    enable_ascii = 0;
}

void opt_ascii(args *args)
{
    enable_color = 0;
    enable_ascii = 1;
}

void opt_pre(args *args)
{
    mode_post = 0;
}

void opt_post(args *args)
{
    mode_post = 1;
}

void opt_help(args *args);

option options[] = {
    {"-h", "--help",         "",     "display this message, and exit",         &opt_help},
    {"-A", "--asm",          "FILE", "display assembly from FILE",             &opt_asm},
    {"-H", "--header-every", "",     "output header every N lines (0=none)",   &opt_header_every},
    {"-r", "--trace-read",   "",     "trace memory reads",                     &opt_trace_read},
    {"-w", "--trace-write" , "",     "trace memory writes",                    &opt_trace_write},
    {"-c", "--color",        "",     "coloured output (default)",              &opt_color},
    {"-a", "--ascii",        "",     "ascii decorated output",                 &opt_ascii},
    {"-p", "--plain",        "",     "undecorated output",                     &opt_plain},
    {"",   "--pre",          "",     "output pre-instruction state (default)", &opt_pre},
    {"",   "--post",         "",     "output post-instruction state",          &opt_post},
};

void opt_help(args *args)
{
    fprintf(stderr, "%s: vixen cpu simulator\n\nOptions:\n", args->prog);

    int maxw = 0;
    for(int i=0; i<sizeof(options)/sizeof(options[0]); ++i) {
        option *opt = &options[i];
        int w = 2;  // indent
        if (*opt->short_opt) {
            w += strlen(opt->short_opt);
            if (*opt->long_opt) {
                w += 2; // comma, space
            }
        }
        if (*opt->long_opt) {
            w += strlen(opt->long_opt);
        }
        if (*opt->arg_opt) {
            w += 1; // space
            w += strlen(opt->arg_opt);
        }
        w += 2; // spaces before message
        if (w > maxw) maxw = w;
    }

    for(int i=0; i<sizeof(options)/sizeof(options[0]); ++i) {
        option *opt = &options[i];
        char buf[200];
        strcpy(buf, "  ");
        if (*opt->short_opt) {
            strcat(buf, opt->short_opt);
            if (*opt->long_opt) {
                strcat(buf, ", ");
            }
        }
        if (*opt->long_opt) {
            strcat(buf, opt->long_opt);
        }
        if (*opt->arg_opt) {
            strcat(buf, " ");
            strcat(buf, opt->arg_opt);
        }
        int w = strlen(buf);
        memset(buf + strlen(buf), ' ', maxw-w);
        strcpy(buf + maxw, opt->msg);
        strcat(buf, "\n");
        fputs(buf, stderr);
    }
    exit(0);
}

void parse_args(int argc, const char* argv[]) {
    args args = { argv[0], 0, argv, argc };

    while(--args.c) {
        args.opt = *++args.v;
        bool found = 0;
        for(int j=0; j<sizeof(options) / sizeof(options[0]); j++) {
            option *opt = &options[j];
            if (
                    *opt->short_opt && 0==strcmp(args.opt, opt->short_opt) ||
                    *opt->long_opt && 0==strcmp(args.opt, opt->long_opt)
            ) {
                opt->fn(&args);
                found = 1;
                break;
            }
        }
        if (!found) {
            fprintf(stderr, "%s: unknown option `%s'.\n", args.prog, args.opt);
            exit(1);
        }
    }
}

int main(int argc, const char* argv[])
{
    parse_args(argc, argv);
    load_prog();
    load_asm();

    for(int i=0; i<16; i++) r[i] = 0;
    for(int i=0; i<4; i++) special_regs[i] = 0;

    const char spaces[] = "                            ";

    while(1) {
        u16 pc = r[15];
        u16 op = mem_rd(pc, 1);
        if (mode_post) {
            r[15] = pc + 2;
            untouch_all();
            execute(op);
        }

        trace_headers();
        const char *label = asm_labels[pc];
        if (label != 0) {
            if (enable_ascii) {
                printf("%102s.%s\n", "", label);
            } else {
                printf("%85s.%s\n", "", label);
            }
        }
    
        trace_flags();
        trace_regs();
        printf(" %s; %s%s%s\n", 
                attr(dark|green),
                touched_skip ? attr_strike : "",
                (asm_file && asm_text[pc]) ? asm_text[pc] : disasm,
                attr_reset
        );

        if (!mode_post) {
            r[15] = pc + 2;
            untouch_all();
            execute(op);
        }
    }
}
