module  RTC_I2CIF(
/*AUTOARG*/
   // Outputs
   SDAO, RtcAddr, RtcDataI, RtcWr_b, Write10_set, ReadPxo_Event_done,
   WritePxo_Event_set, Write3_Motion_Event_set, cpd_raddr_upd_i2c,
   cpd_r_i2c, reset_xybuf, latdxy_xybuf, prelat_xybuf, DirSum_reset,
   busy_protect,
   // Inputs
   rst, lpoclk, C_purstb_lpo, SCL, SCL_inv, SDAI, SDAI_inv, SCL_data,
   SDAI_data, RtcDataO, B_slaveID_state, ATPG_TM, ATPG_CLK, B_banksel,
   B_i2c_timeout_enh, B_i2c_timeout, B_w3clr_enh, B_i2c_rd1_latdxy,
   D_direction, B_ppg_enh, B_spo2_enh
   );

`include "./def_para.v"

//----------------------------------------------------------------------
//  port direction declaration
//----------------------------------------------------------------------
input           rst;            //internal reset
input           lpoclk;          //timeout clock
input		C_purstb_lpo;

// I2C I/F
input           SCL;               //serial clock
input           SCL_inv;           //inverse serial clock
input           SDAI;              //serial data input
input           SDAI_inv;          //inverse serial data input
output          SDAO;              //serial data output
input		SCL_data;          //SCL data in
input		SDAI_data;	   //SDAI data in

// RTC MCU I/F
output  [7:0]   RtcAddr;           //address bus, only 16 address for registers
output  [7:0]   RtcDataI;          //data bus input
input   [7:0]   RtcDataO;          //data bus output
//output                RtcRd_b_rbank;     //read pulse
output          RtcWr_b;           //write pulse

output		Write10_set;

// Mouse application
input		B_slaveID_state;
input           ATPG_TM;
input           ATPG_CLK;
input   [2:0]   B_banksel;
input           B_i2c_timeout_enh;
input   [1:0]   B_i2c_timeout;
input		B_w3clr_enh;
input		B_i2c_rd1_latdxy;

input		D_direction;

output          ReadPxo_Event_done;
output          WritePxo_Event_set;
output		Write3_Motion_Event_set;
//output          ReadAE_Event_set;
//output          ReadFDIQ_Event_set;

// CPD
input		B_ppg_enh;
input		B_spo2_enh;
output		cpd_raddr_upd_i2c;
output		cpd_r_i2c;

reg             Dir0x02_issue;
reg             DirSum_reset;
reg             busy_protect;

// To XYBuf_Top
output		reset_xybuf;
output		latdxy_xybuf;
output		prelat_xybuf;

output          DirSum_reset;
output          busy_protect;

//----------------------------------------------------------------------
//  reg, wire declaration
//----------------------------------------------------------------------
reg             StartCmd_SDA;
reg             StartCmd;
reg             StopCmd;
reg     [3:0]   BitCnt;
reg             BitCnt_Eq_2;
reg     [7:0]   ShiftReg;
reg     [6:0]   TXShiftReg;
reg             Rwb;
reg     [2:0]   I2CSt,NxtI2CSt;
reg             RtcWr_b;
reg             RtcRd_b;
//reg             RtcRd_b_rbank;
reg             Read2_Event_set;
reg             ReadPxo_Event_set;
reg             ReadPxo_Event_done;
reg             WritePxo_Event_set;
reg		Write3_Motion_Event_set;
//reg             ReadAE_Event_set;
//reg             ReadFDIQ_Event_set;
reg		cpd_raddr_upd_i2c;
reg		cpd_r_i2c;

wire		sync_SDAO;
wire		sync_B_i2c_timeout_enh;
reg     [14:0]  timer;
reg		timeout;
wire            timeout_wire;

// --------------------------------------------
//      PAD_ID  B_slaveID_state SLAVE_ID
//      HIGH    1'b1           0x33
//      LOW     1'b0           0x13
// --------------------------------------------
wire    [6:0]   SLAVE_ID = {1'b0, B_slaveID_state, 5'b1_0011};

//----------------------------------------------------------------------
//  BitCnt[3:0]
//----------------------------------------------------------------------
wire	BitCnt_eq_0;
wire	BitCnt_eq_1;
wire	BitCnt_eq_2;
wire	BitCnt_eq_3;
wire	BitCnt_eq_4;
wire	BitCnt_eq_5;
wire	BitCnt_eq_6;
wire	BitCnt_eq_7;
wire	BitCnt_eq_8;

GATE_BUF BUF_BitCnt_eq_0 (.O(BitCnt_eq_0), .I(BitCnt == 4'd0));
GATE_BUF BUF_BitCnt_eq_1 (.O(BitCnt_eq_1), .I(BitCnt == 4'd1));
GATE_BUF BUF_BitCnt_eq_2 (.O(BitCnt_eq_2), .I(BitCnt == 4'd2));
GATE_BUF BUF_BitCnt_eq_3 (.O(BitCnt_eq_3), .I(BitCnt == 4'd3));
GATE_BUF BUF_BitCnt_eq_4 (.O(BitCnt_eq_4), .I(BitCnt == 4'd4));
GATE_BUF BUF_BitCnt_eq_5 (.O(BitCnt_eq_5), .I(BitCnt == 4'd5));
GATE_BUF BUF_BitCnt_eq_6 (.O(BitCnt_eq_6), .I(BitCnt == 4'd6));
GATE_BUF BUF_BitCnt_eq_7 (.O(BitCnt_eq_7), .I(BitCnt == 4'd7));
GATE_BUF BUF_BitCnt_eq_8 (.O(BitCnt_eq_8), .I(BitCnt == 4'd8));

//----------------------------------------------------------------------
//  start and stop command of I2C
//----------------------------------------------------------------------

//wire  StartCmd_Rst = ATPG_TM ? rst : (rst | BitCnt_Eq_2);
wire StartCmd_Rst;
GATE_MUX2 MUX_StartCmd_Rst (.O(StartCmd_Rst), .S(ATPG_TM), .A(rst | BitCnt_Eq_2), .B(rst));

// Aki for SDA glitch issue
always @(posedge SDAI_inv or posedge StartCmd_Rst)
begin
  if (StartCmd_Rst)
    StartCmd_SDA <= 0;
  else
    StartCmd_SDA <= (SCL_data);
end

always @(posedge SCL_inv or posedge StartCmd_Rst)
begin
  if (StartCmd_Rst)
    StartCmd <= 0;
  else if (StartCmd_SDA)
    StartCmd <= 1;
end

//wire  StopCmd_Rst     = ATPG_TM ? rst :(rst | StartCmd);
wire StopCmd_Rst;
GATE_MUX2 MUX_StopCmd_Rst (.O(StopCmd_Rst), .S(ATPG_TM), .A(rst | StartCmd), .B(rst));

always @(posedge SDAI or posedge StopCmd_Rst)
begin
  if (StopCmd_Rst)
    StopCmd <= 0;
  else
    StopCmd <= (SCL_data);
end

//----------------------------------------------------------------------
//  Aki NACK command of I2C from Master
//----------------------------------------------------------------------
reg NackCmd;
reg AckCmd;

always @(posedge SCL or posedge rst)
begin
  if (rst)
    NackCmd <= 0;
  else if ((SDAI_data == 1) && (BitCnt == 4'd8))
    NackCmd <= 1;
  else if (NackCmd)
    NackCmd <= 0;
end
always @(posedge SCL or posedge rst)
begin
  if (rst)
    AckCmd <= 0;
  else if ((SDAI_data == 0) && (BitCnt == 4'd8))
    AckCmd <= 1;
  else if (AckCmd)
    AckCmd <= 0;
end

//----------------------------------------------------------------------
//  BitCnt_Eq_2
//----------------------------------------------------------------------
always @(posedge SCL or posedge rst)
begin
  if (rst)
    BitCnt_Eq_2 <= 1'b0;
  else if (BitCnt == 1)
    BitCnt_Eq_2 <= 1'b1;
  else
    BitCnt_Eq_2 <= 1'b0;
end

//----------------------------------------------------------------------
//  I2CFSM
//    sample SDAI at rising edge of SCL
//
//----------------------------------------------------------------------

parameter       I2CStIdle       = 3'd0;
parameter       I2CStSlaveID    = 3'd1;
parameter       I2CStWrAddr     = 3'd2;
parameter       I2CStWrData     = 3'd3;
parameter       I2CStWrData_Next= 3'd4;
parameter       I2CStRdData     = 3'd5;

//----------------------------------------------------------------------
//  sequential logic
//    for state transition
//
//----------------------------------------------------------------------
wire    I2CSt_Rst;

GATE_MUX2 MUX_I2CSt_Rst (.O(I2CSt_Rst), .S(ATPG_TM), .A(rst | StopCmd | timeout), .B(rst));

always @(posedge SCL or posedge I2CSt_Rst)
begin
  if (I2CSt_Rst)
    I2CSt <= I2CStIdle;
  else
    I2CSt <= NxtI2CSt;
end

//----------------------------------------------------------------------
//  combinational logic
//    for next state inferring and output signal
//----------------------------------------------------------------------

always @(I2CSt or StartCmd or BitCnt or ShiftReg or Rwb or StopCmd or NackCmd or SLAVE_ID)
begin
  case (I2CSt)
    I2CStIdle:
      begin
        if (StartCmd)
          NxtI2CSt = I2CStSlaveID;
        else
          NxtI2CSt = I2CStIdle;
      end

    I2CStSlaveID:
      begin
        if (StopCmd)
          NxtI2CSt = I2CStIdle;
	else if (StartCmd)
          NxtI2CSt = I2CStSlaveID;
        else if (BitCnt == 4'd8)
          begin
            if (ShiftReg[7:1] == SLAVE_ID)
              begin
                if (Rwb == 1)
                  NxtI2CSt = I2CStRdData;
                else
                  NxtI2CSt = I2CStWrAddr;
              end
            else
                NxtI2CSt = I2CStIdle;
          end
        else
          NxtI2CSt = I2CStSlaveID;
      end

    I2CStWrAddr:
      begin
        if (StopCmd)
          NxtI2CSt = I2CStIdle;
	//for repeated start condition
        else if (StartCmd)
          NxtI2CSt = I2CStSlaveID;
        else if (BitCnt == 4'd8)
          NxtI2CSt = I2CStWrData;
        else
          NxtI2CSt = I2CStWrAddr;
      end

    I2CStWrData:
      begin
        if (StopCmd)
          NxtI2CSt = I2CStIdle;
        //for repeated start condition
        else if (StartCmd)
          NxtI2CSt = I2CStSlaveID;
        else if (BitCnt == 4'd8)
          NxtI2CSt = I2CStWrData_Next;
        else
          NxtI2CSt = I2CStWrData;
      end

    I2CStWrData_Next:
      begin
        if (StopCmd)
          NxtI2CSt = I2CStIdle;
        //for repeated start condition
        else if (StartCmd)
          NxtI2CSt = I2CStSlaveID;
        else
          NxtI2CSt = I2CStWrData_Next;
      end

    I2CStRdData:
      begin
        if (StopCmd)
          NxtI2CSt = I2CStIdle;
	//for repeated start condition
        else if (StartCmd)
          NxtI2CSt = I2CStSlaveID;
        else if (NackCmd)
          NxtI2CSt = I2CStIdle;
        else
          NxtI2CSt = I2CStRdData;
      end

    default:
      begin
        NxtI2CSt = I2CStIdle;
      end
  endcase
end             // I2CFSM

//----------------------------------------------------------------------
//  output logic
//----------------------------------------------------------------------
reg SlaveID_Ok;

always @(I2CSt or BitCnt or ShiftReg or SLAVE_ID)
begin
  if (I2CSt == I2CStSlaveID && BitCnt == 4'd8)
    begin
      if (ShiftReg[7:1] == SLAVE_ID)
        SlaveID_Ok = 1;
      else
        SlaveID_Ok = 0;
    end
  else
    SlaveID_Ok = 0;
end

//----------------------------------------------------------------------
//  bit number counter
//----------------------------------------------------------------------
always @(posedge SCL or posedge I2CSt_Rst)
begin
  if (I2CSt_Rst)
    BitCnt <= 4'd0;
  else if ((I2CSt != I2CStSlaveID) & StartCmd == 1 ) // for non slave id state to resync by start
    BitCnt <= 4'd1;
  else if ((I2CSt == I2CStSlaveID) & StartCmd == 1 & BitCnt != 1) // for slave id state to resync by start
    BitCnt <= 4'd1;
  //for error re-sync
  //else if ((I2CSt == I2CStIdle) && (StartCmd == 1))
  //  BitCnt <= 4'd1;
  //for repeated start condition
  //else if ((I2CSt == I2CStWrData || I2CSt == I2CStWrData_Next) && (StartCmd == 1))
  //  BitCnt <= 4'd1;
  else if ((BitCnt == 4'd8))
    BitCnt <= 4'd0;
  else
    BitCnt <= BitCnt + 1;
end

//----------------------------------------------------------------------
//  8-bit shift register, left shift
//----------------------------------------------------------------------
always @(posedge SCL or posedge I2CSt_Rst)
begin
  if (I2CSt_Rst)
    ShiftReg <= 8'b0;
  //else if (~RtcRd_b)
  //  ShiftReg <= RtcDataO;
  //Aki,For Burst Read SDAI=0 for Ack, SDAI=1 for NACK
  //else if ((BitCnt == 4'd8) && (Rwb == 1) && (SDAI_data == 0))
  //  ShiftReg <= RtcDataO;
  else if (BitCnt != 4'd8)
    ShiftReg <= {ShiftReg[6:0], (SDAI_data)};
end

wire    [7:0]   RtcDataI = ShiftReg;

//----------------------------------------------------------------------
//  Rwb
//----------------------------------------------------------------------
always @(posedge SCL or posedge I2CSt_Rst)
begin
  if (I2CSt_Rst)
    Rwb <= 1'b0;
  else if ((BitCnt == 4'd7) && (I2CSt == I2CStSlaveID))
    Rwb <= (SDAI_data);
end

//----------------------------------------------------------------------
//  RtcAddr
//----------------------------------------------------------------------
reg     [7:0]   RtcAddr;
wire    [6:0]   RtcAddr_add1 = (RtcAddr[6:0] + 'd1);

always @(posedge SCL or posedge rst)
begin
  if (rst)
    RtcAddr <= 8'b0;
  else if ((BitCnt == 4'd8) && (I2CSt == I2CStWrAddr))                                //single mode
    RtcAddr <= ShiftReg[7:0];
  //else if ((BitCnt == 4'd0) && (I2CSt == I2CStWrData_Next) && (Rwb == 0))             //write burst mode
  else if ((BitCnt == 4'd0) && (I2CSt == I2CStWrData_Next) && (Rwb == 0) && ~RtcAddr[7]) //write burst mode
    RtcAddr <= {RtcAddr[7],RtcAddr_add1};
  //else if ((BitCnt == 4'd7) && (I2CSt == I2CStRdData) && (Rwb == 1))                  //read burst mode for pre-fetch
  else if ((BitCnt == 4'd7) && (I2CSt == I2CStRdData) && (Rwb == 1) && ~RtcAddr[7]) begin //read burst mode for pre-fetch
    if (RtcAddr[6:0] == CPD_ADDR)
        RtcAddr <=  RtcAddr;
    else
        RtcAddr <= {RtcAddr[7],RtcAddr_add1};
  end
end

wire    Write10_set = ((B_banksel == 'd0) & (RtcAddr[6:0] == 'd10) & (I2CSt == I2CStWrData_Next) & (BitCnt == 'd0));

//----------------------------------------------------------------------
//  Write3 clear motion
//----------------------------------------------------------------------
wire    Write3_set = ((B_banksel == 'd0) & (RtcAddr[6:0] == 'd3) & (I2CSt == I2CStWrData_Next) & (BitCnt == 'd0));

//always @(posedge SCL or posedge rst)
always @(posedge SCL or posedge I2CSt_Rst)
begin
//  if (rst)
  if (I2CSt_Rst)
    Write3_Motion_Event_set <= 1'b0;
  else if (Write3_set)
    Write3_Motion_Event_set <= B_w3clr_enh;
  else if (BitCnt_eq_8)
    Write3_Motion_Event_set <= 1'b0;
end

//----------------------------------------------------------------------
//  Write15 clear PxoDump pixel index
//----------------------------------------------------------------------
//wire    Write15_set = ((B_banksel == 'd0) & (RtcAddr[6:0] == 'd15) & (I2CSt == I2CStWrData_Next) & (BitCnt == 'd0));
wire    Write15_set = ((B_banksel == 'd0) & (RtcAddr[6:0] == 'd15) & (I2CSt == I2CStWrData) & (BitCnt == 'd8));

always @(posedge SCL or posedge rst)
begin
  if (rst)
    WritePxo_Event_set <= 1'b0;
  else
    WritePxo_Event_set <= Write15_set;
end


/**********************************************************************/
/***                        negative edge                           ***/
/**********************************************************************/
//----------------------------------------------------------------------
//  RtcWr_b
//----------------------------------------------------------------------
GATE_MUX2    MUX_RtcWr_b   (.O( RtcWr_b_SCL_inv ), .S( ATPG_TM ), .A( SCL_inv ), .B( ATPG_CLK ));

// Because GATE_GCK is DFF-based in FPGA, not latch-based
// GCK/en timing margin for p_storedata is only 0.5T
// for this reason, datavalid needs to early toggle 1T for FPGA
always @(posedge RtcWr_b_SCL_inv or posedge I2CSt_Rst)
begin
  if (I2CSt_Rst)
    RtcWr_b <= 1'b1;
`ifdef FPGA
  else if ((BitCnt == 4'd7) && (I2CSt == I2CStWrData) && (Rwb == 1'b0))
    RtcWr_b <= 1'b0;
  else if ((BitCnt == 4'd7) && (I2CSt == I2CStWrData_Next) && (Rwb == 1'b0))
    RtcWr_b <= 1'b0;
