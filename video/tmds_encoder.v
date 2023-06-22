`default_nettype none

// File hdl/tmds_encoder.vhd translated with vhd2vl v3.0 VHDL to Verilog RTL translator
// vhd2vl settings:
//  * Verilog Module Declaration Style: 2001

// vhd2vl is Free (libre) Software:
//   Copyright (C) 2001 Vincenzo Liguori - Ocean Logic Pty Ltd
//     http://www.ocean-logic.com
//   Modifications Copyright (C) 2006 Mark Gonzales - PMC Sierra Inc
//   Modifications (C) 2010 Shankar Giri
//   Modifications Copyright (C) 2002-2017 Larry Doolittle
//     http://doolittle.icarus.com/~larry/vhd2vl/
//   Modifications (C) 2017 Rodrigo A. Melo
//
//   vhd2vl comes with ABSOLUTELY NO WARRANTY.  Always check the resulting
//   Verilog for correctness, ideally with a formal verification tool.
//
//   You are welcome to redistribute vhd2vl under certain conditions.
//   See the license (GPLv2) file included with the source for details.

// The result of translation follows.  Its copyright status should be
// considered unchanged from the original VHDL.

//--------------------------------------------------------------------------------
// Engineer: Mike Field <hamster@snap.net.nz>
// 
// Description: TMDS Encoder 
//     8 bits colour, 2 control bits and one blanking bits in
//       10 bits of TMDS encoded data out
//     Clocked at the pixel clock
//
//--------------------------------------------------------------------------------
// See: http://hamsterworks.co.nz/mediawiki/index.php/Dvid_test
//      http://hamsterworks.co.nz/mediawiki/index.php/FPGA_Projects
//
// Copyright (c) 2012 Mike Field <hamster@snap.net.nz>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// no timescale needed

module tmds_encoder(
        input wire clk,
        input wire [7:0] data,
        input wire [1:0] c,
        input wire blank,
        input wire resetn,
        output reg [9:0] encoded
    );

    function [3:0] popcount(input [7:0] bits);
        integer i;
        popcount = 4'b0;
        for(i=0; i<8; i=i+1) begin
            popcount = popcount + {3'b0, bits[i]};
        end
    endfunction

    // Work out the two different encodings for the byte
    reg [8:0] xored, xnored;
    always @* begin: encodings
        integer i;
        xored[0] = data[0];
        xnored[0] = data[0];
        for(i=1; i<8; i=i+1) begin
            xored[i] = data[i] ^ xored[i-1];
            xnored[i] = ~(data[i] ^ xnored[i-1]);
        end
        xored[8] = 1'b1;
        xnored[8] = 1'b0;
    end

    // Decide which encoding to use
    wire [3:0] ones = popcount(data);
    reg [8:0] data_word, data_word_inv;
    always @* begin
        data_word = (ones > 4 || (ones == 4 && data[0] == 1'b0)) ? xnored : xored;
        data_word_inv = ~data_word;
    end

    // Work out the DC bias of the dataword
    wire [3:0] disparity = popcount(data_word[7:0]) - 4'd6;

    // Now work out what the output should be
    reg [3:0] bias;
    always @(posedge clk) begin
        if (!resetn) begin
            bias <= 4'b0;
        end
        if (blank) begin
            // In the control periods, all values have a balanced bit count
            // Equivalent to: encoded <= {c[1], 9'b010101011} ^ {10{~c[0]}
            case(c)
                2'b00: encoded <= {2'b11, 8'b01010100};
                2'b01: encoded <= {2'b00, 8'b10101011};
                2'b10: encoded <= {2'b01, 8'b01010100};
                2'b11: encoded <= {2'b10, 8'b10101011};
            endcase
            bias <= 4'b0;
        end
        else if (bias == 4'b0 || disparity == 4'b0) begin
            // dataword has no disparity
            if (data_word[8] == 1'b1) begin
                encoded <= {2'b01, data_word[7:0]};
                bias <= bias + disparity;
            end
            else begin
                encoded <= {2'b10, data_word_inv[7:0]};
                bias <= bias - disparity;
            end
        end
        else if (bias[3] == disparity[3]) begin
            encoded <= {{1'b1,data_word[8]}, data_word_inv[7:0]};
            bias <= bias + {3'b0,data_word[8]} - disparity;
        end
        else begin
            encoded <= {{1'b0,data_word[8]}, data_word[7:0]};
            bias <= bias - {3'b0,data_word_inv[8]} + disparity;
        end
    end

endmodule
