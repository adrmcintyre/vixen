`default_nettype none

module sprites(
    input clk_pixel,
    input v_valid,
    input hsync,
    input [9:0] v_pos,
    input [9:0] h_pos,

    // registers
    input         reg_wr,
    input  [15:0] reg_data,
    input  [7:0]  reg_addr,

    // memory access
    output [15:0] mem_addr,
    output        mem_rd,
    input  [7:0]  mem_din,

    output active,
    output [11:0] rgb444
);
    // control registers
    always @(posedge clk_pixel) begin
        if (reg_wr) begin
            casez(reg_addr)
            8'b01??_????: reg_pos[reg_addr[5:1]] <= reg_data;
            8'b1???_????: reg_look[reg_addr[6:1]] <= reg_data;
            default: ;
            endcase
        end
    end

    localparam H_VISIBLE = 10'd640;

    // sprite registers
    // positions:
    // +00:              [10]=xflip; [9:0]=xpos
    // +02: [15]=enable; [10]=yflip; [9:0]=ypos
    localparam POS_MAX = 5'h1f;

    reg [15:0] reg_pos[0:POS_MAX];

    // looks:
    // +00=bitmap address
    // +02=color 1
    // +04=color 2
    // +06=color 3
    localparam LOOK_MAX = 6'h3f;

    reg [15:0] reg_look[0:LOOK_MAX];

    // all control registers start at zero
    initial begin: init_control
        integer i;
        for(i=0; i<=POS_MAX; i=i+1) reg_pos[i] = 16'h0000;
        for(i=0; i<=LOOK_MAX; i=i+1) reg_look[i] = 16'h0000;
    end

    localparam
        SPRITE_WIDTH  = 16,
        SPRITE_HEIGHT = 16;

    localparam [2:0] STATE_IDLE  = 3'd0;
    localparam [2:0] STATE_FETCH = 3'd1;
    localparam [2:0] STATE_WAIT  = 3'd2;
    localparam [2:0] STATE_READ  = 3'd3;
    localparam [2:0] STATE_WRITE = 3'd4;

    reg [2:0] state = STATE_IDLE;

    reg [3:0] index;
    reg [1:0] byteoff;     // TODO Better name
    reg [3:0] dx;

    reg [15:0] addr;
    reg        rd = 1'b0;
    reg [511:0] fifo;

    wire [15:0] addr_base = reg_look[{index,2'd0}];
    wire [15:0] pos_x = reg_pos[{index,1'd0}];
    wire [15:0] pos_y = reg_pos[{index,1'd1}];

    wire [9:0]  x      = pos_x[9:0];
    wire        flip_x = pos_x[10];
    wire [3:0]  xor_x  = {4{flip_x}};
    wire [9:0]  compose_x = x + {6'b0,dx^xor_x};

    wire [9:0] y      = pos_y[9:0];
    wire       flip_y = pos_y[10];
    wire       enable = pos_y[15];
    wire [3:0] xor_y  = {4{flip_y}};

    wire [9:0] dy10 = v_pos - y;
    wire [3:0] dy   = dy10[3:0] ^ xor_y;
    wire       visible = dy10[9:4] == 6'd0;   // i.e. dy is in range [0..15]

    assign mem_addr = addr;
    assign mem_rd   = rd;

    // TODO Better name
    wire [7:0] din = {mem_din[1:0], mem_din[3:2], mem_din[5:4], mem_din[7:6]};
    wire       valid = enable & visible;
    wire [7:0] fifo_in = valid ? din : {4{2'b00}};
    wire [1:0] fifo_out = fifo[1:0];

    wire [3:0] index_next;
    wire [1:0] byteoff_next;
    assign {index_next,byteoff_next} = {index,byteoff} + {4'd0,2'd1};
    wire [15:0] base_next = reg_look[{index_next,2'd0}];
    wire [15:0] pos_y_next = reg_pos[{index_next,1'd1}];

    wire [9:0] y_next      = pos_y_next[9:0];
    wire       flip_y_next = pos_y_next[10];
    wire [3:0] xor_y_next  = {4{flip_y_next}};
    wire [9:0] dy10_next = v_pos - y_next;
    wire [3:0] dy_next   = dy10_next[3:0] ^ xor_y_next;

    // assert for one cycle at start of hsync (when hsync goes low)
    reg old_hsync = 1'b1;
    always @(posedge clk_pixel) begin
        old_hsync <= hsync;
    end
    wire hsync_start = (old_hsync==1'b1) && (hsync==1'b0);

    always @(posedge clk_pixel) begin
        case (state)
        STATE_IDLE: begin
            if (v_valid && hsync_start) begin
                compose_swap <= ~compose_swap;
                index <= 4'd0;
                byteoff <= 2'd0;
                dx <= 4'd0;
                rd <= 1'b0;
                state <= STATE_FETCH;
            end
        end

        STATE_FETCH: begin
            rd <= 1'b1;
            addr <= addr_base + {10'b0,dy,byteoff};
            state <= STATE_WAIT;
        end

        STATE_WAIT: begin
            state <= STATE_READ;
        end

        STATE_READ: begin
            fifo  <= {fifo_in, fifo[511:8]};
            state <= ({index,byteoff} == {4'd15,2'd3}) ? STATE_WRITE : STATE_WAIT;
            index <= index_next;
            byteoff  <= byteoff_next;
            addr  <= base_next + {10'b0,dy_next,byteoff_next};
        end

        STATE_WRITE: begin
            rd <= 1'b0;
            if (fifo_out != 2'b00) begin
                compose_buf[{compose_x,~compose_swap}] <= {index,fifo_out};
            end
            fifo <= {2'b00,fifo[511:2]};
            {index,dx} <= {index,dx} + {4'd0,4'd1};
            if ({index,dx} == {4'd15,4'd15}) begin
                state <= STATE_IDLE;
            end
        end

        default: begin
            state <= STATE_IDLE;
        end
        endcase
    end

    // double buffer [5:2]=index [1:0]=color
    (* no_rw_check *)
    reg [5:0] compose_buf[0:H_VISIBLE*2-1];

    reg compose_swap = 1'b0;

    reg [3:0] compose_sprite = 0;
    reg [1:0] compose_color = 0;
    always @(posedge clk_pixel) begin
        // this is read-before-write
        {compose_sprite,compose_color} <= compose_buf[{h_pos, ~compose_swap}];
        compose_buf[{h_pos, ~compose_swap}] <= {4'd0, 2'b00}; // set transparent color
    end

    assign rgb444 = reg_look[{compose_sprite,compose_color}][11:0];
    assign active = compose_color != 0;

endmodule


