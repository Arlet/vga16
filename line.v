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
reg [9:0] y = 0;			// line number
reg [9:0] x = 0;			// line x coordinate
reg [9:0] w = 0;			// width
reg [9:0] h = 0;			// height
reg [9:0] off = 0;			// offset (scan_y - y0)
reg [15:0] col_1;			// color

//reg [10:0] e;				// line x error
//wire epos = ~e[10];			// e positive
//reg [5:0] segment = 0;			// 
//reg [5:0] max_segment = 15;		// 

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

/*
 * scanline counter
 */
always @(posedge clk)
	if( trigger )			scan_y <= 0;
	else if( copy_done )		scan_y <= scan_y + 1;

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

reg drawing = 0;			// actively drawing
reg vector_valid = 0;
reg xy_valid = 0;

always @(posedge clk)
	if( trigger | copy_done )	drawing <= 1;
	else if( last_vector )		drawing <= 0;

always @(posedge clk)
	if( ~drawing )			vector <= 0;
	else if( read_vector )		vector <= vector + 1;

always @(posedge clk)
	if( read_vector ) begin
	    vector_valid <= drawing && !last_vector;
	    xy_valid <= vector_valid;
	end

reg fill = 0;
reg first = 1;

always @(posedge clk)
	if( xy_valid && w != 0 && off <= h ) begin
	    x <= x + 1;
	    w <= w - 1;
	end else if( read_vector ) begin
	        x <= x0;
		w <= x1 - x0;
		h <= y1 - y0;
	        y <= y0;
	      off <= scan_y - y0;
	    col_1 <= col;
	end 

always @(posedge clk)
	if( xy_valid )
	    if( w == 0 || y != scan_y )	first <= 1;
	    else			first <= 0;

assign read_vector = !xy_valid || w == 0 || off > h;

`ifdef NO
always @(posedge clk)
	if( state == DRAW )
	    case( seg_state )
		SEG_LOAD: begin
			if( y == 0 ) begin
			    x <= segment << 5;
			    e <= 0;
			end else begin
			    x <= seg_x[segment]; 
			    e <= seg_e[segment];
			end
			seg_state <= SEG_DRAW;
			fill <= 1;
		    end

	 	SEG_DRAW: begin
			if( epos ) begin
			    x <= w[10] ? x + 1 : x - 1;
			    e <= e - seg_h[segment]; 
			end else begin
			    e <= e + w[9:0];
			    seg_state <= SEG_SAVE;
			end
			fill <= 0;
		    end

		SEG_SAVE: begin
		        seg_x[segment] <= x;
			seg_e[segment] <= e;
			segment <= segment + 1;
			seg_state <= SEG_LOAD; 
		    end
	    endcase
	else begin
	    segment <= 0;
	    seg_state <= SEG_LOAD;
	end
`endif

wire plot = xy_valid && off <= h;
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
//reg [9:0] rd_addr = 0;
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
	.WEA( 1'b1 /*state == COPY && ~fifo_full */ ),

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

