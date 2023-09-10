`default_nettype none

module videoctl
(
    // clock
	input clk_pixel,
    input nreset,
    // registers
    input         reg_clk,
    input         reg_wr,
    input  [15:0] reg_data,
    input  [6:0]  reg_addr,
    // vga output
    output reg vsync,
    output reg hsync,
    output reg blank,
    output     [23:0] rgb,
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
    //                                                     |_____  hsync
    // __________xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx____________  rgb data


    // Vertical timings
    //                           v_total
    // :--------------------------------------------------------->:
    //
    //   v_back                 v_visible              v_front v_sync
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

    localparam H_SYNC_START = H_BACK + H_VISIBLE + H_FRONT;
    localparam V_SYNC_START = V_BACK + V_VISIBLE + V_FRONT;
    localparam H_TOTAL = H_SYNC_START + H_SYNC;
    localparam V_TOTAL = V_SYNC_START + V_SYNC;

    // TODO make this a control param
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

    // external addresses of registers
    localparam ADDR_CTL         = 8'h00>>1;
    localparam ADDR_PALETTE     = 8'h20>>1;
    localparam ADDR_SPRITE_POS  = 8'h40>>1;
    localparam ADDR_SPRITE_LOOK = 8'h80>>1;

    // control registers
    localparam CTL_BASE   = 4'h0; // address of first byte of video memory
    localparam CTL_LEFT   = 4'h1; // h_pos of first pixel, from start of horizontal back porch
    localparam CTL_RIGHT  = 4'h2; // h_pos+1 of last pixel, from start of horizontal back porch
    localparam CTL_TOP    = 4'h3; // v_pos of first line, from start of vertical back porch
    localparam CTL_BOTTOM = 4'h4; // v_pos+1 of last line, from start of vertical back porch
    localparam CTL_MODE   = 4'h5; // [5:4]=vert zoom-1; [3:2]=horiz zoom-1; [1:0]=display mode 
    localparam CTL_MAX    = 4'hf;

    localparam MODE_TEXT = 2'd0;
    localparam MODE_1BPP = 2'd1;
    localparam MODE_2BPP = 2'd2;
    localparam MODE_4BPP = 2'd3;

    reg [15:0] reg_control[0:CTL_MAX];

    wire [15:0] base_addr = reg_control[CTL_BASE] [15:0];
    wire [9:0]  vp_left   = reg_control[CTL_LEFT]  [9:0];
    wire [9:0]  vp_right  = reg_control[CTL_RIGHT] [9:0];
    wire [9:0]  vp_top    = reg_control[CTL_TOP]   [9:0];
    wire [9:0]  vp_bottom = reg_control[CTL_BOTTOM][9:0];
    wire [1:0]  mode      = reg_control[CTL_MODE]  [1:0];
    wire [1:0]  hzoom_max = reg_control[CTL_MODE]  [3:2];
    wire [1:0]  vzoom_max = reg_control[CTL_MODE]  [5:4];
    wire [7:0]  hphys_max = 8'd0; // TODO?

    // palette registers
    localparam PALETTE     = 4'h0; // palette: 16-bits * 16 entries = 256 bits
    localparam PALETTE_MAX = 4'hf;

    reg [15:0] reg_palette[0:PALETTE_MAX];

    // sprite registers
    // positions:
    // +00:              [10]=xflip; [9:0]=xpos
    // +02: [15]=enable; [10]=yflip; [9:0]=ypos
    localparam SPRITE_POS_MAX = 5'h1f;

    reg [15:0] reg_sprite_pos[0:SPRITE_POS_MAX];

    // looks:
    // +00=bitmap address
    // +02=color 1
    // +04=color 2
    // +06=color 3
    localparam SPRITE_LOOK_MAX = 6'h3f;

    reg [15:0] reg_sprite_look[0:SPRITE_LOOK_MAX];

    // all control registers start at zero
    initial begin: init_control
        integer i;
        for(i=0; i<=CTL_MAX; i=i+1) reg_control[i] = 16'h0000;
        for(i=0; i<=PALETTE_MAX; i=i+1) reg_palette[i] = 16'h0000;
        for(i=0; i<=SPRITE_POS_MAX; i=i+1) reg_sprite_pos[i] = 16'h0000;
        for(i=0; i<=SPRITE_LOOK_MAX; i=i+1) reg_sprite_look[i] = 16'h0000;
    end

    // control registers: external write port
    always @(posedge reg_clk) begin
        if (reg_wr) begin
            casez(reg_addr)
            7'b000_????: reg_control[reg_addr[3:0]] <= reg_data;
            7'b001_????: reg_palette[reg_addr[3:0]] <= reg_data;
            7'b01?_????: reg_sprite_pos[reg_addr[4:0]] <= reg_data;
            7'b1??_????: reg_sprite_look[reg_addr[5:0]] <= reg_data;
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
    assign mem_addr = sprite_rd ? sprite_addr : char_addr;
    assign mem_rd = char_rd | sprite_rd;

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


    //-------------------------------------------------------------------------
    // SPRITE COMPOSITION STARTS HERE
    //-------------------------------------------------------------------------

    localparam
        SPRITE_WIDTH  = 16,
        SPRITE_HEIGHT = 16;

    localparam [2:0] SPRITE_IDLE  = 3'd0;
    localparam [2:0] SPRITE_FETCH = 3'd1;
    localparam [2:0] SPRITE_WAIT  = 3'd2;
    localparam [2:0] SPRITE_READ  = 3'd3;
    localparam [2:0] SPRITE_WRITE = 3'd4;

    reg [2:0] sprite_state = SPRITE_IDLE;

    reg [3:0] sprite_index;
    reg [1:0] sprite_byte;
    reg [3:0] sprite_dx;

    reg [15:0] sprite_addr;
    reg        sprite_rd = 1'b0;
    reg [511:0] sprite_fifo;

    wire [15:0] sprite_base = reg_sprite_look[{sprite_index,2'd0}];
    wire [15:0] sprite_pos_x = reg_sprite_pos[{sprite_index,1'd0}];
    wire [15:0] sprite_pos_y = reg_sprite_pos[{sprite_index,1'd1}];

    wire [9:0]  sprite_x      = sprite_pos_x[9:0];
    wire        sprite_flip_x = sprite_pos_x[10];
    wire [3:0]  sprite_xor_x  = {4{sprite_flip_x}};
    wire [9:0]  compose_x = sprite_x + {6'b0,sprite_dx^sprite_xor_x};

    wire [9:0] sprite_y      = sprite_pos_y[9:0];
    wire       sprite_flip_y = sprite_pos_y[10];
    wire       sprite_enable = sprite_pos_y[15];
    wire [3:0] sprite_xor_y  = {4{sprite_flip_y}};

    wire [9:0] sprite_dy10 = v_pos - sprite_y;
    wire [3:0] sprite_dy   = sprite_dy10[3:0] ^ sprite_xor_y;
    wire       sprite_visible = sprite_dy10[9:4] == 6'd0;   // i.e. sprite_dy is in range [0..15]

    wire [7:0] sprite_din = {mem_din[1:0], mem_din[3:2], mem_din[5:4], mem_din[7:6]};
    wire       sprite_valid = sprite_enable & sprite_visible;
    wire [7:0] sprite_fifo_in = sprite_valid ? sprite_din : {4{2'b00}};
    wire [1:0] sprite_fifo_out = sprite_fifo[1:0];

    wire [3:0] sprite_index_next;
    wire [1:0] sprite_byte_next;
    assign {sprite_index_next,sprite_byte_next} = {sprite_index,sprite_byte} + {4'd0,2'd1};
    wire [15:0] sprite_base_next = reg_sprite_look[{sprite_index_next,2'd0}];

    wire [15:0] sprite_pos_y_next = reg_sprite_pos[{sprite_index_next,1'd1}];
    wire [9:0] sprite_y_next      = sprite_pos_y_next[9:0];
    wire [9:0] sprite_dy10_next = v_pos - sprite_y_next;
    wire       sprite_flip_y_next = sprite_pos_y_next[10];
    wire [3:0] sprite_xor_y_next  = {4{sprite_flip_y_next}};
    wire [3:0] sprite_dy_next   = sprite_dy10_next[3:0] ^ sprite_xor_y_next;

    // TODO - pipeline further to get down to 1 read per clock
    always @(posedge clk_pixel) begin
        case (sprite_state)
        SPRITE_IDLE: begin
            if (v_valid && h_pos == H_SYNC_START) begin
                compose_swap <= ~compose_swap;
                sprite_index <= 4'd0;
                sprite_byte <= 2'd0;
                sprite_dx <= 4'd0;
                sprite_rd <= 1'b0;
                sprite_state <= SPRITE_FETCH;
            end
        end

        SPRITE_FETCH: begin
            sprite_rd <= 1'b1;
            sprite_addr <= sprite_base + {10'b0,sprite_dy,sprite_byte};
            sprite_state <= SPRITE_WAIT;
        end

        SPRITE_WAIT: begin
            sprite_state <= SPRITE_READ;
        end

        SPRITE_READ: begin
            sprite_fifo  <= {sprite_fifo_in, sprite_fifo[511:8]};
            sprite_state <= ({sprite_index,sprite_byte} == {4'd15,2'd3}) ? SPRITE_WRITE : SPRITE_WAIT;
            sprite_index <= sprite_index_next;
            sprite_byte  <= sprite_byte_next;
            sprite_addr  <= sprite_base_next + {10'b0,sprite_dy_next,sprite_byte_next};
        end

        SPRITE_WRITE: begin
            sprite_rd <= 1'b0;
            if (sprite_fifo_out != 2'b00) begin
                compose_buf[{compose_x,~compose_swap}] <= {sprite_index,sprite_fifo_out};
            end
            sprite_fifo <= {2'b00,sprite_fifo[511:2]};
            {sprite_index,sprite_dx} <= {sprite_index,sprite_dx} + {4'd0,4'd1};
            if ({sprite_index,sprite_dx} == {4'd15,4'd15}) begin
                sprite_state <= SPRITE_IDLE;
            end
        end

        default: begin
            sprite_state <= SPRITE_IDLE;
        end
        endcase
    end

    // double buffer [5:2]=index [1:0]=color
    reg [5:0] compose_buf[0:H_VISIBLE*2-1];

    reg compose_swap = 1'b0;

    reg [3:0] compose_sprite = 0;
    reg [1:0] compose_color = 0;
    always @(posedge clk_pixel) begin
        // this is read-before-write
        {compose_sprite,compose_color} <= compose_buf[{h_pos, ~compose_swap}];
        compose_buf[{h_pos, ~compose_swap}] <= {4'd0, 2'b00}; // set transparent color
    end

    wire [11:0] sprite_rgb444 = reg_sprite_look[{compose_sprite,compose_color}][11:0];

    // Split into 4-bit components
    wire [11:0] rgb444 = (compose_color == 0) ? char_rgb444 : sprite_rgb444;
    wire [3:0] red4 = rgb444[8+:4];
    wire [3:0] grn4 = rgb444[4+:4];
    wire [3:0] blu4 = rgb444[0+:4];

    // Expand to 8 bits by replicating top 4 bits into bottom 4 to ensure
    // we use the full dynamic range (effectively multiplies by 255/15).
    wire [7:0] red8 = {red4, red4};
    wire [7:0] grn8 = {grn4, grn4};
    wire [7:0] blu8 = {blu4, blu4};

    // output
    assign rgb = (h_valid && v_valid) ? {red8, grn8, blu8} : BORDER;

endmodule

