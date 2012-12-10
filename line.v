/*
 * draw a line from (0,0) to (w,h)
 *
 * (c) Arlet Ottens <arlet@c-scape.nl>
 */
module line( 
	input clk,
	input [9:0] w,
	input trigger,
	input fifo_full,
	output reg fifo_write,
	output reg [15:0] fifo_data );

reg [10:0] x;				// line x coordinate
reg [10:0] e;				// line x error
wire epos = ~e[10];			// e positive
reg [10:0] y = 0;			// line number
reg [5:0] segment = 0;			// 
reg [5:0] max_segment = 6;		// 

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
wire last_line = (y == 479);

wire copy_done;

reg [10:0] seg_x[0:63];			// segment 'x' 
reg [10:0] seg_e[0:63];			// segment 'e' 
reg [10:0] seg_h[0:63];			// segment 'h' 
reg [15:0] seg_col[0:63];		// segment color

reg [9:0] rd_addr = 0;
wire [15:0] rd_data;
wire [9:0] wr_addr = x;
wire [15:0] wr_data = seg_col[segment];

wire last_segment = (segment == max_segment);

initial begin
    seg_h[0] = 360;
    seg_h[1] = 440;
    seg_h[2] = 240;
    seg_h[3] = 200;
    seg_h[4] = 301;
    seg_h[5] = 100;
    seg_h[6] = 50;

    seg_col[0] = 16'b11111_111111_00000;
    seg_col[1] = 16'b00000_111111_11111;
    seg_col[2] = 16'b11111_000000_11111; 
    seg_col[3] = 16'b11111_000000_00000;
    seg_col[4] = 16'b00000_111111_00000;
    seg_col[5] = 16'b00000_100000_11111;
    seg_col[6] = 16'b11111_111111_11111;
end

parameter
	SEG_INIT = 2'd0,
	SEG_LOAD = 2'd1,
	SEG_DRAW = 2'd2,
	SEG_SAVE = 2'd3;

reg [1:0] seg_state = SEG_INIT;
reg [1:0] seg_next;

/*
 * line drawing
 */

always @(posedge clk)
	if( state == DRAW )
	    case( seg_state )
	        SEG_INIT: begin
		       x <= segment << 3;
		       e <= 0;
		       seg_state <= SEG_DRAW;
		    end

		SEG_LOAD: begin
			if( y == 0 ) begin
			    x <= segment << 3;
			    e <= 0;
			end else begin
			    x <= seg_x[segment]; 
			    e <= seg_e[segment];
			end
			seg_state <= SEG_DRAW;
		    end

	 	SEG_DRAW:
		    if( epos ) begin
			x <= x + 1;
			e <= e - seg_h[segment];
		    end else begin
			e <= e + w;
			seg_state <= SEG_SAVE;
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

wire plot = epos && state == DRAW && seg_state == SEG_DRAW;
assign linebuf_write = plot;
assign draw_done = state == DRAW && seg_state == SEG_SAVE && last_segment;

/*
 * scanline counter
 */
always @(posedge clk)
	if( trigger )			y <= 0;
	else if( draw_done )		y <= y + 1;

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

