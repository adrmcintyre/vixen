`default_nettype none

module videoctl
(
    // clock
	input clk_pixel,
    input nreset,
    // registers
    input         reg_wr,
    input  [15:0] reg_data,
    input  [7:0]  reg_addr,
    // vga output
    output reg vsync = 1'b1,
    output reg hsync = 1'b1,
    output reg blank = 1'b0,
    output [9:0] hpos,
    output [9:0] vpos,
    output     hvalid,
    output     vvalid,
    output [11:0] rgb444,
    // memory access
    output [15:0] mem_addr,
    output        mem_rd,
    input  [7:0]  mem_din
);

    // Horizontal timings
    //                        h_total
    // :------------------------------------------------------->:
    //
    //   h_back              h_visible              h_front h_sync
    // :-------->:---------------------------------->:---->:--->:
    //
    // ____________________________________________________  
    //                                                     |____|  hsync
    // __________xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx____________  rgb data


    // Vertical timings
    //                           v_total
    // :--------------------------------------------------------->:
    //
    //   v_back                 v_visible              v_front v_sync
    // :---------->:------------------------------------>:--->:-->:
    // _______________________________________________________
    //                                                        |___|  vsync
    // ____________xx_xx_xx_xx_xx_xx_xx_xx_xx_xx_xx_xx_xx__________  rgb data
    //
    // __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __ __   hsync
    //   _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _

    localparam H_BACK = 10'd44;
    localparam H_VISIBLE = 10'd640;     // VGA width
    localparam H_FRONT = 10'd16;
    localparam H_SYNC = 10'd96;
    localparam H_LATENCY = 10'd2;

    localparam V_BACK = 10'd31;
    localparam V_VISIBLE = 10'd480;     // VGA height
    localparam V_FRONT = 10'd10;
    localparam V_SYNC = 10'd2;

    localparam H_SYNC_START = H_BACK + H_VISIBLE + H_FRONT;
    localparam V_SYNC_START = V_BACK + V_VISIBLE + V_FRONT;
    localparam H_TOTAL = H_SYNC_START + H_SYNC;
    localparam V_TOTAL = V_SYNC_START + V_SYNC;

    localparam FONT_FILE = "out/font.bin";

    localparam CHAR_WIDTH = 8;
    localparam CHAR_HEIGHT = 8;

    localparam CHAR_LEFT = 0;
    localparam CHAR_PRE_RIGHT = 6;
    localparam CHAR_RIGHT = 7;
    localparam CHAR_TOP = 0;
    localparam CHAR_BOTTOM = 7;

    // control registers
    localparam CTL_BASE   = 4'h0; // address of first byte of video memory
    localparam CTL_LEFT   = 4'h1; // h_pos of first pixel, from start of horizontal back porch
    localparam CTL_RIGHT  = 4'h2; // h_pos+1 of last pixel, from start of horizontal back porch
    localparam CTL_TOP    = 4'h3; // v_pos of first line, from start of vertical back porch
    localparam CTL_BOTTOM = 4'h4; // v_pos+1 of last line, from start of vertical back porch
    localparam CTL_MODE   = 4'h5; // [5:4]=vert zoom-1; [3:2]=horiz zoom-1; [1:0]=display mode 
    localparam CTL_BORDER = 4'hf; // border color

    localparam MODE_TEXT = 2'd0;
    localparam MODE_1BPP = 2'd1;
    localparam MODE_2BPP = 2'd2;
    localparam MODE_4BPP = 2'd3;

    reg [15:0] base_addr = 16'h0;
    reg [9:0]  vp_left   = 10'd0;
    reg [9:0]  vp_right  = 10'd0;
    reg [9:0]  vp_top    = 10'd0;
    reg [9:0]  vp_bottom = 10'd0;
    reg [1:0]  mode      = 2'd0;
    reg [1:0]  hzoom_max = 2'd0;
    reg [1:0]  vzoom_max = 2'd0;
    reg [11:0] border_rgb444 = 12'b0;
    reg [7:0]  hphys_max = 8'd0; // TODO?

    // palette registers
    localparam PALETTE     = 4'h0; // palette: 16-bits * 16 entries = 256 bits
    localparam PALETTE_MAX = 4'hf;

    reg [11:0] reg_palette[0:PALETTE_MAX];

    // all control registers start at zero
    initial begin: init_control
        integer i;
        for(i=0; i<=PALETTE_MAX; i=i+1) reg_palette[i] = 12'b0;
    end

    always @(posedge clk_pixel) begin
        if (reg_wr) begin
            casez(reg_addr[5:0])
                6'b0?_????:
                    casez({reg_addr[4:1],1'b0})
                        5'h00: base_addr <= reg_data[15:0];
                        5'h02: vp_left   <= reg_data[9:0];
                        5'h04: vp_right  <= reg_data[9:0];
                        5'h06: vp_top    <= reg_data[9:0];
                        5'h08: vp_bottom <= reg_data[9:0];
                        5'h0a: {vzoom_max, hzoom_max, mode} <= reg_data[5:0];
                        5'h1e: border_rgb444 <= reg_data[11:0];
                        default: ;
                    endcase
                6'b1?_????: reg_palette[reg_addr[4:1]] <= reg_data[11:0];
            endcase
        end
    end

    // TODO - horizontal zoom has some timing issues:
    //      zoom=1 okay
    //      zoom=2 2 pixels to left
    //      zoom=3 4 pixels to left
    //      zoom=4 6 pixels to left

    reg [2:0] mode_pre1, mode_pre2;
    reg [2:0] mode_bpp;
    reg mode_text;
    always @* begin
        case (mode)
            MODE_TEXT: {mode_text, mode_bpp, mode_pre1, mode_pre2} = {1'b1, 3'd1, 3'd7, 3'd6};
            MODE_1BPP: {mode_text, mode_bpp, mode_pre1, mode_pre2} = {1'b0, 3'd1, 3'd7, 3'd6};
            MODE_2BPP: {mode_text, mode_bpp, mode_pre1, mode_pre2} = {1'b0, 3'd2, 3'd6, 3'd4};
            MODE_4BPP: {mode_text, mode_bpp, mode_pre1, mode_pre2} = {1'b0, 3'd4, 3'd4, 3'd0};
        endcase
    end

    reg [CHAR_WIDTH-1:0] font_rom[0:256*CHAR_HEIGHT-1];
    initial begin
        if (FONT_FILE != "") $readmemb(FONT_FILE, font_rom);
    end

    reg [9:0] h_pos = 0;
    reg [9:0] v_pos = 0;

    always @(posedge clk_pixel) 
    begin
        if (~nreset) begin
            h_pos <= H_LATENCY;
            v_pos <= 10'b0;
        end
        else begin
            //Pixel counters
            if (h_pos == H_TOTAL-1 + H_LATENCY) begin
                h_pos <= 0;
                if (v_pos == V_TOTAL - 1) begin
                    v_pos <= 0;
                end
                else begin
                    v_pos <= v_pos + 1;
                end
            end
            else begin
                h_pos <= h_pos + 1;
            end
            blank <= !visible;
            hsync <= !(H_BACK + H_VISIBLE + H_FRONT + H_LATENCY <= h_pos);
            vsync <= !(V_BACK + V_VISIBLE + V_FRONT <= v_pos);
        end
    end

    // TODO - maintain these in a similar way to h_valid, etc.
    // to avoid instantiating a bunch of >= / < logic
    wire h_active = (H_BACK + H_LATENCY <= h_pos && h_pos < H_BACK + H_VISIBLE + H_LATENCY);
    wire v_active = (V_BACK <= v_pos && v_pos < V_BACK + V_VISIBLE);
    wire visible = h_active && v_active;

    reg h_valid_in_2 = 0;
    reg h_valid_in_1 = 0;
    reg h_valid = 0;
    reg v_valid = 0;
    reg [9:0] vp_hpos = 0;

    always @(posedge clk_pixel) begin
        h_valid <= h_valid_in_1;
        h_valid_in_1 <= h_valid_in_2;

        if (h_pos == vp_left) begin
            h_valid_in_2 <= 1;
            vp_hpos <= 0;
        end
        else if (h_pos == vp_right) begin
            h_valid_in_2 <= 0;
        end
        else begin
            vp_hpos <= vp_hpos + 1;
        end

        if (v_pos == vp_top) begin
            v_valid <= 1;
        end
        else if (v_pos == vp_bottom) begin
            v_valid <= 0;
        end
    end

    // maintain offsets within char, and init char_addr at start of each line
    reg [15:0] char_addr = 0;
    reg [15:0] char_addr_left;  // address of left most char of line
    reg [2:0] char_y = 0;       // y-offset within char
    reg [2:0] char_x = 0;       // x-offset within char

    reg [7:0] hphys_cnt = 0; // physical pixel counter
    reg [1:0] vzoom_cnt = 0; // vertical zoom countdown
    reg [1:0] hzoom_cnt = 0; // horizontal zoom countdown

    always @(posedge clk_pixel) begin
        if (v_valid) begin
            if (h_pos == vp_left) begin
                if (v_pos == vp_top) begin
                    char_addr <= base_addr;
                    char_addr_left <= base_addr;
                    char_y <= 0;
                    vzoom_cnt <= vzoom_max;
                end
                else begin
                    if (vzoom_cnt != 0) begin
                        char_addr <= char_addr_left;
                        vzoom_cnt <= vzoom_cnt - 1;
                    end
                    else begin
                        vzoom_cnt <= vzoom_max;
                        if (!mode_text || {1'b0,char_y} == CHAR_BOTTOM) begin
                            char_y <= 0;
                            char_addr_left <= char_addr;
                        end
                        else begin
                            char_addr <= char_addr_left;
                            char_y <= char_y + 1;
                        end
                    end
                end
                hzoom_cnt <= hzoom_max;
                hphys_cnt <= hphys_max;
                char_x <= mode_pre1;
            end
            else if (h_valid_in_2) begin
                if (hphys_cnt == 0) begin
                    hphys_cnt <= hphys_max;
                end
                else begin
                    hphys_cnt <= hphys_cnt - 1;
                end

                if (hzoom_cnt != 0) begin
                    hzoom_cnt <= hzoom_cnt - 1;
                end
                else begin
                    // the issue is perhaps that char_x is counting logical rather than physical pixels
                    hzoom_cnt <= hzoom_max;
                    if (char_x == mode_pre2) begin
                        char_addr <= char_addr+1;
                    end
                    if (char_x == mode_pre1) begin
                        char_x <= 0;
                    end
                    else begin
                        char_x <= char_x + mode_bpp;
                    end
                end
            end
        end
    end

    wire char_rd = h_valid_in_2 && v_valid && (char_x == mode_pre1);

    // memory read
    assign mem_addr = char_addr;
    assign mem_rd = char_rd;

    wire [7:0] char_din = mem_din;

    // pixel shift-register
    reg [CHAR_WIDTH-1:0] char_pixels = {CHAR_WIDTH{1'b0}};

    always @(posedge clk_pixel) begin
        if (hzoom_cnt == 0) begin
            if (char_x == 0) begin
                char_pixels <= mode_text ? font_rom[{char_din,char_y}] : char_din;
            end
            else begin
                char_pixels <= char_pixels << mode_bpp;
            end
        end
    end

    // palette lookup
    reg [3:0] char_pixel;
    always @* begin
        case (mode)
            MODE_TEXT,
            MODE_1BPP: char_pixel = {3'b0, char_pixels[CHAR_RIGHT]};
            MODE_2BPP: char_pixel = {2'b0, char_pixels[CHAR_RIGHT-:2]};
            MODE_4BPP: char_pixel = char_pixels[CHAR_RIGHT-:4];
        endcase
    end

    // Retrieve RRRR:GGGG:BBBB - the top 4 bits are (currently) ignored.
    wire [11:0] char_rgb444 = reg_palette[char_pixel][11:0];

    assign rgb444 = (h_valid && v_valid) ? char_rgb444 : border_rgb444;
    assign hvalid = h_valid;
    assign vvalid = v_valid;
    assign hpos = h_pos;
    assign vpos = v_pos;

endmodule

