/*
 * tb.v -- testbench
 *
 * (c) Arlet Ottens <arlet@c-scape.nl>
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

integer image = 0;
integer scan = 0;

reg [63:0] name = "0000.ppm";

initial begin
        image = $fopen( name );
	$fwrite( image, "P3 640 480 1\n" );
end

always @(negedge vsync) begin
     $fclose( image );
     name[39:32] = "0" + (scan % 10);
     name[47:40] = "0" + (scan / 10) % 10; 
     name[55:48] = "0" + (scan / 100) % 10; 
     name[63:56] = "0" + (scan / 1000); 
     image = $fopen( name );
     $fwrite( image, "P3 640 480 1\n" );
     $display( "opened %s", name );
     scan = scan + 1;
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