`else
  else if ((BitCnt == 4'd8) && (I2CSt == I2CStWrData) && (Rwb == 1'b0))
    RtcWr_b <= 1'b0;
  else if ((BitCnt == 4'd8) && (I2CSt == I2CStWrData_Next) && (Rwb == 1'b0))
    RtcWr_b <= 1'b0;
`endif
  else
    RtcWr_b <= 1'b1;
end

//----------------------------------------------------------------------
//  RtcRd_b
//----------------------------------------------------------------------
always @(posedge SCL_inv or posedge I2CSt_Rst)
begin
  if (I2CSt_Rst)
    RtcRd_b <= 1'b1;
  else if ((BitCnt == 4'd8) && (I2CSt == I2CStSlaveID) && (Rwb == 1'b1))
    RtcRd_b <= 1'b0;
  else if ((BitCnt == 4'd8) && (I2CSt == I2CStRdData) && (Rwb == 1'b1))
    RtcRd_b <= 1'b0;
  else
    RtcRd_b <= 1'b1;
end

//----------------------------------------------------------------------
//  prelat_xybuf
//----------------------------------------------------------------------
reg	prelat_read;
always @(posedge SCL_inv or posedge I2CSt_Rst)
   if (I2CSt_Rst)
      prelat_read  <= 0;
   else if (I2CSt == I2CStSlaveID) begin
      if (BitCnt_eq_1)
         prelat_read  <= 1;
      else if (BitCnt_eq_8)
         prelat_read  <= 0;
   end

