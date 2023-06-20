`default_nettype none

module harness ();
    localparam TRACE_CPU = 1;           // trace CPU state
    localparam TRACE_MAX_REG = 15;      // max register to include (pc=r15 is always shown)
    localparam DUMP_VRAM_ON_HALT = 1;   // dump contents of video RAM on halt
    localparam DUMP_FRAME_ON_HALT = 0;  // dump video frame on halt
    localparam DUMP_FRAME_SYNCS = 0;    // include hsync+vsync in frame dump

    reg clk = 1'b0;
    always #5 clk <= ~clk;

    top uat(
            .clk_25mhz(clk),
            .gpdi_dp(),
            .gpdi_dn(),
            .btn(7'b0),
            .wifi_gpio0());

    wire        cpu_mem_en   = uat.cpu.mem_en;
    wire        cpu_mem_wr   = uat.cpu.mem_wr;
    wire        cpu_mem_wide = uat.cpu.mem_wide;
    wire [15:0] cpu_mem_addr = uat.cpu.mem_addr;
    wire [15:0] cpu_mem_din  = uat.cpu.mem_din;
    wire [15:0] mem_dout     = uat.cpu.mem_dout;

    reg halted = 0;
    integer cycles = 0;

    always @(posedge clk) begin
        cycles <= cycles + 1;

        if (uat.cpu.state == uat.cpu.EXECUTE) begin
            if (!halted && TRACE_CPU) begin: trace_cpu
                integer r;
                
                $write("%x %x EXECUTE %-s [%s%s%s%s]",
                        uat.cpu.pc-16'd2, uat.cpu.op,
                        uat.cpu.text,
                        uat.cpu.flag_n ? "N" : ".",
                        uat.cpu.flag_z ? "Z" : ".",
                        uat.cpu.flag_c ? "C" : ".",
                        uat.cpu.flag_v ? "V" : ".");

                for(r=0; r<=TRACE_MAX_REG && r<=14; r=r+1) begin
                    $write(" r%0d=%x", r, uat.cpu.r[r]);
                end
                $display(" pc=%x", uat.cpu.pc);
            end
            case (uat.cpu.substate)
                uat.cpu.SS_STORE: begin
                    if (!halted && TRACE_CPU) begin
                        if (uat.cpu.ld_st_wide) begin
                            $display("%x %x WRITE", uat.cpu.ld_st_addr, uat.cpu.r_target);
                        end
                        else begin
                            $display("%x %x   WRITE", uat.cpu.ld_st_addr, uat.cpu.r_target[7:0]);
                        end
                    end
                end

                uat.cpu.SS_HALT: begin
                    if (!halted && TRACE_CPU) begin
                        $display("HALT");
                    end
                    halted <= 1;
                end

                uat.cpu.SS_TRAP: begin
                    if (!halted && TRACE_CPU) begin
                        $display("TRAP - unknown instruction");
                    end
                    $finish;
                end
            endcase
        end
    end

    reg dumped_vram = 0;

    always @(posedge clk) begin
        if (halted && DUMP_VRAM_ON_HALT && !dumped_vram)
        begin: dump_vram
            integer x,y;
            reg [15:0] addr;
            addr = 16'h0000-64*40;
            for(y=0; y<40; y=y+1) begin: dump_y
                for(x=0; x<64; x=x+2) begin: dump_x
                    reg [7:0] ch1, ch2;
                    ch1 = uat.mem.bank0.mem[addr>>1][7:0];
                    ch2 = uat.mem.bank1.mem[addr>>1][7:0];
                    $write("%c %c ", (ch1>=8'h20 && ch1<=8'h7f) ? ch1 : ".",
                                     (ch2>=8'h20 && ch2<=8'h7f) ? ch2 : ".");
                    addr=addr+2;
                end
                $write("\n");
            end
            dumped_vram <= 1;
        end
    end

    // note hsync and vsync are active low
    reg vsync = 1;
    reg hsync = 1;
    integer vsync_count = 0;
    reg dumped_frame = 0;

    always @(posedge uat.clk_pixel) begin
        if (halted &&
                (!DUMP_VRAM_ON_HALT || dumped_vram) &&  // ensure vram was dumped first if requested
                (DUMP_FRAME_ON_HALT && !dumped_frame)
        )
        begin
            if (~uat.vga_vsync && vsync) begin
                if (vsync_count < 1) begin
                    vsync_count = vsync_count+1;
                    $write("\nFRAME %0d\n", vsync_count);
                end
                else begin
                    dumped_frame <= 1;
                end
            end
            if (vsync_count > 0) begin
                if (~uat.vga_hsync && hsync) begin
                    $write("\n");
                end
                if (uat.vga_blank) begin
                    if (DUMP_FRAME_SYNCS) begin
                        $write("%c", ~uat.vga_hsync ? (~uat.vga_vsync ? "+" : "-") : (~uat.vga_vsync ? "|" : "."));
                    end
                end
                else begin
                    $write("%x", uat.vga_color[3:0]);
                end
            end

            vsync <= uat.vga_vsync;
            hsync <= uat.vga_hsync;
        end
    end

    always @(posedge clk) begin
        if (halted &&
            (!DUMP_VRAM_ON_HALT || dumped_vram) &&
            (!DUMP_FRAME_ON_HALT || dumped_frame)
        )
        begin
            $finish();
        end
    end

endmodule
