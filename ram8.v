`default_nettype none

module ram8 #(
        parameter FILE = "",
        parameter LSB = 0
) (
        input clk,
        input en,
        input wr,
        input [14:0] addr,
        input [7:0]  din,
        output [7:0] dout
);
    reg [7:0] mem[0:32767];

    initial begin : load_data
        integer file, i, c;
        file = $fopen(FILE, "r");
        if (file == 0) begin
            $fatal(1, "Could not load '%s'", FILE);
        end
        i = 0;
        c = $fgetc(file);
        while (c !== -1) begin
            if ((i & 1) == LSB) mem[i>>1] = c[7:0];
            i = i + 1;
            c = $fgetc(file);
        end
        $fclose(file);
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
