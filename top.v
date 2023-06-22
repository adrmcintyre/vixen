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

    wire [15:0] mem_dout;
    wire [7:0] video_data;
    memory mem(
            .clk1(clk),
            .en1(cpu_mem_en),
            .wr1(cpu_mem_wr),
            .wide1(cpu_mem_wide),
            .addr1(cpu_mem_addr),
            .din1(cpu_mem_din),
            .dout1(mem_dout),
            .clk2(clk_pixel),
            .en2(video_rd),
            .addr2(video_addr),
            .dout2(video_data));

    wire cpu_mem_en, cpu_mem_wr, cpu_mem_wide;
    wire [15:0] cpu_mem_addr;
    wire [15:0] cpu_mem_din;
    vixen cpu(
            .clk(clk),
            .mem_en(cpu_mem_en),
            .mem_wr(cpu_mem_wr),
            .mem_wide(cpu_mem_wide),
            .mem_addr(cpu_mem_addr),
            .mem_din(cpu_mem_din),
            .mem_dout(mem_dout),
            .led(led)
            );

    wire vga_vsync;
    wire vga_hsync;
    wire vga_blank;
    wire [23:0] video_rgb;
    wire [15:0] video_addr;
    wire video_rd;
    videoctl video(
        .clk_pixel(clk_pixel),
        .nreset(clk_locked),
        .vsync(vga_vsync),
        .hsync(vga_hsync),
        .blank(vga_blank),
        .rgb(video_rgb),
        .addr(video_addr),
        .rd(video_rd),
        .din(video_data));

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
