/*
 * draw a line from (0,0) to (w,h)
 *
 * (c) Arlet Ottens <arlet@c-scape.nl>
 */
module line( 
    input clk,
    input [9:0] w,
    input [9:0] h,
    input trigger,
    input [15:0] color,
    input fifo_full,
    output reg fifo_write,
    output reg [15:0] fifo_data );

reg [10:0] x;		// line x coordinate
reg [10:0] e;		// line x error
wire epos = ~e[10];	// e >= 0 

/*
 * line drawing state machine
 */

parameter
        SYNC = 3'd0,                    // ready with field, waiting for new vsync
        IDLE = 3'd1,                    // waiting for sprite / newline
        BUSY = 3'd2,                    // paint the sprite
        COPY = 3'd3;                    // copy the scanline to the video output

reg [2:0] state = 0;
reg [2:0] next = 0;

wire draw;

reg paint_done = 0;
reg paint_start = 0;
wire linebuf_write;

wire copy_start = 1;
wire copy_done;

reg [9:0] rd_addr = 0;
wire [15:0] rd_data;
wire [9:0] wr_addr = x;
wire [15:0] wr_data = 16'b00000_111111_00000;

/*
 * line drawing
 */

always @(posedge clk)
    if( trigger ) begin
        x <= 0;
	e <= 0;
    end else if( state == BUSY && !paint_done ) begin
        if( epos ) begin
	    x <= x + 1;
	    e <= e - h;
	end else begin
	    paint_done <= 1;
	    e <= e + w;
	end
    end else if( paint_done ) begin
       paint_done <= 0;
    end

wire plot = epos && !paint_done && state == BUSY;
assign linebuf_write = plot;

always @(posedge clk)
    if( trigger )
        paint_start <= 1;
    else if( state == BUSY )
	paint_start <= 0;
    else if( state == COPY )
	paint_start <= 1;

/*
 * state machine
 */

always @(posedge clk)
        state <= next;

always @* begin
        next = state;
        case( state )
            SYNC: if( trigger )                 next = IDLE;

            IDLE: if( paint_start )             next = BUSY;
                  else if( copy_start )         next = COPY;

            BUSY: if( paint_done )              next = IDLE;

            COPY: if( copy_done )		next = IDLE;
        endcase
end


/*
 * copy handling 
 */

reg [9:0] copy_addr = 0;
assign copy_done = (copy_addr == 640) & ~fifo_full;

reg vid_data_valid = 0;

always @*
    	rd_addr = copy_addr;

always @(posedge clk)
	if( state != COPY )
	    vid_data_valid <= 0;
	else
	    vid_data_valid <= 1;

wire copy_enable = !fifo_full || !vid_data_valid;

always @(posedge clk)
	if( state != COPY )
	    copy_addr <= 0;
	else if( copy_enable )
	    copy_addr <= copy_addr + 1;

RAMB16_S18_S18 line_buffer(
	// read/erase port 
	.CLKA(clk),
	.ADDRA(rd_addr),
	.DIPA(2'b0),
	.DIA(0),
	.DOA(rd_data),
	.ENA( state != COPY || copy_enable ),
	.SSRA(1'b0),
	.WEA( state == COPY && copy_enable ),

	// write port
	.CLKB(clk),
	.ADDRB(wr_addr),
	.DIPB(2'b0),
	.DIB(wr_data),
	.ENB(linebuf_write),
	.WEB(linebuf_write),
	.SSRB(1'b0)
	);

defparam line_buffer.WRITE_MODE_A = "READ_FIRST";

// send FIFO data 
// the copy done signal indicates last pixel of the scanline

always @(posedge clk)
	if( !fifo_full )
	    fifo_data <= rd_data;

always @(posedge clk)
	fifo_write <= (state == COPY) & vid_data_valid;

endmodule

