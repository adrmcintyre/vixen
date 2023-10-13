`default_nettype none

// Count leading zeros in a nibble
module clz4 (
        input      [3:0] din,
        output reg [2:0] cnt
);
    always @* casez(din)
        4'b1???: cnt = 3'b000;
        4'b01??: cnt = 3'b001;
        4'b001?: cnt = 3'b010;
        4'b0001: cnt = 3'b011;
        4'b0000: cnt = 3'b100;
    endcase
endmodule

