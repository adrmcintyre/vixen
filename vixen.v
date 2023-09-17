`default_nettype none

module vixen (
        input      clk,
        output reg mem_en,
        output reg mem_wr,
        output reg mem_wide,
        output reg [15:0] mem_addr,
        output reg [15:0] mem_din,
        input      [15:0] mem_dout,

        output [7:0] led
);
    // register file
    reg  [15:0] r[0:15];
    wire [15:0] pc = {r[15][15:1], 1'b0};
    reg  supervisor_mode;

    localparam
        FLAGS      = 2'd0,
        USER_FLAGS = 2'd1,
        USER_R13   = 2'd2,
        USER_R14   = 2'd3;

    reg [15:0] special_reg[0:3];

    wire [15:0] flags = special_reg[FLAGS];

    localparam RESET_VECTOR = 16'h0000;
    localparam TRAP_VECTOR  = 16'h0004;
    localparam SWI_VECTOR   = 16'h0008;
    localparam IRQ_VECTOR   = 16'h000c;
    wire irq_assert = pc == 16'h0104;

    localparam FLAG_N = 4'd15;
    localparam FLAG_Z = 4'd14;
    localparam FLAG_C = 4'd13;
    localparam FLAG_V = 4'd12;
    localparam FLAG_I = 4'd0;

    wire flag_n = flags[FLAG_N];     // negative
    wire flag_z = flags[FLAG_Z];     // zero
    wire flag_c = flags[FLAG_C];     // carry
    wire flag_v = flags[FLAG_V];     // overflow
    wire flag_i = flags[FLAG_I];     // interrupts

    wire [15:0] op = mem_dout;          // last instruction fetched
    wire [15:0] ld_value = mem_wide ? mem_dout : {8'b0, mem_dout[15:8]};

    // instruction decoding
    wire [3:0] dst              = op[3:0];      // alu dst reg
    wire [3:0] src              = op[7:4];      // alu src reg

    wire [3:0] op_num4          = op[7:4];      // 4 bit literal
    wire [4:0] op_num5          = op[12:8];     // 5 bit literal
    wire [7:0] op_num8          = op[11:4];     // 8 bit literal
    wire       op_sign          = op[12];       // sign bit for mov num8

    wire [1:0] op_major_cat     = op[15:14];    // op code major category
    wire [5:0] op_arithlog      = op[13:8];     // arithmetic/logical opcode subcat
    wire [1:0] op_mov8_br       = op[13:12];    // mov num8 / b / bl

    wire       op_ld_st_wide    = op[13];       // load/store size
    wire [3:0] op_ld_st_base    = op[7:4];      // reg specifying base address
    wire [3:0] op_ld_st_target  = op[3:0];      // reg to load/store

    wire [7:4] op_pred_cond     = op[7:4];      // condition code

    wire [11:0] op_br_offset    = op[11:0];     // signed branch offset

    wire [3:0] op_special_reg = op[7:4];
    reg  [1:0] op_special_special;

    // CPU state
    localparam
        RESET     = 3'd0,
        FETCH     = 3'd1,
        FETCH2    = 3'd2,
        EXECUTE   = 3'd3,
        LOAD      = 3'd4,
        LOAD2     = 3'd5;

    localparam
        SS_NOP        = 4'd0,
        SS_ALU        = 4'd1,
        SS_LOAD       = 4'd2,
        SS_STORE      = 4'd3,
        SS_RD_FLAGS   = 4'd4,
        SS_WR_FLAGS   = 4'd5,
        SS_RD_SPECIAL = 4'd6,
        SS_WR_SPECIAL = 4'd7,
        SS_SWI        = 4'd8,
        SS_RTU        = 4'd9,
        SS_BRANCH     = 4'd10,
        SS_PRED       = 4'd11,
        SS_HALT       = 4'd12,
        SS_TRAP       = 4'd13;

    reg [2:0] state = RESET;
    reg [3:0] substate = SS_NOP;
    reg [4*8-1:0] text;
    reg predicated;
    reg [3:0] reg_target;

    integer i;

    assign led = {substate==SS_HALT,state,substate};

    always @(posedge clk) begin
        case (state)
            RESET: begin
                special_reg[FLAGS]      <= 16'h0;
                special_reg[USER_FLAGS] <= 16'h0;
                special_reg[USER_R13]   <= 16'h0;
                special_reg[USER_R14]   <= 16'h0;

                for(i=0; i<=14; i=i+1) begin
                    r[i] <= 16'h0;
                end
                r[15] <= RESET_VECTOR;
                supervisor_mode <= 1'b1;
                predicated <= 1;

                mem_en   <= 0;
                mem_addr <= 0;
                mem_din  <= 0;
                mem_wr   <= 0;
                mem_wide <= 0;

                state <= FETCH;
            end

            FETCH: begin
                mem_addr <= pc;
                mem_wr   <= 0;
                mem_wide <= 1;
                mem_en   <= 1;

                state <= FETCH2;
            end

            FETCH2: begin
                if (flag_i && irq_assert) begin
                    supervisor_mode <= 1'b1;
                    special_reg[FLAGS][FLAG_I] <= 1'b0;     // disable interrupts
                    special_reg[USER_FLAGS] <= flags;
                    special_reg[USER_R13]  <= r[13];
                    special_reg[USER_R14]  <= r[14];
                    r[14] <= pc;
                    r[15] <= IRQ_VECTOR;
                    state <= FETCH;
                end
                else begin
                    mem_en <= 0;
                    predicated <= 1;
                    r[15] <= pc+2;
                    state <= predicated ? EXECUTE : FETCH;
                end
            end

            EXECUTE: begin
                mem_addr <= pc;
                mem_wr   <= 0;
                mem_wide <= 1;
                mem_en   <= 1;

                case (substate)
                    SS_NOP: begin
                        state <= FETCH2;
                    end

                    SS_ALU: begin
                        if (alu_wr_reg) begin
                            r[dst] <= alu_out;
                            if (dst == 15) begin
                                mem_addr <= alu_out;
                            end
                        end
                        if (alu_wr_nz) special_reg[FLAGS][FLAG_N] <= alu_n;
                        if (alu_wr_nz) special_reg[FLAGS][FLAG_Z] <= alu_z;
                        if (alu_wr_c)  special_reg[FLAGS][FLAG_C] <= alu_c;
                        if (alu_wr_v)  special_reg[FLAGS][FLAG_V] <= alu_v;

                        state <= FETCH2;
                    end

                    SS_LOAD: begin
                        reg_target <= ld_st_target;

                        mem_addr <= ld_st_addr;
                        mem_wr <= 0;
                        mem_wide <= ld_st_wide;
                        mem_en <= 1;

                        state <= LOAD;
                    end

                    SS_STORE: begin
                        mem_din <= r_target;
                        mem_addr <= ld_st_addr;
                        mem_wr <= 1;
                        mem_wide <= ld_st_wide;
                        mem_en <= 1;

                        state <= FETCH;
                    end

                    SS_SWI: begin
                        supervisor_mode <= 1'b1;
                        special_reg[FLAGS][FLAG_I] <= 1'b0;     // disable interrupts
                        special_reg[USER_FLAGS] <= flags;
                        special_reg[USER_R13]   <= r[13];
                        special_reg[USER_R14]   <= r[14];
                        r[14] <= pc;
                        r[15] <= SWI_VECTOR;
                        state <= FETCH;
                    end

                    SS_TRAP: begin
                        supervisor_mode <= 1'b1;
                        special_reg[FLAGS][FLAG_I] <= 1'b0;     // disable interrupts
                        special_reg[USER_FLAGS] <= flags;
                        special_reg[USER_R13]   <= r[13];
                        special_reg[USER_R14]   <= r[14];
                        r[14] <= pc;
                        r[15] <= TRAP_VECTOR;
                        state <= FETCH;
                    end

                    SS_RD_FLAGS: begin
                        r[op_special_reg] <= special_reg[FLAGS];
                        state <= FETCH2;
                    end

                    SS_WR_FLAGS: begin
                        special_reg[FLAGS] <= r[op_special_reg];
                        state <= FETCH2;
                    end

                    SS_RD_SPECIAL: begin
                        // TODO - trap when not in supervisor_mode?
                        if (supervisor_mode) begin
                            r[op_special_reg] <= special_reg[op_special_special];
                        end
                        state <= FETCH2;
                    end

                    SS_WR_SPECIAL: begin
                        // TODO - trap when not in supervisor_mode?
                        if (supervisor_mode) begin
                            special_reg[op_special_special] <= r[op_special_reg];
                        end
                        state <= FETCH2;
                    end

                    // return from supervisor mode
                    SS_RTU: begin
                        if (supervisor_mode) begin
                            supervisor_mode <= 1'b0;
                            r[13] <= special_reg[USER_R13];
                            r[14] <= special_reg[USER_R14];
                            r[15] <= r_src;
                            special_reg[FLAGS] <= special_reg[USER_FLAGS];
                            mem_addr <= r_src;
                        end
                        state <= FETCH2;
                    end

                    SS_BRANCH: begin
                        if (br_link) begin
                            r[14] <= pc;
                        end
                        r[15] <= br_addr;
                        mem_addr <= br_addr;
                        state <= FETCH2;
                    end

                    SS_PRED: begin
                        predicated <= pred_true;
                        state <= FETCH2;
                    end
                    
                    SS_HALT: begin
                        // enter a loop, no memory access
                        mem_addr <= pc-2;
                        mem_wr   <= 0;
                        mem_wide <= 1;
                        mem_en   <= 0;

                        state <= EXECUTE;
                    end

                    default: begin
                        // should be unreachable state
                        state <= RESET;
                    end

                endcase
            end

            LOAD: begin
                mem_en <= 0;
                state <= LOAD2;
            end

            LOAD2: begin
                mem_addr <= pc;
                mem_wr   <= 0;
                mem_wide <= 1;
                mem_en   <= 1;

                r[reg_target] <= ld_value;
                if (reg_target == 15) begin
                    mem_addr <= ld_value;
                end

                state <= FETCH2;
            end

            default: begin
                // should be unreachable state
                state <= RESET;
            end
        endcase
    end


    // ALU
    reg alu_mov_op;
    reg alu_add_op;
    reg alu_sub_op;
    reg alu_cmp_op;
    reg alu_shift_op;
    reg alu_logic_op;
    reg alu_tst_op;
    reg alu_c;
    reg [15:0] alu_out;
    reg alu_signs_ne;

    wire [15:0] r_dst = r[dst];
    wire [15:0] r_src = r[src];

    wire alu_wr_reg = alu_add_op | alu_sub_op              | alu_shift_op | alu_logic_op | alu_mov_op ;
    wire alu_wr_nz  = alu_add_op | alu_sub_op | alu_cmp_op | alu_shift_op | alu_logic_op | alu_tst_op ;
    wire alu_wr_c   = alu_add_op | alu_sub_op | alu_cmp_op | alu_shift_op                             ;
    wire alu_wr_v   = alu_add_op | alu_sub_op | alu_cmp_op                                            ;

    wire alu_n = alu_out[15];
    wire alu_z = alu_out == 16'b0;
    wire alu_v = alu_n ^ alu_signs_ne ^ alu_c ^ (alu_sub_op | alu_cmp_op);

    wire [3:0]  alu_reg  = dst;

    // Load / Store
    reg [15:0] ld_st_addr;
    reg [15:0] ld_st_data;
    reg [3:0]  ld_st_target;

    reg ld_st_wr;
    reg ld_st_rd;
    reg ld_st_wide;
    wire [15:0] r_base   = r[op_ld_st_base];
    wire [15:0] r_target = r[op_ld_st_target];

    // Branch unit
    reg        br_link;
    reg [15:0] br_addr;

    // Flags special ops
    reg       flags_load;
    reg       flags_save;
    reg [3:0] flags_target;

    // predication
    reg pred_true;

    always @* begin
        alu_mov_op   = 1'b0;
        alu_add_op   = 1'b0;
        alu_sub_op   = 1'b0;
        alu_shift_op = 1'b0;
        alu_logic_op = 1'b0;
        alu_cmp_op   = 1'b0;
        alu_tst_op   = 1'b0;
        alu_c        = 1'b0;
        alu_out      = 16'b0;
        alu_signs_ne = 1'b0;

        ld_st_addr   = 16'b0;
        ld_st_wide   = 1'b0;
        ld_st_data   = 16'b0;
        ld_st_target = 4'b0;

        br_link   = 1'b0;
        br_addr   = 16'b0;

        pred_true = 1'b1;

        flags_target = 4'b0;

        substate = SS_TRAP;
        text = "----";

        case (op_major_cat)
            2'b00: begin
                substate = SS_ALU;
                alu_signs_ne = r_dst[15] ^ r_src[15];

                // ALU ops take one of these forms:
                // 000o-oooo-ssss-rrrr ; op r_dst, r_src
                // 000o-oooo-nnnn-rrrr ; op r_dst, #num4
                // 000o-oooo-nnnn-rrrr ; op r_dst, #1<<num4
                // 0010-nnnn-nnnn-rrrr ; add r_dst, #num8
                // 0011-nnnn-nnnn-rrrr ; sub r_dst, #num8

                // 00??-????-????-????
                casez (op_arithlog)
                    6'b00_0000: {text, alu_mov_op, alu_out} = {"MOV ", 1'b1, r_src};    // mov r_dst, r_src
                    6'b00_0001: {text, alu_mov_op, alu_out} = {"MVN ", 1'b1, ~r_src};   // mvn r_dst, r_src

                    6'b00_0010: {text, alu_add_op, alu_c, alu_out} = {"ADC ", 1'b1, ({1'b0,r_dst} + {1'b0,r_src})  + {16'b0,flag_c}};   // adc r_dst, r_src
                    6'b00_0011: {text, alu_sub_op, alu_c, alu_out} = {"SBC ", 1'b1, ({1'b0,r_dst} + {1'b0,~r_src}) + {16'b0,flag_c}};   // sbc r_dst, r_src

                    6'b00_0100: {text, alu_add_op, alu_c, alu_out} = {"ADD ", 1'b1, ({1'b0,r_dst} + {1'b0,r_src})};                     // add r_dst, r_src
                    6'b00_0101: {text, alu_sub_op, alu_c, alu_out} = {"SUB ", 1'b1, ({1'b0,r_dst} + {1'b0,~r_src}) + {16'b0,1'b1}};     // sub r_dst, r_src

                    6'b00_0110: {text, alu_sub_op, alu_c, alu_out} = {"RSC ", 1'b1, ({1'b0,r_src} + {1'b0,~r_dst}) + {16'b0,flag_c}};   // rsc r_dst, r_src
                    6'b00_0111: {text, alu_sub_op, alu_c, alu_out} = {"RSB ", 1'b1, ({1'b0,r_src} + {1'b0,~r_dst}) + {16'b0,1'b1}};     // rsb r_dst, r_src

                    6'b00_1000: substate = SS_TRAP;                                                                 // unused (8 bits)
                    6'b00_1001: substate = SS_TRAP;                                                                 // unused (8 bits)
                    6'b00_1010: substate = SS_TRAP;                                                                 // unused (8 bits)
                    6'b00_1011: substate = SS_TRAP;                                                                 // unused (8 bits)

                    6'b00_1100: {text, alu_logic_op, alu_out}      = {"AND ", 1'b1, r_dst & r_src};                               // and r_dst, r_src
                    6'b00_1101: {text, alu_cmp_op, alu_c, alu_out} = {"CMP ", 1'b1, ({1'b0,r_dst} + {1'b0,~r_src}) + 1'b1};       // cmp r_dst, r_src
                    6'b00_1110: {text, alu_cmp_op, alu_c, alu_out} = {"CMN ", 1'b1, ({1'b0,r_dst} + {1'b0,r_src})};               // cmn r_dst, r_src

                    6'b00_1111: {text, alu_logic_op, alu_out} = {"MUL ", 1'b1, r_dst * r_src};                                    // mul r_dst, r_src 

                    6'b01_0000:                                                                             // ror r_dst, r_src
                        begin
                            if (r_src[3:0] == 0) begin
                                {text, alu_logic_op, alu_out} = {"ROR ", 1'b1, r_dst};
                            end
                            else begin
                                alu_shift_op = 1'b1;
                                text = "ROR ";
                                {alu_out, alu_c} = {r_dst[14:0],2'b00} << (15-r_src[3:0]) | {r_dst,1'b0} >> r_src[3:0];
                            end
                        end
                    6'b01_0001: {text, alu_shift_op, alu_c, alu_out} = {"LSL ", 1'b1, {1'b0,r_dst} << r_src};             // lsl r_dst, r_src
                    6'b01_0010: {text, alu_shift_op, alu_out, alu_c} = {"LSR ", 1'b1, {r_dst,1'b0} >> r_src};             // lsr r_dst, r_src
                    6'b01_0011: {text, alu_shift_op, alu_out, alu_c} = {"ASR ", 1'b1, $signed({r_dst,1'b0}) >>> r_src};   // asr r_dst, r_src
                    6'b01_0100: {text, alu_logic_op, alu_out} = {"ORR ", 1'b1, r_dst | r_src};                            // orr r_dst, r_src
                    6'b01_0101: {text, alu_logic_op, alu_out} = {"EOR ", 1'b1, r_dst ^ r_src};                            // eor r_dst, r_src
                    6'b01_0110: {text, alu_logic_op, alu_out} = {"BIC ", 1'b1, r_dst & ~r_src};                           // bic r_dst, r_src
                    6'b01_0111: {text, alu_tst_op,   alu_out} = {"TST ", 1'b1, r_dst & r_src};                            // tst r_dst, r_src

                    6'b01_1000:
                        begin
                            alu_shift_op = 1'b1;
                            if (op_num4 == 0) begin
                                {text, alu_out, alu_c} = {"RRX ", flag_c, r_dst};                                         // rrx r_dst        ; when num4 == 0
                            end
                            else begin
                                text = "ROR#";
                                {alu_out, alu_c} = {r_dst[14:0],2'b00} << (15-op_num4) | {r_dst,1'b0} >> op_num4;         // ror r_dst, #num4 ; when num4 != 0
                            end
                        end

                    6'b01_1001: {text, alu_shift_op, alu_c, alu_out} = {"LSL#", 1'b1, {1'b0,r_dst} << op_num4};           // lsl r_dst, #num4   ; IDEA: steal num==0 - 16 encodings
                    6'b01_1010: {text, alu_shift_op, alu_out, alu_c} = {"LSR#", 1'b1, {r_dst,1'b0} >> op_num4};           // lsr r_dst, #num4   ; IDEA: steal num==0 - 16 encodings
                    6'b01_1011: {text, alu_shift_op, alu_out, alu_c} = {"ASR#", 1'b1, $signed({r_dst,1'b0}) >>> op_num4}; // asr r_dst, #num4   ; IDEA: steal num==0 - 16 encodings

                    6'b01_1100: {text, alu_logic_op, alu_out} = {"ORR#", 1'b1, r_dst |  (16'b1 << op_num4)};              // orr r_dst, #1<<num4
                    6'b01_1101: {text, alu_logic_op, alu_out} = {"EOR#", 1'b1, r_dst ^  (16'b1 << op_num4)};              // eor r_dst, #1<<num4
                    6'b01_1110: {text, alu_logic_op, alu_out} = {"BIC#", 1'b1, r_dst & ~(16'b1 << op_num4)};              // bic r_dst, #1<<num4
                    6'b01_1111: {text, alu_tst_op,   alu_out} = {"TST#", 1'b1, r_dst &  (16'b1 << op_num4)};              // tst r_dst, #1<<num4

                    // 001n-nnnn-nnnn-rrrr
                    6'b1?_????: begin
                        // 001n-nnnn-nnnn-rrrr                                      // add r_dst, #signed_num9 ; r_dst != r15 - IDEA: do not set flags; IDEA steal num==0 - 16 encodings
                        if (dst != 4'b1111) begin
                            text = "ADD#";
                            alu_add_op = 1'b1;
                            alu_signs_ne = r_dst[15] ^ op_sign;
                            {alu_c, alu_out} = {1'b0,r_dst} + {{9{op_sign}},op_num8};
                        end
                        // 001?-????-????-1111
                        else if (op[12:8] == 5'b1_1111) begin
                            // 0011-1111-cccc-1111 : pr<cond>
                            substate = SS_PRED;
                            case (op_pred_cond)
                                4'b0000: {text, pred_true} = {"PREQ", flag_z};                        // preq      ; ==
                                4'b0001: {text, pred_true} = {"PRNE", ~flag_z};                       // prne      ; !=
                                4'b0010: {text, pred_true} = {"PRCS", flag_c};                        // prcs prhs ; unsigned >= or carry out    (or no borrow)
                                4'b0011: {text, pred_true} = {"PRCC", ~flag_c};                       // prcc prlo ; unsigned <  or no carry out (or borrow)
                                4'b0100: {text, pred_true} = {"PRMI", flag_n};                        // prmi      ; negative result
                                4'b0101: {text, pred_true} = {"PRPL", ~flag_n};                       // prpl      ; positive or zero result
                                4'b0110: {text, pred_true} = {"PRVS", flag_v};                        // prvs      ; signed overflow
                                4'b0111: {text, pred_true} = {"PRVC", ~flag_v};                       // prvc      ; signed no overflow
                                4'b1000: {text, pred_true} = {"PRHI", flag_c & ~flag_z};              // prhi      ; unsigned >
                                4'b1001: {text, pred_true} = {"PRLS", ~flag_c | flag_z};              // prls      ; unsigned <=
                                4'b1010: {text, pred_true} = {"PRGE", ~(flag_n ^ flag_v)};            // prge      ; signed >=
                                4'b1011: {text, pred_true} = {"PRLT", flag_n ^ flag_v};               // prlt      ; signed <
                                4'b1100: {text, pred_true} = {"PRGT", ~flag_z & ~(flag_n ^ flag_v)};  // prgt      ; signed >
                                4'b1101: {text, pred_true} = {"PRLE", flag_z | (flag_n ^ flag_v)};    // prle      ; signed <=
                                // 0011-1111-1110-1111
                                4'b1110: {text, substate} = {"NOP ", SS_NOP};
                                // 0011-1111-1111-1111
                                4'b1111: {text, substate} = {"HLT ", SS_HALT};
                            endcase
                        end
                        else begin
                            //001x-xxxx-yyyy-1111 : x-xxxx != 1_1111
                            casez (op)
                                16'b0010_????_????_1111: {text, substate} = {"SWI ", SS_SWI};   // swi #num8

                                16'b0011_0000_????_1111: {text, substate} = {"MRS ", SS_RD_FLAGS};  // mrs r, flags
                                16'b0011_0001_????_1111: {text, substate} = {"MSR ", SS_WR_FLAGS};  // msr flags, r

                                16'b0011_0010_????_1111: {text, substate, op_special_special} = {"MRS ", SS_RD_SPECIAL, USER_FLAGS}; // mrs r, uflags
                                16'b0011_0011_????_1111: {text, substate, op_special_special} = {"MSR ", SS_WR_SPECIAL, USER_FLAGS}; // msr uflags, r

                                16'b0011_0100_????_1111: {text, substate, op_special_special} = {"MRS ", SS_RD_SPECIAL, USER_R13};   // mrs r, u13
                                16'b0011_0101_????_1111: {text, substate, op_special_special} = {"MSR ", SS_WR_SPECIAL, USER_R13};   // msr u13, r

                                16'b0011_0110_????_1111: {text, substate, op_special_special} = {"MRS ", SS_RD_SPECIAL, USER_R14};   // mrs r, u14
                                16'b0011_0111_????_1111: {text, substate, op_special_special} = {"MSR ", SS_WR_SPECIAL, USER_R14};   // msr u14, r

                                16'b0011_1000_????_1111: {text, substate} = {"RTU ", SS_RTU};   // rtu r

                                default: begin
                                    substate = SS_TRAP;
                                end
                            endcase
                        end
                    end
                endcase
            end

            // 01wn-nnnn-bbbb-tttt:
            // 010n-nnnn-bbbb-tttt      ldb target, [base,#num5] ; alias "ldb target, [base]" when n == 0
            // 011n-nnnn-bbbb-tttt      ldw target, [base,#num5] ; alias "ldw target, [base]" when n == 0
            2'b01: begin
                text = op_ld_st_wide ? "LDW " : "LDB ";
                substate = SS_LOAD;
                ld_st_addr   = r_base + {11'b0,op_num5};
                ld_st_wide   = op_ld_st_wide;
                ld_st_target = op_ld_st_target;
            end

            // 10wn-nnnn-bbbb-tttt:
            // 100n-nnnn-bbbb-tttt      stb target, [base,#num5] ; alias "stb target, [base]" when n == 0
            // 101n-nnnn-bbbb-tttt      stw target, [base,#num5] ; alias "stw target, [base]" when n == 0
            2'b10: begin
                text = op_ld_st_wide ? "STW " : "STB ";
                substate = SS_STORE;
                ld_st_addr = r_base + {11'b0,op_num5};
                ld_st_wide = op_ld_st_wide;
                ld_st_data = r_target;
            end

            // 11??-????-????-????
            2'b11: begin
                casez (op_mov8_br)
                    // 1100-nnnn-nnnn-rrrr  ; mov r, #num8          -- IDEA signed?
                    // 1101-nnnn-nnnn-rrrr  ; mov r, #num8<<8
                    2'b00: {text, substate, alu_mov_op, alu_out} = {"MVL ", SS_ALU, 1'b1, {8'b0, op_num8}};    // mov r, #num8
                    2'b01: {text, substate, alu_mov_op, alu_out} = {"MVH ", SS_ALU, 1'b1, {op_num8, 8'b0}};    // mov r, #num8<<8

                    // 1110-oooo-oooo-oooo
                    2'b10: begin
                        text = "B   ";
                        substate = SS_BRANCH;
                        br_link = 0;
                        br_addr = pc + {{3{op_br_offset[11]}}, op_br_offset, 1'b0};
                    end

                    // 1111-oooo-oooo-oooo
                    2'b11: begin
                        text = "BL  ";
                        substate = SS_BRANCH;
                        br_link = 1;
                        br_addr = pc + {{3{op_br_offset[11]}}, op_br_offset, 1'b0};
                    end
                endcase
            end
        endcase
    end
endmodule
