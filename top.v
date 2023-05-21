
module top ();
    reg clk = 1'b0;
    always #5 clk <= ~clk;

    vixen vixen(.clk(clk));

    integer cycles = 0;
    always @(posedge clk) begin
        cycles <= cycles + 1;
    end
endmodule
