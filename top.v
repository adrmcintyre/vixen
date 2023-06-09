`default_nettype none

module top (
        input  clk_25mhz,
        output [3:0] gpdi_dp,
        output [3:0] gpdi_dn,
        input  [6:0] btn,
        output       wifi_gpio0
);
    assign wifi_gpio0 = 1'b1;

    wire clk = clk_25mhz;       // this is the ECP5's external clock - maybe we can use the PLL to run 
    wire video_clk = clk_25mhz; // we may want to run video_clk at a different rate

    wire [15:0] mem_dout;
    wire [7:0] mem_dout2;
    memory mem(
            .clk(clk),
            .en(cpu_mem_en),
            .wr(cpu_mem_wr),
            .wide(cpu_mem_wide),
            .addr(cpu_mem_addr),
            .din(cpu_mem_din),
            .dout(mem_dout),
            .clk2(video_clk),
            .en2(video_en),
            .addr2(video_addr),
            .dout2(mem_dout2));

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
            .mem_dout(mem_dout));

    wire [9:0] hdmi_x;
    wire [9:0] hdmi_y;
    wire hdmi_locked;
    hdmi_video hdmi(
            .clk_25mhz(video_clk),
            .vga_vsync(),
            .vga_hsync(),
            .vga_blank(),
            .x(hdmi_x),
            .y(hdmi_y),
            .color(video_color),
            .gpdi_dp(gpdi_dp),
            .gpdi_dn(gpdi_dn),
            .clk_locked(hdmi_locked));

    wire video_en;
    wire [15:0] video_addr;
    wire [23:0] video_color;
    videoctl video(
        .clk(video_clk),
        .clk_locked(hdmi_locked),
        .screen_x(hdmi_x),
        .screen_y(hdmi_y),
        .vaddr(video_addr),
        .en(video_en),
        .din(mem_dout2),
        .color(video_color));

endmodule
