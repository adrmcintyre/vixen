`default_nettype none

// DDR mode uses Lattice ECP5 vendor-specific module ODDRX1F
module fake_differential
(
  input clk_shift, // used only in DDR mode
  // [1:0]:DDR [0]:SDR TMDS
  input [1:0] in_clock, in_red, in_green, in_blue,
  // [3]:clock [2]:red [1]:green [0]:blue 
  output [3:0] out_p, out_n
);
    wire [1:0] tmds[3:0];
    assign tmds[3] = in_clock;
    assign tmds[2] = in_red;
    assign tmds[1] = in_green;
    assign tmds[0] = in_blue;

    // register stage to improve timing of the fake differential
    reg [1:0] R_tmds_p[3:0], R_tmds_n[3:0];
    generate
      genvar i;
      for(i = 0; i < 4; i=i+1)
      begin : TMDS_pn_registers
        always @(posedge clk_shift) R_tmds_p[i] <=  tmds[i];
        always @(posedge clk_shift) R_tmds_n[i] <= ~tmds[i];
      end
    endgenerate

    // output SDR/DDR to fake differential
    generate
      genvar j;
        for(j = 0; j < 4; j=j+1)
        begin : DDR_output_mode
          ODDRX1F
          ddr_p_instance
          (
            .D0(R_tmds_p[j][0]),
            .D1(R_tmds_p[j][1]),
            .Q(out_p[j]),
            .SCLK(clk_shift),
            .RST(0)
          );
          ODDRX1F
          ddr_n_instance
          (
            .D0(R_tmds_n[j][0]),
            .D1(R_tmds_n[j][1]),
            .Q(out_n[j]),
            .SCLK(clk_shift),
            .RST(0)
          );
        end
    endgenerate

endmodule