assign prelat_xybuf = prelat_read;

//----------------------------------------------------------------------
//  Read2_Event_set
//----------------------------------------------------------------------
wire    Read_Event = BitCnt[3] & Rwb & (SlaveID_Ok || ((I2CSt == I2CStRdData) & ~RtcAddr[7]));

// when B_i2c_rd1_latdxy=1:  read-1 will trigger Read2_Event (align to PKN260)
//                      =0 (default)
//wire    Read2_Event_set_wire = Read_Event & (B_banksel=='d0) & (RtcAddr[6:0] == 'd2);
wire	Read2_Event_vld = B_i2c_rd1_latdxy ? 1'b1 : (I2CSt == I2CStSlaveID);
wire    Read2_Event_set_wire = Read_Event & (B_banksel=='d0) & (RtcAddr[6:0] == 'd2) & Read2_Event_vld;

always @(posedge SCL_inv or posedge I2CSt_Rst)
  if (I2CSt_Rst)
    Read2_Event_set <= 1'b0;
  else
    Read2_Event_set <= Read2_Event_set_wire;

assign latdxy_xybuf = Read2_Event_set;

reg	latdxy_xybuf_d1;
always @(posedge SCL_inv or posedge I2CSt_Rst)
  if (I2CSt_Rst)
    latdxy_xybuf_d1 <= 0;
  else if (latdxy_xybuf)
    latdxy_xybuf_d1 <= 1;
  else if (latdxy_xybuf_d1)
    latdxy_xybuf_d1 <= 0;

