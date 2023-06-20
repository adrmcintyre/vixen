`default_nettype none

// dual port memory with separate clocks
// primary port can do word or byte read+write
// secondary port is byte only reads (for video)

module memory (
        // read/write port
        input  clk1,
        input  en1,
        input  wr1,
        input  wide1,
        input  [15:0] addr1,
        input  [15:0] din1,
        output [15:0] dout1,
        // read port
        input  clk2,
        input  en2,
        input  [15:0] addr2,
        output [7:0]  dout2
);
    wire [14:0] mem_addr = addr1[15:1];
    wire aligned = ~addr1[0];

    wire bank0_wr = wr1 & (wide1 | aligned);
    wire bank1_wr = wr1 & (wide1 | ~aligned);

    wire [14:0] bank0_addr = aligned ? mem_addr : mem_addr + 1;
    wire [14:0] bank1_addr = mem_addr;

    wire [7:0] bank0_din = (~wide1 | ~aligned) ? din1[7:0] : din1[15:8];
    wire [7:0] bank1_din = (~wide1 | aligned)  ? din1[7:0] : din1[15:8];

    wire [7:0] bank0_dout;
    wire [7:0] bank0_dout2;

    wire [7:0] bank1_dout;
    wire [7:0] bank1_dout2;

    wire bank0_en1 = 1'b1 | en1;
    wire bank0_en2 = 1'b1 | en2 & ~addr2[0];
    wire bank1_en1 = 1'b1 | en1;
    wire bank1_en2 = 1'b1 | en2 & addr2[0];

    ram8 #(.FILE("out/mem.bin.0")) bank0(
            .clk1(clk1),
            .en1(bank0_en1),
            .wr1(bank0_wr),
            .addr1(bank0_addr),
            .din1(bank0_din),
            .dout1(bank0_dout),
            .clk2(clk2),
            .en2(bank0_en2),
            .addr2(addr2[15:1]),
            .dout2(bank0_dout2));

    ram8 #(.FILE("out/mem.bin.1")) bank1(
            .clk1(clk1),
            .en1(bank1_en1),
            .wr1(bank1_wr),
            .addr1(bank1_addr),
            .din1(bank1_din),
            .dout1(bank1_dout),
            .clk2(clk2),
            .en2(bank1_en2),
            .addr2(addr2[15:1]),
            .dout2(bank1_dout2));

    assign dout1 = aligned ? {bank0_dout, bank1_dout} : {bank1_dout, bank0_dout};
    assign dout2 = addr2[0] ? bank0_dout2 : bank1_dout2;
endmodule
