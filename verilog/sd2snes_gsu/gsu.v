`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    06:32:24 02/24/2018 
// Design Name: 
// Module Name:    gsu 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module gsu(
  input         RST,
  input         CLK,

  input  [23:0] SAVERAM_MASK,
  input  [23:0] ROM_MASK,

  // MMIO interface
  input         ENABLE,
  input         SNES_RD_start,
  input         SNES_WR_start,
  input         SNES_WR_end,
  input  [23:0] SNES_ADDR,
  input  [7:0]  DATA_IN,
  output        DATA_ENABLE,
  output [7:0]  DATA_OUT,
  
  // ROM interface
  input         ROM_BUS_RDY,
  output        ROM_BUS_RRQ,
  output        ROM_BUS_WORD,
  output [23:0] ROM_BUS_ADDR,
  input  [15:0] ROM_BUS_RDDATA,

  // RAM interface
  input         RAM_BUS_RDY,
  output        RAM_BUS_RRQ,
  output        RAM_BUS_WRQ,
  output        RAM_BUS_WORD,
  output [23:0] RAM_BUS_ADDR,
  input  [15:0] RAM_BUS_RDDATA,
  output [15:0] RAM_BUS_WRDATA,
  
  // ACTIVE interface
  //output        ACTIVE,
  output        IRQ,
  output        GO,
  output        RON,
  output        RAN,
  
  // State debug read interface
  input  [9:0]  PGM_ADDR, // [9:0]
  output [7:0]  PGM_DATA, // [7:0]

  // config interface
  input  [7:0]  reg_group_in,
  input  [7:0]  reg_index_in,
  input  [7:0]  reg_value_in,
  input  [7:0]  reg_invmask_in,
  input         reg_we_in,
  input  [7:0]  reg_read_in,
  output [7:0]  config_data_out,
  // config interface

  output        DBG
);

`define DEBUG

// temporaries
integer i;
wire pipeline_advance;
wire op_complete;

//-------------------------------------------------------------------
// INPUTS
//-------------------------------------------------------------------
reg [7:0]  data_in_r;
reg [23:0] addr_in_r;
reg        enable_r;
reg [9:0]  pgm_addr_r;

always @(posedge CLK) begin
  data_in_r  <= DATA_IN;
  addr_in_r  <= SNES_ADDR;
  enable_r   <= ENABLE;
  pgm_addr_r <= PGM_ADDR;
end

//-------------------------------------------------------------------
// PARAMETERS
//-------------------------------------------------------------------
parameter NUM_GPR = 16;

parameter
  R0    = 8'h00,
  R1    = 8'h01,
  R2    = 8'h02,
  R3    = 8'h03,
  R4    = 8'h04,
  R5    = 8'h05,
  R6    = 8'h06,
  R7    = 8'h07,
  R8    = 8'h08,
  R9    = 8'h09,
  R10   = 8'h0A,
  R11   = 8'h0B,
  R12   = 8'h0C,
  R13   = 8'h0D,
  R14   = 8'h0E,
  R15   = 8'h0F
  ;

parameter
  ADDR_R0    = 8'h00,
  ADDR_R1    = 8'h02,
  ADDR_R2    = 8'h04,
  ADDR_R3    = 8'h06,
  ADDR_R4    = 8'h08,
  ADDR_R5    = 8'h0A,
  ADDR_R6    = 8'h0C,
  ADDR_R7    = 8'h0E,
  ADDR_R8    = 8'h10,
  ADDR_R9    = 8'h12,
  ADDR_R10   = 8'h14,
  ADDR_R11   = 8'h16,
  ADDR_R12   = 8'h18,
  ADDR_R13   = 8'h1A,
  ADDR_R14   = 8'h1C,
  ADDR_R15   = 8'h1E,
  ADDR_GPRL  = 8'b000x_xxx0,
  ADDR_GPRH  = 8'b000x_xxx1,
  
  ADDR_SFR   = 8'h30,
  ADDR_BRAMR = 8'h33,
  ADDR_PBR   = 8'h34,
  ADDR_ROMBR = 8'h36,
  ADDR_CFGR  = 8'h37,
  ADDR_SCBR  = 8'h38,
  ADDR_CLSR  = 8'h39,
  ADDR_SCMR  = 8'h3A,
  ADDR_VCR   = 8'h3B,
  ADDR_RAMBR = 8'h3C,
  ADDR_CBR   = 8'h3E,
  
  ADDR_CACHE_BASE = 10'h100
  ;

//---
// Instructions
//---
// special
`define OP_STOP          8'h00
`define OP_NOP           8'h01
`define OP_CACHE         8'h02 // x
// branches (no reset state)
`define OP_BRA           8'h05 // x
`define OP_BGE           8'h06 // x
`define OP_BLT           8'h07 // x
`define OP_BNE           8'h08 // x
`define OP_BEQ           8'h09 // x
`define OP_BPL           8'h0A // x
`define OP_BMI           8'h0B // x
`define OP_BCC           8'h0C // x
`define OP_BCS           8'h0D // x
`define OP_BVC           8'h0E // x
`define OP_BVS           8'h0F // x
`define OP_LOOP          8'h3C // x
// prefix (also see branch) no reset state
`define OP_ALT1          8'h3D
`define OP_ALT2          8'h3E
`define OP_ALT3          8'h3F
`define OP_TO            8'h10,8'h11,8'h12,8'h13,8'h14,8'h15,8'h16,8'h17,8'h18,8'h19,8'h1A,8'h1B,8'h1C,8'h1D,8'h1E,8'h1F
`define OP_WITH          8'h20,8'h21,8'h22,8'h23,8'h24,8'h25,8'h26,8'h27,8'h28,8'h29,8'h2A,8'h2B,8'h2C,8'h2D,8'h2E,8'h2F
`define OP_FROM          8'hB0,8'hB1,8'hB2,8'hB3,8'hB4,8'hB5,8'hB6,8'hB7,8'hB8,8'hB9,8'hBA,8'hBB,8'hBC,8'hBD,8'hBE,8'hBF 
// mov
// move/moves paired with/to/from
`define OP_IBT           8'hA0,8'hA1,8'hA2,8'hA3,8'hA4,8'hA5,8'hA6,8'hA7,8'hA8,8'hA9,8'hAA,8'hAB,8'hAC,8'hAD,8'hAE,8'hAF // x
`define OP_IWT           8'hF0,8'hF1,8'hF2,8'hF3,8'hF4,8'hF5,8'hF6,8'hF7,8'hF8,8'hF9,8'hFA,8'hFB,8'hFC,8'hFD,8'hFE,8'hFF // x
// load from ROM
`define OP_GETB          8'hEF // x
// load from RAM
`define OP_LD            8'h40,8'h41,8'h42,8'h43,8'h44,8'h45,8'h46,8'h47,8'h48,8'h49,8'h4A,8'h4B // x
`define OP_ST            8'h30,8'h31,8'h32,8'h33,8'h34,8'h35,8'h36,8'h37,8'h38,8'h39,8'h3A,8'h3B // x
`define OP_SBK           8'h90 // x
`define OP_GETC_RAMB_ROMB 8'hDF // x
// bitmap
`define OP_CMODE_COLOR   8'h4E // x
`define OP_PLOT_RPIX     8'h4C // x
// alu
`define OP_ADD           8'h50,8'h51,8'h52,8'h53,8'h54,8'h55,8'h56,8'h57,8'h58,8'h59,8'h5A,8'h5B,8'h5C,8'h5D,8'h5E,8'h5F
`define OP_SUB           8'h60,8'h61,8'h62,8'h63,8'h64,8'h65,8'h66,8'h67,8'h68,8'h69,8'h6A,8'h6B,8'h6C,8'h6D,8'h6E,8'h6F
`define OP_AND_BIC       8'h71,8'h72,8'h73,8'h74,8'h75,8'h76,8'h77,8'h78,8'h79,8'h7A,8'h7B,8'h7C,8'h7D,8'h7E,8'h7F
`define OP_OR_XOR        8'hC1,8'hC2,8'hC3,8'hC4,8'hC5,8'hC6,8'hC7,8'hC8,8'hC9,8'hCA,8'hCB,8'hCC,8'hCD,8'hCE,8'hCF
`define OP_NOT           8'h4F
// rotate/shift/inc/dec
`define OP_LSR           8'h03
`define OP_ASR_DIV2      8'h96
`define OP_ROL           8'h04
`define OP_ROR           8'h97
`define OP_INC           8'hD0,8'hD1,8'hD2,8'hD3,8'hD4,8'hD5,8'hD6,8'hD7,8'hD8,8'hD9,8'hDA,8'hDB,8'hDC,8'hDD,8'hDE
`define OP_DEC           8'hE0,8'hE1,8'hE2,8'hE3,8'hE4,8'hE5,8'hE6,8'hE7,8'hE8,8'hE9,8'hEA,8'hEB,8'hEC,8'hED,8'hEE
// byte
`define OP_SWAP          8'h4D
`define OP_SEX           8'h95
`define OP_LOB           8'h9E
`define OP_HIB           8'hC0
`define OP_MERGE         8'h70
// multiply
`define OP_FMULT_LMULT   8'h9F
`define OP_MULT          8'h80,8'h81,8'h82,8'h83,8'h84,8'h85,8'h86,8'h87,8'h88,8'h89,8'h8A,8'h8B,8'h8C,8'h8D,8'h8E,8'h8F
// jump
`define OP_LINK          8'h91,8'h92,8'h93,8'h94 // x
`define OP_JMP_LJMP      8'h98,8'h99,8'h9A,8'h9B,8'h9C,8'h9D // x

//-------------------------------------------------------------------
// CONFIG
//-------------------------------------------------------------------

// C0 Control
// 0 - Go (1) 
// 1 - MatchFullInst

// C1 StepControl
// [7:0] StepCount

// C2 BreakpointControl
// 0 - BreakOnInstRdByteWatch
// 1 - BreakOnDataRdByteWatch
// 2 - BreakOnDataWrByteWatch
// 3 - BreakOnInstRdAddrWatch
// 4 - BreakOnDataRdAddrWatch
// 5 - BreakOnDataWrAddrWatch
// 6 - BreakOnStop
// 7 - BreakOnError

// C3 ???

// C4 DataWatch
// [7:0] DataWatch

// C5-C7 AddrWatch (little endian)
// [23:0] AddrWatch

// breakpoint state
reg         brk_inst_rd_byte; initial brk_inst_rd_byte = 0;
reg         brk_data_rd_byte; initial brk_data_rd_byte = 0;
reg         brk_data_wr_byte; initial brk_data_wr_byte = 0;
reg         brk_inst_rd_addr; initial brk_inst_rd_addr = 0;
reg         brk_data_rd_addr; initial brk_data_rd_addr = 0;
reg         brk_data_wr_addr; initial brk_data_wr_addr = 0;
reg         brk_stop;         initial brk_stop = 0;
reg         brk_error;        initial brk_error = 0;

parameter CONFIG_REGISTERS = 8;
reg [7:0] config_r[CONFIG_REGISTERS-1:0]; initial for (i = 0; i < CONFIG_REGISTERS; i = i + 1) config_r[i] = 8'h00;

