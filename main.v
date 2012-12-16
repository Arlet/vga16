/*
 * top level module
 *
 * (C) Arlet Ottens <arlet@c-scape.nl>
 *
 */

module main( 
    input reset,
    input clk100,
    output pclk_out,
    output [4:0] red,
    output [5:0] green,
    output [4:0] blue,
    output vsync,
    output hsync
	 );

wire [15:0] rgb;
assign blue = rgb[4:0];
assign green = rgb[10:5];
assign red = rgb[15:11];
wire fifo_write;
wire fifo_full;
wire [15:0] fifo_data;
wire pclk0;
wire vtrigger;

/* pixel clock output using DDR flipflop */
ODDR2 ODDR2 (
    .Q(pclk_out),
    .C0(pclk),
    .C1(~pclk),
    .CE(1'b1),
    .D0(1'b1),
    .D1(1'b0),
    .R(1'b0),
    .S(1'b0)
    );

wire dcm_clk100;
wire clk;

/* clock buffers */
IBUFG IBUFG_clk( .I(clk100), .O(dcm_clk100) );
BUFG BUFG_clk( .I(dcm_clk100), .O(clk) );
BUFG BUFG_PCLK( .I(pclk0), .O(pclk) );

/* Use DCM to generate 25 MHz VGA pixel clock from 100 MHz main clock */

DCM_SP #(
         .CLKDV_DIVIDE(4.0),
         .CLKFX_DIVIDE(8),
         .CLKFX_MULTIPLY(2),
         .CLKIN_DIVIDE_BY_2("FALSE"),
         .CLKIN_PERIOD(10.0),
         .CLKOUT_PHASE_SHIFT("FIXED"),
         .CLK_FEEDBACK("1X"),
         .DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"),
         .DLL_FREQUENCY_MODE("LOW"),
         .DUTY_CYCLE_CORRECTION("TRUE"),
         .PHASE_SHIFT(0),
         .STARTUP_WAIT("FALSE")
) DCM_SP_inst (
        .CLKFX(pclk0),      // 0 degree DCM CLK output
        .CLKFB(pclk),      // DCM clock feedback
        .PSEN(1'b0),       // no variable phase shift
        .CLKIN(dcm_clk100),       // Clock input (from IBUFG, BUFG or DCM)
        .RST(1'b0)
);

reg [10:0] w = 1;

always @(posedge clk)
   if( vtrigger )
       w <= w + 1;

parameter
	RED   = 16'b11111_000000_00000,
	GREEN = 16'b00000_111111_00000,
	BLUE  = 16'b00000_000000_11111;

/*
 * VGA generator
 */
vga vga( 
	.clk(clk),
	.pclk(pclk),
	.hsync(hsync),
	.vsync(vsync),
	.fifo_data(fifo_data),
	.fifo_write(fifo_write),
	.fifo_full(fifo_full),
	.rgb(rgb) ,
	.vtrigger(vtrigger)
   	);

wire [9:0] vector_nr;
wire read_vector;
reg [9:0] x0;
reg [9:0] y0;
reg [9:0] x1;
reg [9:0] y1;
reg last_vector;
reg [15:0] col;

always @(posedge clk)
	if( read_vector ) 
	    if( vector_nr == 32 )  begin
		x0 <= 17; 
		y0 <= 17;
		x1 <= 31;
		y1 <= 31;
		last_vector <= 1;
		col <= RED;
	    end else begin
		x0 <= 16 + (vector_nr[0] ? {vector_nr[4:1], 4'h0} : 0);
		y0 <= 16 + (vector_nr[0] ? 0 : {vector_nr[5:1], 4'h0});
		x1 <= 16 + (vector_nr[0] ? {vector_nr[4:1], 4'h0} : 240);
		y1 <= 16 + (vector_nr[0] ? 240 : {vector_nr[5:1], 4'h0});
		last_vector <= 0; 
		col <= GREEN;
	    end

line line( 
    	.clk(clk),
	.vector(vector_nr),
	.read_vector(read_vector),
	.x0(x0),
	.y0(y0),
	.x1(x1),
	.y1(y1),
	.col(col),
	.last_vector(last_vector),
	.trigger(vtrigger),
	.fifo_full(fifo_full),
	.fifo_write(fifo_write),
	.fifo_data(fifo_data) );

endmodule

