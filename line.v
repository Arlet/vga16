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

reg [10:0] x;				// line x coordinate
reg [10:0] e;				// line x error
wire epos = ~e[10];			// e positive
reg [10:0] line = 0;			// line number

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
wire linebuf_write;
wire last_line = (line == 479);

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
	end else if( state == DRAW ) begin
	    if( epos ) begin
		x <= x + 1;
		e <= e - h;
	    end else 
		e <= e + w;
	end

wire plot = epos && !draw_done && state == DRAW;
assign linebuf_write = plot;
assign draw_done = (state == DRAW && !epos);

/*
 * line counter
 */
always @(posedge clk)
	if( trigger )			line <= 0;
	else if( draw_done )		line <= line + 1;

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
 * copy handling 
 */

reg [9:0] copy_addr = 0;
assign copy_done = (copy_addr == 640) & ~fifo_full;

reg vid_data_valid = 0;

always @*
    	rd_addr = copy_addr;

always @(posedge clk)
	if( state != COPY )		vid_data_valid <= 0;
	else				vid_data_valid <= 1;

wire copy_enable = !fifo_full || !vid_data_valid;

always @(posedge clk)
	if( state != COPY )		copy_addr <= 0;
	else if( copy_enable )		copy_addr <= copy_addr + 1;

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

