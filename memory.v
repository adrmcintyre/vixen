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
    // Port A
    wire [14:0] mem_addr1 = addr1[15:1];
    wire aligned1 = ~addr1[0];

    wire [14:0] hi_addr1 = aligned1 ? mem_addr1 : mem_addr1 + 1;
    wire [14:0] lo_addr1 = mem_addr1;

    wire [7:0] hi_din1 = (wide1 & aligned1)  ? din1[15:8] : din1[7:0]; 
    wire [7:0] lo_din1 = (wide1 & ~aligned1) ? din1[15:8] : din1[7:0];

    wire [7:0] hi_dout1;
    wire [7:0] lo_dout1;

    wire hi_en1 = en1 & (wide1 | aligned1);
    wire lo_en1 = en1 & (wide1 | ~aligned1);

    wire hi_wr1 = wr1 & hi_en1;
    wire lo_wr1 = wr1 & lo_en1;

    // Port B
    wire [14:0] mem_addr2 = addr2[15:1];
    wire aligned2 = ~addr2[0];

    wire [14:0] hi_addr2 = mem_addr2;
    wire [14:0] lo_addr2 = mem_addr2;

    wire hi_en2 = en2 & aligned2;
    wire lo_en2 = en2 & ~aligned2;

    wire [7:0] hi_dout2;
    wire [7:0] lo_dout2;

    ram8 #(.FILE("out/mem.bin.0")) hi(
            // port A
            .clk1(clk1),
            .en1(hi_en1),
            .wr1(wr1),
            .addr1(hi_addr1),
            .din1(hi_din1),
            .dout1(hi_dout1),
            // port B
            .clk2(clk2),
            .en2(hi_en2),
            .addr2(hi_addr2),
            .dout2(hi_dout2));

    ram8 #(.FILE("out/mem.bin.1")) lo(
            // port A
            .clk1(clk1),
            .en1(lo_en1),
            .wr1(wr1),
            .addr1(lo_addr1),
            .din1(lo_din1),
            .dout1(lo_dout1),
            // port B
            .clk2(clk2),
            .en2(lo_en2),
            .addr2(lo_addr2),
            .dout2(lo_dout2));

    assign dout1 = aligned1 ? {hi_dout1, lo_dout1} : {lo_dout1, hi_dout1};
    assign dout2 = aligned2 ? hi_dout2 : lo_dout2;
endmodule
