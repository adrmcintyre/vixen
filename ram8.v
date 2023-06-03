`default_nettype none

module ram8 #(
        parameter FILE = ""
) (
        input clk,
        input en,
        input wr,
        input [14:0] addr,
        input [7:0]  din,
        output reg [7:0] dout
);
    reg [7:0] mem[0:32767];

    initial begin
        if (FILE != "") $readmemh(FILE, mem);
    end

    always @(posedge clk) begin
        if (en) begin
            if (wr) begin
                mem[addr] <= din;
            end 
            dout <= mem[addr];
        end
    end
endmodule
