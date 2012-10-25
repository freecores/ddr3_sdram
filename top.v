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

module top
(
	input       	mck62M5,
    output	[1:0]	mled,
    input	[1:0]	mbtn,
    output			txd,
    input			rxd,

	inout	[63:0]	ddq,
	inout	[7:0]	dqsp,
	inout	[7:0]	dqsn,
	output	[7:0]	ddm,
	output	[15:0]	da,
	output	[2:0]	dba,
	output	[2:0]	dcmd,
	output	[1:0]	dce,
	output	[1:0]	dcs,
	output	[1:0]	dckp,
	output	[1:0]	dckn,
	output	[1:0]	dodt	
);
    
    wire 			Reset;
    wire 			IO_Ready;
    wire 			IO_Addr_Strobe;
    wire 			IO_Read_Strobe;
    wire 			IO_Write_Strobe;
    wire [31 : 0] 	IO_Read_Data;
    wire [1 : 0] 	GPI1;
    wire [31 : 0] 	IO_Address;
    wire [3 : 0] 	IO_Byte_Enable;
    wire [31 : 0] 	IO_Write_Data;
    wire [1 : 0] 	GPO1;
    wire [3 : 0] 	page;

    wire 			srd;
    wire 			swr;
    wire [33:5]		sa;
    wire [255:0]	swdat;
    wire [31:0]		smsk;
    wire [255:0]	srdat;
    wire 			srdy;
    
    wire 			ck150;
    wire 			ck75;

	wire [0 : 31]	Trace_Instruction;
	wire [0 : 31]	Trace_PC;
	wire [0 : 4]	Trace_Reg_Addr;
	wire [0 : 14]	Trace_MSR_Reg;
	wire [0 : 31]	Trace_New_Reg_Value;
	wire [0 : 31]	Trace_Data_Address;
	wire [0 : 31]	Trace_Data_Write_Value;
	wire [0 : 3]	Trace_Data_Byte_Enable;

	wire [2:0]		dbg_out;
	wire [7:0]		dbg_in;

    drac_ddr3 drac
    (
    	.ckin				(mck62M5),
    	.ckout				(ck150),
    	.ckouthalf			(ck75),
	   	.reset				(Reset),
    				
		.ddq				(ddq),
		.dqsp				(dqsp),
		.dqsn				(dqsn),
		.ddm				(ddm),
		.da					(da),
		.dba				(dba),
		.dcmd				(dcmd),
		.dce				(dce),
		.dcs				(dcs),
		.dckp				(dckp),
		.dckn				(dckn),
		.dodt				(dodt),
						
		.srd				(srd),	
		.swr				(swr),	
		.sa					(sa),		
		.swdat				(swdat),	
		.smsk				(smsk),	
		.srdat				(srdat),	
		.srdy				(srdy),
		
		.dbg_out			(dbg_out),
		.dbg_in				(dbg_in)
    );

	adapter glue
	(
		.ckmb				(ck75),
		.ckdr				(ck150),
		.reset				(Reset),
		
		.srd				(srd),
		.swr				(swr),
		.sa					(sa),
		.swdat				(swdat),
		.smsk				(smsk),
		.srdat				(srdat),
		.srdy				(srdy),
		
		.IO_Ready			(IO_Ready),
		.IO_Addr_Strobe		(IO_Addr_Strobe),
		.IO_Read_Strobe		(IO_Read_Strobe),
		.IO_Write_Strobe	(IO_Write_Strobe),
		.IO_Read_Data		(IO_Read_Data),
		.IO_Address			(IO_Address),
		.IO_Byte_Enable		(IO_Byte_Enable),
		.IO_Write_Data		(IO_Write_Data),
		.page				(page),
		.dbg_out			(dbg_out)		
	);
        
    microblaze_mcs_v1_1 mcs_0
    (
		.Clk					(ck75), 
		.Reset					(Reset), 
		.IO_Ready				(IO_Ready), 
		.UART_Rx				(rxd), 
		.IO_Addr_Strobe			(IO_Addr_Strobe), 
		.IO_Read_Strobe			(IO_Read_Strobe), 
		.IO_Write_Strobe		(IO_Write_Strobe), 
		.UART_Tx				(txdraw), 
		.IO_Read_Data			(IO_Read_Data), 
		.GPI1					(mbtn), 
		.GPI2					(dbg_in), 
		.IO_Address				(IO_Address), 
		.IO_Byte_Enable			(IO_Byte_Enable), 
		.IO_Write_Data			(IO_Write_Data),
		.GPO1					(mled),
		.GPO2					(page),
		.GPO3					(dbg_out),
		.Trace_Instruction		(Trace_Instruction),		// Opcode
		.Trace_Valid_Instr		(Trace_Valid_Instr), 		// valid opcode y/n
		.Trace_PC				(Trace_PC), 				// PC
		.Trace_Reg_Write		(Trace_Reg_Write), 			// output Trace_Reg_Write
		.Trace_Reg_Addr			(Trace_Reg_Addr), 			// output [0 : 4] Trace_Reg_Addr
		.Trace_MSR_Reg			(Trace_MSR_Reg), 			// output [0 : 14] Trace_MSR_Reg
		.Trace_New_Reg_Value	(Trace_New_Reg_Value), 		// output [0 : 31] Trace_New_Reg_Value
		.Trace_Jump_Taken		(Trace_Jump_Taken), 		// Jump Taken
		.Trace_Delay_Slot		(Trace_Delay_Slot), 		// Delay Slot
		.Trace_Data_Address		(Trace_Data_Address), 		// Data Address
		.Trace_Data_Access		(Trace_Data_Access), 		// Data_Access y/n
		.Trace_Data_Read		(Trace_Data_Read), 			// Data Read y/n
		.Trace_Data_Write		(Trace_Data_Write), 		// Data Write y/n
		.Trace_Data_Write_Value	(Trace_Data_Write_Value),	// Data Write Value
		.Trace_Data_Byte_Enable	(Trace_Data_Byte_Enable),	// Data Byte Enables
		.Trace_MB_Halted		(Trace_MB_Halted) 			// Halted
	);
	
assign txd = ~txdraw;
	
endmodule