reg	reset_xybuf;
always @(posedge SCL_inv or posedge I2CSt_Rst)
  if (I2CSt_Rst)
    reset_xybuf <= 0;
  else if (latdxy_xybuf_d1)
    reset_xybuf <= 1;
  else if (BitCnt[3])		// increase pulse width for xyclk CDCSync
    reset_xybuf <= 0;

//----------------------------------------------------------------------
//  Dir0x02_issue, DirSum_reset, busy_protect
//----------------------------------------------------------------------
always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        Dir0x02_issue     <= 1'b0;
    else if(Dir0x02_issue)
        Dir0x02_issue     <= 1'b0;
    else if(Read2_Event_set)
        Dir0x02_issue     <= D_direction;

always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        DirSum_reset <= 1'b0;
    else if (Dir0x02_issue)
        DirSum_reset <= 1'b1;
    else if (BitCnt[3])
        DirSum_reset <= 1'b0;

always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        busy_protect <= 1'b0;
    else if(I2CSt == I2CStSlaveID && (B_banksel=='d0) && (RtcAddr[6:0] == 'd2))
        busy_protect <= BitCnt_eq_1 ? 1'b1 : busy_protect;
    else if(BitCnt[3])
        busy_protect <= 1'b0;

//----------------------------------------------------------------------
//  ReadPxo_Event_set
//----------------------------------------------------------------------
wire    ReadPxo_Event_set_wire = Read_Event & (B_banksel=='d0) & (RtcAddr[6:0] == 'd15);

