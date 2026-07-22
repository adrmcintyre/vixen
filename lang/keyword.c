#include "header.h"

// each table should be arranged in ascii order
const u8 keywords_hpx[] = {
    op_print,    info_cmd_any,  'p','r','i','n','t',
    op_proc,     info_control,  'p','r','o','c',
    fail, 0
};
const u8 keywords_aiqy[] = {
    op_inf,      info_const,    'I','n','f',

    op_abs,      info_fn1,      'a','b','s',
    op_asc,      info_fn1,      'a','s','c',

    op_if,       info_control,  'i','f',
    op_input,    info_cmd_any,  'i','n','p','u','t',
    op_int,      info_fn1,      'i','n','t',
    fail, 0
};
const u8 keywords_bjrz[] = {
    op_break,    info_control,  'b','r','e','a','k',
    op_repeat,   info_control,  'r','e','p','e','a','t',
    op_return,   info_control,  'r','e','t','u','r','n',
    op_right,    info_fn2,      'r','i','g','h','t',
    op_rnd,      info_fn0,      'r','n','d',
    fail, 0
};
const u8 keywords_cks[] = {
    op_chr,      info_fn1,      'c','h','r',
    op_class,    info_control,  'c','l','a','s','s',

    op_sgn,      info_fn1,      's','g','n',
    op_sqr,      info_fn1,      's','q','r',
    op_stop,     info_cmd0,     's','t','o','p',
    op_str,      info_fn1,      's','t','r',
    op_substr,   info_fn3,      's','u','b','s','t','r',
    fail, 0
};
const u8 keywords_dlt[] = {
    op_true,     info_const,    'T','r','u','e',

    op_left,     info_fn2,      'l','e','f','t',
    op_len,      info_fn1,      'l','e','n',
    fail, 0
};
const u8 keywords_emu[] = {
    op_else,     info_control,  'e','l','s','e',
    op_end,      info_control,  'e','n','d',
    op_endif,    info_control,  'e','n','d','i','f',

    op_until,    info_control,  'u','n','t','i','l',
    fail, 0
};
const u8 keywords_fnv[] = {
    op_false,    info_const,    'F','a','l','s','e',
    op_nan,      info_const,    'N','a','N',
    op_float,    info_fn1,      'f','l','o','a','t',
    op_func,     info_control,  'f','u','n','c',
    fail, 0
};
const u8 keywords_gow[] = {
    op_wend,     info_control,  'w','e','n','d',
    op_while,    info_control,  'w','h','i','l','e',
    fail, 0
};

const u8* keywords[] = {
    keywords_hpx,
    keywords_aiqy,
    keywords_bjrz,
    keywords_cks,
    keywords_dlt,
    keywords_emu,
    keywords_fnv,
    keywords_gow
};

// Returns 1 if token_ptr..input_ptr identifies a keyword
// with kw set to op and info.
OpData kw;

bool lookup_keyword()
{
    u8 ch = *token_ptr;
    u16 i = ch & 7;
    const u8 *kwd_ptr = keywords[i];

    kw.op = (Op) *kwd_ptr++;
    while(kw.op != fail) {
        const u8* p = token_ptr;

        kw.info = (OpInfo) *kwd_ptr++;

        u8 kwd_ch;
        while(1) {
            ch = *p;
            kwd_ch = *kwd_ptr++;
            if (kwd_ch & 0x80) {
                if (p != input_ptr) break;
                return true;
            }
            if (kwd_ch > ch) {
                return false;
            }
            if (kwd_ch < ch) {
                // skip until id byte
                while(1) {
                    kwd_ch = *kwd_ptr++;
                    if (kwd_ch & 0x80) break;
                }
                break;
            }
            p++;
        }
        kw.op = (Op) kwd_ch;
    }
    return false;
}
