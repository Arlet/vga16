/*
 * vga.v 
 *
 * VGA signal generator. Generates hsync/vsync timing, and retrieves
 * pixel data from async FIFO. 
 *
 * (C) Arlet Ottens, <arlet@c-scape.nl>
 */

module vga( 
	input clk,		// main clock
	output reg vtrigger,	// start of new screen (clk domain)
	input [15:0] fifo_data,	// fifo data (clk domain)
	input fifo_write,	// fifo write enable (clk domain)
	output fifo_full,	// fifo full signal (clk domain)

	input pclk,		// pixel clock input (async)
	output reg hsync, 	// horizontal sync output (pclk domain)
	output reg vsync,	// vertical sync output (pclk domain)
	output [15:0] rgb   	// 16 bit RGB-565 output (pclk domain)
	);

/* 
 * states (used for both H and V state machines)
 */
parameter
    VIDEO  = 2'd0,		// active video area
    FRONT  = 2'd1,		// front porch
    SYNC   = 2'd2,		// sync pulse
    BACK   = 2'd3;		// back porch

/*
 * horizontal state 
 */
reg [11:0] hcount = 0;		// down counter for horizontal state 
reg [1:0] hnext = SYNC;		// next horizontal state
wire hcount_done = hcount <= 1;	// done when count is 1 (or 0). 
reg [11:0] htiming[3:0];	// horizontal timing lookup table 
reg next_line;			// one cycle trigger for vertical state
reg hactive = 0;		// '1' during active display

/*
 * vertical state 
 */
reg [11:0] vcount = 0;		// down counter for vertical state 
reg [1:0] vnext = BACK;		// next vertical state
wire vcount_done = vcount <= 1;	// done when count is 1 (or 0). 
reg [11:0] vtiming[3:0];	// vertical timing lookup table 
reg vactive = 0;		// '1' during active display

initial begin
    htiming[VIDEO] = 640;
    htiming[FRONT] = 16;
    htiming[SYNC]  = 96;
    htiming[BACK]  = 48;

    vtiming[VIDEO] = 480;
    vtiming[FRONT] = 10;
    vtiming[SYNC]  = 2;
    vtiming[BACK]  = 33;
end

initial
    $monitor( "%d", vnext );

/*
 * horizontal logic
 */
always @(posedge pclk)
    if( hcount_done )
        hcount <= htiming[hnext];
    else
	hcount <= hcount - 1;

always @(posedge pclk)
    if( hcount_done )
	hnext <= hnext + 1;

always @(posedge pclk) begin
    hsync   <= hnext == BACK;
    hactive <= hnext == FRONT;
end

always @(posedge pclk)
    next_line <= hcount_done & hsync;

/*
 * vertical logic
 */

always @(posedge pclk)
    if( next_line )
	if( vcount_done )
	    vcount <= vtiming[vnext];
	else
	    vcount <= vcount - 1;

always @(posedge pclk)
    if( next_line )
        if( vcount_done )
	    vnext <= vnext + 1;

always @(posedge pclk) begin
    vsync   <= vnext == BACK;
    vactive <= vnext == FRONT;
end

reg vsync0;
reg vsync1;
reg vsync2;

/*
 * synchronize vsync to 'clk' domain:
 * generate one cycle trigger when vsync falls 
 */
always @(posedge clk) begin
    vsync0 <= vsync;
    vsync1 <= vsync0;
    vsync2 <= vsync1;
    vtrigger <= vsync2 & ~vsync1;
end



/*
 * data output
 */

wire [17:0] fifo_out;
wire fifo_read = hnext == FRONT && vnext == FRONT; 
wire fifo_empty;

/* 
 * fifo for incoming pixel data
 */
async_fifo fifo( 
        .clka(clk),
        .in({2'b0,fifo_data}),
        .wr(fifo_write),
        .full(fifo_full),

        .clkb(pclk),
        .out(fifo_out),
        .rd(fifo_read),
        .empty(fifo_empty)
        );

assign rgb = hactive & vactive ? fifo_out[15:0] : 0;

endmodule
