`default_nettype none

module videoctl
(
    // clock
	input clk_pixel,
    input nreset,
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
    localparam h_total = h_visible + h_front + h_sync + h_back;

    localparam v_visible = 10'd480;     // VGA height
    localparam v_front = 10'd10;
    localparam v_sync = 10'd2;
    localparam v_back = 10'd31;

    localparam COLS = 64;
    localparam ROWS = 40;

    localparam CHAR_WIDTH = 8;
    localparam CHAR_HEIGHT = 8;

    localparam CHAR_LEFT = 0;
    localparam CHAR_PRE_RIGHT = 6;
    localparam CHAR_RIGHT = 7;
    localparam CHAR_TOP = 0;
    localparam CHAR_BOTTOM = 7;

    // place video character buffer at top of RAM
    localparam BASE_ADDR = -(COLS * ROWS);
    localparam LAST_ADDR = 16'hffff;

    localparam [9:0] MARGIN_LEFT = (h_visible - COLS * CHAR_WIDTH) / 2;
    localparam [9:0] MARGIN_TOP = (v_visible - ROWS * CHAR_HEIGHT) / 2;

    localparam [9:0] VIEWPORT_LEFT = MARGIN_LEFT;
    localparam [9:0] VIEWPORT_TOP = MARGIN_TOP;
    localparam [9:0] VIEWPORT_RIGHT = h_visible - VIEWPORT_LEFT;;
    localparam [9:0] VIEWPORT_BOTTOM = v_visible - VIEWPORT_TOP;

    localparam [23:0] RGB_CANARY = 24'hffffaa;
    localparam [23:0] RGB_BLACK  = 24'h000000;
    localparam [23:0] RGB_WHITE  = 24'hffffff;

    localparam [23:0] BORDER     = RGB_CANARY;
    localparam [23:0] BACKGROUND = RGB_BLACK;
    localparam [23:0] FOREGROUND = RGB_WHITE;

    localparam FONT_FILE = "out/font.bin";

    reg [CHAR_WIDTH-1:0] font_rom[0:256*CHAR_HEIGHT-1];
    initial begin
        if (FONT_FILE != "") $readmemb(FONT_FILE, font_rom);
    end

    localparam v_total = v_visible + v_front + v_sync + v_back;

    reg [9:0] h_pos = 0;
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
        if (h_pos == VIEWPORT_LEFT-2) begin
            h_valid_in_2 <= 1;
        end
        else if (h_pos == VIEWPORT_RIGHT-2) begin
            h_valid_in_2 <= 0;
        end

        if (v_pos == VIEWPORT_TOP) begin
            v_valid <= 1;
        end
        else if (v_pos == VIEWPORT_BOTTOM) begin
            v_valid <= 0;
        end
    end

    // maintain offsets within char, and init addr at start of each line
    reg [15:0] addr_left;   // address of left most char of line
    reg [2:0] char_y = 0;   // y-offset within char
    reg [2:0] char_x = 0;   // x-offset within char

    always @(posedge clk_pixel) begin
        if (v_valid) begin
            if (h_pos == VIEWPORT_LEFT-2) begin
                if (v_pos == VIEWPORT_TOP) begin
                    addr <= BASE_ADDR;
                    addr_left <= BASE_ADDR;
                    char_y <= CHAR_TOP;
                end
                else if ({1'b0,char_y} == CHAR_BOTTOM) begin
                    char_y <= CHAR_TOP;
                    addr_left <= addr;
                end
                else begin
                    addr <= addr_left;
                    char_y <= char_y + 1;
                end
                char_x <= CHAR_RIGHT;
            end
            else if (h_valid_in_2) begin
                if (char_x == CHAR_PRE_RIGHT) begin
                    addr <= addr+1;
                end
                if (char_x == CHAR_RIGHT) begin
                    char_x <= CHAR_LEFT;
                end
                else begin
                    char_x <= char_x+1;
                end
            end
        end
    end

    // memory read
    assign rd = h_valid_in_2 && v_valid && (char_x == CHAR_RIGHT);
    wire [7:0] char = din;

    // pixel shift-register
    reg [CHAR_WIDTH-1:0] pixels = {CHAR_WIDTH{1'b0}};

    always @(posedge clk_pixel) begin
        if (char_x == CHAR_LEFT) begin
            pixels <= font_rom[{char,char_y}];
        end
        else begin
            pixels <= pixels << 1;
        end
    end

    // output
    assign rgb = (h_valid && v_valid) ? (pixels[CHAR_RIGHT] ? FOREGROUND : BACKGROUND) : BORDER;

endmodule

