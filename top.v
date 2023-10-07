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
    wire [15:0] cpu_dout;
    wire [15:0] cpu_din = irqctl_rd ? irqctl_dout : mem_dout1;
    vixen cpu(
            .clk(clk),
            .irq(irq_assert),
            .en(cpu_en),
            .wr(cpu_wr),
            .wide(cpu_wide),
            .addr(cpu_addr),
            .dout(cpu_dout),
            .din(cpu_din),
            .led(led));

    // memory map i/o at fc00-ffff
    wire io_sel = (cpu_addr[15:10] == 6'h3f);
    wire [9:0] io_addr = cpu_addr[9:0];
    wire io_en = cpu_en & io_sel;
    wire io_wr = io_en & cpu_wr;
    wire io_rd = io_en & ~cpu_wr;

    wire mem_sel = ~io_sel;
    wire mem_en = cpu_en & mem_sel;
    wire mem_wr = mem_en & cpu_wr;
    wire mem_rd = mem_en & ~cpu_wr;

    wire        mem_en2   = sprite_rd | video_rd;
    wire [15:0] mem_addr2 = sprite_rd ? sprite_addr : video_addr;

    // memory
    wire [15:0] mem_dout1;
    wire [7:0]  mem_dout2;
    memory mem(
            .clk1(clk),
            .en1(mem_en),
            .wr1(mem_wr),
            .wide1(cpu_wide),
            .addr1(cpu_addr),
            .din1(cpu_dout),
            .dout1(mem_dout1),
            .clk2(clk_pixel),
            .en2(mem_en2),
            .addr2(mem_addr2),
            .dout2(mem_dout2));

    wire irqctl_sel = io_sel && (io_addr >= 10'h100 && io_addr <= 10'h103);
    wire irqctl_en = irqctl_sel & cpu_en;
    wire irqctl_wr = irqctl_en & cpu_wr;
    wire irqctl_rd = irqctl_en & ~cpu_wr;
    wire [0:0] irqctl_addr = io_addr[1:1];
    wire [15:0] irqctl_dout;
    wire irq_assert;
    irq_controller irq_ctl(
            .reset(1'b0),
            .clk(clk),
            .irqs_in({14'b0,vga_vsync}),
            .wr(irqctl_wr),
            .addr(irqctl_addr),
            .din(cpu_dout),
            .dout(irqctl_dout),
            .irq_assert(irq_assert));

    // video registers at fc00-fcff
    wire video_io_sel = io_sel && (io_addr <= 10'h0ff);
    wire video_io_en = video_io_sel & cpu_en;
    wire video_io_wr = video_io_en & cpu_wr;
    wire video_io_rd = video_io_en & ~cpu_wr;

    // these are in clk_pixel clock domain
    wire        synced_video_io_wr;
    wire [7:0]  synced_video_io_addr;
    wire [15:0] synced_video_io_data;

    cdc_bus #(.WIDTH(8+16), .DEPTH(3)) cdc(
            .src_clk(clk),
            .src_en(video_io_wr),
            .src_bus({io_addr[7:0], cpu_dout}),
            .dst_clk(clk_pixel),
            .dst_en(synced_video_io_wr),
            .dst_bus({synced_video_io_addr, synced_video_io_data}));

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
        .rgb444(video_rgb444),
        .mem_addr(video_addr),
        .mem_rd(video_rd),
        .mem_din(mem_dout2),
        .reg_wr(synced_video_io_wr && (synced_video_io_addr[7:6] == 2'b0)),
        .reg_data(synced_video_io_data),
        .reg_addr(synced_video_io_addr)
    );

    // TODO - when vsync goes low we want to generate an irq
    // also need some way to record the source of the irq
    // and be able to clear it / mask it.
    
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
            .mem_din(mem_dout2),
            .reg_wr(synced_video_io_wr && (synced_video_io_addr[7:6] != 2'b0)),
            .reg_data(synced_video_io_data),
            .reg_addr(synced_video_io_addr),
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
