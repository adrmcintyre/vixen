`default_nettype none

module vixen (
        input clk
);
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

    reg [15:0] op;          // last instruction fetched

    // instruction decoding
    wire [3:0] dst              = op[3:0];      // alu dst reg
    wire [3:0] src              = op[7:4];      // alu src reg

    wire [3:0] op_num4          = op[7:4];      // 4 bit literal
    wire [4:0] op_num5          = op[12:8];     // 5 bit literal
    wire [7:0] op_num8          = op[11:4];     // 8 bit literal

    wire [1:0] op_major_cat     = op[15:14];    // op code major category
    wire [5:0] op_arithlog      = op[13:8];     // arithmetic/logical opcode subcat
    wire [1:0] op_mov8_br       = op[13:12];    // mov num8 / b / bl

    wire       op_ld_st_wide    = op[13];       // load/store size
    wire [3:0] op_ld_st_base    = op[7:4];      // reg specifying base address
    wire [3:0] op_ld_st_target  = op[3:0];      // reg to load/store

    wire       op_br_link       = op[12];       // link bit
    wire [3:0] op_br_cond       = op[11:8];     // condition code
    wire [7:0] op_br_offset     = op[7:0];      // signed branch offset

    wire [4:0] op_special = {op[12], op[7:4]};  // special instruction subcat
    wire [3:0] op_flags_target  = op[3:0];

    // CPU state
    localparam
        RESET     = 3'd0,
        FETCH     = 3'd1,
        FETCH_END = 3'd2,
        EXECUTE   = 3'd3,
        RETIRE    = 3'd4;

    reg [2:0] state = RESET;
    reg [15:0] next_pc;
    reg reg_rd;
    reg [3:0] reg_target;

    always @(posedge clk) begin
        case (state)
            RESET: begin
                //$display("RESET");
                flag_n <= 1'b0;
                flag_z <= 1'b0;
                flag_c <= 1'b0;
                flag_v <= 1'b0;
                for(integer i=0; i<=15; i=i+1) begin
                    r[i] <= 16'h0000;
                end
                next_pc <= 16'h0000;
                op <= 0;

                reg_rd <= 0;

                mem_en   <= 0;
                mem_addr <= pc;
                mem_din  <= 0;
                mem_wr   <= 0;
                mem_wide <= 0;

                state <= FETCH;
            end

            FETCH: begin
                //$display("FETCH pc=%x", next_pc);
                mem_addr <= pc;
                mem_wr   <= 0;
                mem_wide <= 1;
                mem_en   <= 1;
                r[15] <= pc;
                state <= FETCH_END;
            end

            FETCH_END: begin
                //$display("FETCH_END");
                op <= mem_dout;
                mem_en <= 0;
                state <= EXECUTE;
                r[15] <= pc + 2;
            end

            EXECUTE: begin
                $display("%x EXECUTE pc=%x op=%x [%s%s%s%s] r0=%x r1=%x r2=%x r3=%x",
                        pc-16'd2, pc,
                        op,
                        flag_n ? "N" : ".",
                        flag_z ? "Z" : ".",
                        flag_c ? "C" : ".",
                        flag_v ? "V" : ".",
                        r[0], r[1], r[2], r[3]);

                // update flags
                if (alu_wr_n) flag_n <= alu_data[15];
                if (alu_wr_z) flag_z <= alu_data == 16'b0;
                if (alu_wr_c) flag_c <= alu_c;
                // TODO - totally wrong - must calc in ALU - v = sign(x)==sign(y) && sign(result) != sign(x)
                if (alu_wr_v) flag_v <= alu_data[14];

                //$display("  alu_wr_reg=%x alu_data=%x ld_rd=%x ld_wr=%x fsave=%x fload=%x br=%x : op=%x dst=%x num8=%x",
                //     alu_wr_reg, alu_data, ld_st_rd, ld_st_wr, flags_save, flags_load, br_enable, op, dst, op_num8);

                // write to register file
                if (alu_wr_reg) begin
                    r[dst] <= alu_data;
                end
                else if (ld_st_rd) begin
                    reg_rd <= 1;
                    reg_target <= ld_st_target;

                    mem_addr <= ld_st_addr;
                    mem_wr <= 0;
                    mem_wide <= ld_st_wide;
                    mem_en <= 1;
                end
                else if (ld_st_wr) begin
                    mem_din <= r[reg_target];
                    mem_addr <= ld_st_addr;
                    mem_wr <= 1;
                    mem_wide <= ld_st_wide;
                    mem_en <= 1;
                end
                else if (flags_save) begin
                    r[flags_target] <= {flag_n, flag_z, flag_c, flag_v, 12'b0};
                end
                else if (flags_load) begin
                    {flag_n, flag_z, flag_c, flag_v} <= r[flags_target][15:12];
                end
                else if (br_enable) begin
                    if (br_link) begin
                        r[14] <= pc;
                    end
                    r[15] <= br_addr;
                    //$display("  branch to %x", br_addr);
                end
                else if (halt) begin
                    $finish;
                end
                state <= RETIRE;
            end

            RETIRE: begin
                //$display("RETIRE");
                mem_en <= 0;
                if (reg_rd) begin
                    r[reg_target] <= mem_dout;
                    reg_rd <= 0;
                end
                state <= FETCH;
            end
        endcase
    end

    
    // ALU
    reg wr_reg_only;
    reg wr_reg_nzcv;
    reg wr_reg_nzc;
    reg wr_reg_nz;
    reg wr_nzcv;
    reg wr_nz;
    reg next_c;
    reg [15:0] res;

    wire [15:0] r_dst = r[dst];
    wire [15:0] r_src = r[src];

    wire alu_wr_reg = wr_reg_only | wr_reg_nzcv | wr_reg_nzc | wr_reg_nz;
    wire alu_wr_n   = wr_nzcv     | wr_reg_nzcv | wr_reg_nzc | wr_reg_nz | wr_nz;
    wire alu_wr_z   = wr_nzcv     | wr_reg_nzcv | wr_reg_nzc | wr_reg_nz | wr_nz;
    wire alu_wr_c   = wr_nzcv     | wr_reg_nzcv | wr_reg_nzc;
    wire alu_wr_v   = wr_nzcv     | wr_reg_nzcv;

    wire [15:0] alu_data = res;
    wire        alu_c    = next_c;
    wire [3:0]  alu_reg  = dst;

    // Load / Store
    reg [15:0] ld_st_addr;
    reg [15:0] ld_st_data;
    reg [3:0]  ld_st_target;
    reg        ld_st_wr;
    reg        ld_st_rd;
    reg        ld_st_wide;
    wire [15:0] r_base   = r[op_ld_st_base];
    wire [15:0] r_target = r[op_ld_st_target];

    // Branch unit
    reg        br_enable;
    reg        br_link;
    reg [15:0] br_addr;

    // Flags special ops
    reg       flags_load;
    reg       flags_save;
    reg [3:0] flags_target;
    reg       halt;

    always @* begin
        wr_reg_only = 1'b0;
        wr_reg_nzcv = 1'b0;
        wr_reg_nzc  = 1'b0;
        wr_reg_nz   = 1'b0;
        wr_nzcv     = 1'b0;
        wr_nz       = 1'b0;
        next_c      = 1'b0;
        res         = 16'b0;

        ld_st_addr   = 16'b0;
        ld_st_wide   = 1'b0;
        ld_st_data   = 16'b0;
        ld_st_target = 4'b0;
        ld_st_rd     = 1'b0;
        ld_st_wr     = 1'b0;

        br_enable = 1'b0;
        br_link   = 1'b0;
        br_addr   = 16'b0;

        flags_load   = 1'b0;
        flags_save   = 1'b0;
        flags_target = 4'b0;

        halt         = 1'b0;

        case (op_major_cat)
            2'b00: begin
                // ALU ops take one of these forms:
                // 000o-oooo-ssss-rrrr ; op r_dst, r_src
                // 000o-oooo-nnnn-rrrr ; op r_dst, #num4
                // 000o-oooo-nnnn-rrrr ; op r_dst, #1<<num4
                // 0010-nnnn-nnnn-rrrr ; add r_dst, #num8
                // 0011-nnnn-nnnn-rrrr ; sub r_dst, #num8
                casez (op_arithlog)
                    6'b00_0000: {wr_reg_only, res} = {1'b1, r_src};    // mov r_dst, r_src
                    6'b00_0001: {wr_reg_only, res} = {1'b1, ~r_src};   // mvn r_dst, r_src

                    6'b00_0010: {wr_reg_nzcv, next_c, res} = {1'b1, ({1'b0,r_dst} + r_src) + flag_c};     // adc r_dst, r_src
                    6'b00_0011: {wr_reg_nzcv, next_c, res} = {1'b1, ({1'b0,r_dst} + ~r_src) + flag_c};    // sbc r_dst, r_src

                    6'b00_0100: {wr_reg_nzcv, next_c, res} = {1'b1, ({1'b0,r_dst} + r_src)};              // add r_dst, r_src
                    6'b00_0101: {wr_reg_nzcv, next_c, res} = {1'b1, ({1'b0,r_dst} + ~r_src) + 1'b1};      // sub r_dst, r_src

                    6'b00_0110: {wr_reg_nzcv, next_c, res} = {1'b1, ({1'b0,r_src} + ~r_dst) + flag_c};    // rsc r_dst, r_src
                    6'b00_0111: {wr_reg_nzcv, next_c, res} = {1'b1, ({1'b0,r_src} + ~r_dst) + 1'b1};      // rsb r_dst, r_src

                    // 0000-10..-....-....
                    //6'b00_1000:                                                                   // unused (8 bits) ; IDEA teq r_dst, r_src
                    //6'b00_1001:                                                                   // unused (8 bits) ; IDEA teq r_dst, #1<<n
                    //6'b00_1010:                                                                   // unused (8 bits)
                    //6'b00_1011:                                                                   // unused (8 bits)

                    6'b00_1100: {wr_reg_nz, res} = {1'b1, r_dst & r_src};                         // and r_dst, r_src
                    6'b00_1101: {wr_nzcv, next_c, res} = {1'b1, ({1'b0,r_dst} + ~r_src) + 1'b1};  // cmp r_dst, r_src
                    6'b00_1110: {wr_nzcv, next_c, res} = {1'b1, ({1'b0,r_dst} + r_src)};          // cmn r_dst, r_src

                    //6'b00_1111:                                                                   // unused (8 bits) ; IDEA mul r_dst, r_src

                    6'b01_0000:                                                                     // ror r_dst, r_src
                        begin
                            if (r_src[7:0] == 0) begin
                                {wr_reg_nz, res} = {1'b1, r_dst};
                            end
                            else begin
                                wr_reg_nzc = 1'b1;
                                {res, next_c} = {r_dst, r_dst, 1'b0} >> r_src[3:0];
                            end
                        end
                    6'b01_0001: {wr_reg_nzc, next_c, res} = {1'b1, {1'b0,r_dst} << r_src};            // lsl r_dst, r_src
                    6'b01_0010: {wr_reg_nzc, res, next_c} = {1'b1, {r_dst,1'b0} >> r_src};            // lsr r_dst, r_src
                    6'b01_0011: {wr_reg_nzc, res, next_c} = {1'b1, $signed({r_dst,1'b0}) >>> r_src};  // asr r_dst, r_src
                    6'b01_0100: {wr_reg_nz, res} = {1'b1, r_dst | r_src};                             // orr r_dst, r_src
                    6'b01_0101: {wr_reg_nz, res} = {1'b1, r_dst ^ r_src};                             // eor r_dst, r_src
                    6'b01_0110: {wr_reg_nz, res} = {1'b1, r_dst & ~r_src};                            // bic r_dst, r_src
                    6'b01_0111: {wr_nz, res}     = {1'b1, r_dst & r_src};                             // tst r_dst, r_src
                    
                    6'b01_1000:
                        begin
                            wr_reg_nzc = 1'b1;
                            if (op_num4 == 0)                                                           
                                {res, next_c} = {flag_c, r_dst};                                       // rrx r_dst        ; when num4 == 0 
                            else                                                                        
                                {res, next_c} = {r_dst, r_dst, 1'b0} >> r_src[3:0];                  // ror r_dst, #num4 ; when num4 != 0 
                        end

                    6'b01_1001: {wr_reg_nzc, next_c, res} = {1'b1, {1'b0,r_dst} << op_num4};           // lsl r_dst, #num4
                    6'b01_1010: {wr_reg_nzc, res, next_c} = {1'b1, {r_dst,1'b0} >> op_num4};           // lsr r_dst, #num4
                    6'b01_1011: {wr_reg_nzc, res, next_c} = {1'b1, $signed({r_dst,1'b0}) >>> op_num4}; // asr r_dst, #num4

                    6'b01_1100: {wr_reg_nz, res} = {1'b1, r_dst |  (1'b1 << op_num4)};                 // orr r_dst, #1<<num4
                    6'b01_1101: {wr_reg_nz, res} = {1'b1, r_dst ^  (1'b1 << op_num4)};                 // eor r_dst, #1<<num4
                    6'b01_1110: {wr_reg_nz, res} = {1'b1, r_dst & ~(1'b1 << op_num4)};                 // bic r_dst, #1<<num4
                    6'b01_1111: {wr_nz, res}     = {1'b1, r_dst &  (1'b1 << op_num4)};                 // tst r_dst, #1<<num4

                    6'b10_????: {wr_reg_nzcv, next_c, res} = {1'b1, ({1'b0,r_dst} + op_num8)};                 // add r_dst, #num8
                    6'b11_????: {wr_reg_nzcv, next_c, res} = {1'b1, ({1'b0,r_dst} + ~{8'b0,op_num8}) + 1'b1};  // sub r_dst, #num8     ; IDEA adc r_dst, #num8<<8

                    default: $display("default1");
                endcase
            end

            // 010n-nnnn-bbbb-tttt      ldb target, [base,#num5] ; alias "ldb target, [base]" when n == 0
            // 011n-nnnn-bbbb-tttt      ldw target, [base,#num5] ; alias "ldw target, [base]" when n == 0
            2'b01: begin
                ld_st_addr   = r_base + op_num5;
                ld_st_wide   = op_ld_st_wide;
                ld_st_target = op_ld_st_target;
                ld_st_rd     = 1'b1;
            end

            // 100n-nnnn-bbbb-tttt      stb target, [base,#num5] ; alias "stb target, [base]" when n == 0
            // 101n-nnnn-bbbb-tttt      stw target, [base,#num5] ; alias "stw target, [base]" when n == 0
            2'b10: begin 
                ld_st_addr = r_base + op_num5;
                ld_st_wide = op_ld_st_wide;
                ld_st_data = r_target;
                ld_st_wr   = 1'b1;
            end

            2'b11: begin
                casez (op_mov8_br)
                    // 1100-nnnn-nnnn-rrrr  ; mov r, #num8
                    // 1101-nnnn-nnnn-rrrr  ; mov r, #num8<<8
                    2'b00: {wr_reg_only, res} = {1'b1, {8'b0, op_num8}};    // mov r, #num8    ; IDEA movhi r, #num8
                    2'b01: {wr_reg_only, res} = {1'b1, {op_num8, 8'b0}};    // mov r, #num8<<8 ; IDEA movlo r, #num8

                    // 1110-cccc-nnnn-nnnn     b[cc] +2*signed(offset)
                    // 1111-cccc-nnnn-nnnn     bl[cond] +2*signed(offset)
                    2'b1?: begin
                        br_link = op_br_link;
                        br_addr = pc + {{7{op_br_offset[7]}}, op_br_offset, 1'b0};

                        case (op_br_cond)
                            4'b0000: br_enable = flag_z;                        // beq     ; ==
                            4'b0001: br_enable = ~flag_z;                       // bne     ; !=
                            4'b0010: br_enable = flag_c;                        // bcs bhs ; unsigned >= or carry out    (or no borrow)
                            4'b0011: br_enable = ~flag_c;                       // bcc blo ; unsigned <  or no carry out (or borrow)
                            4'b0100: br_enable = flag_n;                        // bmi     ; negative result
                            4'b0101: br_enable = ~flag_n;                       // bpl     ; positive or zero result
                            4'b0110: br_enable = flag_v;                        // bvs     ; signed overflow
                            4'b0111: br_enable = ~flag_v;                       // bvc     ; signed no overflow
                            4'b1000: br_enable = flag_c & ~flag_z;              // bhi     ; unsigned >
                            4'b1001: br_enable = ~flag_c | flag_z;              // bls     ; unsigned <=
                            4'b1010: br_enable = ~(flag_n ^ flag_v);            // bge     ; signed >=
                            4'b1011: br_enable = flag_n ^ flag_v;               // blt     ; signed <
                            4'b1100: br_enable = ~flag_z & ~(flag_n ^ flag_v);  // bgt     ; signed >
                            4'b1101: br_enable = flag_z | (flag_n ^ flag_v);    // ble     ; signed <=
                            4'b1110: br_enable = 1'b1;                          // bal     ; always
                            4'b1111: begin
                                // 1110-1111-....-....     ; unused 256 encodings
                                // 1111-1111-0000-rrrr     mov r, flags
                                // 1111-1111-0001-rrrr     mov flags, r
                                // 1111-1111-....-....     ; unused 223 encodings
                                // 1111-1111-1111-1111     hlt
                                casex (op_special)
                                    9'b1_0000: {flags_save, flags_target} = {1'b1, op_flags_target};
                                    9'b1_0001: {flags_load, flags_target} = {1'b1, op_flags_target};
                                    9'b1_1111: halt = 1'b1;
                                    default: $display("default2");
                                endcase
                            end
                            default: $display("default3");
                        endcase
                    end
                    default: $display("default4");
                endcase
            end
            default: $display("default5");
        endcase
    end
endmodule
