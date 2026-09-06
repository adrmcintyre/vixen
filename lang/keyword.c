#include "header.h"

// TODO - document table format

typedef struct {
    char *name;
    Op op;
    OpInfo info;
} Keyword;

// each table should be arranged in ascii order
const Keyword keywords_hpx[] = {
    {"pop",         op_pop,         info_fn1,       },
    {"print",       op_print,       info_cmd_any,   },
    {0,             fail,           0,              },
};
const Keyword keywords_aiqy[] = {
    {"Inf",         op_inf,         info_const,    },
     
    {"abs",         op_abs,         info_fn1,      },
    {"append",      op_append,      info_cmd2,     },
    {"asc",         op_asc,         info_fn1,      },
     
    {"if",          op_if,          info_control,  },
    {"in",          op_in,          info_control,  },
    {"input",       op_input,       info_cmd_any,  },
    {"int",         op_int,         info_fn1,      },
    {0,             fail,           0,             },
};
const Keyword keywords_bjrz[] = {
    {"break",       op_break,       info_control,  },
     
    {"repeat",      op_repeat,      info_control,  },
    {"return",      op_return,      info_control,  },
    {"rnd",         op_rnd,         info_fn0,      },
    {0,             fail,           0,             },
};
const Keyword keywords_cks[] = {
    {"chr",         op_chr,         info_fn1,      },
    {"class",       op_class,       info_control,  },
    {"continue",    op_continue,    info_control,  },
     
    {"sgn",         op_sgn,         info_fn1,      },
    {"sqr",         op_sqr,         info_fn1,      },
    {"stop",        op_stop,        info_cmd0,     },
    {"str",         op_str,         info_fn1,      },
    {0,             fail,           0,             },
};
const Keyword keywords_dlt[] = {
    {"True",        op_true,        info_const,    },
    
    {"len",         op_len,         info_fn1,      },
    {0,             fail,           0,             },
};
const Keyword keywords_emu[] = {
    {"else",        op_else,        info_control,  },
    {"end",         op_end,         info_control,  },
    {"endif",       op_endif,       info_control,  },
    {"extend",      op_extend,      info_cmd2,     },
     
    {"until",       op_until,       info_control,  },
    {0,             fail,           0,             },
};
const Keyword keywords_fnv[] = {
    {"False",       op_false,       info_const,    },
    {"NaN",         op_nan,         info_const,    },
    {"None",        op_none,        info_const,    },
    {"float",       op_float,       info_fn1,      },
    {"for",         op_for,         info_control,  },
    {"func",        op_func,        info_control,  },
    {"next",        op_next,        info_control,  },
    {0,             fail,           0,             },
};
const Keyword keywords_gow[] = {
    {"wend",        op_wend,        info_control,  },
    {"while",       op_while,       info_control,  },
    {0,             fail,           0,             },
};

// Table of keywords indexed by the bottom 3 bits of the first character.
const Keyword* keywords[] = {
    keywords_hpx,
    keywords_aiqy,
    keywords_bjrz,
    keywords_cks,
    keywords_dlt,
    keywords_emu,
    keywords_fnv,
    keywords_gow
};

// TODO doc
OpData lookup_keyword(const u8* word_ptr, u16 word_len)
{
    const u8 *word_end_ptr = word_ptr + word_len;
    u8 ch = *word_ptr;
    u16 i = ch & 7;
    const Keyword *kwd_ptr = keywords[i];

    while (kwd_ptr->op != fail) {
        const u8* namep = (const u8*) kwd_ptr->name;
        const u8* wordp = word_ptr;
        while (1) {
            u8 namech = *namep;
            if (namech == 0) {
                // exact match
                if (wordp == word_end_ptr) {
                    return (OpData){.op=kwd_ptr->op, .info=kwd_ptr->info};
                }
                // input was just a prefix of the current keyword
                break;
            }
            u8 wordch = *wordp;
            if (namech < wordch) {
                break;
            }
            if (namech > wordch) {
                return (OpData){.op=fail};
            }
            namep++;
            wordp++;
        }
        kwd_ptr++;
    }
    return (OpData){.op=fail};
}

OpData opdata_from_value(Value value)
{
    return (OpData){.op=(value.u>>8), .info=(value.u & 0xff)};
}

Value opdata_to_value(OpData opdata)
{
    u16 u = ((u16)opdata.op)<<8 | (u16)(opdata.info);
    return (Value){.k=kind_keyword, .u=u};
}
