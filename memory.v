`default_nettype none

// dual port memory with separate clocks
// primary port can do word or byte read+write
// secondary port is byte only reads (for video)

module memory (
        input  clk,
        input  en,
        input  wr,
        input  wide,
        input  [15:0] addr,
        input  [15:0] din,
        output [15:0] dout,
        input  clk2,
        input  en2,
        input  [15:0] addr2,
        output [7:0]  dout2
);
    wire [14:0] mem_addr = addr[15:1];
    wire aligned = ~addr[0];

    wire bank0_wr = wr & (wide | aligned);
    wire bank1_wr = wr & (wide | ~aligned);

    wire [14:0] bank0_addr = aligned ? mem_addr : mem_addr + 1;
    wire [14:0] bank1_addr = mem_addr;

    wire [7:0] bank0_din = (~wide | ~aligned) ? din[7:0] : din[15:8];
    wire [7:0] bank1_din = (~wide | aligned)  ? din[7:0] : din[15:8];

    wire [7:0] bank0_dout;
    wire [7:0] bank0_dout2;
    ram8 #(.FILE("out/mem.bin.0")) bank0(
            .clk(clk),
            .en(en),
            .wr(bank0_wr),
            .addr(bank0_addr),
            .din(bank0_din),
            .dout(bank0_dout),
            .clk2(clk),
            .en2(en2 & ~addr2[0]),
            .addr2(addr2[15:1]),
            .dout2(bank0_dout2));

    wire [7:0] bank1_dout;
    wire [7:0] bank1_dout2;
    ram8 #(.FILE("out/mem.bin.1")) bank1(
            .clk(clk),
            .en(en),
            .wr(bank1_wr),
            .addr(bank1_addr),
            .din(bank1_din),
            .dout(bank1_dout),
            .clk2(clk2),
            .en2(en2 & addr2[0]),
            .addr2(addr2[15:1]),
            .dout2(bank1_dout2));

    assign dout = aligned ? {bank0_dout, bank1_dout} : {bank1_dout, bank0_dout};
    assign dout2 = addr2[0] ? bank1_dout2 : bank0_dout2;
endmodule
