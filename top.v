`default_nettype none

module top (
        input  clk_25mhz,
        output [7:0] led
//      ,
//      output [3:0] gpdi_dp, gpdi_dn,
//      input  [6:0] btn,
//      output       wifi_gpio0
);
//  assign wifi_gpio0 = 1'b1;

    vixen v(.clk(clk_25mhz), .leds(led));

endmodule
