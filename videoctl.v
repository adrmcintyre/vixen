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

    localparam h_visible = 10'd640;     // VGA width
    localparam h_front = 10'd16;
    localparam h_sync = 10'd96;
    localparam h_back = 10'd44;

    localparam v_visible = 10'd480;     // VGA height
    localparam v_front = 10'd10;
    localparam v_sync = 10'd2;
    localparam v_back = 10'd31;

    localparam h_total = h_visible + h_front + h_sync + h_back;
    localparam v_total = v_visible + v_front + v_sync + v_back;

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

    localparam CTL_BASE      = 6'h00;
    localparam CTL_LEFT      = 6'h02;    // set reg to vp_left-2
    localparam CTL_RIGHT     = 6'h04;    // set reg to vp_right-2
    localparam CTL_TOP       = 6'h06;
    localparam CTL_BOTTOM    = 6'h08;
    localparam CTL_MODE      = 6'h0A;
    localparam CTL_PAL_RED   = 6'h10;
    localparam CTL_PAL_GREEN = 6'h20;
    localparam CTL_PAL_BLUE  = 6'h30;

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

    reg [9:0] h_pos = 0;    // TODO offset -2 to make up for adjustment problem elsewhere
    reg [9:0] v_pos = 0;

    always @(posedge clk_pixel) 
    begin
        if (~nreset) begin
            h_pos <= 10'b0;
            v_pos <= 10'b0;
        end
        else begin
            //Pixel counters
            if (h_pos == h_total - 1) begin
                h_pos <= 0;
                if (v_pos == v_total - 1) begin
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
            hsync <= !((h_pos >= (h_visible + h_front)) && (h_pos < (h_visible + h_front + h_sync)));
            vsync <= !((v_pos >= (v_visible + v_front)) && (v_pos < (v_visible + v_front + v_sync)));
        end
    end

    // TODO - maintain these in a similar way to h_valid, etc.
    // to avoid instantiating a bunch of >= / < logic
    wire h_active = (h_pos < h_visible);
    wire v_active = (v_pos < v_visible);
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

    always @(posedge clk_pixel) begin
        if (v_valid) begin
            if (h_pos == vp_left) begin
                if (v_pos == vp_top) begin
                    addr <= base_addr;
                    addr_left <= base_addr;
                    char_y <= CHAR_TOP;
                end
                else if (!mode_text || {1'b0,char_y} == CHAR_BOTTOM) begin
                    char_y <= CHAR_TOP;
                    addr_left <= addr;
                end
                else begin
                    addr <= addr_left;
                    char_y <= char_y + 1;
                end
                char_x <= mode_pre1;
            end
            else if (h_valid_in_2) begin
                if (char_x == mode_pre2) begin
                    addr <= addr+1;
                end
                if (char_x == mode_pre1) begin
                    char_x <= CHAR_LEFT;
                end
                else begin
                    char_x <= char_x + mode_bpp;
                end
            end
        end
    end

    // memory read
    assign rd = h_valid_in_2 && v_valid && (char_x == mode_pre1);
    wire [7:0] data = din;

    // pixel shift-register
    reg [CHAR_WIDTH-1:0] pixels = {CHAR_WIDTH{1'b0}};

    /*
    reg [2:0] pix_acc = 0;  // pixel is emitted every time this hits 0
    reg [2:0] pix_inc = 0;  // pix_acc increment

    always @(posedge clk_pixel) begin
        pix_acc <= pix_acc + pix_inc;
        if (pix_acc == 3'd0) begin
            if (char_x == CHAR_LEFT) begin
                pixels <= mode_text ? font_rom[{data,char_y}] : data;
            end
            else begin
                pixels <= pixels << mode_bpp;
            end
        end
    end
    */

    always @(posedge clk_pixel) begin
        if (char_x == 0) begin
            pixels <= mode_text ? font_rom[{data,char_y}] : data;
        end
        else begin
            pixels <= pixels << mode_bpp;
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
    wire [7:0] red   = control[CTL_PAL_RED   | pixel];
    wire [7:0] green = control[CTL_PAL_GREEN | pixel];
    wire [7:0] blue  = control[CTL_PAL_BLUE  | pixel];

    // output
    assign rgb = (h_valid && v_valid) ? {red,green,blue} : BORDER;

endmodule

