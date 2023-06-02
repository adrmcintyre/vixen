`default_nettype none

module vixen (
        input clk
);
    integer display_state = 0;

    // MEMORY SUBSYSTEM
    reg         mem_en;
    reg         mem_wr;
    reg         mem_wide;
    reg  [15:0] mem_addr;
    reg  [15:0] mem_din;
    wire [15:0] mem_dout;

    memory mem(
            .clk(clk),
            .en(mem_en),
            .wr(mem_wr),
            .wide(mem_wide),
            .addr(mem_addr),
            .din(mem_din),
            .dout(mem_dout));

    // register file
    reg  [15:0] r[0:15];
    wire [15:0] pc = {r[15][15:1], 1'b0};
    reg flag_n;
    reg flag_z;
    reg flag_c;
    reg flag_v;

    wire [15:0] op = mem_dout;          // last instruction fetched

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

    wire [3:0] op_flags_target  = op[7:4];

    // CPU state
    localparam
        RESET     = 3'd0,
        FETCH     = 3'd1,
        EXECUTE   = 3'd2,
        LOAD      = 3'd3;

    localparam
        SS_NOP      = 4'd0,
        SS_ALU      = 4'd1,
        SS_LOAD     = 4'd2,
        SS_STORE    = 4'd3,
        SS_RD_FLAGS = 4'd4,
        SS_WR_FLAGS = 4'd5,
        SS_BRANCH   = 4'd6,
        SS_PRED     = 4'd7,
        SS_HALT     = 4'd8,
        SS_TRAP     = 4'd9;

    reg [2:0] state = RESET;
    reg [3:0] substate;
    reg [15:0] next_pc;
    reg reg_rd;
    reg predicated;
    reg [3:0] reg_target;

    task TRACE(input [7*8-1:0] label);
        $display("%x %x EXECUTE %-s pc=%x [%s%s%s%s] r0=%x r1=%x r2=%x r3=%x r4=%x r5=%x r6=%x r7=%x .. r14=%x",
                pc-16'd2, op,
                label,
                pc,
                flag_n ? "N" : ".",
                flag_z ? "Z" : ".",
                flag_c ? "C" : ".",
                flag_v ? "V" : ".",
                r[0], r[1], r[2], r[3],
                r[4], r[5], r[6], r[7],
                r[14]);
    endtask

    always @(posedge clk) begin
        case (state)
            RESET: begin
                if (display_state) $display("RESET");

                flag_n <= 1'b0;
                flag_z <= 1'b0;
                flag_c <= 1'b0;
                flag_v <= 1'b0;
                for(integer i=0; i<=15; i=i+1) begin
                    r[i] <= 16'h0000;
                end
                next_pc <= 16'h0000;
                //op <= 0;
                predicated <= 1;

                reg_rd <= 0;

                mem_en   <= 0;
                mem_addr <= pc;
                mem_din  <= 0;
                mem_wr   <= 0;
                mem_wide <= 0;

                state <= FETCH;
            end

            FETCH: begin
                if (display_state) $display("FETCH pc=%x", next_pc);
                mem_addr <= pc;
                mem_wr   <= 0;
                mem_wide <= 1;
                mem_en   <= 1;

                r[15] <= pc+2;
                predicated <= 1;
                state <= predicated ? EXECUTE : FETCH;
            end

            EXECUTE: begin
                state <= FETCH;

                case (substate)
                    SS_NOP: begin
                        TRACE("NOP");
                    end

                    SS_ALU: begin
                        TRACE("ALU");
                        if (alu_wr_reg) begin
                            r[dst] <= alu_out;
                        end
                        if (alu_wr_nz) flag_n <= alu_n;
                        if (alu_wr_nz) flag_z <= alu_z;
                        if (alu_wr_c)  flag_c <= alu_c;
                        if (alu_wr_v)  flag_v <= alu_v;
                    end

                    SS_LOAD: begin
                        TRACE("LOAD");
                        reg_rd <= 1;
                        reg_target <= ld_st_target;

                        mem_addr <= ld_st_addr;
                        mem_wr <= 0;
                        mem_wide <= ld_st_wide;
                        mem_en <= 1;

                        state <= LOAD;
                    end

                    SS_STORE: begin
                        TRACE("STORE");
                        mem_din <= r_target;
                        mem_addr <= ld_st_addr;
                        mem_wr <= 1;
                        mem_wide <= ld_st_wide;
                        mem_en <= 1;

                        state <= FETCH;
                    end

                    SS_RD_FLAGS: begin
                        TRACE("RDFLAGS");
                        r[flags_target] <= {flag_n, flag_z, flag_c, flag_v, 12'b0};
                    end

                    SS_WR_FLAGS: begin
                        TRACE("WRFLAGS");
                        {flag_n, flag_z, flag_c, flag_v} <= r[flags_target][15:12];
                    end

                    SS_BRANCH: begin
                        TRACE("BRANCH");
                        if (br_link) begin
                            r[14] <= pc;
                        end
                        r[15] <= br_addr;
                    end

                    SS_PRED: begin
                        TRACE("PRED");
                        predicated <= pred_true;
                    end

                    SS_HALT: begin
                        TRACE("HALT");
                        $finish;
                    end

                    SS_TRAP: begin
                        TRACE("TRAP");
                        $finish;
                    end

                endcase
            end

            LOAD: begin
                TRACE("LOAD2");
                mem_en <= 0;
                r[reg_target] <= mem_dout;
                reg_rd <= 0;
                state <= FETCH;
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
                    6'b00_0000: {alu_mov_op, alu_out} = {1'b1, r_src};    // mov r_dst, r_src
                    6'b00_0001: {alu_mov_op, alu_out} = {1'b1, ~r_src};   // mvn r_dst, r_src

                    6'b00_0010: {alu_add_op, alu_c, alu_out} = {1'b1, ({1'b0,r_dst} + {1'b0,r_src}) + flag_c};      // adc r_dst, r_src
                    6'b00_0011: {alu_sub_op, alu_c, alu_out} = {1'b1, ({1'b0,r_dst} + {1'b0,~r_src}) + flag_c};     // sbc r_dst, r_src

                    6'b00_0100: {alu_add_op, alu_c, alu_out} = {1'b1, ({1'b0,r_dst} + {1'b0,r_src})};               // add r_dst, r_src
                    6'b00_0101: {alu_sub_op, alu_c, alu_out} = {1'b1, ({1'b0,r_dst} + {1'b0,~r_src}) + 1'b1};       // sub r_dst, r_src

                    6'b00_0110: {alu_sub_op, alu_c, alu_out} = {1'b1, ({1'b0,r_src} + {1'b0,~r_dst}) + flag_c};     // rsc r_dst, r_src
                    6'b00_0111: {alu_sub_op, alu_c, alu_out} = {1'b1, ({1'b0,r_src} + {1'b0,~r_dst}) + 1'b1};       // rsb r_dst, r_src

                    6'b00_1000: substate = SS_TRAP;                                                                 // unused (8 bits) ; IDEA teq r_dst, r_src
                    6'b00_1001: substate = SS_TRAP;                                                                 // unused (8 bits) ; IDEA teq r_dst, #1<<n
                    6'b00_1010: substate = SS_TRAP;                                                                 // unused (8 bits)
                    6'b00_1011: substate = SS_TRAP;                                                                 // unused (8 bits)

                    6'b00_1100: {alu_logic_op, alu_out} = {1'b1, r_dst & r_src};                                    // and r_dst, r_src
                    6'b00_1101: {alu_cmp_op, alu_c, alu_out} = {1'b1, ({1'b0,r_dst} + {1'b0,~r_src}) + 1'b1};       // cmp r_dst, r_src
                    6'b00_1110: {alu_cmp_op, alu_c, alu_out} = {1'b1, ({1'b0,r_dst} + {1'b0,r_src})};               // cmn r_dst, r_src

                    6'b00_1111: substate = SS_TRAP;                                                                 // unused (8 bits) ; IDEA mul r_dst, r_src

                    6'b01_0000:                                                                             // ror r_dst, r_src
                        begin
                            if (r_src[7:0] == 0) begin
                                {alu_logic_op, alu_out} = {1'b1, r_dst};
                            end
                            else begin
                                alu_shift_op = 1'b1;
                                {alu_out, alu_c} = {r_dst, r_dst, 1'b0} >> r_src[3:0];
                            end
                        end
                    6'b01_0001: {alu_shift_op, alu_c, alu_out} = {1'b1, {1'b0,r_dst} << r_src};             // lsl r_dst, r_src
                    6'b01_0010: {alu_shift_op, alu_out, alu_c} = {1'b1, {r_dst,1'b0} >> r_src};             // lsr r_dst, r_src
                    6'b01_0011: {alu_shift_op, alu_out, alu_c} = {1'b1, $signed({r_dst,1'b0}) >>> r_src};   // asr r_dst, r_src
                    6'b01_0100: {alu_logic_op, alu_out} = {1'b1, r_dst | r_src};                            // orr r_dst, r_src
                    6'b01_0101: {alu_logic_op, alu_out} = {1'b1, r_dst ^ r_src};                            // eor r_dst, r_src
                    6'b01_0110: {alu_logic_op, alu_out} = {1'b1, r_dst & ~r_src};                           // bic r_dst, r_src
                    6'b01_0111: {alu_tst_op,   alu_out} = {1'b1, r_dst & r_src};                            // tst r_dst, r_src

                    6'b01_1000:
                        begin
                            alu_shift_op = 1'b1;
                            if (op_num4 == 0) begin
                                {alu_out, alu_c} = {flag_c, r_dst};                                         // rrx r_dst        ; when num4 == 0
                            end
                            else begin
                                {alu_out, alu_c} = {r_dst, r_dst, 1'b0} >> r_src[3:0];                      // ror r_dst, #num4 ; when num4 != 0
                            end
                        end

                    6'b01_1001: {alu_shift_op, alu_c, alu_out} = {1'b1, {1'b0,r_dst} << op_num4};           // lsl r_dst, #num4
                    6'b01_1010: {alu_shift_op, alu_out, alu_c} = {1'b1, {r_dst,1'b0} >> op_num4};           // lsr r_dst, #num4
                    6'b01_1011: {alu_shift_op, alu_out, alu_c} = {1'b1, $signed({r_dst,1'b0}) >>> op_num4}; // asr r_dst, #num4

                    6'b01_1100: {alu_logic_op, alu_out} = {1'b1, r_dst |  (1'b1 << op_num4)};               // orr r_dst, #1<<num4
                    6'b01_1101: {alu_logic_op, alu_out} = {1'b1, r_dst ^  (1'b1 << op_num4)};               // eor r_dst, #1<<num4
                    6'b01_1110: {alu_logic_op, alu_out} = {1'b1, r_dst & ~(1'b1 << op_num4)};               // bic r_dst, #1<<num4
                    6'b01_1111: {alu_tst_op,   alu_out} = {1'b1, r_dst &  (1'b1 << op_num4)};               // tst r_dst, #1<<num4

                    // 001n-nnnn-nnnn-rrrr
                    6'b1?_????: begin
                        // 001n-nnnn-nnnn-rrrr                                      // add r_dst, #signed_num9 ; r_dst != r15
                        if (dst != 4'b1111) begin
                            alu_add_op = 1'b1;
                            alu_signs_ne = r_dst[15] ^ op_sign;
                            {alu_c, alu_out} = {1'b0,r_dst} + {{9{op_sign}},op_num8};
                        end
                        // 001?-????-????-1111
                        else if (op[12:8] == 5'b1_1111) begin
                            // 0011-1111-cccc-1111 : pr<cond>                       // IDEA 001o-oooo-cccc-1111 ; br<cc> -62..+64
                            substate = SS_PRED;
                            case (op_pred_cond)
                                4'b0000: pred_true = flag_z;                        // preq      ; ==
                                4'b0001: pred_true = ~flag_z;                       // prne      ; !=
                                4'b0010: pred_true = flag_c;                        // prcs prhs ; unsigned >= or carry out    (or no borrow)
                                4'b0011: pred_true = ~flag_c;                       // prcc prlo ; unsigned <  or no carry out (or borrow)
                                4'b0100: pred_true = flag_n;                        // prmi      ; negative result
                                4'b0101: pred_true = ~flag_n;                       // prpl      ; positive or zero result
                                4'b0110: pred_true = flag_v;                        // prvs      ; signed overflow
                                4'b0111: pred_true = ~flag_v;                       // prvc      ; signed no overflow
                                4'b1000: pred_true = flag_c & ~flag_z;              // prhi      ; unsigned >
                                4'b1001: pred_true = ~flag_c | flag_z;              // prls      ; unsigned <=
                                4'b1010: pred_true = ~(flag_n ^ flag_v);            // prge      ; signed >=
                                4'b1011: pred_true = flag_n ^ flag_v;               // prlt      ; signed <
                                4'b1100: pred_true = ~flag_z & ~(flag_n ^ flag_v);  // prgt      ; signed >
                                4'b1101: pred_true = flag_z | (flag_n ^ flag_v);    // prle      ; signed <=
                                // 0011-1111-1110-1111
                                4'b1110: substate = SS_NOP;
                                // 0011-1111-1111-1111
                                4'b1111: substate = SS_HALT;
                            endcase
                        end
                        else begin
                            //001x-xxxx-yyyy-1111 : x-xxxx != 1_1111    (494 encodings unused)
                            casez (op)
                                16'b0011_0000_????_1111: {substate, flags_target} = {SS_RD_FLAGS, op_flags_target}; // rdf r
                                16'b0011_0001_????_1111: {substate, flags_target} = {SS_WR_FLAGS, op_flags_target}; // wrf r
                                default: begin
                                    substate = SS_TRAP;
                                end
                            endcase
                        end
                    end
                endcase
            end

            // 010w-nnnn-bbbb-tttt:
            // 010n-nnnn-bbbb-tttt      ldb target, [base,#num5] ; alias "ldb target, [base]" when n == 0
            // 011n-nnnn-bbbb-tttt      ldw target, [base,#num5] ; alias "ldw target, [base]" when n == 0
            2'b01: begin
                substate = SS_LOAD;
                ld_st_addr   = r_base + op_num5;
                ld_st_wide   = op_ld_st_wide;
                ld_st_target = op_ld_st_target;
            end

            // 100w-nnnn-bbbb-tttt:
            // 100n-nnnn-bbbb-tttt      stb target, [base,#num5] ; alias "stb target, [base]" when n == 0
            // 101n-nnnn-bbbb-tttt      stw target, [base,#num5] ; alias "stw target, [base]" when n == 0
            2'b10: begin
                substate = SS_STORE;
                ld_st_addr = r_base + op_num5;
                ld_st_wide = op_ld_st_wide;
                ld_st_data = r_target;
            end

            // 11??-????-????-????
            2'b11: begin
                casez (op_mov8_br)
                    // 1100-nnnn-nnnn-rrrr  ; mov r, #num8
                    // 1101-nnnn-nnnn-rrrr  ; mov r, #num8<<8
                    2'b00: {substate, alu_mov_op, alu_out} = {SS_ALU, 1'b1, {8'b0, op_num8}};    // mov r, #num8
                    2'b01: {substate, alu_mov_op, alu_out} = {SS_ALU, 1'b1, {op_num8, 8'b0}};    // mov r, #num8<<8

                    // 1110-oooo-oooo-oooo
                    2'b10: begin
                        substate = SS_BRANCH;
                        br_link = 0;
                        br_addr = pc + {{3{op_br_offset[11]}}, op_br_offset, 1'b0};
                    end

                    // 1111-oooo-oooo-oooo
                    2'b11: begin
                        substate = SS_BRANCH;
                        br_link = 1;
                        br_addr = pc + {{3{op_br_offset[11]}}, op_br_offset, 1'b0};
                    end
                endcase
            end
        endcase
    end
endmodule
