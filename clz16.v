`default_nettype none

// Count leading zeros in 16-bit word
module clz16 (
        input      [15:0] din,
        output reg [4:0]  cnt
);
    wire [2:0] cnt3, cnt2, cnt1, cnt0;
    clz4 c3(.din(din[15:12]), .cnt(cnt3));
    clz4 c2(.din(din[11:8]),  .cnt(cnt2));
    clz4 c1(.din(din[7:4]),   .cnt(cnt1));
    clz4 c0(.din(din[3:0]),   .cnt(cnt0));

    always @* casez({cnt3[2], cnt2[2], cnt1[2], cnt0[2]})
        4'b0???: cnt = {2'b00, cnt3[1:0]};
        4'b10??: cnt = {2'b01, cnt2[1:0]};
        4'b110?: cnt = {2'b10, cnt1[1:0]};
        4'b1110: cnt = {2'b11, cnt0[1:0]};
        default: cnt = 5'd16;
    endcase
endmodule

