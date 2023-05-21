module ram8 #(
        parameter FILE=""
) (
        input clk,
        input en,
        input wr,
        input [14:0] addr,
        input [7:0]  din,
        output [7:0] dout
);
    reg [7:0] mem[0:32767];

    initial begin
        $readmemh(FILE, mem);
    end

    always @(posedge clk) begin
        if (en) begin
            if (wr) begin
                mem[addr] <= din;
            end
        end
    end

    assign dout = mem[addr];
endmodule
