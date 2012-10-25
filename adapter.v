/* 
	MicroBlaze MCS to DDR3 glue
	(C) Copyright 2012 Silicon On Inspiration
	www.sioi.com.au
	86 Longueville Road
	Lane Cove 2066
	New South Wales
	AUSTRALIA

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

`timescale 1ns / 1ps

module adapter
(
	input 				ckmb,
	input 				ckdr,
	input 				reset,

	output				srd,
	output				swr,
	output	[33:5]		sa,
	output	[255:0]		swdat,
	output	[31:0]		smsk,
	input	[255:0]		srdat,
	input				srdy,

	output 				IO_Ready,
	input				IO_Addr_Strobe,
	input				IO_Read_Strobe,
	input				IO_Write_Strobe,
	output 	[31 : 0]	IO_Read_Data,
	input	[31 : 0] 	IO_Address,
	input	[3 : 0] 	IO_Byte_Enable,
	input	[31 : 0] 	IO_Write_Data,
	input	[3 : 0] 	page,
	input	[2:0]		dbg_out
);

reg 		[31 : 0]	rdat;
reg 		[255 : 0]	wdat;
reg 		[31 : 0]	msk;
reg 		[33 : 2]	addr;
reg						rdy1;
reg						rdy2;
reg						read;
reg						write;

wire		[31:0]		iowd;
wire		[3:0]		mask;

parameter				BADBAD = 256'hBAD0BAD0BAD0BAD0BAD0BAD0BAD0BAD0BAD0BAD0BAD0BAD0BAD0BAD0BAD0BAD0;

always @ (posedge ckmb) begin

	if (IO_Addr_Strobe && IO_Write_Strobe) begin
		case (IO_Address[4:2])
			0:	wdat[31:0] <= iowd;
			1:	wdat[63:32] <= iowd;
			2:	wdat[95:64] <= iowd;
			3:	wdat[127:96] <= iowd;
			4:	wdat[159:128] <= iowd;
			5:	wdat[191:160] <= iowd;
			6:	wdat[223:192] <= iowd;
			7:	wdat[255:224] <= iowd;

// BADBAD markers for bebugging byte masking
// NB: This approach breaks the per-pin IODELAY2 software adjustment on the DQ lines
//			0:	wdat <= {BADBAD[255:32], iowd};
//			1:	wdat <= {BADBAD[255:64], iowd, BADBAD[31:0]};
//			2:	wdat <= {BADBAD[255:96], iowd, BADBAD[63:0]};
//			3:	wdat <= {BADBAD[255:128], iowd, BADBAD[95:0]};
//			4:	wdat <= {BADBAD[255:160], iowd, BADBAD[127:0]};
//			5:	wdat <= {BADBAD[255:192], iowd, BADBAD[159:0]};
//			6:	wdat <= {BADBAD[255:224], iowd, BADBAD[191:0]};
//			7:	wdat <= {iowd, BADBAD[223:0]};
		endcase
		
		case (IO_Address[4:2])
		
			0:	msk <= {28'hFFFFFFF, mask};
			1:	msk <= {24'hFFFFFF, mask, 4'hF};
			2:	msk <= {20'hFFFFF, mask, 8'hFF};
			3:	msk <= {16'hFFFF, mask, 12'hFFF};
			4:	msk <= {12'hFFF, mask, 16'hFFFF};
			5:	msk <= {8'hFF, mask, 20'hFFFFF};
			6:	msk <= {4'hF, mask, 24'hFFFFFF};
			7:	msk <= {mask, 28'hFFFFFFF};
/*
ZZ - write full 256 bits during testing !
			0:	msk <= {28'h0000000, mask};
			1:	msk <= {24'h000000, mask, 4'h0};
			2:	msk <= {20'h00000, mask, 8'h00};
			3:	msk <= {16'h0000, mask, 12'h000};
			4:	msk <= {12'h000, mask, 16'h0000};
			5:	msk <= {8'h00, mask, 20'h00000};
			6:	msk <= {4'h0, mask, 24'h000000};
			7:	msk <= {mask, 28'h0000000};
*/
		endcase
	end
	
	if (IO_Addr_Strobe)
		addr <= {page[3:0], IO_Address[29:2]};	
end
		
always @ (posedge ckmb or posedge reset) begin
	if (reset) begin
		read		<= 1'b0;
		write		<= 1'b0;		
		rdy2		<= 1'b0;		
	end	else begin
		if (IO_Addr_Strobe && IO_Read_Strobe)
			read	<= 1'b1;
		else if (IO_Addr_Strobe && IO_Write_Strobe)
			write	<= 1'b1;
		if (rdy1) begin
			read	<= 1'b0;
			write	<= 1'b0;
			rdy2	<= 1'b1;
		end			
		if (rdy2)
			rdy2	<= 1'b0;
	end
end

always @ (posedge ckdr or posedge reset) begin
	if (reset) begin
		rdy1		<= 1'b0;
	end	else begin
		if (srdy)
			rdy1	<= 1'b1;
		if (rdy2)
			rdy1	<= 1'b0;		
		if (srdy) case (addr[4:2])
			0:	rdat <= srdat[31:0];
			1:	rdat <= srdat[63:32];
			2:	rdat <= srdat[95:64];
			3:	rdat <= srdat[127:96];
			4:	rdat <= srdat[159:128];
			5:	rdat <= srdat[191:160];
			6:	rdat <= srdat[223:192];
			7:	rdat <= srdat[255:224];
		endcase
	end
end

assign iowd 			= IO_Write_Data;
assign mask 			= ~IO_Byte_Enable;

assign IO_Read_Data		= rdat;
assign IO_Ready			= rdy2;
assign srd				= read;
assign swr				= write;
assign swdat			= wdat;
assign smsk				= msk;
assign sa				= addr[33:5];

endmodule