always @(posedge CLK) begin
  if (RST) begin
    for (i = 0; i < CONFIG_REGISTERS; i = i + 1) config_r[i] <= 8'h00;
  end
  else if (reg_we_in && (reg_group_in == 8'h03)) begin
    if (reg_index_in < CONFIG_REGISTERS) config_r[reg_index_in] <= (config_r[reg_index_in] & reg_invmask_in) | (reg_value_in & ~reg_invmask_in);
  end
  else begin
    // TODO: figure out how to do the data compares on time without getting false matches
    config_r[0][0] <= config_r[0][0] & ~|(config_r[2] & {brk_error,brk_stop,brk_data_wr_addr,brk_data_rd_addr,brk_inst_rd_addr,brk_data_wr_byte,brk_data_rd_byte,brk_inst_rd_byte});
  end
end

assign config_data_out = config_r[reg_read_in];

assign      CONFIG_CONTROL_ENABLED       = config_r[0][0];
assign      CONFIG_CONTROL_MATCHPARTINST = config_r[0][1];

wire [7:0]  CONFIG_STEP_COUNT   = config_r[1];
wire [7:0]  CONFIG_DATA_WATCH   = config_r[4];
wire [23:0] CONFIG_ADDR_WATCH   = {config_r[7],config_r[6],config_r[5]};

//-------------------------------------------------------------------
// FLOPS
//-------------------------------------------------------------------
reg cache_rom_rd_r; initial cache_rom_rd_r = 0;
reg exe_rom_rd_r; initial exe_rom_rd_r = 0;

reg cache_ram_rd_r; initial cache_ram_rd_r = 0;
reg exe_ram_rd_r; initial exe_ram_rd_r = 0;
reg exe_ram_wr_r; initial exe_ram_wr_r = 0;
reg bmp_ram_rd_r; initial bmp_ram_rd_r = 0;
reg bmp_ram_wr_r; initial bmp_ram_wr_r = 0;

reg cache_word_r;
reg exe_word_r;
reg bmp_word_r;

reg [23:0] cache_addr_r;
reg [23:0] exe_addr_r;
reg [15:0] exe_data_r;
reg [23:0] bmp_addr_r;
reg [15:0] bmp_data_r;

reg [23:0] debug_inst_addr_r;

reg [15:0] gsu_cycle_cnt_r; initial gsu_cycle_cnt_r = 0;

reg [1:0]  gsu_cycle_r; initial gsu_cycle_r = 0;
reg        gsu_clock_en;

// step counter for pipelines
reg [7:0] stepcnt_r; initial stepcnt_r = 0;
reg       step_r; initial step_r = 0;

always @(posedge CLK) begin
  if (RST) begin
    gsu_cycle_r <= 0;
    gsu_clock_en <= 0;
  end
  else begin
    gsu_cycle_r  <= gsu_cycle_r + 1;
    gsu_clock_en <= (gsu_cycle_r == 2'b10);
  end
end

// Assert clock enable every 4 FPGA clocks.  Delays are calculated in
// terms of GSU clocks so this is used to align transitions and
// operate counters.

always @(posedge CLK) begin
  if (RST) begin
    gsu_cycle_cnt_r <= 0;
  end
  else if (gsu_clock_en & step_r) begin
    gsu_cycle_cnt_r <= gsu_cycle_cnt_r + 1;
  end
end

//-------------------------------------------------------------------
// STATE
//-------------------------------------------------------------------
reg [15:0] REG_r   [15:0];

// Special Registers
reg [15:0] SFR_r;   // 3030-3031
reg [7:0]  BRAMR_r; // 3033
reg [7:0]  PBR_r;   // 3034
reg [7:0]  ROMBR_r; // 3036
reg [7:0]  CFGR_r;  // 3037
reg [7:0]  SCBR_r;  // 3038
reg [7:0]  CLSR_r;  // 3039
reg [7:0]  SCMR_r;  // 303A
reg [7:0]  VCR_r;   // 303B
reg        RAMBR_r; // 303C
reg [15:0] CBR_r;   // 303E
// unmapped
reg [7:0]  COLR_r;
reg [7:0]  POR_r;
reg [7:0]  SREG_r;
reg [7:0]  DREG_r;
reg [7:0]  ROMRDBUF_r;
reg [15:0] RAMWRBUF_r; // FIXME: this should be 8b
reg [15:0] RAMADDR_r;

// Important breakouts
assign SFR_Z    = SFR_r[1];
assign SFR_CY   = SFR_r[2];
assign SFR_S    = SFR_r[3];
assign SFR_OV   = SFR_r[4];
assign SFR_GO   = SFR_r[5];
assign SFR_RR   = SFR_r[6];
assign SFR_ALT1 = SFR_r[8];
assign SFR_ALT2 = SFR_r[9];
assign SFR_IL   = SFR_r[10];
assign SFR_IH   = SFR_r[11];
assign SFR_B    = SFR_r[12];
assign SFR_IRQ  = SFR_r[15];

assign BRAMR_EN = BRAMR_r[0];

assign CFGR_MS0 = CFGR_r[5];
assign CFGR_IRQ = CFGR_r[7];

assign CLSR_CLS = CLSR_r[0];

wire [1:0] SCMR_MD; assign SCMR_MD = SCMR_r[1:0];
wire [1:0] SCMR_HT; assign SCMR_HT = {SCMR_r[5],SCMR_r[2]};
assign SCMR_RAN = SCMR_r[3];
assign SCMR_RON = SCMR_r[4];

assign POR_TRS  = POR_r[0];
assign POR_DTH  = POR_r[1];
assign POR_HN   = POR_r[2];
assign POR_FHN  = POR_r[3];
assign POR_OBJ  = POR_r[4];

//-------------------------------------------------------------------
// Latency
//-------------------------------------------------------------------
reg [3:0] lat_fetch_r;
reg [3:0] lat_memory_r;
reg [3:0] lat_fmult_r;
reg [3:0] lat_mult_r;

always @(posedge CLK) begin
  lat_fetch_r  <= CLSR_r[0] ? 1-1 : 2-1;
  //lat_fetch_r  <= CLSR_r[0] ? 6-1 : 7-1; // FIXME: temporary to test cache
  lat_memory_r <= CLSR_r[0] ? 6-1 : 7-1;
  lat_fmult_r  <= (CLSR_r[0] | CFGR_MS0) ? 8-1 : 16-1;
  lat_mult_r   <= (CLSR_r[0] | CFGR_MS0) ? 2-1 : 4-1;
end

//-------------------------------------------------------------------
// PIPELINE IO
//-------------------------------------------------------------------
// Fetch -> Execute
// The fetch pipe and execution pipe are synchronized via the opbuf.
// Fetch operates one byte ahead of execution.
//reg [7:0]  i2e_op_r[1:0]; initial for (i = 0; i < 2; i = i + 1) i2e_op_r[i] = `OP_NOP;
//reg        i2e_ptr_r; initial i2e_ptr_r = 0;

// Execute -> RegisterFile
reg        e2r_val_r;
reg        e2r_sneswrite_r;
reg [3:0]  e2r_destnum_r;
reg [15:0] e2r_data_pre_r;
reg [15:0] e2r_data_r;
reg [15:0] e2r_r15_r;
reg [15:0] e2r_r4_r;
reg        e2r_loop_r;
reg        e2r_wpbr_r;
reg        e2r_wcbr_r;
reg        e2r_lmult_r;
reg [15:0] e2r_pbr_r;
reg [15:0] e2r_cbr_r;
reg        e2r_wpor_r;
reg [7:0]  e2r_por_r;
reg        e2r_wcolr_r;
reg [7:0]  e2r_colr_r;
// non dest registers to update
reg [1:0]  e2r_alt_r;
reg        e2r_z_r;
reg        e2r_cy_r;
reg        e2r_s_r;
reg        e2r_ov_r;
reg        e2r_b_r;
reg        e2r_g_r;
reg        e2r_irq_r;
reg [3:0]  e2r_sreg_r;
reg [3:0]  e2r_dreg_r;

// Fetch -> Common
reg        i2c_waitcnt_val_r; initial i2c_waitcnt_val_r = 0;
reg [3:0]  i2c_waitcnt_r;

// Execute -> Common
reg        e2c_waitcnt_val_r; initial e2c_waitcnt_val_r = 0;
reg [3:0]  e2c_waitcnt_r;

// Bitmap -> Common
reg        b2c_waitcnt_val_r; initial b2c_waitcnt_val_r = 0;
reg [3:0]  b2c_waitcnt_r;

// Execute -> Bitmap
reg        e2b_plot_r;
reg        e2b_rpix_r;
reg [7:0]  e2b_colr_r;
reg [15:0] e2b_offset_r;
reg [2:0]  e2b_index_r;

// Cache flush interface
reg        e2i_flush_r;
reg        r2i_flush_r;

reg waitcnt_zero_r;
wire waitcnt_zero;

//-------------------------------------------------------------------
// Cache
//-------------------------------------------------------------------
// GSU/SNES interface
reg        cache_mmio_wren_r; initial cache_mmio_wren_r = 0;
reg  [7:0] cache_mmio_wrdata_r;
reg  [8:0] cache_mmio_addr_r;

reg        cache_gsu_wren_r; initial cache_gsu_wren_r = 0;
reg  [7:0] cache_gsu_wrdata_r;
reg  [8:0] cache_gsu_addr_r;

wire       cache_wren;
wire [8:0] cache_addr;
wire [7:0] cache_wrdata;
wire [7:0] cache_rddata;
// 
wire       debug_cache_wren;
wire [8:0] debug_cache_addr;
wire [7:0] debug_cache_wrdata;
wire [7:0] debug_cache_rddata;

assign cache_wren   = SFR_GO ? cache_gsu_wren_r   : cache_mmio_wren_r;
assign cache_addr   = SFR_GO ? cache_gsu_addr_r   : cache_mmio_addr_r;
assign cache_wrdata = SFR_GO ? cache_gsu_wrdata_r : cache_mmio_wrdata_r;

assign debug_cache_wren = 0;
assign debug_cache_addr = {~pgm_addr_r[8],pgm_addr_r[7:0]};

// valid bits
reg [31:0] cache_val_r; initial cache_val_r = 0;

gsu_cache cache (
  .clka(CLK), // input clka
  .wea(cache_wren), // input [0 : 0] wea
  .addra(cache_addr), // input [8 : 0] addra
  .dina(cache_wrdata), // input [7 : 0] dina
  .douta(cache_rddata), // output [7 : 0] douta
  
  .clkb(CLK), // input clkb
  .web(debug_cache_wren), // input [0 : 0] web
  .addrb(debug_cache_addr), // input [8 : 0] addrb
  .dinb(debug_cache_wrdata), // input [7 : 0] dinb
  .doutb(debug_cache_rddata) // output [7 : 0] doutb
);

//-------------------------------------------------------------------
// REGISTER/MMIO ACCESS
//-------------------------------------------------------------------
// This handles all state read and write.  The main execution pipeline
// feeds intermediate results back here.
reg        data_enable_r;
reg [7:0]  data_out_r;
reg [7:0]  data_flop_r;

reg        snes_write_r;
reg        snes_writereg_r;

reg        snes_writebuf_val_r;
reg        snes_writebuf_reg_r;
reg        snes_writebuf_gpr_r;
reg [9:0]  snes_writebuf_addr_r;
reg [7:0]  snes_writebuf_data_r;

reg        snes_readbuf_val_r;

reg        idle_r;

always @(posedge CLK) begin
  if (RST) begin
    for (i = 0; i < NUM_GPR; i = i + 1) begin
      REG_r[i] <= 0;
    end
    
    SFR_r   <= 0;
    PBR_r   <= 0;
    //ROMBR_r <= 0;
    //RAMBR_r <= 0;
    CBR_r   <= 0;
    SCBR_r  <= 0;
    SCMR_r  <= 0;
    COLR_r  <= 0;
    POR_r   <= 0;
    BRAMR_r <= 0;
    VCR_r   <= 4;
    CFGR_r  <= 0;
    CLSR_r  <= 0;
    
    SREG_r  <= 0;
    DREG_r  <= 0;
    
    //ROMRDBUF_r <= 0;
    //RAMWRBUF_r <= 0;
    //RAMADDR_r  <= 0;
    
    data_enable_r <= 0;
    data_flop_r <= 0;
    
    snes_writebuf_val_r <= 0;
    snes_writebuf_reg_r <= 0;
    snes_writebuf_gpr_r <= 0;
    snes_readbuf_val_r <= 0;
    
    cache_mmio_wren_r <= 0;
  end
  else begin
    // True data enable.  This assumes we need unmapped read addresses to be openbus.
    // Register Read
    if (enable_r) begin
      if (SNES_RD_start) begin
        if (~|addr_in_r[9:8]) begin
          casex (addr_in_r[7:0])
            ADDR_GPRL : begin data_out_r <= REG_r[addr_in_r[4:1]][7:0];  if (~SFR_GO) data_enable_r <= 1; end
            ADDR_GPRH : begin data_out_r <= REG_r[addr_in_r[4:1]][15:8]; if (~SFR_GO) data_enable_r <= 1; end
          
            ADDR_SFR  : begin data_out_r <= SFR_r[7:0];  data_enable_r <= 1; end
            ADDR_SFR+1: begin data_out_r <= SFR_r[15:8]; data_enable_r <= 1; end
            ADDR_PBR  : begin data_out_r <= PBR_r;       if (~SFR_GO) data_enable_r <= 1; end
            ADDR_ROMBR: begin data_out_r <= ROMBR_r;     if (~SFR_GO) data_enable_r <= 1; end
            ADDR_VCR  : begin data_out_r <= VCR_r;       data_enable_r <= 1; end
            ADDR_RAMBR: begin data_out_r <= RAMBR_r;     if (~SFR_GO) data_enable_r <= 1; end
            ADDR_CBR+0: begin data_out_r <= CBR_r[7:0];  if (~SFR_GO) data_enable_r <= 1; end
            ADDR_CBR+1: begin data_out_r <= CBR_r[15:8]; if (~SFR_GO) data_enable_r <= 1; end
          endcase
        end
        else begin
          data_enable_r <= 1;
          cache_mmio_addr_r <= {~addr_in_r[8],addr_in_r[7:0]};
        end
      end
      else if (|addr_in_r[9:8]) begin
        data_out_r <= cache_rddata;
      end
    end
    else begin
      data_enable_r <= 0;
    end
  
    // Register Write Buffer.  snes writes are sent on non-GSU clocks
    if (SNES_WR_end & enable_r) begin
      snes_writebuf_val_r  <= 1;
      snes_writebuf_reg_r  <= ~|addr_in_r[9:8];
      snes_writebuf_gpr_r  <= ~|addr_in_r[9:5];
      snes_writebuf_addr_r <= addr_in_r[9:0];
      snes_writebuf_data_r <= data_in_r;
    end
    else if (snes_writebuf_val_r & ~gsu_clock_en) begin
      snes_writebuf_val_r <= 0;
      snes_writebuf_reg_r <= 0;
      snes_writebuf_gpr_r <= 0;
    end

    if (SNES_RD_start && enable_r && addr_in_r[9:0] == {2'h0,ADDR_SFR+1}) begin
      snes_readbuf_val_r <= 1;
    end
    else if (snes_readbuf_val_r & ~gsu_clock_en) begin
      snes_readbuf_val_r <= 0;
    end
    
    // Cache flush on GO 1->0.  Sync with IDLE.
    if (snes_writebuf_val_r & ~gsu_clock_en) begin
      if (snes_writebuf_reg_r) begin
        if (snes_writebuf_addr_r[7:0] == ADDR_SFR) begin
          if (SFR_GO & ~snes_writebuf_data_r[5]) r2i_flush_r <= 1;
        end
        else if (snes_writebuf_addr_r[7:0] == ADDR_PBR) begin
          // this can only be done at IDLE so use the same deassertion conditions
          r2i_flush_r <= 1;
        end
      end
    end
    else if (idle_r) begin
      r2i_flush_r <= 0;
    end
    
    // Registers that can be modifed by both
    if (snes_writebuf_val_r & ~gsu_clock_en) begin
      if (snes_writebuf_reg_r) begin
        case (snes_writebuf_addr_r[7:0])
          ADDR_R15+1: SFR_r[5] <= 1;
          
          ADDR_SFR  : begin SFR_r[6:1] <= snes_writebuf_data_r[6:1]; CBR_r[15:4] <= 0; end
          ADDR_SFR+1: {SFR_r[15],SFR_r[12:8]} <= {snes_writebuf_data_r[7],snes_writebuf_data_r[4:0]};
          ADDR_BRAMR: BRAMR_r[0] <= snes_writebuf_data_r[0];
          ADDR_PBR  : PBR_r <= snes_writebuf_data_r;
          ADDR_CFGR : {CFGR_r[7],CFGR_r[5]} <= {snes_writebuf_data_r[7],snes_writebuf_data_r[5]};
          ADDR_SCBR : SCBR_r <= snes_writebuf_data_r;
          ADDR_CLSR : CLSR_r[0] <= snes_writebuf_data_r[0];
          ADDR_SCMR : SCMR_r[5:0] <= snes_writebuf_data_r[5:0];
        endcase
      end
      else begin
        cache_mmio_wren_r <= 1;
        cache_mmio_wrdata_r <= snes_writebuf_data_r;
        cache_mmio_addr_r <= {~snes_writebuf_addr_r[8],snes_writebuf_addr_r[7:0]};
      end
    end
    else if (snes_readbuf_val_r & ~gsu_clock_en) begin
      // clear interrupt
      SFR_r[15] <= 0;
    end
    else if (pipeline_advance & op_complete) begin
      // TODO: R, IL,IH, IRQ
      SFR_r[1]   <= e2r_z_r;
      SFR_r[2]   <= e2r_cy_r;
      SFR_r[3]   <= e2r_s_r;
      SFR_r[4]   <= e2r_ov_r;
      SFR_r[5]   <= e2r_g_r;
      SFR_r[9:8] <= e2r_alt_r;
      SFR_r[12]  <= e2r_b_r;
      SFR_r[15]  <= e2r_irq_r;

      SREG_r     <= e2r_sreg_r;
      DREG_r     <= e2r_dreg_r;
      if (e2r_wpbr_r)  PBR_r <= e2r_pbr_r;
      if (e2r_wcbr_r)  CBR_r[15:4] <= e2r_cbr_r[15:4];
      if (e2r_wpor_r)  POR_r <= e2r_por_r;
      if (e2r_wcolr_r) COLR_r <= e2r_colr_r;
    end
    else begin
      cache_mmio_wren_r <= 0;
    end

    // Register file
    if (snes_writebuf_val_r & snes_writebuf_gpr_r & ~gsu_clock_en) begin
      if (snes_writebuf_addr_r[0]) REG_r[snes_writebuf_addr_r[5:1]] <= {snes_writebuf_data_r,data_flop_r};
      else                         data_flop_r                      <= snes_writebuf_data_r;
    end
    else if (pipeline_advance) begin
      if (e2r_val_r & op_complete) begin
        case (e2r_destnum_r)
          R0 : begin REG_r[R0 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R1 : begin REG_r[R1 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R2 : begin REG_r[R2 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R3 : begin REG_r[R3 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R4 : begin REG_r[R4 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R5 : begin REG_r[R5 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R6 : begin REG_r[R6 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R7 : begin REG_r[R7 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R8 : begin REG_r[R8 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R9 : begin REG_r[R9 ] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R10: begin REG_r[R10] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R11: begin REG_r[R11] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R12: begin REG_r[R12] <= e2r_data_r; REG_r[R15] <= (e2r_loop_r ? REG_r[R13] : REG_r[R15] + 1); end
          R13: begin REG_r[R13] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R14: begin REG_r[R14] <= e2r_data_r; REG_r[R15] <= REG_r[R15] + 1; end
          R15: begin REG_r[R15] <= e2r_data_r;                               end
        endcase
      end
      else begin
        // TODO: integrate this into one of the non-GSU clocks.  Gets tricky with LOOP - could adjust R15 in DECODE and write in EXECUTE when we would normally do R15+1 or branch target.
        REG_r[R15] <= REG_r[R15] + 1;
      end
    end
    else if (e2r_lmult_r & gsu_clock_en) begin
      // TODO: fix this hack when we fix the need for separate R15.
      REG_r[R4] <= e2r_r4_r;
    end
  end
end

//-------------------------------------------------------------------
// COMMON PIPELINE
//-------------------------------------------------------------------

reg [3:0] fetch_waitcnt_r;
reg [3:0] exe_waitcnt_r;
reg [3:0] bmp_waitcnt_r;

always @(posedge CLK) begin
  if (RST) begin
    fetch_waitcnt_r <= 0;
    exe_waitcnt_r <= 0;
    bmp_waitcnt_r <= 0;
    waitcnt_zero_r <= 0;
    
    stepcnt_r <= 0;
    step_r <= 0;
  end
  else begin
    // decrement delay counters
    if (i2c_waitcnt_val_r) fetch_waitcnt_r <= i2c_waitcnt_r;
    else if (gsu_clock_en & |fetch_waitcnt_r) fetch_waitcnt_r <= fetch_waitcnt_r - 1;

    if (e2c_waitcnt_val_r) exe_waitcnt_r <= e2c_waitcnt_r;
    else if (gsu_clock_en & |exe_waitcnt_r) exe_waitcnt_r <= exe_waitcnt_r - 1;

    if (b2c_waitcnt_val_r) bmp_waitcnt_r <= b2c_waitcnt_r;
    else if (gsu_clock_en & |bmp_waitcnt_r) bmp_waitcnt_r <= bmp_waitcnt_r - 1;
    
    // ok to advance to next instruction byte
    step_r <= CONFIG_CONTROL_ENABLED || (!op_complete & !CONFIG_CONTROL_MATCHPARTINST) || (stepcnt_r != CONFIG_STEP_COUNT);
    
    if (pipeline_advance & (op_complete | CONFIG_CONTROL_MATCHPARTINST)) stepcnt_r <= CONFIG_STEP_COUNT;
    //waitcnt_zero_r <= ~|fetch_waitcnt_r & ~|exe_waitcnt_r;
  end
end

assign waitcnt_zero = ~|fetch_waitcnt_r & ~|exe_waitcnt_r;

//-------------------------------------------------------------------
// ROM PIPELINE
//-------------------------------------------------------------------
parameter
  ST_ROM_IDLE      = 8'b00000001,
  ST_ROM_FETCH_RD  = 8'b00000010,
  ST_ROM_DATA_RD   = 8'b00000100,
  //ST_ROM_DATA_WR   = 8'b00001000,
  ST_ROM_FETCH_END = 8'b00010000,
  ST_ROM_DATA_END  = 8'b00100000
  ;
reg [7:0] ROM_STATE; initial ROM_STATE = ST_ROM_IDLE;
reg rom_bus_rrq_r; initial rom_bus_rrq_r = 0;
reg [23:0] rom_bus_addr_r;
reg [15:0] rom_bus_data_r;
reg        rom_bus_word_r;
//reg [3:0] rom_waitcnt_r;

// The ROM/RAM should be dedicated to the GSU whenever it wants to do a fetch
always @(posedge CLK) begin
  if (RST) begin
    ROM_STATE <= ST_ROM_IDLE;

    ROMRDBUF_r <= 0;
  end
  else begin
    case (ROM_STATE)
      ST_ROM_IDLE: begin
        if (exe_rom_rd_r & SCMR_RON) begin
          rom_bus_rrq_r <= 1;
          rom_bus_addr_r <= exe_addr_r;
          rom_bus_word_r <= exe_word_r;
          ROM_STATE <= ST_ROM_DATA_RD;
        end
        else if (cache_rom_rd_r & SCMR_RON) begin
          rom_bus_rrq_r <= 1;
          rom_bus_addr_r <= cache_addr_r;
          rom_bus_word_r <= cache_word_r;
          ROM_STATE <= ST_ROM_FETCH_RD;
        end
      end
      ST_ROM_FETCH_RD,
      ST_ROM_DATA_RD: begin
        rom_bus_rrq_r <= 0;
        
        if (~rom_bus_rrq_r & ROM_BUS_RDY) begin
          rom_bus_data_r <= ROM_BUS_RDDATA;
          ROM_STATE <= (|(ROM_STATE & ST_ROM_FETCH_RD)) ? ST_ROM_FETCH_END : ST_ROM_DATA_END;
        end
      end
      ST_ROM_FETCH_END,
      ST_ROM_DATA_END: begin
        ROM_STATE <= ST_ROM_IDLE;
      end
    endcase
  end
end

assign ROM_BUS_RRQ = rom_bus_rrq_r;
assign ROM_BUS_WORD = rom_bus_word_r;
assign ROM_BUS_ADDR = rom_bus_addr_r;

//-------------------------------------------------------------------
// RAM PIPELINE
//-------------------------------------------------------------------
parameter
  ST_RAM_IDLE      = 9'b000000001,
  ST_RAM_FETCH_RD  = 9'b000000010,
  ST_RAM_DATA_RD   = 9'b000000100,
  ST_RAM_DATA_WR   = 9'b000001000,
  ST_RAM_BMP_RD    = 9'b000010000,
  ST_RAM_BMP_WR    = 9'b000100000,
  ST_RAM_FETCH_END = 9'b001000000,
  ST_RAM_DATA_END  = 9'b010000000,
  ST_RAM_BMP_END   = 9'b100000000
  ;
reg [8:0] RAM_STATE; initial RAM_STATE = ST_RAM_IDLE;
reg ram_bus_rrq_r; initial ram_bus_rrq_r = 0;
reg ram_bus_wrq_r; initial ram_bus_wrq_r = 0;
reg [23:0] ram_bus_addr_r;
reg [15:0] ram_bus_data_r;
reg        ram_bus_word_r;
//reg [3:0] ram_waitcnt_r;

always @(posedge CLK) begin
  if (RST) begin
    RAM_STATE <= ST_RAM_IDLE;
    
    ram_bus_rrq_r <= 0;
    ram_bus_wrq_r <= 0;
    
    RAMWRBUF_r <= 0;
    RAMADDR_r  <= 0;
  end
  else begin
    case (RAM_STATE)
      ST_RAM_IDLE: begin
        // TODO: determine if the cache can make demand fetches
        if (exe_ram_rd_r & SCMR_RAN) begin
          ram_bus_rrq_r <= 1;
          ram_bus_word_r <= exe_word_r;
          ram_bus_addr_r <= exe_addr_r; // TODO: get correct cache address for demand fetch
          RAMADDR_r <= exe_addr_r[15:0];
          RAM_STATE <= ST_RAM_DATA_RD;
        end
        else if (exe_ram_wr_r & SCMR_RAN) begin
          ram_bus_wrq_r <= 1;
          ram_bus_word_r <= exe_word_r;
          ram_bus_addr_r <= exe_addr_r; // TODO: get correct cache address for demand fetch
          RAMADDR_r <= exe_addr_r[15:0];
          //rom_bus_data_r <= gsu_ram_data_r; // TODO: data to write
          RAMWRBUF_r <= exe_data_r;
          RAM_STATE <= ST_RAM_DATA_WR;
        end
        else if (cache_ram_rd_r & SCMR_RAN) begin
          ram_bus_rrq_r <= 1;
          ram_bus_addr_r <= cache_addr_r;
          ram_bus_word_r <= cache_word_r;
          RAM_STATE <= ST_RAM_FETCH_RD;
        end
        else if (bmp_ram_rd_r & SCMR_RAN) begin
          ram_bus_rrq_r <= 1;
          ram_bus_word_r <= bmp_word_r;
          ram_bus_addr_r <= bmp_addr_r; // TODO: get correct cache address for demand fetch
          RAMADDR_r <= bmp_addr_r[15:0];
          RAM_STATE <= ST_RAM_BMP_RD;
        end
        else if (bmp_ram_wr_r & SCMR_RAN) begin
          ram_bus_wrq_r <= 1;
          ram_bus_word_r <= bmp_word_r;
          ram_bus_addr_r <= bmp_addr_r; // TODO: get correct cache address for demand fetch
          RAMADDR_r <= bmp_addr_r[15:0];
          //rom_bus_data_r <= gsu_ram_data_r; // TODO: data to write
          RAMWRBUF_r <= bmp_data_r;
          RAM_STATE <= ST_RAM_BMP_WR;
        end
      end
      ST_RAM_FETCH_RD,
      ST_RAM_DATA_RD,
      ST_RAM_DATA_WR,
      ST_RAM_BMP_RD,
      ST_RAM_BMP_WR: begin
        ram_bus_rrq_r <= 0;
        ram_bus_wrq_r <= 0;
        
        if ((~ram_bus_rrq_r & ~ram_bus_wrq_r) & RAM_BUS_RDY) begin
          ram_bus_data_r <= RAM_BUS_RDDATA;
          RAM_STATE <= (|(RAM_STATE & ST_RAM_FETCH_RD)) ? ST_RAM_FETCH_END : (|(RAM_STATE & (ST_RAM_BMP_RD | ST_RAM_BMP_WR))) ? ST_RAM_BMP_END : ST_RAM_DATA_END;
        end
      end
      ST_RAM_FETCH_END,
      ST_RAM_DATA_END,
      ST_RAM_BMP_END: begin
        RAM_STATE <= ST_RAM_IDLE;
      end
    endcase
  end
end

assign RAM_BUS_RRQ = ram_bus_rrq_r;
assign RAM_BUS_WRQ = ram_bus_wrq_r;
assign RAM_BUS_WORD = ram_bus_word_r;
assign RAM_BUS_ADDR = ram_bus_addr_r;
assign RAM_BUS_WRDATA = RAMWRBUF_r;

//-------------------------------------------------------------------
// BITMAP PIPELINE
//-------------------------------------------------------------------

// WriteBuffers
reg [7:0]  PIXBUF_VALID_r[1:0];
reg [15:0] PIXBUF_OFFSET_r[1:0];
reg [7:0]  PIXBUF_r[1:0][7:0];

reg        bmp_mode_r;
reg [3:0]  bmp_bppm1_r;
reg [7:0]  bmp_x_r[1:0];
reg [7:0]  bmp_y_r[1:0];
reg [15:0] bmp_char_r[1:0];
reg [15:0] bmp_char_shift_r[1:0];
reg [15:0] bmp_offset_r;
reg [2:0]  bmp_index_r;
reg [7:0]  bmp_colr_r;
reg        bmp_flush_buf_r;
reg        bmp_flush_rmw_r;
reg [7:0]  bmp_flush_colr_r;
reg [2:0]  bmp_plane_r;
reg [15:0] bmp_rpix_char_r;
reg [15:0] bmp_rpix_char_shift_r;
reg [7:0]  bmp_rpix_x_r;
reg [7:0]  bmp_rpix_y_r;

//reg [1:0]  bmp_pixbuf_allvalid_r;
//reg [1:0]  bmp_pixbuf_onevalid_r;
reg [7:0]  bmp_index_bit_r;

parameter  BMP_MODE_PLOT = 0;
parameter  BMP_MODE_RPIX = 1;

parameter
  ST_BMP_IDLE             = 8'b00000001,
  ST_BMP_FLUSH_READ       = 8'b00000010,
  ST_BMP_FLUSH_READ_WAIT  = 8'b00000100,
  ST_BMP_FLUSH_WRITE      = 8'b00001000,
  ST_BMP_FLUSH_WRITE_WAIT = 8'b00010000,
  ST_BMP_FILL             = 8'b00100000,
  ST_BMP_FILL_WAIT        = 8'b01000000,
  ST_BMP_END              = 8'b10000000
  ;
reg [7:0]  BMP_STATE; initial BMP_STATE = ST_BMP_IDLE;

always @(*) begin
  case (SCMR_HT | {2{POR_OBJ}})
    0: bmp_rpix_char_r = {e2b_offset_r[4:0],4'b0000} + e2b_offset_r[12:8];
    1: bmp_rpix_char_r = {e2b_offset_r[4:0],4'b0000} + {e2b_offset_r[4:0],2'b00} + e2b_offset_r[12:8];
    2: bmp_rpix_char_r = {e2b_offset_r[4:0],4'b0000} + {e2b_offset_r[4:0],3'b000} + e2b_offset_r[12:8];
    3: bmp_rpix_char_r = {e2b_offset_r[12],e2b_offset_r[4],e2b_offset_r[11:8],e2b_offset_r[3:0]};
  endcase
end

always @(posedge CLK) begin
  if (RST) begin
    BMP_STATE <= ST_BMP_IDLE;

    for (i = 0; i < 2; i = i + 1) PIXBUF_VALID_r[i] <= 0;
  end
  else begin
    // plot character number
    // x - [4:0],000
    // y - [12:5]
    for (i = 0; i < 2; i = i + 1) begin
      bmp_x_r[i] <= {PIXBUF_OFFSET_r[i][4:0],3'b000};
      bmp_y_r[i] <= PIXBUF_OFFSET_r[i][12:5];
      
      case (SCMR_HT | {2{POR_OBJ}})
        0: bmp_char_r[i] <= {PIXBUF_OFFSET_r[i][4:0],4'b0000} + PIXBUF_OFFSET_r[i][12:8];
        1: bmp_char_r[i] <= {PIXBUF_OFFSET_r[i][4:0],4'b0000} + {PIXBUF_OFFSET_r[i][4:0],2'b00} + PIXBUF_OFFSET_r[i][12:8];
        2: bmp_char_r[i] <= {PIXBUF_OFFSET_r[i][4:0],4'b0000} + {PIXBUF_OFFSET_r[i][4:0],3'b000} + PIXBUF_OFFSET_r[i][12:8];
        3: bmp_char_r[i] <= {PIXBUF_OFFSET_r[i][12],PIXBUF_OFFSET_r[i][4],PIXBUF_OFFSET_r[i][11:8],PIXBUF_OFFSET_r[i][3:0]};
      endcase
      
      case (SCMR_MD)
        0: bmp_char_shift_r[i] <= {bmp_char_r[i],4'h0};
        1: bmp_char_shift_r[i] <= {bmp_char_r[i],5'h00};
        2: bmp_char_shift_r[i] <= {bmp_char_r[i],5'h00};
        3: bmp_char_shift_r[i] <= {bmp_char_r[i],6'h00};
      endcase

      //bmp_pixbuf_onevalid_r[i] <= |PIXBUF_VALID_r[i];
      //bmp_pixbuf_allvalid_r[i] <= &PIXBUF_VALID_r[i];
    end
    
    bmp_rpix_x_r <= {e2b_offset_r[4:0],3'b000};
    bmp_rpix_y_r <= e2b_offset_r[12:5];
    
    case (SCMR_MD)
      0: bmp_rpix_char_shift_r <= {bmp_rpix_char_r,4'h0};
      1: bmp_rpix_char_shift_r <= {bmp_rpix_char_r,5'h00};
      2: bmp_rpix_char_shift_r <= {bmp_rpix_char_r,5'h00};
      3: bmp_rpix_char_shift_r <= {bmp_rpix_char_r,6'h00};
    endcase
    
    // {1, 3, 3, 7}
    bmp_bppm1_r <= {&SCMR_MD, |SCMR_MD, 1'b1};
    bmp_index_bit_r <= (8'h01 << e2b_index_r);

    case (BMP_STATE)
      ST_BMP_IDLE: begin // overlaps ST_EXE_MEMORY.  Single cycle operations 
        // watch for EXE command
        bmp_flush_colr_r <= 0;
        bmp_plane_r      <= 0;
        bmp_offset_r <= e2b_offset_r;
        bmp_index_r  <= e2b_index_r;

        if      (e2b_plot_r) begin
          bmp_mode_r   <= BMP_MODE_PLOT;
          bmp_colr_r   <= e2b_colr_r;
          
          if (PIXBUF_OFFSET_r[0] != e2b_offset_r && (|PIXBUF_VALID_r[0] && |PIXBUF_VALID_r[1])/*&bmp_pixbuf_onevalid_r*/) begin
            // flush1
            bmp_flush_buf_r <= 1;
            bmp_flush_rmw_r <= ~&PIXBUF_VALID_r[1];

            BMP_STATE <= &PIXBUF_VALID_r[1] ? ST_BMP_FLUSH_WRITE : ST_BMP_FLUSH_READ;
          end
          else begin
            // write and potential swap
            BMP_STATE <= ST_BMP_END;
          end
        end
        else if (e2b_rpix_r) begin
          bmp_mode_r <= BMP_MODE_RPIX;
          bmp_colr_r <= 0;

          // check if buffer0 is valid and flush
          if (|PIXBUF_VALID_r[0]) begin
            bmp_flush_buf_r <= 0;
            bmp_flush_rmw_r <= ~&PIXBUF_VALID_r[0];

            BMP_STATE <= &PIXBUF_VALID_r[0] ? ST_BMP_FLUSH_WRITE : ST_BMP_FLUSH_READ;
          end
          // check if buffer1 is valid and flush
          else if (|PIXBUF_VALID_r[1]) begin
            bmp_flush_buf_r <= 1;
            bmp_flush_rmw_r <= ~&PIXBUF_VALID_r[1];

            BMP_STATE <= &PIXBUF_VALID_r[1] ? ST_BMP_FLUSH_WRITE : ST_BMP_FLUSH_READ;
          end
          // perform fill
          else begin
            BMP_STATE <= ST_BMP_FILL;
          end
        end
      end
      ST_BMP_FLUSH_READ: begin
        // perform next read
        if (bmp_waitcnt_r == 0) begin
          b2c_waitcnt_val_r <= 1;
          b2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.

          // address common between read and write
          bmp_addr_r <= 24'hE00000 + bmp_char_shift_r[bmp_flush_buf_r] + {SCBR_r,10'h000} + {bmp_y_r[bmp_flush_buf_r][2:0],1'b0} + {bmp_plane_r[2:1], 3'b000, bmp_plane_r[0]};

          // read
          bmp_ram_rd_r <= 1;
          bmp_word_r <= 0;
          
          BMP_STATE <= ST_BMP_FLUSH_READ_WAIT;
        end
      end
      ST_BMP_FLUSH_READ_WAIT: begin        
        b2c_waitcnt_val_r <= 0;

        if (|(RAM_STATE & ST_RAM_BMP_END)) begin
          bmp_ram_rd_r <= 0;
          
          // collect data
          bmp_flush_colr_r <= ram_bus_data_r[7:0];
          
          BMP_STATE <= ST_BMP_FLUSH_WRITE;
        end
      end
      ST_BMP_FLUSH_WRITE: begin
        // perform next write
        if (bmp_waitcnt_r == 0) begin
          b2c_waitcnt_val_r <= 1;
          b2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.

          // address common between read and write
          bmp_addr_r <= 24'hE00000 + bmp_char_shift_r[bmp_flush_buf_r] + {SCBR_r,10'h000} + {bmp_y_r[bmp_flush_buf_r][2:0],1'b0} + {bmp_plane_r[2:1], 3'b000, bmp_plane_r[0]};

          // write
          bmp_ram_wr_r <= 1;
          bmp_word_r <= 0;
          bmp_data_r <= ({PIXBUF_r[bmp_flush_buf_r][7][bmp_plane_r],PIXBUF_r[bmp_flush_buf_r][6][bmp_plane_r],PIXBUF_r[bmp_flush_buf_r][5][bmp_plane_r],PIXBUF_r[bmp_flush_buf_r][4][bmp_plane_r],
                          PIXBUF_r[bmp_flush_buf_r][3][bmp_plane_r],PIXBUF_r[bmp_flush_buf_r][2][bmp_plane_r],PIXBUF_r[bmp_flush_buf_r][1][bmp_plane_r],PIXBUF_r[bmp_flush_buf_r][0][bmp_plane_r]} & PIXBUF_VALID_r[bmp_flush_buf_r])
                        | (bmp_flush_colr_r & ~PIXBUF_VALID_r[bmp_flush_buf_r]);
          
          BMP_STATE <= ST_BMP_FLUSH_WRITE_WAIT;
        end
      end
      ST_BMP_FLUSH_WRITE_WAIT: begin
        b2c_waitcnt_val_r <= 0;

        // test for end
        if (|(RAM_STATE & ST_RAM_BMP_END)) begin
          bmp_ram_wr_r <= 0;
          
          if (bmp_plane_r == bmp_bppm1_r) begin
            // invalidate
            PIXBUF_VALID_r[bmp_flush_buf_r] <= 0;
            bmp_plane_r <= 0;
            
            if (bmp_mode_r == BMP_MODE_PLOT) begin
              // flush done, perform write
              BMP_STATE <= ST_BMP_END;
            end
            else if (~bmp_flush_buf_r & |PIXBUF_VALID_r[1]) begin
              bmp_flush_buf_r <= 1;
              bmp_flush_rmw_r <= ~&PIXBUF_VALID_r[1];

              BMP_STATE <= &PIXBUF_VALID_r[1] ? ST_BMP_FLUSH_WRITE : ST_BMP_FLUSH_READ;
            end
            else begin
              BMP_STATE <= ST_BMP_FILL;
            end
          end
          else begin
            // continue flush
            bmp_plane_r <= bmp_plane_r + 1;
            
            BMP_STATE <= bmp_flush_rmw_r ? ST_BMP_FLUSH_READ : ST_BMP_FLUSH_WRITE;
          end
        end
      end
      ST_BMP_FILL: begin
        // generate next read
        if (bmp_waitcnt_r == 0) begin
          b2c_waitcnt_val_r <= 1;
          b2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.

          // address common between read and write
          bmp_addr_r <= 24'hE00000 + bmp_rpix_char_shift_r + {SCBR_r,10'h000} + {bmp_rpix_y_r[2:0],1'b0} + {bmp_plane_r[2:1], 3'b000, bmp_plane_r[0]};

          // read
          bmp_ram_rd_r <= 1;
          bmp_word_r <= 0;
          
          BMP_STATE <= ST_BMP_FILL_WAIT;
        end
      end
      ST_BMP_FILL_WAIT: begin
        b2c_waitcnt_val_r <= 0;

        if (|(RAM_STATE & ST_RAM_BMP_END)) begin
          bmp_ram_rd_r <= 0;

          bmp_plane_r <= bmp_plane_r + 1;
          
          // collect data
          bmp_colr_r[bmp_plane_r] <= ram_bus_data_r[bmp_index_r];
          
          BMP_STATE <= bmp_plane_r == bmp_bppm1_r ? ST_BMP_END : ST_BMP_FILL;
        end
      end
      ST_BMP_END: begin
        if (bmp_mode_r == BMP_MODE_PLOT) begin
          // write color and offset
          PIXBUF_OFFSET_r[0]             <= bmp_offset_r;
          PIXBUF_r[0][bmp_index_r]       <= bmp_colr_r;
          
          // swap buffer if valid.  The only way to get here is:
          // 1) 0 is empty
          // 2) offset was same
          // 3) offset was different 0 is nonempty and 1 is empty (due to flush or start state)
          if (PIXBUF_OFFSET_r[0] != e2b_offset_r && |PIXBUF_VALID_r[0]) begin
            // copy over buffer if (3)
            PIXBUF_VALID_r[1]  <= PIXBUF_VALID_r[0];
            PIXBUF_OFFSET_r[1] <= PIXBUF_OFFSET_r[0];
            for (i = 0; i < 8; i = i + 1) PIXBUF_r[1][i] <= PIXBUF_r[0][i];
            
            PIXBUF_VALID_r[0] <= bmp_index_bit_r;
          end
          else begin
            PIXBUF_VALID_r[0] <= PIXBUF_VALID_r[0] | bmp_index_bit_r;
          end
        end
        // RPIX gets the data directly from the local color register
      
        // signal completion to EXE
        BMP_STATE <= ST_BMP_IDLE;
      end
    endcase
  end
end

//-------------------------------------------------------------------
// FETCH PIPELINE
//-------------------------------------------------------------------
// The frontend of the pipeline starts with the fetch operation which
// is pipelined relative to execute and operates a clock ahead.

// The cache holds instructions to execute and is accesible by the GSU
// using a PC of 0-$1FF.  It is true dual port to support debug reads
// and writes.

// The fetch pipeline is composed primarily of the cache lookup state machine
// which can access the cache once per GSU clock.  It synchronizes with the
// 4x FPGA clock and the execution pipeline.  It does this 
// - Cache hit
// - ROM fill (into cache if offset)
parameter
  ST_FETCH_IDLE      = 8'b00000001,
  ST_FETCH_ADDR      = 8'b00000010,
  ST_FETCH_CACHE     = 8'b00000100,
  ST_FETCH_HIT       = 8'b00001000,
  ST_FETCH_FILL      = 8'b00010000,
  ST_FETCH_FILL_WAIT = 8'b00100000,
  ST_FETCH_WRITE     = 8'b01000000,
  ST_FETCH_WAIT      = 8'b10000000
  ;
reg [7:0] FETCH_STATE; initial FETCH_STATE = ST_FETCH_IDLE;

// Fetch operations
// - Check if cache hit (use valid bits) or !cache address
// - if miss or no allocate then load miss pipeline
// - read data out of cache or from fill
// - wait for cycles to expire and edge

// TODO: Fix cache index calculation.
// TODO: Add snes cache injection

reg         fetch_wait_r;
reg [7:0]   fetch_data_r;

reg         fetch_cache_match_r;

reg         fetch_install_val_r;
reg [5:0]   fetch_install_block_r;

// debug
reg         fetch_cache_comp_r;
reg         fetch_error;
reg [7:0]   fetch_cache_data_r;

always @(posedge CLK) begin
  if (RST) begin
    FETCH_STATE <= ST_FETCH_IDLE;
  
    cache_val_r <= 0;
    
    i2c_waitcnt_val_r <= 0;
    cache_rom_rd_r <= 0;
    cache_ram_rd_r <= 0;
    fetch_wait_r <= 0;
    
    fetch_data_r <= `OP_NOP;
    
    fetch_install_val_r <= 0;
    fetch_error <= 0;
  end
  else begin
    // handle cache valid bits
    // Make sure not to invalidate the cache until after the operation to avoid deadlock with cache fill->invalidate->cache lookup->cache fill
    if ((e2i_flush_r & pipeline_advance) | (r2i_flush_r & idle_r)) begin
      // pulsed for one clock
      cache_val_r <= 0;
    end
    else if (fetch_install_val_r) begin
      // demand fill
      cache_val_r[fetch_install_block_r] <= 1;
    end
    else if (cache_mmio_wren_r & &cache_mmio_addr_r[3:0]) begin
      // cache line injection
      cache_val_r[cache_mmio_addr_r[8:4]] <= 1;
    end
  
    case (FETCH_STATE)
      ST_FETCH_IDLE: begin
        // align to GSU clock
        if (SFR_GO & gsu_clock_en) begin
          FETCH_STATE <= ST_FETCH_ADDR;
        end

        // TODO: decide what we do if clear the GO bit vs STOP.  Clearing the GO bit we need to insert NOPs, but is it safe
        // to do that for STOP which may have some weird op hidden in the delay slot for next execution?
        fetch_data_r <= `OP_NOP;
        fetch_install_val_r <= 0;
      end
      ST_FETCH_ADDR: begin
        // address for cache // FIXME: cache seems to corrupt something
        fetch_cache_comp_r <= 0;
        
        fetch_install_val_r <= 0;
        fetch_cache_match_r <= (REG_r[R15][15:0] - CBR_r) < 512;
        cache_gsu_addr_r    <= {~REG_r[R15][8],REG_r[R15][7:0]};

        cache_addr_r <= (PBR_r < 8'h60) ? ((PBR_r[6] ? {PBR_r,REG_r[R15]} : {PBR_r[4:0],REG_r[R15][14:0]}) & ROM_MASK)
                                        : 24'hE00000 + ({PBR_r[4:0],REG_r[R15]} & SAVERAM_MASK);
        
        FETCH_STATE <= ST_FETCH_CACHE;
      end
      ST_FETCH_CACHE: begin
        // transition based on hit/miss
        debug_inst_addr_r <= cache_addr_r;

        if (fetch_cache_match_r & cache_val_r[cache_gsu_addr_r[8:4]]) begin
          // FIXME: need to put this 2 cycles before WAIT
          i2c_waitcnt_val_r <= 1;
          i2c_waitcnt_r     <= lat_fetch_r;

          FETCH_STATE <= ST_FETCH_HIT;
        end
        else begin
          // align cache address if we are going to install
          if (fetch_cache_match_r) cache_addr_r[3:0] <= 0;
          // align with start of line
          cache_gsu_addr_r[3:0] <= 0;

          FETCH_STATE <= ST_FETCH_FILL;
        end
        
      end
      ST_FETCH_HIT: begin
        // get data from cache.  Looks like it takes 2 cycles to read out of a true dual port??
        fetch_data_r <= cache_rddata;
        fetch_cache_data_r <= cache_rddata;

        // FIXME: temp to test cache
        //fetch_cache_match_r <= 0;
        //FETCH_STATE <= ST_FETCH_FILL;
        //fetch_cache_comp_r <= 1;
        
        FETCH_STATE <= ST_FETCH_WAIT;
        fetch_wait_r <= 1;
      end
      ST_FETCH_FILL: begin
        // TODO: check for elapsed time and perform access.
        // FIXME: need to handle delays better.  This has different behavior for cache fill vs standard fill.
        if (fetch_waitcnt_r == 0) begin
          cache_rom_rd_r <= (PBR_r < 8'h60);
          cache_ram_rd_r <= (PBR_r >= 8'h60);
          cache_word_r <= 1;
          
          i2c_waitcnt_val_r <= 1;
          i2c_waitcnt_r     <= lat_memory_r;
          FETCH_STATE       <= ST_FETCH_FILL_WAIT;
        end
      end
      ST_FETCH_FILL_WAIT: begin
        i2c_waitcnt_val_r <= 0;
        
        // check for end and install in cache
        if (|(ROM_STATE & ST_ROM_FETCH_END) | |(RAM_STATE & ST_RAM_FETCH_END)) begin
          cache_rom_rd_r <= 0;
          cache_ram_rd_r <= 0;
          fetch_data_r <= cache_rom_rd_r ? rom_bus_data_r : ram_bus_data_r;
          
          if (~fetch_cache_match_r) begin          
            FETCH_STATE <= ST_FETCH_WAIT;
            fetch_wait_r <= 1;
          end
          else begin
            // allocate byte in cache
            cache_gsu_wren_r <= 1;
            cache_gsu_wrdata_r <= cache_rom_rd_r ? rom_bus_data_r : ram_bus_data_r;

            FETCH_STATE <= ST_FETCH_WRITE;
          end
        end
      end
      ST_FETCH_WRITE: begin
        cache_gsu_wren_r    <= 0;
        cache_addr_r[3:0] <= cache_addr_r[3:0] + 1; // TODO: could install 16b if we wanted.  Also fix address compare above
        
        if (&cache_addr_r[3:0]) begin
          FETCH_STATE <= ST_FETCH_ADDR; // Go back and check the cache.  FIXME: Is this going to be a problem when GO bit is cleared by the SNES?

          fetch_install_val_r <= 1;
          fetch_install_block_r <= cache_gsu_addr_r[8:4];          
        end
        else begin
          FETCH_STATE <= ST_FETCH_FILL;
          cache_gsu_addr_r[3:0] <= cache_gsu_addr_r[3:0] + 1;
        end
      end
      ST_FETCH_WAIT: begin
        i2c_waitcnt_val_r <= 0;
        
        if (fetch_cache_comp_r) begin
          fetch_error <= fetch_error || (fetch_cache_data_r != fetch_data_r);
        end
        
        if (pipeline_advance) begin
          fetch_wait_r <= 0;

          if (e2r_g_r) FETCH_STATE <= ST_FETCH_ADDR;
          else         FETCH_STATE <= ST_FETCH_IDLE;
        end
      end
    endcase
  end
end

//-------------------------------------------------------------------
// EXECUTION PIPELINE
//-------------------------------------------------------------------
parameter
  ST_EXE_IDLE        = 8'b00000001,
  
  ST_EXE_DECODE      = 8'b00000010,
  ST_EXE_REGREAD     = 8'b00000100,
  ST_EXE_EXECUTE     = 8'b00001000,
  ST_EXE_MEMORY      = 8'b00010000,
  ST_EXE_MEMORY_WAIT = 8'b00100000,
  ST_EXE_WAIT        = 8'b01000000
  ;
reg [7:0]  EXE_STATE; initial EXE_STATE = ST_EXE_IDLE;

reg        exe_branch_r;

reg [7:0]  exe_opcode_r;
reg        exe_operand_valid_r;
reg [15:0] exe_operand_r;
reg [1:0]  exe_opsize_r;
reg [15:0] exe_src_r;
reg [15:0] exe_dst_r;
reg [15:0] exe_srcn_r;
reg        exe_alt1_r;
reg        exe_alt2_r;
reg        exe_cy_r;
reg [15:0] exe_fmult_srca_r;
reg [15:0] exe_fmult_srcb_r;
reg [7:0]  exe_mult_srca_r;
reg [7:0]  exe_mult_srcb_r;
reg [7:0]  exe_umult_srca_r;
reg [7:0]  exe_umult_srcb_r;
reg [7:0]  exe_colr_r;
reg        exe_zs_r;

reg [15:0] exe_n;
reg [15:0] exe_result;
reg        exe_carry;

wire [31:0] exe_fmult_out;
wire [15:0] exe_mult_out;
wire [15:0] exe_umult_out;

reg [7:0]  exe_byte_r;
reg [15:0] exe_plot_offset_r;
reg [2:0]  exe_plot_index_r;
reg        exe_plot_mem_r;

reg        exe_error;

always @(posedge CLK) begin
  if (RST) begin
    EXE_STATE <= ST_EXE_IDLE;
    
    e2r_alt_r  <= 0;
    e2r_sreg_r <= 0;
    e2r_dreg_r <= 0;
    e2r_z_r    <= 0;
    e2r_cy_r   <= 0;
    e2r_s_r    <= 0;
    e2r_ov_r   <= 0;
    e2r_b_r    <= 0;
    e2r_g_r    <= 0;
    e2r_irq_r  <= 0;

    e2r_val_r <= 0;
    e2r_loop_r <= 0;
    e2r_wpbr_r <= 0;
    e2r_wcbr_r <= 0;
    e2r_lmult_r <= 0;
    e2r_wpor_r <= 0;
    e2r_wcolr_r <= 0;
    exe_zs_r <= 0;
    
    e2r_data_r <= 0;
    e2r_data_pre_r <= 0;
    e2r_r15_r <= 0;
    e2r_r4_r <= 0;
    
    exe_branch_r <= 0;
    exe_opcode_r <= `OP_NOP;
    exe_byte_r <= 0;
    exe_opsize_r <= 0;
    exe_operand_r <= 0;
    exe_operand_valid_r <= 0;    

    exe_addr_r <= 0;
    e2c_waitcnt_val_r <= 0;
    exe_ram_rd_r <= 0;
    exe_ram_wr_r <= 0;

    e2b_plot_r  <= 0;
    e2b_rpix_r  <= 0;
    
    e2i_flush_r <= 0;
    
    exe_error <= 0;
    
    ROMBR_r <= 0;
    RAMBR_r <= 0;
  end
  else begin
    case (EXE_STATE)
      ST_EXE_IDLE: begin
        // align to GSU clock.  Sinks up with fetch.
        if (SFR_GO & gsu_clock_en) begin
          EXE_STATE <= ST_EXE_DECODE;
        end
        
        // handle snes write reg data
        //e2r_data_r <= {data_in_r,data_flop_r};
        //e2r_destnum_r <= addr_in_r[4:1];
      end
      ST_EXE_DECODE: begin
        if (~|exe_opsize_r) begin      
          exe_zs_r <= 0;

          // calculate operands
          case (exe_opcode_r)
            `OP_BRA,`OP_BGE,`OP_BLT,`OP_BNE,`OP_BEQ,`OP_BPL,`OP_BMI,`OP_BCC,`OP_BCS,`OP_BVC,`OP_BVS : exe_opsize_r <= 2;
            `OP_IBT: exe_opsize_r <= 2;
            `OP_IWT: exe_opsize_r <= 3;
            default: exe_opsize_r <= 1;
          endcase

          // handle prefixes
          case (exe_opcode_r)
            `OP_BRA           : exe_branch_r <= 1;
            `OP_BGE           : exe_branch_r <= ( SFR_S == SFR_OV);
            `OP_BLT           : exe_branch_r <= ( SFR_S != SFR_OV);
            `OP_BNE           : exe_branch_r <= (~SFR_Z);   
            `OP_BEQ           : exe_branch_r <= ( SFR_Z);
            `OP_BPL           : exe_branch_r <= (~SFR_S);
            `OP_BMI           : exe_branch_r <= ( SFR_S);
            `OP_BCC           : exe_branch_r <= (~SFR_CY);
            `OP_BCS           : exe_branch_r <= ( SFR_CY);
            `OP_BVC           : exe_branch_r <= (~SFR_OV);
            `OP_BVS           : exe_branch_r <= ( SFR_OV);
            
            `OP_ALT1          : begin e2r_alt_r <= 1; e2r_b_r <= 0; end
            `OP_ALT2          : begin e2r_alt_r <= 2; e2r_b_r <= 0; end
            `OP_ALT3          : begin e2r_alt_r <= 3; e2r_b_r <= 0; end
            `OP_TO            : if (~SFR_B) e2r_dreg_r <= exe_opcode_r[3:0];
            `OP_WITH          : begin e2r_sreg_r <= exe_opcode_r[3:0]; e2r_dreg_r <= exe_opcode_r[3:0]; e2r_b_r <= 1; end
            `OP_FROM          : if (~SFR_B) e2r_sreg_r <= exe_opcode_r[3:0];
            
            default           : begin e2r_alt_r <= 0; e2r_sreg_r <= 0; e2r_dreg_r <= 0; e2r_b_r <= 0; end
          endcase
          
          // generate dithered color value for PLOT
          if (exe_opcode_r == `OP_PLOT_RPIX) begin
            if (~SFR_ALT1 & POR_DTH & ~&SCMR_MD) begin
              exe_colr_r <= {4'h0, ((REG_r[R1][0] ^ REG_r[R2][0]) ? COLR_r[7:4] : COLR_r[3:0])};
            end
            else begin
              exe_colr_r <= COLR_r;
            end
          end

        end
        else begin
          exe_operand_valid_r <= 1;
          exe_operand_r <= exe_operand_valid_r ? {exe_byte_r,exe_operand_r[7:0]} : {8'h00,exe_byte_r};
        end

        // get previous values for defaults
        e2r_z_r    <= SFR_Z;
        e2r_cy_r   <= SFR_CY;
        e2r_s_r    <= SFR_S;
        e2r_ov_r   <= SFR_OV;
        //e2r_b_r    <= SFR_B;
        e2r_g_r    <= SFR_GO;
        e2r_irq_r  <= SFR_IRQ;
        
        // get default destination
        e2r_destnum_r <= DREG_r;
        e2r_r15_r <= REG_r[R15];
        
        exe_alt1_r <= SFR_ALT1;
        exe_alt2_r <= SFR_ALT2;
        exe_cy_r   <= SFR_CY;
        // get register sources
        exe_src_r <= REG_r[SREG_r];
        //exe_dst_r <= REG_r[DREG_r];
        exe_srcn_r <= REG_r[exe_opcode_r[3:0]];
       
        exe_plot_offset_r <= {REG_r[R2][7:0],5'h00} + REG_r[R1][7:3];
        exe_plot_index_r  <= ~REG_r[R1][2:0];
                
        EXE_STATE <= ST_EXE_EXECUTE;
      end
      ST_EXE_EXECUTE: begin
        if (op_complete) begin
          case (exe_opcode_r)
            `OP_BRA,`OP_BGE,`OP_BLT,`OP_BNE,`OP_BEQ,`OP_BPL,`OP_BMI,`OP_BCC,`OP_BCS,`OP_BVC,`OP_BVS: begin
              if (exe_branch_r) begin
                // calculate branch target
                e2r_val_r <= 1;
                e2r_destnum_r <= R15;
                e2r_data_pre_r <= e2r_r15_r + {{8{exe_operand_r[7]}},exe_operand_r[7:0]};
          
                exe_branch_r <= 0;
              end
            end          
            `OP_STOP           : begin
              // TODO: deal with interrupts and other stuff here
              e2r_g_r <= 0;
              e2r_irq_r <= 1;
            end
            //OP_NOP            : begin end
            `OP_CACHE          : begin
              if (e2r_r15_r[15:4] != CBR_r[15:4]) begin
                e2r_wcbr_r  <= 1;
                e2r_cbr_r[15:4] <= e2r_r15_r[15:4];
                e2i_flush_r <= 1;
              end
            end

            `OP_TO            : begin
              if (SFR_B) begin
                e2r_val_r  <= 1;
                e2r_destnum_r <= exe_opcode_r[3:0]; // uses N as destination
                e2r_data_pre_r <= exe_src_r;
                
                // reset
                e2r_alt_r <= 0; e2r_sreg_r <= 0; e2r_dreg_r <= 0; e2r_b_r <= 0;
              end
            end
            `OP_WITH          : begin end
            `OP_FROM          : begin
              if (SFR_B) begin
                exe_result = exe_srcn_r; // uses N as source

                e2r_val_r  <= 1;
                e2r_data_pre_r <= exe_result;

                exe_zs_r <= 1;
                //e2r_z_r    <= ~|exe_result;
                //e2r_s_r    <= exe_result[15];
                e2r_ov_r   <= exe_result[7];

                // reset
                e2r_alt_r <= 0; e2r_sreg_r <= 0; e2r_dreg_r <= 0; e2r_b_r <= 0;
              end
            end
            
            `OP_LOOP           : begin
              exe_result = REG_r[R12] - 1;
              
              e2r_val_r  <= 1;
              e2r_destnum_r <= R12;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
              
              e2r_loop_r <= REG_r[R12] != 1;
            end

            `OP_CMODE_COLOR    : begin
              if (exe_alt1_r) begin
                e2r_wpor_r <= 1;
                e2r_por_r  <= {3'h0,exe_src_r[4:0]};
              end
              else begin
                e2r_wcolr_r <= 1;
                e2r_colr_r  <= POR_HN ? {COLR_r[7:4],exe_src_r[7:4]} : POR_FHN ? {COLR_r[7:4],exe_src_r[3:0]} : exe_src_r[7:0];
              end
            end
            `OP_PLOT_RPIX      : begin
              if (exe_alt1_r) begin
                // RPIX
                e2r_val_r    <= 1;
                
                // generate rpixel
                e2b_rpix_r   <= 1;
                e2b_offset_r <= exe_plot_offset_r;
                e2b_index_r  <= exe_plot_index_r;
              end
              else begin
                // PLOT
                e2r_val_r      <= 1;
                e2r_destnum_r  <= R1;
                e2r_data_pre_r <= REG_r[R1] + 1;
                
                // generate plot - skip if transparent
                //e2b_plot_r     <= POR_TRS || ((SCMR_MD == 3) ? (POR_FHN ? (exe_colr_r[3:0] != 0) : (exe_colr_r != 0)) : (exe_colr_r[3:0] != 0));
                e2b_plot_r     <= POR_TRS || ((SCMR_MD != 3 || POR_FHN) ? (exe_colr_r[3:0] != 0) : (exe_colr_r != 0));
                exe_plot_mem_r <= (PIXBUF_OFFSET_r[0] != exe_plot_offset_r) && (|PIXBUF_VALID_r[0] && |PIXBUF_VALID_r[1]);
                
                e2b_offset_r   <= exe_plot_offset_r;
                e2b_index_r    <= exe_plot_index_r;
                e2b_colr_r     <= exe_colr_r;
              end
            end

            // ALU
            `OP_ADD          : begin 
              exe_n      = exe_alt2_r ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
              {exe_carry,exe_result} = exe_src_r + exe_n + (exe_alt1_r & exe_cy_r);
              
              e2r_val_r <= 1;
              // e2r_destnum_r <= DREG_r; // standard dest
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
              e2r_ov_r   <= (exe_src_r[15] ^ exe_result[15]) & (exe_n[15] ^ exe_result[15]);
              e2r_cy_r   <= exe_carry;
            end
            `OP_SUB          : begin
              exe_n      = (~exe_alt1_r & exe_alt2_r) ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
              {exe_carry,exe_result} = exe_src_r - exe_n - (exe_alt1_r & ~exe_alt2_r & ~exe_cy_r);
              
              // CMP doesn't output the result
              e2r_val_r <= ~(exe_alt1_r & exe_alt2_r);
              // e2r_destnum_r <= DREG_r; // standard dest
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
              e2r_ov_r   <= (exe_src_r[15] ^ exe_result[15]) & (exe_src_r[15] ^ exe_n[15]);
              e2r_cy_r   <= ~exe_carry;
            end
            `OP_AND_BIC      : begin
              exe_n      = exe_alt2_r ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
              exe_result = exe_src_r & (exe_alt1_r ? ~exe_n : exe_n);
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
            end
            `OP_OR_XOR       : begin
              exe_n      = exe_alt2_r ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
              exe_result = exe_alt1_r ? exe_src_r ^ exe_n : exe_src_r | exe_n;
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
            end
            `OP_NOT           : begin
              exe_result = ~exe_src_r;
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
            end
            
            // ROTATE/SHIFT/INC/DEC
            `OP_LSR           : begin
              exe_result = {1'b0,exe_src_r[15:1]};
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
              e2r_cy_r   <= exe_src_r[0];
            end
            `OP_ASR_DIV2      : begin
              exe_result = (exe_alt1_r & (&exe_src_r))? 0 : {exe_src_r[15],exe_src_r[15:1]};
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
              e2r_cy_r   <= exe_src_r[0];
            end
            `OP_ROL           : begin
              exe_result = {exe_src_r[14:0],exe_cy_r};
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
              e2r_cy_r   <= exe_src_r[15];
            end
            `OP_ROR           : begin
              exe_result = {exe_cy_r,exe_src_r[15:1]};
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
              e2r_cy_r   <= exe_src_r[0];
            end
            
            // BYTE
            `OP_SWAP          : begin
              exe_result = {exe_src_r[7:0],exe_src_r[15:8]};
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
            end
            `OP_SEX           : begin
              exe_result = {{8{exe_src_r[7]}},exe_src_r[7:0]};
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
            end
            `OP_LOB           : begin
              exe_result = {8'h00,exe_src_r[7:0]};
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              e2r_z_r    <= ~|exe_result;
              e2r_s_r    <= exe_result[7];
            end
            `OP_HIB           : begin
              exe_result = {8'h00,exe_src_r[15:8]};
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
              
              e2r_z_r    <= ~|exe_result;
              e2r_s_r    <= exe_result[7];
            end
            `OP_MERGE         : begin
              exe_result = {REG_r[R7][15:8],REG_r[R8][15:8]};
              
              e2r_val_r  <= 1;
              e2r_data_pre_r <= exe_result;
            end
            
            // MULTIPLY
            `OP_FMULT_LMULT   : begin
              exe_fmult_srca_r <= exe_src_r;
              exe_fmult_srcb_r <= REG_r[R6];

              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r     <= lat_fmult_r; // TODO: account for slow clock and multiplier.
            end
            `OP_MULT         : begin
              exe_mult_srca_r <= exe_src_r;
              exe_mult_srcb_r <= exe_alt2_r ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;
              exe_umult_srca_r <= exe_src_r;
              exe_umult_srcb_r <= exe_alt2_r ? {12'h000, exe_opcode_r[3:0]} : exe_srcn_r;

              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r     <= lat_mult_r; // TODO: account for slow clock and multiplier.
            end
            
            `OP_GETC_RAMB_ROMB: begin
              if      (exe_alt1_r & exe_alt2_r)   ROMBR_r    <= exe_src_r;
              else if (exe_alt2_r)                RAMBR_r    <= exe_src_r[0];
            end
            `OP_INC          : begin
              exe_result = exe_srcn_r + 1;
              
              e2r_val_r  <= 1;
              e2r_destnum_r <= exe_opcode_r[3:0]; // uses N as destination                  
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
            end
            `OP_DEC          : begin
              exe_result = exe_srcn_r - 1;
              
              e2r_val_r  <= 1;
              e2r_destnum_r <= exe_opcode_r[3:0]; // uses N as destination
              e2r_data_pre_r <= exe_result;
              
              exe_zs_r <= 1;
              //e2r_z_r    <= ~|exe_result;
              //e2r_s_r    <= exe_result[15];
            end
            // LINK
            `OP_LINK         : begin
              exe_result = e2r_r15_r + exe_opcode_r[3:0];
                
              e2r_val_r  <= 1;
              e2r_destnum_r <= R11;
              e2r_data_pre_r <= exe_result;
            end
            // JMP/LJMP
            `OP_JMP_LJMP     : begin
              e2r_val_r <= 1;
              e2r_destnum_r <= R15;

              if (exe_alt1_r) begin
                // LJMP
                e2r_data_pre_r   <= exe_src_r;
                e2r_wpbr_r  <= 1; // write PBR with srcn
                e2r_pbr_r   <= exe_srcn_r;
                e2r_wcbr_r  <= 1;
                e2r_cbr_r[15:4]   <= exe_src_r[15:4];
                e2i_flush_r <= 1;
              end
              else begin
                // JMP
                e2r_data_pre_r   <= exe_srcn_r;
              end
            end
            
          endcase
        end

        EXE_STATE <= ST_EXE_MEMORY;
      end
      ST_EXE_MEMORY: begin
        if (op_complete) begin
          case (exe_opcode_r)
            `OP_PLOT_RPIX      : begin             
              // done with the operations
              e2b_plot_r <= 0;
              e2b_rpix_r <= 0;
              exe_plot_mem_r <= 0;
              e2r_data_r <= e2r_data_pre_r; // R1 for PLOT
              
              // if RPIX then wait for data return.  otherwise we need a quick exit for 1 GSU clock plot operations
              if (exe_alt1_r | (exe_plot_mem_r & e2b_plot_r)) begin
                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else begin
                EXE_STATE <= ST_EXE_WAIT;
              end
            end
            `OP_GETC_RAMB_ROMB: begin
              if (~exe_alt1_r & ~exe_alt2_r) begin
                //e2r_val_r    <= 1;
                e2r_wcolr_r <= 1;

                e2c_waitcnt_val_r <= 1;
                // TODO: add 16b cache latencies
                e2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.

                exe_rom_rd_r <= 1;
                exe_word_r <= 1; // load for cache

                exe_addr_r <= ((ROMBR_r[6] ? {ROMBR_r,REG_r[R14]} : {ROMBR_r[4:0],REG_r[R14][14:0]}) & ROM_MASK);

                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else begin
                EXE_STATE <= ST_EXE_WAIT;
              end
            end
            `OP_FMULT_LMULT   : begin
              e2r_val_r      <= 1;
              
              e2r_data_r     <= exe_fmult_out[31:16];
              e2r_r4_r       <= exe_fmult_out[15:0];
              e2r_lmult_r    <= exe_alt1_r;
              
              e2r_z_r        <= ~|exe_fmult_out[31:16];
              e2r_s_r        <= exe_fmult_out[31];
              e2r_cy_r       <= exe_fmult_out[15];
                            
              //EXE_STATE <= ST_EXE_MEMORY_WAIT;
              EXE_STATE <= ST_EXE_WAIT;
            end
            `OP_MULT         : begin
              exe_result = exe_alt1_r ? exe_umult_out : exe_mult_out;
            
              e2r_val_r      <= 1;
              
              e2r_data_r     <= exe_result;
              
              e2r_z_r        <= ~|exe_result;
              e2r_s_r        <= exe_result[15];
                            
              EXE_STATE <= ST_EXE_WAIT;
            end
          
            `OP_IBT          : begin
              if (exe_alt1_r) begin
                // LMS Rn, (2*imm8)
                //exe_memory = 1;
                e2r_val_r    <= 1;
                e2r_destnum_r   <= exe_opcode_r[3:0];
                 
                e2c_waitcnt_val_r <= 1;
                e2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.
          
                exe_ram_rd_r <= 1;
                exe_word_r <= 1;

                exe_addr_r <= {4'hE,3'h0,RAMBR_r,7'h00,exe_operand_r[7:0],1'b0};
                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else if (exe_alt2_r) begin
                // SMS (2*imm8), Rn                
                e2c_waitcnt_val_r <= 1;
                e2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.
          
                // TODO: this really does a byte at a time.
                // TODO: do we need to handle misaligned data in a special way?
                exe_ram_wr_r <= 1;
                exe_word_r <= 1;
                exe_data_r <= exe_srcn_r;

                exe_addr_r <= {4'hE,3'h0,RAMBR_r,7'h00,exe_operand_r[7:0],1'b0};
                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else begin
                e2r_val_r    <= 1;
                e2r_destnum_r   <= exe_opcode_r[3:0];
                e2r_data_r   <= {{8{exe_operand_r[7]}},exe_operand_r[7:0]};
                EXE_STATE <= ST_EXE_WAIT;
              end
            end
            `OP_IWT          : begin
              if (exe_alt1_r) begin
                // LM Rn, (imm)
                e2r_val_r    <= 1;
                e2r_destnum_r   <= exe_opcode_r[3:0];

                e2c_waitcnt_val_r <= 1;
                e2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.
          
                exe_ram_rd_r <= 1;
                exe_word_r <= 1;

                exe_addr_r <= {4'hE,3'h0,RAMBR_r,exe_operand_r};
                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else if (exe_alt2_r) begin
                // SM (imm), Rn
                e2c_waitcnt_val_r <= 1;
                e2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.
          
                // TODO: this really does a byte at a time.
                // TODO: do we need to handle misaligned data in a special way?
                exe_ram_wr_r <= 1;
                exe_word_r <= 1;
                exe_data_r <= exe_srcn_r;

                exe_addr_r <= {4'hE,3'h0,RAMBR_r,exe_operand_r};
                EXE_STATE <= ST_EXE_MEMORY_WAIT;
              end
              else begin
                e2r_val_r    <= 1;
                e2r_destnum_r   <= exe_opcode_r[3:0];
                e2r_data_r   <= exe_operand_r;
                EXE_STATE <= ST_EXE_WAIT;
              end
            end
            `OP_GETB          : begin
              e2r_val_r    <= 1;

              e2c_waitcnt_val_r <= 1;
              // TODO: add 16b cache latencies
              e2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.

              // TODO: decide if we need separate state machines for this
              exe_rom_rd_r <= 1;
              exe_word_r <= 1;

              exe_addr_r <= ((ROMBR_r[6] ? {ROMBR_r,REG_r[R14]} : {ROMBR_r[4:0],REG_r[R14][14:0]}) & ROM_MASK);

              EXE_STATE <= ST_EXE_MEMORY_WAIT;
              //EXE_STATE <= ST_EXE_WAIT;
            end
            `OP_SBK           : begin
              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r <= lat_memory_r; // TODO: account for slow clock.
          
              // TODO: this really does a byte at a time.
              // TODO: do we need to handle misaligned data in a special way?
              exe_ram_wr_r <= 1;
              exe_word_r <= 1;
              exe_data_r <= exe_src_r;

              exe_addr_r <= {8'hE0,RAMADDR_r};
              EXE_STATE <= ST_EXE_MEMORY_WAIT;
            end
            `OP_LD           : begin
              e2r_val_r    <= 1;
                 
              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r <= exe_alt1_r ? lat_memory_r : lat_memory_r;

              exe_ram_rd_r <= 1;
              exe_word_r <= ~exe_alt1_r;

              exe_addr_r <= {4'hE,3'h0,RAMBR_r,exe_srcn_r};

              EXE_STATE <= ST_EXE_MEMORY_WAIT;
              //EXE_STATE <= ST_EXE_WAIT;
            end
            `OP_ST           : begin
              e2c_waitcnt_val_r <= 1;
              e2c_waitcnt_r <= exe_alt1_r ? lat_memory_r-1 : lat_memory_r-1; // TODO: account for slow clock.

              exe_ram_wr_r <= 1;
              exe_word_r <= ~exe_alt1_r;
              exe_data_r <= exe_src_r;

              exe_addr_r <= {4'hE,3'h0,RAMBR_r,exe_srcn_r};

              EXE_STATE <= ST_EXE_MEMORY_WAIT;
              //EXE_STATE <= ST_EXE_WAIT;
            end
            // hopefully relax timing by setting some condition codes here
            `OP_MERGE         : begin
              e2r_z_r    <= |({e2r_data_pre_r[15:12],e2r_data_pre_r[7:4]});
              e2r_ov_r   <= |({e2r_data_pre_r[15:14],e2r_data_pre_r[7:6]});
              e2r_s_r    <= |({e2r_data_pre_r[15:15],e2r_data_pre_r[7:7]});
              e2r_cy_r   <= |({e2r_data_pre_r[15:13],e2r_data_pre_r[7:5]});

              e2r_data_r <= e2r_data_pre_r;
              EXE_STATE <= ST_EXE_WAIT;
            end
            default: begin
              if (exe_zs_r) begin
                e2r_z_r    <= ~|e2r_data_pre_r;
                e2r_s_r    <= e2r_data_pre_r[15];
                exe_zs_r   <= 0;
              end
            
              e2r_data_r <= e2r_data_pre_r;
              EXE_STATE <= ST_EXE_WAIT;
            end
          endcase
        end
        else begin
          e2r_data_r <= e2r_data_pre_r;
          EXE_STATE <= ST_EXE_WAIT;
        end
      end
      ST_EXE_MEMORY_WAIT: begin
        e2c_waitcnt_val_r <= 0;
        
        if ((|(ROM_STATE & ST_ROM_DATA_END)) | (|(RAM_STATE & ST_RAM_DATA_END)) | (|(BMP_STATE & ST_BMP_END))) begin
          exe_rom_rd_r <= 0;
          exe_ram_rd_r <= 0;
          exe_ram_wr_r <= 0;
          // byte loads do zero extension
          
          case (exe_opcode_r)
            `OP_GETB: begin
              e2r_data_r <= (exe_alt1_r & exe_alt2_r) ? {{8{rom_bus_data_r[7]}},rom_bus_data_r[7:0]} : exe_alt2_r ? {exe_src_r[15:8],rom_bus_data_r[7:0]} : exe_alt1_r ? {rom_bus_data_r[7:0],exe_src_r[7:0]} : {8'h00,rom_bus_data_r[7:0]};
            end
            `OP_GETC_RAMB_ROMB: begin
              if (~exe_alt1_r & ~exe_alt2_r) begin
                e2r_colr_r  <= POR_HN ? {COLR_r[7:4],rom_bus_data_r[7:4]} : POR_FHN ? {COLR_r[7:4],rom_bus_data_r[3:0]} : rom_bus_data_r[7:0];
              end
            end
            `OP_PLOT_RPIX: begin
              // RPIX reads data
              if (exe_alt1_r) begin
                e2r_data_r <= {8'h00, bmp_colr_r};

                e2r_z_r    <= ~|bmp_colr_r;
                e2r_s_r    <= 0; // sign bit is always 0
              end
            end
            default: begin
              e2r_data_r <= exe_word_r ? ram_bus_data_r[15:0] : {8'h00,ram_bus_data_r[7:0]};
            end
          endcase

          EXE_STATE <= ST_EXE_WAIT;
        end
      end
      ST_EXE_WAIT: begin
        e2c_waitcnt_val_r <= 0;
        if (gsu_clock_en) e2r_lmult_r <= 0;
        
        if (pipeline_advance) begin
          if (|exe_opsize_r) exe_opsize_r <= exe_opsize_r - 1;
        
          if (e2r_g_r) EXE_STATE <= ST_EXE_DECODE;
          else         EXE_STATE <= ST_EXE_IDLE;
                    
          if (op_complete) begin
            // get next instruction byte
            exe_branch_r <= 0;
            exe_opcode_r <= fetch_data_r;//i2e_op_r[~i2e_ptr_r];
            exe_operand_r <= 0;
            exe_operand_valid_r <= 0;
            exe_zs_r <= 0;

            e2r_val_r  <= 0;
            e2r_loop_r <= 0;
            e2r_wpbr_r <= 0;
            e2r_wcbr_r <= 0;
            e2r_wpor_r <= 0;
            e2r_wcolr_r <= 0;
            
            // deassert flush
            e2i_flush_r <= 0;
          end
          
          exe_byte_r <= fetch_data_r;
        end
      end
      
    endcase
  end
end

// breakpoints
reg      brk_inst_rd_rom_m1;
reg      brk_inst_rd_ram_m1;
reg      brk_data_rd_rom_m1;
reg      brk_data_rd_ram_m1;
reg      brk_data_wr_ram_m1;

reg [23:0] brk_addr_r;

always @(posedge CLK) begin
  if (RST) begin
    brk_inst_rd_rom_m1 <= 0;
    brk_inst_rd_ram_m1 <= 0;
    brk_data_rd_rom_m1 <= 0;
    brk_data_rd_ram_m1 <= 0;
    brk_data_wr_ram_m1 <= 0;

    brk_inst_rd_byte <= 0;
    brk_data_rd_byte <= 0;
    brk_data_wr_byte <= 0;

    brk_inst_rd_addr <= 0;
    brk_data_rd_addr <= 0;
    brk_data_wr_addr <= 0;
    brk_stop         <= 0;
    brk_error        <= 0;
    
    brk_addr_r       <= 0;
  end
  else begin
    //brk_inst_rd_rom_m1 <= (|(ROM_STATE & ST_ROM_FETCH_RD)) && !rom_bus_rrq_r && ROM_BUS_RDY;
    //brk_inst_rd_ram_m1 <= (|(RAM_STATE & ST_RAM_FETCH_RD)) && !ram_bus_rrq_r && RAM_BUS_RDY;
    //brk_data_rd_rom_m1 <= (|(ROM_STATE & ST_ROM_DATA_RD)) && !rom_bus_rrq_r && ROM_BUS_RDY;
    //brk_data_rd_ram_m1 <= (|(RAM_STATE & ST_RAM_DATA_RD)) && !ram_bus_rrq_r && RAM_BUS_RDY;
    //brk_data_wr_ram_m1 <= (|(RAM_STATE & ST_RAM_DATA_WR)) && !ram_bus_wrq_r && RAM_BUS_RDY;

    //brk_inst_rd_byte <= pipeline_advance ? 0 : brk_inst_rd_rom_m1 ? (rom_bus_data_r == CONFIG_DATA_WATCH) : brk_inst_rd_ram_m1 ? (ram_bus_data_r == CONFIG_DATA_WATCH) : brk_inst_rd_byte;
    //brk_data_rd_byte <= pipeline_advance ? 0 : brk_data_rd_rom_m1 ? (rom_bus_data_r == CONFIG_DATA_WATCH) : brk_data_rd_ram_m1 ? (ram_bus_data_r == CONFIG_DATA_WATCH) : brk_data_rd_byte;
    //brk_data_wr_byte <= pipeline_advance ? 0                                                              : brk_data_wr_ram_m1 ? (RAMWRBUF_r     == CONFIG_DATA_WATCH) : brk_data_wr_byte;
  
    brk_inst_rd_addr <= (debug_inst_addr_r == brk_addr_r);
    brk_data_rd_addr <= (exe_ram_rd_r   && (exe_addr_r   == brk_addr_r) || (exe_rom_rd_r && (exe_addr_r   == brk_addr_r)));
    brk_data_wr_addr <= (exe_ram_wr_r   && (exe_addr_r   == brk_addr_r));
    brk_stop         <= exe_opcode_r == `OP_STOP;
    brk_error        <= fetch_error; // FIXME: set this state based on opcode or other error condition
    
  
    brk_addr_r <= (CONFIG_ADDR_WATCH[23:16] < 8'h60) ? ((CONFIG_ADDR_WATCH[22] ? CONFIG_ADDR_WATCH : {CONFIG_ADDR_WATCH[20:16],CONFIG_ADDR_WATCH[14:0]}) & ROM_MASK)
                                                     : 24'hE00000 + ({CONFIG_ADDR_WATCH[4:0],CONFIG_ADDR_WATCH[R15]} & SAVERAM_MASK);
  end
end

//assign pipeline_advance = gsu_clock_en & ~|fetch_waitcnt_r & ~|exe_waitcnt_r & |(EXE_STATE & ST_EXE_WAIT) & |(FETCH_STATE & ST_FETCH_WAIT) & (~CONFIG_STEP_ENABLED | (stepcnt_r != CONFIG_STEP_COUNT));
//assign pipeline_advance = gsu_clock_en & waitcnt_zero_r & |(EXE_STATE & ST_EXE_WAIT) & |(FETCH_STATE & ST_FETCH_WAIT) & (~CONFIG_STEP_ENABLED | (stepcnt_r != CONFIG_STEP_COUNT));
assign pipeline_advance = gsu_clock_en & waitcnt_zero & |(EXE_STATE & ST_EXE_WAIT) & fetch_wait_r & step_r;
assign op_complete = exe_opsize_r == 1;

// Multipliers
gsu_fmult gsu_fmult(
  //.clk(CLK),
  .a(exe_fmult_srca_r[15:0]),
  .b(exe_fmult_srcb_r[15:0]),
  .p(exe_fmult_out)
);

gsu_mult gsu_mult(
  //.clk(CLK),
  .a(exe_mult_srca_r[7:0]),
  .b(exe_mult_srcb_r[7:0]),
  .p(exe_mult_out)
);

gsu_umult gsu_umult(
  //.clk(CLK),
  .a(exe_umult_srca_r[7:0]),
  .b(exe_umult_srcb_r[7:0]),
  .p(exe_umult_out)
);

always @(posedge CLK) idle_r <= |(FETCH_STATE & ST_FETCH_IDLE) & |(EXE_STATE & ST_EXE_IDLE);

//-------------------------------------------------------------------
// DEBUG OUTPUT
//-------------------------------------------------------------------
reg [7:0]  pgmpre_out[3:0];
reg [7:0]  pgmdata_out; //initial pgmdata_out_r = 0;

`ifdef DEBUG
always @(posedge CLK) begin
  pgmdata_out <= pgmpre_out[pgm_addr_r[9:8]];

  case (pgm_addr_r[9:8])
    2'h0: case (pgm_addr_r[7:0])
      //ADDR_GPRL        : pgmpre_out[0] <= REG_r[pgm_addr_r[4:1]][7:0];
      //ADDR_GPRH        : pgmpre_out[0] <= REG_r[pgm_addr_r[4:1]][15:8];
      ADDR_R0          : pgmpre_out[0] <= REG_r[R0][7:0];
      ADDR_R0+1        : pgmpre_out[0] <= REG_r[R0][15:8];
      ADDR_R1          : pgmpre_out[0] <= REG_r[R1][7:0];
      ADDR_R1+1        : pgmpre_out[0] <= REG_r[R1][15:8];
      ADDR_R2          : pgmpre_out[0] <= REG_r[R2][7:0];
      ADDR_R2+1        : pgmpre_out[0] <= REG_r[R2][15:8];
      ADDR_R3          : pgmpre_out[0] <= REG_r[R3][7:0];
      ADDR_R3+1        : pgmpre_out[0] <= REG_r[R3][15:8];
      ADDR_R4          : pgmpre_out[0] <= REG_r[R4][7:0];
      ADDR_R4+1        : pgmpre_out[0] <= REG_r[R4][15:8];
      ADDR_R5          : pgmpre_out[0] <= REG_r[R5][7:0];
      ADDR_R5+1        : pgmpre_out[0] <= REG_r[R5][15:8];
      ADDR_R6          : pgmpre_out[0] <= REG_r[R6][7:0];
      ADDR_R6+1        : pgmpre_out[0] <= REG_r[R6][15:8];
      ADDR_R7          : pgmpre_out[0] <= REG_r[R7][7:0];
      ADDR_R7+1        : pgmpre_out[0] <= REG_r[R7][15:8];
      ADDR_R8          : pgmpre_out[0] <= REG_r[R8][7:0];
      ADDR_R8+1        : pgmpre_out[0] <= REG_r[R8][15:8];
      ADDR_R9          : pgmpre_out[0] <= REG_r[R9][7:0];
      ADDR_R9+1        : pgmpre_out[0] <= REG_r[R9][15:8];
      ADDR_R10         : pgmpre_out[0] <= REG_r[R10][7:0];
      ADDR_R10+1       : pgmpre_out[0] <= REG_r[R10][15:8];
      ADDR_R11         : pgmpre_out[0] <= REG_r[R11][7:0];
      ADDR_R11+1       : pgmpre_out[0] <= REG_r[R11][15:8];
      ADDR_R12         : pgmpre_out[0] <= REG_r[R12][7:0];
      ADDR_R12+1       : pgmpre_out[0] <= REG_r[R12][15:8];
      ADDR_R13         : pgmpre_out[0] <= REG_r[R13][7:0];
      ADDR_R13+1       : pgmpre_out[0] <= REG_r[R13][15:8];
      ADDR_R14         : pgmpre_out[0] <= REG_r[R14][7:0];
      ADDR_R14+1       : pgmpre_out[0] <= REG_r[R14][15:8];
      ADDR_R15         : pgmpre_out[0] <= REG_r[R15][7:0];
      ADDR_R15+1       : pgmpre_out[0] <= REG_r[R15][15:8];

      ADDR_SFR         : pgmpre_out[0] <= SFR_r[7:0];
      ADDR_SFR+1       : pgmpre_out[0] <= SFR_r[15:8];
      ADDR_BRAMR       : pgmpre_out[0] <= BRAMR_r;
      ADDR_PBR         : pgmpre_out[0] <= PBR_r;
      ADDR_ROMBR       : pgmpre_out[0] <= ROMBR_r;
      ADDR_CFGR        : pgmpre_out[0] <= CFGR_r;
      ADDR_SCBR        : pgmpre_out[0] <= SCBR_r;
      ADDR_CLSR        : pgmpre_out[0] <= CLSR_r;
      ADDR_SCMR        : pgmpre_out[0] <= SCMR_r;
      ADDR_VCR         : pgmpre_out[0] <= VCR_r;
      ADDR_RAMBR       : pgmpre_out[0] <= RAMBR_r;
      ADDR_CBR+0       : pgmpre_out[0] <= CBR_r[7:0];
      ADDR_CBR+1       : pgmpre_out[0] <= CBR_r[15:8];
      8'h40            : pgmpre_out[0] <= COLR_r;
      8'h41            : pgmpre_out[0] <= POR_r;
      8'h42            : pgmpre_out[0] <= SREG_r;
      8'h43            : pgmpre_out[0] <= DREG_r;
      8'h44            : pgmpre_out[0] <= ROMRDBUF_r;
      8'h45            : pgmpre_out[0] <= RAMWRBUF_r;
      8'h46            : pgmpre_out[0] <= RAMADDR_r[7:0];
      8'h47            : pgmpre_out[0] <= RAMADDR_r[15:8];
  
//      8'h50,8'h58      : pgmpre_out[0] <= PIXBUF_OFFSET_r[pgm_addr_r[3]][7:0];
//      8'h51,8'h59      : pgmpre_out[0] <= PIXBUF_OFFSET_r[pgm_addr_r[3]][15:8];
//      8'h60,8'h68      : pgmpre_out[0] <= PIXBUF_VALID_r[pgm_addr_r[3]];
//      8'h70            : pgmpre_out[0] <= PIXBUF_r[0][0];
//      8'h71            : pgmpre_out[0] <= PIXBUF_r[0][1];
//      8'h72            : pgmpre_out[0] <= PIXBUF_r[0][2];
//      8'h73            : pgmpre_out[0] <= PIXBUF_r[0][3];
//      8'h74            : pgmpre_out[0] <= PIXBUF_r[0][4];
//      8'h75            : pgmpre_out[0] <= PIXBUF_r[0][5];
//      8'h76            : pgmpre_out[0] <= PIXBUF_r[0][6];
//      8'h77            : pgmpre_out[0] <= PIXBUF_r[0][7];
//      8'h78            : pgmpre_out[0] <= PIXBUF_r[1][0];
//      8'h79            : pgmpre_out[0] <= PIXBUF_r[1][1];
//      8'h7A            : pgmpre_out[0] <= PIXBUF_r[1][2];
//      8'h7B            : pgmpre_out[0] <= PIXBUF_r[1][3];
//      8'h7C            : pgmpre_out[0] <= PIXBUF_r[1][4];
//      8'h7D            : pgmpre_out[0] <= PIXBUF_r[1][5];
//      8'h7E            : pgmpre_out[0] <= PIXBUF_r[1][6];
//      8'h7F            : pgmpre_out[0] <= PIXBUF_r[1][7];
  
      // TODO: add more internal temps @ $80
      8'h80            : pgmpre_out[0] <= SFR_Z;
      8'h81            : pgmpre_out[0] <= SFR_CY;
      8'h82            : pgmpre_out[0] <= SFR_S;
      8'h83            : pgmpre_out[0] <= SFR_OV;
      8'h84            : pgmpre_out[0] <= SFR_GO;
      8'h85            : pgmpre_out[0] <= SFR_RR;
      8'h86            : pgmpre_out[0] <= SFR_ALT1;
      8'h87            : pgmpre_out[0] <= SFR_ALT2;
      8'h88            : pgmpre_out[0] <= SFR_IL;
      8'h89            : pgmpre_out[0] <= SFR_IH;
      8'h8A            : pgmpre_out[0] <= SFR_B;
      8'h8B            : pgmpre_out[0] <= SCMR_MD;
      8'h8C            : pgmpre_out[0] <= SCMR_HT;
      8'h8D            : pgmpre_out[0] <= SCMR_RAN;
      8'h8E            : pgmpre_out[0] <= SCMR_RON;

      // bitmap state
//      8'h90           : pgmpre_out[0] <= BMP_STATE;
//      8'h91           : pgmpre_out[0] <= bmp_mode_r;
//      8'h92           : pgmpre_out[0] <= bmp_bppm1_r;
//      8'h93           : pgmpre_out[0] <= bmp_plane_r;
//      8'h94           : pgmpre_out[0] <= bmp_x_r[0];
//      8'h95           : pgmpre_out[0] <= bmp_y_r[0];
//      8'h96           : pgmpre_out[0] <= bmp_x_r[1];
//      8'h97           : pgmpre_out[0] <= bmp_y_r[1];
//      8'h98           : pgmpre_out[0] <= bmp_char_shift_r[0][7:0];
//      8'h99           : pgmpre_out[0] <= bmp_char_shift_r[0][15:8];
//      8'h9A           : pgmpre_out[0] <= bmp_char_shift_r[1][7:0];
//      8'h9B           : pgmpre_out[0] <= bmp_char_shift_r[1][15:8];
//      8'h9C           : pgmpre_out[0] <= bmp_offset_r[7:0];
//      8'h9D           : pgmpre_out[0] <= bmp_offset_r[15:8];
//      8'h9E           : pgmpre_out[0] <= bmp_index_bit_r;
//      8'h9F           : pgmpre_out[0] <= bmp_colr_r;
//      8'hA0           : pgmpre_out[0] <= bmp_rpix_char_shift_r[7:0];
//      8'hA1           : pgmpre_out[0] <= bmp_rpix_char_shift_r[15:8];
//      8'hA2           : pgmpre_out[0] <= bmp_rpix_x_r;
//      8'hA3           : pgmpre_out[0] <= bmp_rpix_y_r;
//      8'hA4           : pgmpre_out[0] <= bmp_index_r;

      8'hB2           : pgmpre_out[0] <= exe_opcode_r;
      8'hB3           : pgmpre_out[0] <= exe_operand_r[7:0];
      8'hB4           : pgmpre_out[0] <= exe_operand_r[15:8];
      8'hB5           : pgmpre_out[0] <= exe_opsize_r;
      //8'hB6           : pgmpre_out[0] <= exe_byte_r;

      //8'hC0           : pgmpre_out[0] <= FETCH_STATE;
      //8'hC1           : pgmpre_out[0] <= EXE_STATE;
      //8'hC2           : pgmpre_out[0] <= ROM_STATE;
      //8'hC3           : pgmpre_out[0] <= RAM_STATE;

      8'hD0           : pgmpre_out[0] <= config_r[0];
      8'hD1           : pgmpre_out[0] <= config_r[1];
      8'hD2           : pgmpre_out[0] <= config_r[2];
      8'hD3           : pgmpre_out[0] <= config_r[3];
      8'hD4           : pgmpre_out[0] <= config_r[4];
      8'hD5           : pgmpre_out[0] <= config_r[5];
      8'hD6           : pgmpre_out[0] <= config_r[6];
      8'hD7           : pgmpre_out[0] <= config_r[7];

      8'hE0           : pgmpre_out[0] <= stepcnt_r;
      8'hE1           : pgmpre_out[0] <= pipeline_advance;
      8'hE2           : pgmpre_out[0] <= snes_write_r;
      8'hE3           : pgmpre_out[0] <= fetch_waitcnt_r;
      8'hE4           : pgmpre_out[0] <= exe_waitcnt_r;
      8'hE5           : pgmpre_out[0] <= op_complete;      
      8'hE6           : pgmpre_out[0] <= e2r_val_r;      
      8'hE7           : pgmpre_out[0] <= e2r_destnum_r;
      8'hE8           : pgmpre_out[0] <= step_r;
      8'hE9           : pgmpre_out[0] <= gsu_clock_en;
      8'hEA           : pgmpre_out[0] <= fetch_error;

      8'hEC           : pgmpre_out[0] <= lat_fetch_r;
      8'hED           : pgmpre_out[0] <= lat_memory_r;
      8'hEE           : pgmpre_out[0] <= lat_mult_r;
      8'hEF           : pgmpre_out[0] <= lat_fmult_r;
      
      // big endian to make debugging easier
      8'hF0           : pgmpre_out[0] <= cache_val_r[31:23];
      8'hF1           : pgmpre_out[0] <= cache_val_r[23:16];
      8'hF2           : pgmpre_out[0] <= cache_val_r[15: 8];
      8'hF3           : pgmpre_out[0] <= cache_val_r[ 7: 0];
      8'hF4           : pgmpre_out[0] <= fetch_cache_data_r;
      8'hF5           : pgmpre_out[0] <= rom_bus_data_r;
      8'hF6           : pgmpre_out[0] <= fetch_data_r;

      8'hF8           : pgmpre_out[0] <= fetch_cache_match_r;
      8'hF9           : pgmpre_out[0] <= cache_gsu_addr_r[7:0];
      8'hFA           : pgmpre_out[0] <= cache_gsu_addr_r[8];
      8'hFB           : pgmpre_out[0] <= cache_addr_r[ 7: 0];
      8'hFC           : pgmpre_out[0] <= cache_addr_r[15: 8];
      8'hFD           : pgmpre_out[0] <= cache_addr_r[23:16];

      default         : pgmpre_out[0] <= 8'hFF;
    endcase
    2'h1: pgmpre_out[1] <= debug_cache_rddata;
    2'h2: pgmpre_out[2] <= debug_cache_rddata;
//    2'h3: casex (pgm_addr_r[7:0])      
//      // fetch state
//      //8'h00           : pgmpre_out[3] <= FETCH_STATE;
//      //8'h01           : pgmpre_out[3] <= fetch_waitcnt_r;
//      // exe state
////      8'h20           : pgmpre_out[3] <= EXE_STATE;
////      8'h21           : pgmpre_out[3] <= exe_waitcnt_r;
//      8'h22           : pgmpre_out[3] <= exe_opcode_r;
//      8'h23           : pgmpre_out[3] <= exe_operand_r[7:0];
//      8'h24           : pgmpre_out[3] <= exe_operand_r[15:8];
//      8'h25           : pgmpre_out[3] <= exe_opsize_r;
////      8'h26           : pgmpre_out[3] <= e2r_destnum_r;
////  
////      8'h30           : pgmpre_out[3] <= exe_src_r[7:0];
////      8'h31           : pgmpre_out[3] <= exe_src_r[15:8];
////      8'h32           : pgmpre_out[3] <= exe_srcn_r[7:0];
////      8'h33           : pgmpre_out[3] <= exe_srcn_r[15:8];
////      8'h34           : pgmpre_out[3] <= e2r_data_r[7:0];
////      8'h35           : pgmpre_out[3] <= e2r_data_r[15:8];
////  
////      // cache state
////      //8'h40
////      // fill state
////      8'h60           : pgmpre_out[3] <= ROM_BUS_RDY;
////      8'h61           : pgmpre_out[3] <= RAM_BUS_RDY;
//      8'h62           : pgmpre_out[3] <= bmp_data_r[7:0];
//      8'h63           : pgmpre_out[3] <= bmp_data_r[15:8];
////      8'h68           : pgmpre_out[3] <= cache_rom_rd_r;
////      8'h69           : pgmpre_out[3] <= cache_ram_rd_r;
////      8'h6F           : pgmpre_out[3] <= exe_rom_rd_r;
////      8'h70           : pgmpre_out[3] <= exe_ram_rd_r;
////      8'h71           : pgmpre_out[3] <= exe_ram_wr_r;
//      8'h72           : pgmpre_out[3] <= bmp_ram_rd_r;
//      8'h73           : pgmpre_out[3] <= bmp_ram_wr_r;
////      8'h74           : pgmpre_out[3] <= exe_addr_r[7:0];
////      8'h75           : pgmpre_out[3] <= exe_addr_r[15:8];
////      8'h76           : pgmpre_out[3] <= exe_addr_r[23:16];
//      8'h77           : pgmpre_out[3] <= bmp_addr_r[7:0];
//      8'h78           : pgmpre_out[3] <= bmp_addr_r[15:8];
//      8'h79           : pgmpre_out[3] <= bmp_addr_r[23:16];
////      8'h7A           : pgmpre_out[3] <= exe_data_r[7:0];
////      8'h7B           : pgmpre_out[3] <= exe_data_r[15:8];
////      8'h7C           : pgmpre_out[3] <= rom_bus_data_r[7:0];
////      8'h7D           : pgmpre_out[3] <= rom_bus_data_r[15:8];
////      8'h7E           : pgmpre_out[3] <= ram_bus_data_r[7:0];
////      8'h7F           : pgmpre_out[3] <= ram_bus_data_r[15:8];
//
//      // bitmap state
//      8'h80           : pgmpre_out[3] <= BMP_STATE;
//      8'h81           : pgmpre_out[3] <= bmp_mode_r;
//      8'h82           : pgmpre_out[3] <= bmp_bppm1_r;
//      8'h83           : pgmpre_out[3] <= bmp_plane_r;
//      8'h84           : pgmpre_out[3] <= bmp_x_r[0];
//      8'h85           : pgmpre_out[3] <= bmp_y_r[0];
//      8'h86           : pgmpre_out[3] <= bmp_x_r[1];
//      8'h87           : pgmpre_out[3] <= bmp_y_r[1];
//      8'h88           : pgmpre_out[3] <= bmp_char_shift_r[0][7:0];
//      8'h89           : pgmpre_out[3] <= bmp_char_shift_r[0][15:8];
//      8'h8A           : pgmpre_out[3] <= bmp_char_shift_r[1][7:0];
//      8'h8B           : pgmpre_out[3] <= bmp_char_shift_r[1][15:8];
//      8'h8C           : pgmpre_out[3] <= bmp_offset_r[7:0];
//      8'h8D           : pgmpre_out[3] <= bmp_offset_r[15:8];
//      8'h8E           : pgmpre_out[3] <= bmp_index_bit_r;
//      8'h8F           : pgmpre_out[3] <= bmp_colr_r;
//      8'h90           : pgmpre_out[3] <= bmp_rpix_char_shift_r[7:0];
//      8'h91           : pgmpre_out[3] <= bmp_rpix_char_shift_r[15:8];
//      8'h92           : pgmpre_out[3] <= bmp_rpix_x_r;
//      8'h93           : pgmpre_out[3] <= bmp_rpix_y_r;
//      8'h94           : pgmpre_out[3] <= bmp_index_r;
//
//      //8'h98           : pgmpre_out[3] <= e2b_plot_r;
//      //8'h99           : pgmpre_out[3] <= e2b_rpix_r;
//      //8'h9A           : pgmpre_out[3] <= bmp_flush_buf_r;
//      //8'h9B           : pgmpre_out[3] <= bmp_flush_rmw_r;
//      //8'h9C           : pgmpre_out[3] <= bmp_flush_colr_r;
//
//      // config state
//      8'hA0           : pgmpre_out[3] <= config_r[0];
//      8'hA1           : pgmpre_out[3] <= config_r[1];
//      //8'hA2           : pgmpre_out[3] <= config_r[2];
//      //8'hA3           : pgmpre_out[3] <= config_r[3];
//      //8'hA4           : pgmpre_out[3] <= config_r[4];
//      //8'hA5           : pgmpre_out[3] <= config_r[5];
//      //8'hA6           : pgmpre_out[3] <= config_r[6];
//      //8'hA7           : pgmpre_out[3] <= config_r[7];
//  
//      //8'hC0           : pgmpre_out[3] <= ROM_STATE;
//      //8'hC1           : pgmpre_out[3] <= RAM_STATE;
//      
//      // misc
//      //8'hE0           : pgmpre_out[3] <= gsu_cycle_cnt_r[31:24];
//      //8'hE1           : pgmpre_out[3] <= gsu_cycle_cnt_r[23:16];
//      //8'hE2           : pgmpre_out[3] <= gsu_cycle_cnt_r[15: 8];
//      //8'hE3           : pgmpre_out[3] <= gsu_cycle_cnt_r[ 7: 0];
//      //8'hE4           : pgmpre_out[3] <= snes_write_r;
//      //8'hE5           : pgmpre_out[3] <= pipeline_advance;
//      
//      default           : pgmpre_out[3] <= 8'hFF;
//    endcase
  endcase
end
`endif

//-------------------------------------------------------------------
// MISC OUTPUTS
//-------------------------------------------------------------------
assign DBG         = 0;
assign PGM_DATA    = pgmdata_out;

assign DATA_ENABLE = data_enable_r;
assign DATA_OUT    = data_out_r;

//assign ACTIVE      = ~|(ROM_STATE & ST_ROM_IDLE) | ~|(RAM_STATE & ST_RAM_IDLE);
assign GO          = SFR_GO;
assign RON         = SCMR_RON;
assign RAN         = SCMR_RAN;
assign IRQ         = SFR_IRQ & ~CFGR_IRQ;

endmodule
