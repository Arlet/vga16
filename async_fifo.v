/*
 * async_fifo: asynchronous FIFO, 18 bits wide
 *
 * (C) Arlet Ottens <arlet@c-scape.nl>
 */
module async_fifo( 
	input clka,
	input [17:0] in,
	input wr,
	output full,

	input clkb,
	output [17:0] out,
	input rd,
	output empty );

reg [10:0] head_a = 0;
reg [10:0] head_a_b = 0;
reg [10:0] head_b = 0;

reg [10:0] tail_b = 0;
reg [10:0] tail_b_a = 0;
reg [10:0] tail_a = 0;

wire [10:0] size_a = (head_a - tail_a);
assign full  = (size_a >= 11'h200);
assign empty = (tail_b == head_b); 

RAMB16_S18_S18 mem( 
	.CLKA(clka),
	.ADDRA(head_a[9:0]),
	.DIA(in[15:0]),
	.DIPA(in[17:16]),
	.WEA(1'b1),
	.ENA(wr & ~full),
	.SSRA(1'b0),

	.CLKB(clkb),
	.ADDRB(tail_b[9:0]),
	.DOB(out[15:0]),
	.DOPB(out[17:16]),
	.ENB(rd & ~empty),
	.WEB(1'b0),
	.SSRB(1'b0)
	);

handshake handshake( 
	.clka(clka),
	.clkb(clkb),
	.sync_a(sync_a),
	.sync_b(sync_b) );

/*
 * clka domain 
 */
always @(posedge clka)
    if( wr & ~full )
        head_a <= head_a + 1;

always @(posedge clka)
    if( sync_a ) begin
        head_a_b <= head_a;
        tail_a <= tail_b_a;
    end

/*
 * clkb domain 
 */

always @(posedge clkb)
    if( sync_b ) begin
        head_b <= head_a_b;
        tail_b_a <= tail_b;
    end

always @(posedge clkb)
    if( rd & ~empty )
        tail_b <= tail_b + 1;

endmodule
