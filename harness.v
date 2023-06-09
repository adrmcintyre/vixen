`default_nettype none

module top ();
    reg clk = 1'b0;
    always #5 clk <= ~clk;

    wire [15:0] mem_dout;
    memory mem(
            .clk(clk),
            .en(cpu_mem_en),
            .wr(cpu_mem_wr),
            .wide(cpu_mem_wide),
            .addr(cpu_mem_addr),
            .din(cpu_mem_din),
            .dout(mem_dout),
            .clk2(clk),
            .en2(1'b0),
            .addr2(16'b0));

    wire cpu_mem_en, cpu_mem_wr, cpu_mem_wide;
    wire [15:0] cpu_mem_addr;
    wire [15:0] cpu_mem_din;
    vixen cpu(
            .clk(clk),
            .mem_en(cpu_mem_en),
            .mem_wr(cpu_mem_wr),
            .mem_wide(cpu_mem_wide),
            .mem_addr(cpu_mem_addr),
            .mem_din(cpu_mem_din),
            .mem_dout(mem_dout));

    integer cycles = 0;
    always @(posedge clk) begin
        cycles <= cycles + 1;

        if (cpu.state == cpu.EXECUTE) begin
            $display("%x %x EXECUTE %-s [%s%s%s%s] r0=%x r1=%x r2=%x r3=%x r4=%x r5=%x r6=%x r7=%x .. r14=%x pc=%x",
                    cpu.pc-16'd2, cpu.op,
                    cpu.text,
                    cpu.flag_n ? "N" : ".",
                    cpu.flag_z ? "Z" : ".",
                    cpu.flag_c ? "C" : ".",
                    cpu.flag_v ? "V" : ".",
                    cpu.r[0], cpu.r[1], cpu.r[2], cpu.r[3], cpu.r[4], cpu.r[5], cpu.r[6], cpu.r[7],
                    cpu.r[14], cpu.pc);
            case (cpu.substate)
                cpu.SS_STORE: begin
                    if (cpu.ld_st_wide) begin
                        $display("%x %x WRITE", cpu.ld_st_addr, cpu.r_target);
                    end else begin
                        $display("%x %x   WRITE", cpu.ld_st_addr, cpu.r_target[7:0]);
                    end
                end

                cpu.SS_HALT: begin
                    $finish;
                end

                cpu.SS_TRAP: begin
                    $display("TRAP - unknown instruction");
                    $finish;
                end
            endcase
        end
    end
endmodule
