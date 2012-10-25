/* 
	DDR3 DRAM controller
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

module drac_ddr3
(
	input       	ckin,
	output       	ckout,
	output       	ckouthalf,
	output			reset,

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
	output	[1:0]	dodt,
	
	input			srd,
	input			swr,
	input	[33:5]	sa,
	input	[255:0]	swdat,
	input	[31:0]	smsk,
	output	[255:0]	srdat,
	output			srdy,
	
	input	[2:0]	dbg_out,
	output	[7:0]	dbg_in
);

reg					READ;
reg					READ2;

reg					ack;

reg			[15:0]	rDDR_Addr;
reg			[2:0]	rDDR_BankAddr;
reg			[1:0]	rDDR_CS_n;
reg			[2:0]	rDDR_Cmd;
reg			[1:0]	rDDR_CKE;
reg			[1:0]	rDDR_ODT;

reg			[2:0]	STATE;
reg			[2:0]	RTN;
reg			[5:0]	DLY;

reg			[10:0]	RFCNTR;
reg					REFRESH;

reg					RPULSE0;
reg					RPULSE1;
reg					RPULSE2;
reg					RPULSE3;
reg					RPULSE4;
reg					RPULSE5;
reg					RPULSE6;
reg					RPULSE7;
reg					WPULSE0;
reg			[255:0]	Q;

wire		[7:0]	DM;
wire		[7:0]	DM_t;
wire		[7:0]	wDDR_DM;

wire		[7:0]	wDDR_DQS;
wire		[63:0]	DQ_i;
wire		[63:0]	DQ_i_dly;
wire		[255:0]	wQ;
wire		[63:0]	DQ_o;
wire		[63:0]	DQ_t;
wire		[63:0]	wDDR_DQ;

reg			[255:0]	rWdat;
reg			[31:0]	rSmsk;

reg			[13:0]	rLock = 0;
reg					rClrPll = 1;
reg			[13:0]	rStart = 0;
reg					rStarted = 0;

reg			[63:0]	rChgDelay;
reg			[63:0]	rIncDelay;
reg			[63:0]	rCalDelay;
reg			[63:0]	rCalDelay2;
reg			[63:0]	rRstDelay;

// Set up clocks for DDR3.  Use circuitry based on UG382 Ch 1 pp33,34
// Generate the following clocks:
//
// ck600			600MHz clock for DQ IOSERDES2 high speed clock
// ck600_180		600MHz clock for DQS OSERDES2 high speed clock
//					DQS clocking lags DQ clocking by half of one bit time
// ck150			1/4 speed clock for IOSERDES2 parallel side and control logic
// ck75				Clock for MicroBlaze CPU
//
// Create two copies of the 600MHz clocks, providing separate copies for 
// bank 1 and bank 3.  This is necessary as each BUFPLL reaches only a
// single bank.  The other clocks are global (BUFG).
wire				ck600raw;
wire				ck600_180raw;
wire				ck150;
wire				ck150raw;
wire				ck75;
wire				ck75raw;
wire		[1:0]	ck600;
wire		[1:0]	ck600_180;
wire		[1:0]	strobe;
wire		[1:0]	strobe180;

// DDR3 DIMM byte lane levelling is achieved with these IODELAY2 settings:
parameter			LVL_WSLOPE = 3;
parameter			LVL_WPHASE = 6;

	BUFG bufg_main
	(
		.O   						(ckinb),
		.I   						(ckin)
	);

	PLL_BASE
	#(
		.BANDWIDTH              	("OPTIMIZED"),
		.CLK_FEEDBACK           	("CLKFBOUT"),
		.COMPENSATION           	("INTERNAL"),
		.DIVCLK_DIVIDE          	(3),
		.CLKFBOUT_MULT          	(29),
		.CLKFBOUT_PHASE         	(0.000),
		.CLKOUT0_DIVIDE         	(1),
		.CLKOUT0_PHASE          	(0.000),
		.CLKOUT0_DUTY_CYCLE     	(0.500),
		.CLKOUT1_DIVIDE         	(1),
		.CLKOUT1_PHASE          	(180.000),
		.CLKOUT1_DUTY_CYCLE     	(0.500),
		.CLKOUT2_DIVIDE         	(4),
		.CLKOUT2_PHASE          	(0.000),
		.CLKOUT2_DUTY_CYCLE     	(0.500),
		.CLKOUT3_DIVIDE         	(8),
		.CLKOUT3_PHASE          	(0.0),
		.CLKOUT3_DUTY_CYCLE     	(0.500),
		.CLKOUT4_DIVIDE         	(8),
		.CLKOUT4_PHASE          	(0.0),
		.CLKOUT4_DUTY_CYCLE     	(0.500),
		.CLKOUT5_DIVIDE         	(8),
		.CLKOUT5_PHASE          	(0.000),
		.CLKOUT5_DUTY_CYCLE     	(0.500),
		.CLKIN_PERIOD           	(16.000)
	)
	pll_base_main
	(
		.CLKFBOUT              		(pllfb0),
		.CLKOUT0               		(ck600raw),
		.CLKOUT1               		(ck600_180raw),
		.CLKOUT2               		(ck150raw),
		.CLKOUT3               		(ck75raw),
		.CLKOUT4               		(),
		.CLKOUT5               		(),
		.LOCKED                		(locked),
		.RST                   		(rClrPll),
		.CLKFBIN               		(pllfb0),
		.CLKIN                 		(ckinb)
	);

	BUFG bufg_150
	(
		.O   						(ck150),
		.I   						(ck150raw)
	);

	BUFG bufg_75
	(
		.O   						(ck75),
		.I   						(ck75raw)
	);

genvar i;
generate
	for (i = 0; i <= 1; i = i + 1) begin: BUFPLLS
		BUFPLL
		#(
			.DIVIDE        			(4),
			.ENABLE_SYNC			("TRUE")
		)
		bufpll_600
		(
			.IOCLK        			(ck600[i]),
			.LOCK         			(dbg_in[i]),
			.SERDESSTROBE 			(strobe[i]),
			.GCLK         			(ck150),
			.LOCKED       			(locked),
			.PLLIN        			(ck600raw)
		);
		
		BUFPLL
		#(
			.DIVIDE        			(4),
			.ENABLE_SYNC			("TRUE")
		)
		bufpll_600_18
		(
			.IOCLK        			(ck600_180[i]),
			.LOCK         			(dbg_in[2 + i]),
			.SERDESSTROBE 			(strobe180[i]),
			.GCLK         			(ck150),
			.LOCKED       			(locked),
			.PLLIN        			(ck600_180raw)
		);
    end

// CLOCKS, two
wire		[1:0]	ckp;
wire		[1:0]	ckn;
	for (i = 0; i <= 1; i = i + 1) begin: DDRO_CLKS
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_dckp
		(
			.D1         			(1'b0),
			.D2         			(1'b1),
			.D3         			(1'b0),
			.D4         			(1'b1),
			.T1         			(1'b0),
			.T2         			(1'b0),
			.T3         			(1'b0),
			.T4         			(1'b0),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600_180[1]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(ckp[i]),
			.TQ         			(),
			.IOCE       			(strobe180[1]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);
		
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_dckn
		(
			.D1         			(1'b1),
			.D2         			(1'b0),
			.D3         			(1'b1),
			.D4         			(1'b0),
			.T1         			(1'b0),
			.T2         			(1'b0),
			.T3         			(1'b0),
			.T4         			(1'b0),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600_180[1]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(ckn[i]),
			.TQ         			(),
			.IOCE       			(strobe180[1]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);

		OBUF obuft_ckp
		(
		   .O(dckp[i]),  
		   .I(ckp[i])
		);

		OBUF obuf_ckn
		(
		   .O(dckn[i]),  
		   .I(ckn[i])  
		);
    end

// Address, Bank address
// NB ISIM can't grok parameter arrays, hence the following sim/synth bifurcation
`ifdef XILINX_ISIM
`else
	parameter integer bank_a[15:0] = {0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1};
	parameter integer bank_ba[2:0] = {0, 1, 1};
`endif

	wire [15:0] wa;
	for (i = 0; i <= 15; i = i + 1) begin: DDRO_A
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_a
		(
			.D1         			(rDDR_Addr[i]),
			.D2         			(rDDR_Addr[i]),
			.D3         			(rDDR_Addr[i]),
			.D4         			(rDDR_Addr[i]),
			.T1         			(1'b0),
			.T2         			(1'b0),
			.T3         			(1'b0),
			.T4         			(1'b0),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
`ifdef XILINX_ISIM
			.CLK0       			(ck600_180[0]),
`else
			.CLK0       			(ck600_180[bank_a[i]]),
`endif
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(wa[i]),
			.TQ         			(),
`ifdef XILINX_ISIM
			.IOCE       			(strobe180[0]),
`else
			.IOCE       			(strobe180[bank_a[i]]),
`endif
			.TCE        			(1'b1),
			.RST        			(reset)
		);
		
		OBUF obuf_a
		(
		   .O(da[i]),  
		   .I(wa[i])  
		);
    end
		
wire		[2:0]	wba;
	for (i = 0; i <= 2; i = i + 1) begin: DDRO_BA
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_ba
		(
			.D1         			(rDDR_BankAddr[i]),
			.D2         			(rDDR_BankAddr[i]),
			.D3         			(rDDR_BankAddr[i]),
			.D4         			(rDDR_BankAddr[i]),
			.T1         			(1'b0),
			.T2         			(1'b0),
			.T3         			(1'b0),
			.T4         			(1'b0),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
`ifdef XILINX_ISIM
			.CLK0       			(ck600_180[0]),
`else
			.CLK0       			(ck600_180[bank_ba[i]]),
`endif
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(wba[i]),
			.TQ         			(),
`ifdef XILINX_ISIM
			.IOCE       			(strobe180[0]),
`else
			.IOCE       			(strobe180[bank_ba[i]]),
`endif
			.TCE        			(1'b1),
			.RST        			(reset)
		);
		
		OBUF obuf_ba
		(
		   .O(dba[i]),  
		   .I(wba[i])  
		);
    end

// command, ChipSelect
wire		[2:0]	wkmd;
	for (i = 0; i <= 2; i = i + 1) begin: DDRO_KMD
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_kmd
		(
			.D1         			(rDDR_Cmd[i]),	// Command for 1 cycle
			.D2         			(rDDR_Cmd[i]),
			.D3         			(1'b1),			// NOP thereafter
			.D4         			(1'b1),
			.T1         			(1'b0),
			.T2         			(1'b0),
			.T3         			(1'b0),
			.T4         			(1'b0),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600_180[1]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(wkmd[i]),
			.TQ         			(),
			.IOCE       			(strobe180[1]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);
		
		OBUF obuf_kmd
		(
		   .O(dcmd[i]),  
		   .I(wkmd[i])  
		);
    end
    
wire		[1:0]	wcs;
	for (i = 0; i <= 1; i = i + 1) begin: DDRO_CS
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_cs
		(
			.D1         			(rDDR_CS_n[i]),	
			.D2         			(rDDR_CS_n[i]),
			.D3         			(rDDR_CS_n[i]),		
			.D4         			(rDDR_CS_n[i]),
			.T1         			(1'b0),
			.T2         			(1'b0),
			.T3         			(1'b0),
			.T4         			(1'b0),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600_180[1]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(wcs[i]),
			.TQ         			(),
			.IOCE       			(strobe180[1]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);
		
		OBUF obuf_cs
		(
		   .O(dcs[i]),  
		   .I(wcs[i])  
		);
    end
    
// CKE, ODT
wire		[1:0]	wcke;
	for (i = 0; i <= 1; i = i + 1) begin: DDRO_CKE
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_cke
		(
			.D1         			(rDDR_CKE[i]),	
			.D2         			(rDDR_CKE[i]),
			.D3         			(rDDR_CKE[i]),		
			.D4         			(rDDR_CKE[i]),
			.T1         			(1'b0),
			.T2         			(1'b0),
			.T3         			(1'b0),
			.T4         			(1'b0),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600_180[0]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(wcke[i]),
			.TQ         			(),
			.IOCE       			(strobe180[0]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);
		
		OBUF obuf_cke
		(
		   .O(dce[i]),  
		   .I(wcke[i])  
		);
    end

wire		[1:0]	wodt;
	for (i = 0; i <= 1; i = i + 1) begin: DDRO_ODT
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_odt
		(
			.D1         			(rDDR_ODT[i]),	
			.D2         			(rDDR_ODT[i]),
			.D3         			(rDDR_ODT[i]),		
			.D4         			(rDDR_ODT[i]),
			.T1         			(1'b0),
			.T2         			(1'b0),
			.T3         			(1'b0),
			.T4         			(1'b0),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600_180[1]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(wodt[i]),
			.TQ         			(),
			.IOCE       			(strobe180[1]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);
		
		OBUF obuf_odt
		(
		   .O(dodt[i]),  
		   .I(wodt[i])  
		);
    end

// DQ STROBES, 8 differential pairs
wire		[7:0]	dqso;
wire		[7:0]	dqso_d;
wire		[7:0]	dqst;
wire		[7:0]	dqst_d;
wire		[7:0]	dqson;
wire		[7:0]	dqson_d;
wire		[7:0]	dqstn;
wire		[7:0]	dqstn_d;
wire		[7:0]	dummy;
wire		[7:0]	dummyp;
wire		[7:0]	dummyn;
	for (i = 0; i <= 7; i = i + 1) begin: DDRIO_DQS
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_dqsp
		(
			.D1         			(1'b0),
			.D2         			(1'b1),
			.D3         			(1'b0),
			.D4         			(1'b1),
			.T1         			(READ),
			.T2         			(READ),
			.T3         			(READ),
			.T4         			(READ),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600_180[i >> 2]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(dqso[i]),
			.TQ         			(dqst[i]),
			.IOCE       			(strobe180[i >> 2]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);

		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_dqsn
		(
			.D1         			(1'b1),
			.D2         			(1'b0),
			.D3         			(1'b1),
			.D4         			(1'b0),
			.T1         			(READ),
			.T2         			(READ),
			.T3         			(READ),
			.T4         			(READ),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600_180[i >> 2]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(dqson[i]),
			.TQ         			(dqstn[i]),
			.IOCE       			(strobe180[i >> 2]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);

		IODELAY2
		#(
			.DATA_RATE              ("SDR"),
			.ODELAY_VALUE           (LVL_WPHASE + i * LVL_WSLOPE),
			.IDELAY_VALUE           (LVL_WPHASE + i * LVL_WSLOPE),
	       	.IDELAY_TYPE			("FIXED"),
			.DELAY_SRC              ("IO")
		)
		iodelay2_dqsp
		(
			.ODATAIN                (dqso[i]),
			.DOUT                   (dqso_d[i]),
		
			.T                      (dqst[i]),
			.TOUT                   (dqst_d[i]),

			.IDATAIN                (dummyp[i])									
		);
	
		IODELAY2
		#(
			.DATA_RATE              ("SDR"),
			.ODELAY_VALUE           (LVL_WPHASE + i * LVL_WSLOPE),
			.IDELAY_VALUE           (LVL_WPHASE + i * LVL_WSLOPE),
	       	.IDELAY_TYPE			("FIXED"),
			.DELAY_SRC              ("IO")
		)
		iodelay2_dqsn
		(
			.ODATAIN                (dqson[i]),
			.DOUT                   (dqson_d[i]),
		
			.T                      (dqstn[i]),
			.TOUT                   (dqstn_d[i]),

			.IDATAIN                (dummyn[i])						
		);
	
		IOBUF iobuf_dqsp
		(
		   .O(dummyp[i]),  
		   .IO(dqsp[i]),
		   .I(dqso_d[i]),  
		   .T(dqst_d[i])
		);
		
		IOBUF iobuf_dqsn
		(
		   .O(dummyn[i]),  
		   .IO(dqsn[i]),
		   .I(dqson_d[i]),  
		   .T(dqstn_d[i])
		);
	
	end

// DATA MASKS, 8
wire		[7:0]	dmo;
wire		[7:0]	dmo_d;
wire		[7:0]	dmt;
wire		[7:0]	dmt_d;   	
	for (i = 0; i <= 7; i = i + 1) begin: DDRO_DM
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_dm
		(
			.D1         			(rSmsk[i]),
			.D2         			(rSmsk[i + 8]),
			.D3         			(rSmsk[i + 16]),
			.D4         			(rSmsk[i + 24]),
			.T1         			(READ),
			.T2         			(READ),
			.T3         			(READ),
			.T4         			(READ),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600[i >> 2]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(dmo[i]),
			.TQ         			(dmt[i]),
			.IOCE       			(strobe[i >> 2]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);

		IODELAY2
		#(
			.DATA_RATE              ("SDR"),
			.ODELAY_VALUE           (LVL_WPHASE + i * LVL_WSLOPE),
			.IDELAY_VALUE           (LVL_WPHASE + i * LVL_WSLOPE),
	       	.IDELAY_TYPE			("FIXED"),
			.DELAY_SRC              ("IO")
		)
		iodelay2_dm
		(
			.ODATAIN                (dmo[i]),
			.DOUT                   (dmo_d[i]),
		
			.T                      (dmt[i]),
			.TOUT                   (dmt_d[i]),
			
			.IDATAIN                (dummy[i])			
		);
	
		IOBUF iobuf_dm
		(
			.O(dummy[i]),
		   	.IO(ddm[i]),
		   	.I(dmo_d[i]),  
		   	.T(dmt_d[i])
		);
    	end
    	
// DQ LINES, 64
wire		[63:0]	dqo;
wire		[63:0]	dqo_d;
wire		[63:0]	dqt;
wire		[63:0]	dqt_d;   	
wire		[63:0]	dqi;
wire		[63:0]	dqi_d;   	
	for (i = 0; i <= 63; i = i + 1) begin: DDRIO_DQ
		OSERDES2
		#(
			.DATA_RATE_OQ			("SDR"),
			.DATA_RATE_OT   		("SDR"),
			.TRAIN_PATTERN  		(0),
			.DATA_WIDTH     		(4),
			.SERDES_MODE    		("NONE"),
			.OUTPUT_MODE    		("SINGLE_ENDED")
		)
		oserdes2_dq
		(
			.D1         			(rWdat[i]),
			.D2         			(rWdat[i + 64]),
			.D3         			(rWdat[i + 128]),
			.D4         			(rWdat[i + 192]),
			.T1         			(READ),
			.T2         			(READ),
			.T3         			(READ),
			.T4         			(READ),
			.SHIFTIN1   			(1'b1),
			.SHIFTIN2   			(1'b1),
			.SHIFTIN3   			(1'b1),
			.SHIFTIN4   			(1'b1),
			.SHIFTOUT1  			(),
			.SHIFTOUT2  			(),
			.SHIFTOUT3  			(),
			.SHIFTOUT4  			(),
			.TRAIN      			(1'b0),
			.OCE        			(1'b1),
			.CLK0       			(ck600[i >> 5]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.OQ         			(dqo[i]),
			.TQ         			(dqt[i]),
			.IOCE       			(strobe[i >> 5]),
			.TCE        			(1'b1),
			.RST        			(reset)
		);

		IODELAY2
		#(
			.DATA_RATE              ("SDR"),
			.IDELAY_VALUE           (0),
			.ODELAY_VALUE           (LVL_WPHASE + ((i * LVL_WSLOPE) >> 3)),
	       	.IDELAY_TYPE			("VARIABLE_FROM_ZERO"),
			.DELAY_SRC              ("IO")
		)
		iodelay2_dq
		(
			.ODATAIN                (dqo[i]),
			.DOUT                   (dqo_d[i]),
		
			.T                      (dqt[i]),
			.TOUT                   (dqt_d[i]),

			.IDATAIN                (dqi[i]),
			.DATAOUT                (dqi_d[i]),
			
			.CE						(rChgDelay[i]),
			.INC					(rIncDelay[i]),
			.CLK					(ck150),
			.CAL					(rCalDelay2[i]),
			.RST					(rRstDelay[i]),
			.IOCLK0					(ck600[i >> 5])
		);
		
		IOBUF iobuf_dq
		(
		   	.O(dqi[i]),  
		   	.IO(ddq[i]),
		   	.I(dqo_d[i]),  
		   	.T(dqt_d[i])
		);
		
		ISERDES2
		#(
			.BITSLIP_ENABLE 		("FALSE"),
			.DATA_RATE      		("SDR"),
			.DATA_WIDTH     		(4),
			.INTERFACE_TYPE 		("RETIMED"),
			.SERDES_MODE    		("NONE")
		)
		iserdes2_dq
		(
			.Q1         			(wQ[i]),
			.Q2         			(wQ[i + 64]),
			.Q3         			(wQ[i + 128]),
			.Q4         			(wQ[i + 192]),
			.SHIFTOUT   			(),
			.INCDEC     			(),
			.VALID      			(),
			.BITSLIP    			(),
			.CE0        			(READ),
			.CLK0       			(ck600[i >> 5]),
			.CLK1       			(1'b0),
			.CLKDIV     			(ck150),
			.D          			(dqi_d[i]),
			.IOCE       			(strobe[i >> 5]),
			.RST        			(reset),
			.SHIFTIN    			(),
			.FABRICOUT  			(),
			.CFB0       			(),
			.CFB1       			(),
			.DFB        			()
		);
	end
endgenerate

// DDR commands
parameter	K_LMR	= 3'h0;	// Load Mode Register (Mode Register Set)
parameter	K_RFSH	= 3'h1;	// Refresh (auto or self)
parameter	K_CLOSE	= 3'h2;	// aka PRECHARGE
parameter	K_OPEN	= 3'h3;	// aka ACTIVATE
parameter	K_WRITE	= 3'h4;
parameter	K_READ	= 3'h5;
parameter	K_ZQCAL	= 3'h6;	// ZQ calibration
parameter	K_NOP	= 3'h7;

// States
parameter	S_INIT	= 3'h3;
parameter	S_INIT2	= 3'h5;
parameter	S_IDLE	= 3'h0;
parameter	S_READ	= 3'h1;
parameter	S_WRITE	= 3'h2;
parameter	S_PAUSE	= 3'h4;

// Main DDR3 timings			spec	@150MHz	
// tRAS		RAS time			37.5 ns	6 clks	open to close
// tRC		RAS cycle			50.6 ns	8 clks	open to next open
// tRP		RAS precharge		13.1 ns	2 clks	close to open
// tRRD		RAS to RAS delay	4 clks  4 clks	
// tRCD		RAS to CAS delay	13.2 ns	2 clks	
// CL		CAS Latency			5 clks	5 clks	
// tWR		Write time			15 ns	3 clks	Write finished to close issued
// tWTR		Write to Read		4 clks	4 clks	Write finished to read issued
// tRFC		Refresh command 1Gb	110ns	17 clks	Refresh command time for 1Gb parts
// tRFC		Refresh command 2Gb	160ns	24 clks	Refresh command time for 2Gb parts
// tRFC		Refresh command 4Gb	260ns	39 clks	Refresh command time for 4Gb parts
// tREFI	Refresh interval	7.8 us	1170 clks
// tDQSS	DQS start			+-0.25 clks	Time from DDR_Clk to DQS
parameter	tRFC	= 39;
parameter	tRCD	= 3;
parameter	tRP		= 3;

// Provide the PLL with a good long start up reset
always @ (posedge ckinb) begin
 	if (rLock[13] == 1'b1) begin
		rClrPll <= 1'b0;
	end	else begin
		rClrPll <= 1'b1;
		rLock <= rLock + 14'b1;
	end
end

// Hold the rest of the system in reset until the PLL has been locked for
// a good long while
always @ (posedge ckinb) begin
 	if (rStart[13] == 1'b1) begin
		rStarted <= 1'b1;
	end	else begin
		rStarted <= 1'b0;
		if (locked) begin
			rStart <= rStart + 14'b1;
		end else begin
			rStart <= 0;
		end
	end
end

// Add pipeline delays as required to make it easy for PAR to meet timing
always @ (posedge ck150) begin
	Q <= wQ;
	rWdat <= swdat;
	rSmsk <= smsk;
	rCalDelay2 <= rCalDelay;
end

always @ (posedge reset or posedge ck150)
	if (reset) begin
		rDDR_CKE <= 2'b00;
		rDDR_CS_n <= 2'b11;
		rDDR_ODT <= 2'b00;
		rDDR_Cmd <= K_NOP;
		
		STATE <= S_INIT;
		DLY <= 0;
		RTN <= 0;
		RFCNTR <= 0;
		REFRESH <= 0;

		ack <= 0;
		
		RPULSE0 <= 0;
		WPULSE0 <= 0;
		rChgDelay <= 64'd0;
		rIncDelay <= 64'd0;
		rCalDelay <= 64'd0;
		rRstDelay <= 64'd0;
	end	else begin
	 	if (RFCNTR[10:7] == 4'b1001) begin	// 1153/150Mhz  ~7.7us
			RFCNTR <= 0;
			REFRESH <= 1;
		end	else
			RFCNTR <= RFCNTR + 11'b1;
	
		RPULSE1 <= RPULSE0;
		RPULSE2 <= RPULSE1;
		RPULSE3 <= RPULSE2;
		RPULSE4 <= RPULSE3;
		RPULSE5 <= RPULSE4;
		RPULSE6 <= RPULSE5;
		RPULSE7 <= RPULSE6;

		case (dbg_out[2:0])
			3'd0: begin
				ack <= WPULSE0 | RPULSE4;
			end
			
			3'd1: begin
				ack <= WPULSE0 | RPULSE5;
			end
			
			3'd2: begin
				ack <= WPULSE0 | RPULSE6;
			end
			
			3'd3: begin
				ack <= WPULSE0 | RPULSE7;
			end
			
			3'd4: begin
				ack <= WPULSE0 | RPULSE4;
			end
			
			3'd5: begin
				ack <= WPULSE0 | RPULSE5;
			end
			
			3'd6: begin
				ack <= WPULSE0 | RPULSE6;
			end
			
			3'd7: begin
				ack <= WPULSE0 | RPULSE7;
			end
		endcase

		case (STATE)
			S_INIT: begin
				rDDR_CKE <= 2'b11;
				READ <= 0;
				rDDR_BankAddr <= sa[15:13];
				rDDR_Addr <= sa[31:16];
				if (swr) begin
					rDDR_CS_n <= sa[32] ? 2'b01 : 2'b10;
					STATE <= S_INIT2;
					rDDR_Cmd <= sa[10:8];
					WPULSE0 <= 1;
				end
			end
				
			S_INIT2: begin
				RTN <= sa[33] ? S_INIT : S_IDLE;
				rDDR_Cmd <= K_NOP;
				STATE <= S_PAUSE;
				DLY <= 20;
				WPULSE0 <= 0;
			end
				
			S_IDLE: begin
				READ <= 0;
				rDDR_ODT <= 2'b00;
				if (swr) begin
					rDDR_Cmd <= K_OPEN;
					STATE <= S_PAUSE;
					RTN <= S_WRITE;
					DLY <= tRCD - 1;
					rDDR_Addr <= sa[31:16];
					rDDR_BankAddr <= sa[15:13];
					rDDR_CS_n <= sa[32] ? 2'b01 : 2'b10;
				end	else if (srd) begin
					rDDR_Cmd <= K_OPEN;
					STATE <= S_PAUSE;
					RTN <= S_READ;
					DLY <= tRCD - 1;
					rDDR_Addr <= sa[31:16];
					rDDR_BankAddr <= sa[15:13];
					rDDR_CS_n <= sa[32] ? 2'b01 : 2'b10;
				end	else if (REFRESH) begin
					rDDR_Cmd <= K_RFSH;
					STATE <= S_PAUSE;
					RTN <= S_IDLE;
					DLY <= tRFC - 1;
					REFRESH <= 0;
					rDDR_CS_n <= 2'b00;
				end	else begin
					rDDR_Cmd <= K_NOP;
					rDDR_CS_n <= 2'b00;
				end
			end

// Address bits
// ============
//	MB	pg	Lwd	sa	Row	Col	Bnk	CS
// [X]	-	-	- 	-	-	-	-
// [X]	-	-	- 	-	-	-	-
// 	2	-	0	- 	-	-	-	-
// 	3	-  	1  [L] 	-	0	-	-
// 	4	-  	2  [L] 	-	1	-	-
// 	5	-	-	5 	-	2	-	-
// 	6	-	-	6 	-	3	-	-
// 	7	-	-	7 	-	4	-	-
// 	8	-	-	8 	-	5	-	- 	
// 	9	-	-	9 	-	6	-	- 	
// 	10	-	-	10	-	7	-	-	
// 	11	-	-	11	-	8	-	-	
// 	12	-	-	12	-	9	-	-	
// 	13	-	-	13	-  [P]	0	-
// 	14	-	-	14	-	-	1	-
// 	15	-	-	15	-	-	2	-
// 	16	-	-	16	0 	-	-	-
// 	17	-	-	17	1 	-	-	-
// 	18	-	-	18	2 	-	-	-
// 	19	-	-	19	3 	-	-	-
// 	20	-	-	20	4 	-	-	-
// 	21	-	-	21	5 	-	-	-
// 	22	-	-	22	6 	-	-	-
// 	23	-	-	23	7 	-	-	-		
// 	24	-	-	24	8 	-	-	-		
// 	25	-	-	25	9 	-	-	-		
// 	26	-	-	26	10	-	-	-
// 	27	-	-	27	11	-	-	-
// 	28	-	-	28	12	-	-	-
// 	29	-	-	29	13	-	-	-
//	[H] 0	-	30	14	-	-	-
//	[H] 1	-	31	15	-	-	-
// 	 -	2	-	32	-	-	-	0
//	 -	3	-	33	-	-	-   Extra address bit for DRAM init register space 		

			S_WRITE: begin
				rDDR_Cmd <= K_WRITE;
				STATE <= S_PAUSE;
				RTN <= S_IDLE;
				DLY <= 14; // CWL + 2xfer + tWR + tRP
				rDDR_Addr[10:0] <= {1'b1, sa[12:5], 2'b00};	// NB two LSBs ignored by DDR3 during WRITE
				rDDR_Addr[12] <= dbg_out[2];
				rDDR_BankAddr <= sa[15:13];
				rDDR_ODT <= sa[16] ? 2'b10 : 2'b01; // Use ODT only in one rank, otherwise 40R || 40R -> 20R
				WPULSE0 <= 1;
				if (sa[33]) begin
					rChgDelay <= rWdat[63:0];
					rIncDelay <= rWdat[127:64];
					rCalDelay <= rWdat[191:128];
					rRstDelay <= rWdat[255:192];
				end else begin
					rChgDelay <= 64'd0;
					rIncDelay <= 64'd0;
					rCalDelay <= 64'd0;
					rRstDelay <= 64'd0;
				end
			end
				
			S_READ: begin
				rDDR_Cmd <= K_READ;
				STATE <= S_PAUSE;
				RTN <= S_IDLE;
				DLY <= 10; // CL + 2xfer + 1 + tRP
				rDDR_Addr[10:0] <= {1'b1, sa[12:5], 2'b00};
				rDDR_Addr[12] <= dbg_out[2];
				rDDR_BankAddr <= sa[15:13];
				READ <= 1;
				RPULSE0 <= 1;
			end
				
			S_PAUSE: begin
				rDDR_Cmd <= K_NOP;
				DLY <= DLY - 6'b000001;
				if (DLY == 6'b000001)
					STATE <= RTN;
				else
					STATE <= S_PAUSE;
				RPULSE0 <= 0;
				WPULSE0 <= 0;
				rChgDelay <= 64'd0;
				rIncDelay <= 64'd0;
				rCalDelay <= 64'd0;
				rRstDelay <= 64'd0;
			end
		endcase
	end
		
assign srdat			= Q;
assign srdy			   	= ack;

assign ckouthalf	   	= ck75;
assign ckout		   	= ck150;

assign reset			= ~rStarted;
assign dbg_in[4]		= locked;
assign dbg_in[7:5]		= rDDR_Cmd;

endmodule

