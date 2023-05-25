`default_nettype none

module memory (
        input  clk,
        input  en,
        input  wr,
        input  wide,
        input  [15:0] addr,
        input  [15:0] din,
        output [15:0] dout
);
    wire [14:0] mem_addr = addr[15:1];
    wire aligned = ~addr[0];

    wire wr0 = wr & (wide | aligned);
    wire wr1 = wr & (wide | ~aligned);

    wire [14:0] addr0 = aligned ? mem_addr : mem_addr + 1;
    wire [14:0] addr1 = mem_addr;

    wire [7:0] din0 = (~wide | ~aligned) ? din[7:0] : din[15:8];
    wire [7:0] din1 = (~wide | aligned)  ? din[7:0] : din[15:8];

    wire [7:0] dout0;
    wire [7:0] dout1;
    ram8 #(.FILE("mem.bin"), .LSB(0)) mem0(.clk(clk), .en(en), .wr(wr0), .addr(addr0), .din(din0), .dout(dout0));
    ram8 #(.FILE("mem.bin"), .LSB(1)) mem1(.clk(clk), .en(en), .wr(wr1), .addr(addr1), .din(din1), .dout(dout1));

    assign dout = aligned ? {dout0, dout1} : {dout1, dout0};
endmodule
