`default_nettype none

module videoctl
(
    // clock
	input clk_pixel,
    input nreset,
    // registers
    input         reg_clk,
    input         reg_wr,
    input  [7:0]  reg_data,
    input  [5:0]  reg_addr,
    // vga output
    output reg vsync,
    output reg hsync,
    output reg blank,
    output     [23:0] rgb,
    // memory access
    output reg [15:0] addr,
    output        rd,
    input  [7:0]  din
);

    // Horizontal timings
    //                        h_total
    // :------------------------------------------------------->:
    //
    //   h_back              h_visible              h_front h_sync
    // :-------->:---------------------------------->:---->:--->:
    //
    // ____________________________________________________  
    //                                                     |_____  hsync
    // __________xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx____________  rgb data


    // Vertical timings
    //                           v_total
    // :--------------------------------------------------------->:
    //
    //   v_back                 v_visible              v_back v_sync
    // :---------->:------------------------------------>:--->:-->:
    // ________________________________________________________
    //                                                         |___  vsync
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

    localparam H_TOTAL = H_BACK + H_VISIBLE + H_FRONT + H_SYNC;
    localparam V_TOTAL = V_BACK + V_VISIBLE + V_FRONT + V_SYNC;

    localparam [23:0] RGB_CANARY = 24'hffffaa;
    localparam [23:0] BORDER     = RGB_CANARY;

    localparam FONT_FILE = "out/font.bin";

    localparam CHAR_WIDTH = 8;
    localparam CHAR_HEIGHT = 8;

    localparam CHAR_LEFT = 0;
    localparam CHAR_PRE_RIGHT = 6;
    localparam CHAR_RIGHT = 7;
    localparam CHAR_TOP = 0;
    localparam CHAR_BOTTOM = 7;

    localparam CTL_BASE      = 6'h00;   // address of first byte of video memory
    localparam CTL_LEFT      = 6'h02;   // h_pos of first pixel, from start of horizontal back porch
    localparam CTL_RIGHT     = 6'h04;   // h_pos+1 of last pixel, from start of horizontal back porch
    localparam CTL_TOP       = 6'h06;   // v_pos of first line, from start of vertical back porch
    localparam CTL_BOTTOM    = 6'h08;   // v_pos+1 of last line, from start of vertical back porch
    localparam CTL_MODE      = 6'h0A;   // [5:4]=vert zoom-1; [3:2]=horiz zoom-1; [1:0]=display mode 
    localparam CTL_PAL_RED   = 6'h10;   // base of palette entries (red components)
    localparam CTL_PAL_GREEN = 6'h20;   // (green components)
    localparam CTL_PAL_BLUE  = 6'h30;   // (blue components)

    localparam MODE_TEXT = 2'd0;
    localparam MODE_1BPP = 2'd1;
    localparam MODE_2BPP = 2'd2;
    localparam MODE_4BPP = 2'd3;

    // config register interface
    reg [7:0] control[0:'h3f];
    initial begin: init_control
        integer i;
        for(i=0; i<='h3f; i=i+1) control[i] = 8'h00;
    end
    always @(posedge reg_clk) begin
        if (reg_wr) control[reg_addr] <= reg_data;
    end

    wire [15:0] base_addr = {control[CTL_BASE  ],      control[CTL_BASE+1]};
    wire [9:0]  vp_left   = {control[CTL_LEFT  ][1:0], control[CTL_LEFT+1]};
    wire [9:0]  vp_right  = {control[CTL_RIGHT ][1:0], control[CTL_RIGHT+1]};
    wire [9:0]  vp_top    = {control[CTL_TOP   ][1:0], control[CTL_TOP+1]};
    wire [9:0]  vp_bottom = {control[CTL_BOTTOM][1:0], control[CTL_BOTTOM+1]};
    wire [1:0]  mode      = {control[CTL_MODE  ][1:0]};
    wire [1:0]  hzoom_max = {control[CTL_MODE  ][3:2]};
    wire [1:0]  vzoom_max = {control[CTL_MODE  ][5:4]};
    wire [7:0]  hphys_max = 8'd0; // TODO?

    // TODO - horizontal zoom has some timing issues:
    //      zoom=1 okay
    //      zoom=2 2 pixels to left
    //      zoom=3 4 pixels to left
    //      zoom=4 6 pixels to left
    // TODO - test cards for 2-bpp and 4-bpp

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

    always @(posedge clk_pixel) begin
        h_valid <= h_valid_in_1;
        h_valid_in_1 <= h_valid_in_2;

        if (h_pos == vp_left) begin
            h_valid_in_2 <= 1;
        end
        else if (h_pos == vp_right) begin
            h_valid_in_2 <= 0;
        end

        if (v_pos == vp_top) begin
            v_valid <= 1;
        end
        else if (v_pos == vp_bottom) begin
            v_valid <= 0;
        end
    end

    // maintain offsets within char, and init addr at start of each line
    reg [15:0] addr_left;   // address of left most char of line
    reg [2:0] char_y = 0;   // y-offset within char
    reg [2:0] char_x = 0;   // x-offset within char

    reg [7:0] hphys_cnt = 0; // physical pixel counter
    reg [1:0] vzoom_cnt = 0; // vertical zoom countdown
    reg [1:0] hzoom_cnt = 0; // horizontal zoom countdown

    always @(posedge clk_pixel) begin
        if (v_valid) begin
            if (h_pos == vp_left) begin
                if (v_pos == vp_top) begin
                    addr <= base_addr;
                    addr_left <= base_addr;
                    char_y <= 0;
                    vzoom_cnt <= vzoom_max;
                end
                else begin
                    if (vzoom_cnt != 0) begin
                        addr <= addr_left;
                        vzoom_cnt <= vzoom_cnt - 1;
                    end
                    else begin
                        vzoom_cnt <= vzoom_max;
                        if (!mode_text || {1'b0,char_y} == CHAR_BOTTOM) begin
                            char_y <= 0;
                            addr_left <= addr;
                        end
                        else begin
                            addr <= addr_left;
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
                        addr <= addr+1;
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

    // memory read
    assign rd = h_valid_in_2 && v_valid && (char_x == mode_pre1);
    wire [7:0] data = din;

    // pixel shift-register
    reg [CHAR_WIDTH-1:0] pixels = {CHAR_WIDTH{1'b0}};

    always @(posedge clk_pixel) begin
        if (hzoom_cnt == 0) begin
            if (char_x == 0) begin
                pixels <= mode_text ? font_rom[{data,char_y}] : data;
            end
            else begin
                pixels <= pixels << mode_bpp;
            end
        end
    end

    // palette lookup
    reg [3:0] pixel;
    always @* begin
        case (mode)
            MODE_TEXT,
            MODE_1BPP: pixel = {3'b0, pixels[CHAR_RIGHT]};
            MODE_2BPP: pixel = {2'b0, pixels[CHAR_RIGHT-:2]};
            MODE_4BPP: pixel = pixels[CHAR_RIGHT-:4];
        endcase
    end
    wire [7:0] red   = control[CTL_PAL_RED   | {2'b0, pixel}];
    wire [7:0] green = control[CTL_PAL_GREEN | {2'b0, pixel}];
    wire [7:0] blue  = control[CTL_PAL_BLUE  | {2'b0, pixel}];

    // output
    assign rgb = (h_valid && v_valid) ? {red,green,blue} : BORDER;

endmodule

