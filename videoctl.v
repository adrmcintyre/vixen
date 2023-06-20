`default_nettype none

module videoctl
(
    // clock
	input clk_pixel,
    input clk_locked,
    // vga output
    output reg vga_vsync,
    output reg vga_hsync,
    output reg vga_blank,
    output     [23:0] color,
    // memory access
    output reg [15:0] addr,
    output        en,
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

    // place video character buffer at top of RAM
    localparam BASE_ADDR = -(COLS * ROWS);

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

    reg [7:0] font_rom[0:256*8-1];
    initial begin
        if (FONT_FILE != "") $readmemb(FONT_FILE, font_rom);
    end

    localparam v_total = v_visible + v_front + v_sync + v_back;
    wire h_active, v_active, visible;

    reg [9:0] h_pos = 0;
    reg [9:0] v_pos = 0;

    always @(posedge clk_pixel) 
    begin
        if (clk_locked == 0) begin
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
                vga_blank <= !visible;
                vga_hsync <= !((h_pos >= (h_visible + h_front)) && (h_pos < (h_visible + h_front + h_sync)));
                vga_vsync <= !((v_pos >= (v_visible + v_front)) && (v_pos < (v_visible + v_front + v_sync)));
        end
    end

    assign h_active = (h_pos < h_visible);
    assign v_active = (v_pos < v_visible);
    assign visible = h_active && v_active;

    reg [15:0] addr_left;
    reg [2:0] char_x = 0;
    reg [2:0] char_y = 0;

    reg v_valid = 0;
    reg h_valid = 0;

    always @(posedge clk_pixel) begin
        if (v_pos == VIEWPORT_TOP) begin
            v_valid <= 1;
        end
        else if (v_pos == VIEWPORT_BOTTOM) begin
            v_valid <= 0;
        end
    end

    always @(posedge clk_pixel) begin
        if (h_pos == VIEWPORT_LEFT-1) begin
            h_valid <= 1;
        end
        else if (h_pos == VIEWPORT_RIGHT-1) begin
            h_valid <= 0;
        end
    end

    always @(posedge clk_pixel) begin
        if (h_pos == VIEWPORT_LEFT-1) begin
            if (v_pos == VIEWPORT_TOP) begin
                addr <= BASE_ADDR;
                addr_left <= BASE_ADDR;
                char_x <= 0;
                char_y <= 0;
            end
            else if ({1'b0,char_y} == CHAR_HEIGHT-1) begin
                char_y <= 0;
                addr_left <= addr;
            end
            else begin
                addr <= addr_left;
                char_y <= char_y + 1;
            end
        end
        else if (h_valid && v_valid) begin
            if ({1'b0,char_x} == CHAR_WIDTH-1) begin
                char_x <= 0;
                addr <= addr+1;
            end
            else begin
                char_x <= char_x+1;
            end
        end
    end

    wire [7:0] char_index = din;

    reg [7:0] pixels = 8'h00;

    always @(posedge clk_pixel) begin
        if (char_x == 0) begin
            pixels <= font_rom[{char_index,char_y}];
        end
        else begin
            pixels <= pixels << 1;
        end
    end

    assign en = h_valid && v_valid && {1'b0,char_x} == CHAR_WIDTH-1;
    assign color = (h_valid && v_valid) ? (pixels[CHAR_WIDTH-1] ? FOREGROUND : BACKGROUND) : BORDER;

endmodule

