/*
 * draw lines
 *
 * (c) Arlet Ottens <arlet@c-scape.nl>
 */
module line( 
	input clk,

	/*
	 * vector info: 
	 * This module outputs the vector number, and expects to get
	 * the coordinates + color back on the next cycle when
	 * read_vector=1. If read_vector=0, the previous values must be
	 * maintained. 
	 *
	 * (x0,y0) indicates starting point, (x1,y1) indicates end point
	 * top left of screen = (0,0), and y1 >= y0.
	 */
	output reg [9:0] vector = 0,	// vector number
	output read_vector,		// read vector enable
	input [9:0] x0,			// top x coordinate
	input [9:0] y0,			// top y coordinate
	input [9:0] x1,			// vector delta y (abs)
	input [9:0] y1,			// vector delta x (abs)
	input [15:0] col,		// vector color
	input last_vector,		// last vector

	input trigger,			// start of new frame

	input fifo_full,
	output reg fifo_write,
	output reg [15:0] fifo_data );

reg [9:0] scan_y = 0;
reg [9:0] x = 0;			// line x coordinate
reg [9:0] xend = 0;			// line x coordinate last pixel
reg [10:0] e = 0;			// Bresenham error
reg [9:0] w = 0;			// width
reg [9:0] h = 0;			// height
reg [9:0] off = 0;			// offset (scan_y - y0)
reg [15:0] col_1;			// color

reg start_frame = 0;			// start a new frame
reg start_line = 0;			// start a new scanline


/*
 * line drawing state machine
 */

parameter
        SYNC = 2'd0,                    // waiting for vertical trigger
        DRAW = 2'd1,                    // draw the lines in the scanline buffer 
        COPY = 2'd2;                    // copy the scanline to the video output

reg [2:0] state = SYNC;
reg [2:0] next = SYNC;

wire draw_done;
wire last_line = (scan_y == 479);
wire copy_done;

always @(posedge clk)
 	if( trigger )			start_frame <= 1;
	else				start_frame <= 0;

always @(posedge clk)
 	if( trigger | copy_done )	start_line <= 1;
	else				start_line <= 0;


/*
 * scanline counter
 */
always @(posedge clk)
	if( start_frame )		scan_y <= 0;
	else if( start_line )		scan_y <= scan_y + 1;

/*
 * state machine
 */

always @(posedge clk)
        state <= next;

always @* begin
        next = state;
        case( state )
            SYNC: if( trigger )         next = DRAW;

            DRAW: if( draw_done )       next = COPY; 

            COPY: if( copy_done )
	    	      if( last_line )   next = SYNC;
		      else		next = DRAW;
        endcase
end

/*
 * line drawing
 */

reg [9:0] bres_wr_vector = 0;		// vector state write back
wire bres_we;				// state write enable
wire span;				// doing horizontal span
wire [31:0] bres_rd_data;		// Bresenham read state data
wire bres_valid;			// Bresenham state is valid
wire [9:0] bres_x;			// Bresenham state X coordinate
wire [10:0] bres_e;			// Bresenham state error value 

assign bres_valid = bres_rd_data[0]; 
assign bres_x = bres_rd_data[10:1];
assign bres_e = bres_rd_data[21:11];

RAMB16_S36_S36 Bresenham(
	// state read port 
	.CLKA(clk),
	.ADDRA(vector),
	.DIPA(4'b0),
	.DIA(0),
	.DOA(bres_rd_data),
	.ENA(read_vector),
	.SSRA(1'b0),
	.WEA(1'b0),

	// state write back port
	.CLKB(clk),
	.ADDRB(bres_wr_vector),
	.DIPB(4'b0),
	.DIB({e + w, x, 1'b1}),
	.ENB(bres_we),
	.WEB(bres_we),
	.SSRB(1'b0)
	);

reg drawing = 0;			// actively drawing
reg vector_valid = 0;
reg xy_valid = 0;

reg last_pixel = 0;

always @(posedge clk)
	last_pixel <= (x == xend);

wire in_range = off < h || (off == h && !last_pixel);
assign span = xy_valid && ~e[10] && in_range;

always @(posedge clk)
	if( start_line )			drawing <= 1;
	else if( vector_valid & last_vector )	drawing <= 0;

always @(posedge clk)
	if( start_line )			vector <= 0;
	else if( read_vector & drawing )	vector <= vector + 1;

always @(posedge clk)
	if( read_vector ) begin
	    vector_valid <= drawing;
	    xy_valid <= vector_valid && !last_vector;
	end

reg fill = 0;

always @(posedge clk)
	if( span || last_vector )		fill <= 0;
	else if( vector_valid )			fill <= 1;

assign bres_we = xy_valid && off <= h && e[10];		

always @(posedge clk)
	if( start_line )			bres_wr_vector <= 0;
	else if( bres_we )			bres_wr_vector <= bres_wr_vector + 1;

always @(posedge clk)
	if( span ) begin
	    e <= e - h;
	    x <= x + 1;
	end else if( read_vector ) begin
		w     <= x1 - x0;
		h     <= y1 - y0;
		off   <= scan_y - y0;
		xend  <= x1;
		col_1 <= col;
		if( bres_valid ) begin
		    x <= bres_x;
		    e <= bres_e;
		end else begin
		    x <= x0;
		    e <= 49;
		end
	end 

assign read_vector = !xy_valid || !span;

wire plot = (span | fill) && in_range;
reg xy_valid_1 = 0;

always @(posedge clk)
	xy_valid_1 <= xy_valid;

assign draw_done = xy_valid_1 && !xy_valid;

wire [9:0] wr_addr = x;
wire [15:0] wr_data = col_1;

/*
 * copy handling 
 */

reg [9:0] copy_addr = 0;
assign copy_done = (copy_addr == 639) & ~fifo_full;

reg vid_data_valid = 0;
wire [15:0] rd_data;

reg [9:0] fifo_count = 0;

always @(posedge clk)
	if( state != COPY )		vid_data_valid <= 0;
	else				vid_data_valid <= 1;

always @(posedge clk)
	if( state != COPY )		copy_addr <= 0;
	else if( ~fifo_full )		copy_addr <= copy_addr + 1;


RAMB16_S18_S18 line_buffer(
	// read/erase port 
	.CLKA(clk),
	.ADDRA(copy_addr),
	.DIPA(2'b0),
	.DIA(0),
	.DOA(rd_data),
	.ENA( state == COPY && ~fifo_full ),
	.SSRA(1'b0),
	.WEA( 1'b1 ),

	// write port
	.CLKB(clk),
	.ADDRB(wr_addr),
	.DIPB(2'b0),
	.DIB(wr_data),
	.ENB(plot),
	.WEB(plot),
	.SSRB(1'b0)
	);

defparam line_buffer.WRITE_MODE_A = "READ_FIRST";

// send FIFO data 
// the copy done signal indicates last pixel of the scanline

always @(posedge clk)
	if( !fifo_full )
	    fifo_data <= rd_data;

always @(posedge clk)
	if( !fifo_full )
	    fifo_write <= vid_data_valid;

always @(posedge clk)
	if( ~vid_data_valid )		fifo_count <= 0;
	else if( ~fifo_full )		fifo_count <= fifo_count + 1;

endmodule

