/*
 * tb.v -- testbench
 */

`timescale 1ns / 1ps

module tb;

reg clk100;
wire reset;
wire pclk;

assign reset = glbl.GSR;

initial begin
	$recordfile( "results", "wrapsize=2GB" );
	$recordvars( "depth=12", tb );
	clk100 <= 1;
	while( 1 ) 
            #5 clk100 = ~clk100;
	$finish;
end

glbl glbl();

wire hsync; 
wire vsync;
wire [4:0] red;
wire [5:0] green;
wire [4:0] blue;

integer image;

initial begin
        image = $fopen( "image.ppm" );
	$fwrite( image, "P3 640 480 1\n" );
end


always @(posedge pclk)
   if( main.vga.hactive & main.vga.vactive )
       $fwrite( image, "%d %d %d\n", red, green, blue );

main main( .clk100(clk100),
	   .pclk_out(pclk),
	   .hsync(hsync),
	   .vsync(vsync),
	   .red(red),
	   .green(green),
	   .blue(blue) );

endmodule	// tb
