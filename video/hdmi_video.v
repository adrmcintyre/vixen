`default_nettype none

module hdmi_video(
    input clk_25mhz,
    output clk_pixel,
    output clk_locked,
    input vga_vsync,
    input vga_hsync,
    input vga_blank,
    input [23:0] color,
    output [3:0] gpdi_dp,
    output [3:0] gpdi_dn
);
    // clock generator
    wire pll_250mhz, pll_125mhz, pll_25mhz, pll_locked;
    clk_25_250_125_25 clock_instance(
      .clki(clk_25mhz),
      .clko(pll_250mhz),
      .clks1(pll_125mhz),
      .clks2(pll_25mhz),
      .locked(pll_locked)
    );
   
    wire clk_shift = pll_125mhz;
    assign clk_pixel = pll_25mhz;
    assign clk_locked = pll_locked;

    // VGA to digital video converter
    wire [1:0] tmds[3:0];
    vga2dvid vga2dvid_instance(
      .clk_pixel(clk_pixel),
      .clk_shift(clk_shift),
      .in_color(color),
      .in_hsync(vga_hsync),
      .in_vsync(vga_vsync),
      .in_blank(vga_blank),
      .out_clock(tmds[3]),
      .out_red(tmds[2]),
      .out_green(tmds[1]),
      .out_blue(tmds[0]),
      .outp_red(),
      .outp_green(),
      .outp_blue(),
      .resetn(clk_locked)
    );

    // output TMDS SDR/DDR data to fake differential lanes
    fake_differential fake_differential_instance(
      .clk_shift(clk_shift),
      .in_clock(tmds[3]),
      .in_red(tmds[2]),
      .in_green(tmds[1]),
      .in_blue(tmds[0]),
      .out_p(gpdi_dp),
      .out_n(gpdi_dn)
    );
endmodule

