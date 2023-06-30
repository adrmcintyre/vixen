`default_nettype none

module harness ();
    localparam TRACE_CPU = 1;           // trace CPU state
    localparam TRACE_MAX_REG = 15;      // max register to include (pc=r15 is always shown)
    localparam DUMP_VRAM_ON_HALT = 1;   // dump contents of video RAM on halt
    localparam DUMP_FRAME_ON_HALT = 1;  // dump video frame on halt
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
            addr = 16'hfc00-64*40;
            for(y=0; y<40; y=y+1) begin: dump_y
                for(x=0; x<64; x=x+2) begin: dump_x
                    reg [7:0] ch1, ch2;
                    ch1 = uat.mem.hi.mem[addr>>1][7:0];
                    ch2 = uat.mem.lo.mem[addr>>1][7:0];

                    if (ch1>=8'h20 && ch1<=8'h7e) begin
                        $write("%c  ", ch1);
                    end else begin
                        $write("%x ", ch1);
                    end

                    if (ch2>=8'h20 && ch2<=8'h7e) begin
                        $write("%c  ", ch2);
                    end else begin
                        $write("%x ", ch2);
                    end

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
    integer fd_frame;

    always @(posedge uat.clk_pixel) begin
        if (halted &&
                (!DUMP_VRAM_ON_HALT || dumped_vram) &&  // ensure vram was dumped first if requested
                (DUMP_FRAME_ON_HALT && !dumped_frame)
        )
        begin
            if (~uat.vga_vsync && vsync) begin
                if (vsync_count < 1) begin: dump_frame_header
                    integer width;    
                    integer height;   
                    integer pixels;   
                    integer filesize; 

                    vsync_count = vsync_count+1;
                    fd_frame = $fopen("out/frame.bmp", "w");

                    width = uat.video.H_VISIBLE;
                    height = -uat.video.V_VISIBLE;
                    pixels = uat.video.H_VISIBLE * uat.video.V_VISIBLE;
                    filesize = 54 + 3 * pixels;

                    // file header
                    $fwrite(fd_frame, "BM");            // magic
                    $fwrite(fd_frame, "%c%c%c%c", filesize[0+:8], filesize[8+:8], filesize[16+:8], filesize[24+:8]);
                    $fwrite(fd_frame, "%c%c", 0, 0);            // reserved1
                    $fwrite(fd_frame, "%c%c", 0, 0);            // reserved2
                    $fwrite(fd_frame, "%c%c%c%c", 54,0,0,0);    // pixel data offset

                    //BITMAPINFO header
                    $fwrite(fd_frame, "%c%c%c%c", 40,0,0,0);    // this header size
                    $fwrite(fd_frame, "%c%c%c%c", width[0+:8], width[8+:8], width[16+:8], width[23+:8]);
                    $fwrite(fd_frame, "%c%c%c%c", height[0+:8], height[8+:8], height[16+:8], height[23+:8]);
                    $fwrite(fd_frame, "%c%c", 1, 0);            // color planes (1)
                    $fwrite(fd_frame, "%c%c", 24, 0);           // bpp
                    $fwrite(fd_frame, "%c%c%c%c", 0,0,0,0);     // compression method
                    $fwrite(fd_frame, "%c%c%c%c", 0,0,0,0);     // raw bitmap size (0 is ok)
                    $fwrite(fd_frame, "%c%c%c%c", 0,0,0,0);     // horizontal resolution pix/m
                    $fwrite(fd_frame, "%c%c%c%c", 0,0,0,0);     // vertical resolution pix/m
                    $fwrite(fd_frame, "%c%c%c%c", 0,0,0,0);     // number of colours in palette (0 default)
                    $fwrite(fd_frame, "%c%c%c%c", 0,0,0,0);     // number of important colors (or 0)

                    //pixel data: R,G,B - pad rows to multiple of 4 bytes
                    $display("DUMPING FRAME %0d\n", vsync_count);
                end
                else begin
                    $display("DUMPED FRAME");
                    $fclose(fd_frame);
                    dumped_frame <= 1;
                end
            end
            if (vsync_count > 0) begin
                if (~uat.vga_hsync && hsync) begin
                    //$write("\n");
                    ;
                end
                if (uat.vga_blank) begin
                    ;
                    //if (DUMP_FRAME_SYNCS) begin
                    //    $write("%c", ~uat.vga_hsync ? (~uat.vga_vsync ? "+" : "-") : (~uat.vga_vsync ? "|" : "."));
                    //end
                end
                else begin
                    $fwrite(fd_frame, "%c%c%c", uat.video_rgb[0+:8], uat.video_rgb[8+:8], uat.video_rgb[16+:8]);
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
