`default_nettype none

module top (
        input  clk_25mhz,
        output [3:0] gpdi_dp,
        output [3:0] gpdi_dn,
        input  [6:0] btn,
        output [7:0] led,
        output       wifi_gpio0
);
    assign wifi_gpio0 = 1'b1;

    wire clk = clk_25mhz;

    // CPU
    wire cpu_en, cpu_wr, cpu_wide;
    wire [15:0] cpu_addr;
    wire [15:0] cpu_din;
    wire [15:0] cpu_dout;
    vixen cpu(
            .clk(clk),
            .mem_en(cpu_en),
            .mem_wr(cpu_wr),
            .mem_wide(cpu_wide),
            .mem_addr(cpu_addr),
            .mem_din(cpu_dout),
            .mem_dout(cpu_din),
            .led(led));

    // memory map i/o at fc00-ffff
    wire io_sel = (cpu_addr[15:10] == 6'h3f);
    wire [9:0] io_addr = cpu_addr[9:0];

    wire mem_sel = ~io_sel;

    // memory
    memory mem(
            .clk1(clk),
            .en1(cpu_en & mem_sel),
            .wr1(cpu_wr),
            .wide1(cpu_wide),
            .addr1(cpu_addr),
            .din1(cpu_dout),
            .dout1(cpu_din),
            .clk2(clk_pixel),
            .en2(video_rd | sprite_rd),
            .addr2(sprite_rd ? sprite_addr : video_addr),
            .dout2(video_din));

    // video registers at fc00-fcff
    wire video_sel = io_sel && (io_addr <= 10'h0ff);

    // these are in clk_pixel clock domain
    wire video_reg_wr;
    wire [7:0] video_reg_addr;
    wire [15:0] video_reg_data;

    cdc_bus #(.WIDTH(8+16), .DEPTH(3)) cdc(
            .src_clk(clk),
            .src_en(video_sel & cpu_en & cpu_wr),
            .src_bus({io_addr[7:0], cpu_dout}),
            .dst_clk(clk_pixel),
            .dst_en(video_reg_wr),
            .dst_bus({video_reg_addr, video_reg_data}));

    // video controller
    wire vga_vsync;
    wire vga_hsync;
    wire vga_blank;
    wire video_v_valid;
    wire video_h_valid;
    wire [9:0] video_vpos;
    wire [9:0] video_hpos;
    wire [11:0] video_rgb444;
    wire [15:0] video_addr;
    wire video_rd;
    wire [7:0] video_din;
    videoctl video(
        .clk_pixel(clk_pixel),
        .nreset(clk_locked),
        .vsync(vga_vsync),
        .hsync(vga_hsync),
        .blank(vga_blank),
        .vvalid(video_v_valid),
        .hvalid(video_h_valid),
        .hpos(video_hpos),
        .vpos(video_vpos),
//      .vsync_irq(vga_vsync_irq),  // TODO
        .rgb444(video_rgb444),
        .mem_addr(video_addr),
        .mem_rd(video_rd),
        .mem_din(video_din),
        .reg_wr(video_reg_wr && (video_reg_addr[7:6] == 2'b0)),
        .reg_data(video_reg_data),
        .reg_addr(video_reg_addr)
    );
    
    wire sprite_rd;
    wire [15:0] sprite_addr;
    wire sprite_active;
    wire [11:0] sprite_rgb444;
    sprites sprites(
            .clk_pixel(clk_pixel),
            .v_valid(video_v_valid),
            .hsync(vga_hsync),
            .v_pos(video_vpos),
            .h_pos(video_hpos),
            .mem_addr(sprite_addr),
            .mem_rd(sprite_rd),
            .mem_din(video_din),
            .reg_wr(video_reg_wr && (video_reg_addr[7:6] != 2'b0)),
            .reg_data(video_reg_data),
            .reg_addr(video_reg_addr),
            .active(sprite_active),
            .rgb444(sprite_rgb444));

    // TODO - put this in a module?

    // Compose
    wire [11:0] rgb444 = (video_h_valid && video_v_valid && sprite_active)
        ? sprite_rgb444
        : video_rgb444;

    // Split into 4-bit components
    wire [3:0] red4 = rgb444[8+:4];
    wire [3:0] grn4 = rgb444[4+:4];
    wire [3:0] blu4 = rgb444[0+:4];

    // Expand to 8 bits by replicating top 4 bits into bottom 4 to ensure
    // we use the full dynamic range (effectively multiplies by 255/15).
    wire [7:0] red8 = {red4, red4};
    wire [7:0] grn8 = {grn4, grn4};
    wire [7:0] blu8 = {blu4, blu4};

    // output
    wire [23:0] video_rgb = {red8, grn8, blu8};

    // video output
`ifdef IVERILOG
    wire clk_locked = 1'b1;
    wire clk_pixel = clk_25mhz;
`else
    wire clk_pixel;
    wire clk_locked;
    hdmi_video hdmi(
            .clk_25mhz(clk_25mhz),
            .clk_pixel(clk_pixel),
            .clk_locked(clk_locked),
            .vga_vsync(vga_vsync),
            .vga_hsync(vga_hsync),
            .vga_blank(vga_blank),
            .color(video_rgb),
            .gpdi_dp(gpdi_dp),
            .gpdi_dn(gpdi_dn));
`endif

endmodule
