`default_nettype none

module top ();
    reg clk = 1'b0;
    always #5 clk <= ~clk;

    vixen v(.clk(clk));

    integer cycles = 0;
    always @(posedge clk) begin
        cycles <= cycles + 1;

        if (v.state == v.EXECUTE) begin
            $display("%x %x EXECUTE %-s [%s%s%s%s] r0=%x r1=%x r2=%x r3=%x r4=%x r5=%x r6=%x r7=%x .. r14=%x pc=%x",
                    v.pc-16'd2, v.op,
                    v.text,
                    v.flag_n ? "N" : ".",
                    v.flag_z ? "Z" : ".",
                    v.flag_c ? "C" : ".",
                    v.flag_v ? "V" : ".",
                    v.r[0], v.r[1], v.r[2], v.r[3], v.r[4], v.r[5], v.r[6], v.r[7],
                    v.r[14], v.pc);
            case (v.substate)
                v.SS_HALT: begin
                    $finish;
                end

                v.SS_TRAP: begin
                    $display("TRAP - unknown instruction");
                    $finish;
                end
            endcase
        end
    end
endmodule
