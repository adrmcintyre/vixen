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
            .en2(video_rd),
            .addr2(video_addr),
            .dout2(video_din));

    // video registers at fc00-fc3f
    wire video_sel = io_sel && (io_addr <= 10'h03f);

    // video controller
    wire vga_vsync;
    wire vga_hsync;
    wire vga_blank;
    wire [23:0] video_rgb;
    wire [15:0] video_addr;
    wire video_rd;
    wire [7:0] video_din;
    videoctl video(
        .clk_pixel(clk_pixel),
        .nreset(clk_locked),
        .vsync(vga_vsync),
        .hsync(vga_hsync),
        .blank(vga_blank),
        .rgb(video_rgb),
        .addr(video_addr),
        .rd(video_rd),
        .din(video_din),
        .reg_clk(clk),
        .reg_wr(video_sel & cpu_en & cpu_wr),
        .reg_data(cpu_dout),
        .reg_addr(io_addr[5:1])
    );

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
