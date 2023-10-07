`default_nettype none

module cdc_bus #(
        parameter WIDTH = 0,
        parameter DEPTH = 3
) (
        input  src_clk,
        input  src_en,
        input  [WIDTH-1:0] src_bus,
        input  dst_clk,
        output dst_en,
        output [WIDTH-1:0] dst_bus
);

    reg [WIDTH-1:0] hold = 0;
    reg toggle = 1'b0;

    always @(posedge src_clk) begin
        if (src_en) begin
            hold   <= src_bus;
            toggle <= !toggle;
        end
    end

    reg [DEPTH-1:0] pipe = 0;
    reg delayed_enable = 1'b0;

    always @(posedge dst_clk) begin
        pipe <= {pipe[DEPTH-2:0], toggle};
        delayed_enable <= pipe[DEPTH-1] != pipe[DEPTH-2];
    end

    assign dst_en  = delayed_enable;
    assign dst_bus = hold;

endmodule
