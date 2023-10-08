`default_nettype none

// A simple positive-edge triggered interrupt controller.
//
// If any bit in irqs_in goes high, a pending interrupt is registered.
// The irq_assert signal will be set as long as there are any pending
// interrupts which are also enabled.
//
// There are two registers:
//
//  ENABLED
//      Reading this register returns its current state.
//
//      Writes to this register affect only the bits set to 1 in the word
//      written. The specified register bits will be set to the value of
//      bit 15, thus allowing individual bits to be set or cleared without
//      affecting the remaining bits.
//
//      The irq_assert signal will only be asserted for pending interrupts
//      with a corresponding bit set in this register.
//
//  PENDING
//      Reading this register returns a word with bits be set for each
//      interrupt that has yet to be acknowledged.
//
//      Writes to this register affect only the bits set to 1 in the word
//      written; all corresponding pending interrupts are cleared.
//
module irq_controller (
        input reset,
        input clk,
        input  [14:0] irqs_in,
        input         wr,
        input  [0:0]  addr,
        input  [15:0] din,
        output [15:0] dout,
        output irq_assert
);
    localparam
        ENABLED = 0,
        PENDING = 1;
        
    reg [14:0] enabled = 0;
    reg [14:0] pending = 0;

    wire wr_enabled = wr && (addr == ENABLED);
    wire wr_pending = wr && (addr == PENDING);
    wire clear_enabled = wr_enabled & ~din[15];
    wire set_enabled   = wr_enabled & din[15];
    wire [14:0] mask   = din[14:0];

    always @(posedge clk) begin
        if (reset) begin
            enabled <= 0;
        end
        else if (set_enabled) begin
            enabled <= enabled | mask;
        end
        else if (clear_enabled) begin
            enabled <= enabled & ~mask;
        end
    end

    reg  [14:0] irqs_in_prev = 0;
    wire [14:0] irq_edges = irqs_in & ~irqs_in_prev;

    always @(posedge clk) begin
        if (reset) begin
            irqs_in_prev <= 0;
            pending <= 0;
        end
        else begin
            irqs_in_prev <= irqs_in;
            pending <= (wr_pending ? (pending & ~mask) : pending) | irq_edges;
        end
    end

    wire rd_enabled = (~wr) && (addr == ENABLED);
    wire rd_pending = (~wr) && (addr == PENDING);
    reg [15:0] reg_dout = 0;

    always @(posedge clk) begin
        if (reset) begin
            reg_dout <= 0;
        end
        else if (rd_enabled) begin
            reg_dout <= {1'b0,enabled};
        end
        else if (rd_pending) begin
            reg_dout <= {1'b0,pending};
        end
    end

    assign irq_assert = |(pending & enabled);
    assign dout = reg_dout;

endmodule
