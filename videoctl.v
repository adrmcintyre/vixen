`default_nettype none

module videoctl
(
	input         clk,
	input         clk_locked,   //TODO
	input  [9:0]  screen_x,
	input  [9:0]  screen_y,
    output [23:0] color,
    output [15:0] vaddr,
    output        en,
    input  [7:0]  din
);
    localparam VGA_WIDTH = 640;
    localparam VGA_HEIGHT = 480;
    localparam COLS = 64;
    localparam ROWS = 40;
    localparam CHAR_WIDTH = 8;
    localparam CHAR_HEIGHT = 8;

    // place video character buffer at top of RAM
    localparam BASE_ADDR = -(COLS * ROWS);

    localparam [9:0] MARGIN_LEFT = (VGA_WIDTH - COLS * CHAR_WIDTH) / 2;
    localparam [9:0] MARGIN_TOP = (VGA_HEIGHT - ROWS * CHAR_HEIGHT) / 2;

    localparam [9:0] VIEWPORT_LEFT = MARGIN_LEFT;
    localparam [9:0] VIEWPORT_TOP = MARGIN_TOP;
    localparam [9:0] VIEWPORT_RIGHT = VGA_WIDTH - VIEWPORT_LEFT;;
    localparam [9:0] VIEWPORT_BOTTOM = VGA_HEIGHT - VIEWPORT_TOP;

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

    reg hvalid = 0;
    reg vvalid = 0;
    reg [15:0] addr;
    reg [15:0] addr_left;
    reg [2:0] char_x = 0;
    reg [2:0] char_y = 0;

    wire on_frame_start = !vvalid && screen_x == VIEWPORT_LEFT  && screen_y == VIEWPORT_TOP;
    wire on_frame_left  = !hvalid && screen_x == VIEWPORT_LEFT;
    wire on_frame_right = hvalid  && screen_x == VIEWPORT_RIGHT;
    wire on_frame_end   = vvalid  && screen_x == VIEWPORT_RIGHT && screen_y == VIEWPORT_BOTTOM-1;

    always @(posedge clk) begin
        begin
            vvalid <= on_frame_start | vvalid & ~on_frame_end;
            hvalid <= on_frame_left  | hvalid & ~on_frame_right;
        end
    end

    always @(posedge clk) begin
        if (on_frame_start) begin
            addr <= BASE_ADDR;
            addr_left <= BASE_ADDR;
            char_x <= 0;
            char_y <= 0;
        end
        else if (on_frame_left) begin
            if ({1'b0,char_y} == CHAR_HEIGHT-1) begin
                char_y <= 0;
                addr_left <= addr;
            end
            else begin
                char_y <= char_y + 1;
                addr <= addr_left;
            end
        end
        else if (hvalid && vvalid) begin
            if ({1'b0,char_x} == CHAR_WIDTH-1) begin
                addr <= addr + 1;
            end
            else begin
                char_x <= char_x + 1;
            end
        end
    end

    wire [7:0] char_index = din;

    reg [7:0] pixels;

    always @(posedge clk) begin
        if (char_x == 0) begin
            pixels <= font_rom[{char_index,char_y}];
        end
        else begin
            pixels <= pixels << 1;
        end
    end

    assign en = hvalid && vvalid && {1'b0,char_x} == CHAR_WIDTH-1;
    assign vaddr = addr;
    assign color = (hvalid && vvalid) ? BORDER : pixels[CHAR_WIDTH-1] ? FOREGROUND : BACKGROUND;

endmodule

