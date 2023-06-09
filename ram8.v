`default_nettype none

module ram8 #(
        parameter FILE = ""
) (
        input clk,
        input en,
        input wr,
        input [14:0] addr,
        input [7:0]  din,
        output reg [7:0] dout,
        input clk2,
        input en2,
        input [14:0] addr2,
        output [7:0] dout2
);
    reg [7:0] mem[0:32767];

    initial begin
        if (FILE != "") $readmemh(FILE, mem);
    end

    always @(posedge clk) begin
        if (en) begin
            if (wr) begin
                mem[addr] <= din;
                dout <= din;
            end else begin
                dout <= mem[addr];
            end
        end
    end

    // TODO - dual ported sysMEM is *not* inferred
    //        instead we end up doubling up and
    //        running out of resources. Grr.
    //        Two options:
    //          * explicitly instantiate (can we do that?)
    //          * some kind of arbitration
//  always @(posedge clk) begin
//      if (en2) begin
//         dout2 <= mem[addr2];
//      end
//  end
        // synchronous read port... (fingers crossed)
        assign dout2 = en2 ? mem[addr2] : 8'b0;
endmodule
