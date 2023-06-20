`default_nettype none

module ram8 #(
        parameter FILE = ""
) (
        input clk1,
        input en1,
        input wr1,
        input [14:0] addr1,
        input [7:0]  din1,
        output [7:0] dout1,
        input clk2,
        input en2,
        input [14:0] addr2,
        output [7:0] dout2
);
    (* no_rw_check *) reg [8:0] mem[0:32767];

    initial begin
        if (FILE != "") $readmemh(FILE, mem);
    end

    // Registered data out
    reg [7:0] dout1_reg;
    reg [7:0] dout2_reg;

    always @(posedge clk1) begin
        dout1_reg <= mem[addr1][7:0];
        if (wr1) begin
            mem[addr1] <= {1'b0,din1};
        end
    end

    always @(posedge clk2) begin
        dout2_reg <= mem[addr2][7:0];
    end

    assign dout1 = dout1_reg;
    assign dout2 = dout2_reg;

endmodule