always @(posedge SCL_inv or posedge I2CSt_Rst)
  if (I2CSt_Rst)
    ReadPxo_Event_set <= 1'b0;
  else
    ReadPxo_Event_set <= ReadPxo_Event_set_wire;

//----------------------------------------------------------------------
//  ReadPxo_Event_done
//----------------------------------------------------------------------
always @(posedge SCL_inv or posedge I2CSt_Rst)
  if (I2CSt_Rst)
    ReadPxo_Event_done <= 1'b0;
  else if (BitCnt[3])
    ReadPxo_Event_done <= 1'b0;
  else if (ReadPxo_Event_set)
    ReadPxo_Event_done <= 1'b1;

//----------------------------------------------------------------------
//  ReadCPD_Event_set
//----------------------------------------------------------------------
wire    ReadCPD_Event_set_wire = Read_Event & (B_banksel=='d0) & (RtcAddr[6:0] == CPD_ADDR);

always @(posedge SCL_inv or posedge I2CSt_Rst)
  if (I2CSt_Rst)
    cpd_raddr_upd_i2c <= 1'b0;
  else
    cpd_raddr_upd_i2c <= cpd_r_i2c & (BitCnt == 'd5);

always @(posedge SCL_inv or posedge I2CSt_Rst)
  if (I2CSt_Rst)
    cpd_r_i2c <= 1'b0;
  else if ((B_ppg_enh | B_spo2_enh) & ReadCPD_Event_set_wire)
    cpd_r_i2c <= 1'b1;

//----------------------------------------------------------------------
//  TXShiftReg
//----------------------------------------------------------------------
wire    TX_bit;

always @(posedge SCL_inv or posedge I2CSt_Rst)
begin
  if (I2CSt_Rst)
    TXShiftReg <= {7{1'b1}};
  else if (~RtcRd_b)
    TXShiftReg <= RtcDataO[6:0];
  else
    TXShiftReg <= {TXShiftReg[5:0],1'b1};
end

assign  TX_bit = (RtcRd_b)? TXShiftReg[6] : RtcDataO[7];

//----------------------------------------------------------------------
//  SDAO
//----------------------------------------------------------------------
reg             SDAO_tmp;

wire            SDAO_tmp_d;
wire            SDAO;

//wire gate_read_pxo = B_read_image_mode ? vsync_d : 1 ;

always @(posedge SCL_inv or posedge I2CSt_Rst)
begin
  if (I2CSt_Rst)
    SDAO_tmp <= 1;
  else if (StartCmd_SDA)
    SDAO_tmp <= 1;
  else if (BitCnt == 4'd8)
    begin
      if (I2CSt == I2CStSlaveID)
        begin
          if (SlaveID_Ok == 1)
            SDAO_tmp <= 0; // send ACK to host
          else
            SDAO_tmp <= 1; // send NACK to host
        end
      else if (I2CSt == I2CStIdle)  //release wrong slave ID read
        SDAO_tmp <= 1; // receive re-START/STOP from host
      else if ((Rwb == 1) && (I2CSt == I2CStRdData))
        SDAO_tmp <= 1; // receive ACK from host
      else
        SDAO_tmp <= 0; // send ACK to host
    end
  else if (((Rwb == 1'b0) && (BitCnt == 4'b0)) || ((Rwb == 1'b1) && (BitCnt == 4'b0) && (I2CSt == I2CStRdData) && (NackCmd == 1)))
    SDAO_tmp <= 1; // receive re-START/STOP from host
  else if ((Rwb == 1) && (I2CSt == I2CStRdData))
    //SDAO_tmp <= ShiftReg[7];
    SDAO_tmp <= TX_bit;
end

//dalay for avoid negedge SDAO violation => StartCmd_SDA
// SYN
//GATE_DEL SDAO_D1 (.I(SDAO_tmp), .O(SDAO_tmp_d));
//GATE_DEL SDAO_D2 (.I(SDAO_tmp_d), .O(SDAO));

assign #10ps SDAO_tmp_d = SDAO_tmp;
assign #10ps SDAO       = SDAO_tmp_d ;


//----------------------------------------------------------------------
//  Timeout I2C by 32kHz LPO
//    B_i2c_timeout =
//    0: 256ms = 8192T
//    1: 512ms = 16384T
//    2: 768ms = 24576T
//    3: 1024ms = 32768T
//  Check SDAO = 'L' time
//----------------------------------------------------------------------

CDCSync_Signal_ResetH CDCSync_SDAO (
        .DI(SDAO),
        .CLK(lpoclk),
        .RSTn(C_purstb_lpo),
        .DO(sync_SDAO)
);

CDCSync_Signal_ResetL CDCSync_B_i2c_timeout_enh (
        .DI(B_i2c_timeout_enh),
        .CLK(lpoclk),
        .RSTn(C_purstb_lpo),
        .DO(sync_B_i2c_timeout_enh)
);

assign  timeout_wire    = (timer >= {B_i2c_timeout[1:0],13'h1fff});

always @ (posedge lpoclk or negedge C_purstb_lpo)
  if (~C_purstb_lpo)
     timer <= 'd0;
  else if (sync_SDAO || timeout_wire || ~sync_B_i2c_timeout_enh)
     timer <= 'd0;
  else
     timer <= timer + 'd1;

always @ (posedge lpoclk or negedge C_purstb_lpo)
  if (~C_purstb_lpo)
     timeout <= 1'b0;
  else if (sync_B_i2c_timeout_enh)
     timeout <= timeout_wire;
  else
     timeout <= 1'b0;

endmodule          //IF_I2C_Slave
