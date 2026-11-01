module  B_I2CCtl(
    /*AUTOARG*/
    // Outputs
    SDAO, RtcAddr, RtcDataI, RtcWr_b, reset_xybuf, latdxy_xybuf,
    prelat_xybuf,
    // Inputs
    rst, SCL, SCL_inv, SDAI, SDAI_inv, SCL_data, SDAI_data, RtcDataO
);

//----------------------------------------------------------------------
//  port direction declaration
//----------------------------------------------------------------------
// I2C I/F
input           rst;                // internal reset, active high
input           SCL;                // serial clock
input           SCL_inv;            // inverse serial clock
input           SDAI;               // serial data input
input           SDAI_inv;           // inverse serial data input
input           SCL_data;           // SCL data in
input           SDAI_data;          // SDAI data in
output          SDAO;               // serial data output, 0: pull SDA low

// RTC MCU I/F
output  [7:0]   RtcAddr;            // address bus
output  [7:0]   RtcDataI;           // write data bus
input   [7:0]   RtcDataO;           // read data bus
output          RtcWr_b;            // write pulse, active low

// To XYBuf_Top
output          reset_xybuf;
output          latdxy_xybuf;
output          prelat_xybuf;

//----------------------------------------------------------------------
//  reg, wire declaration
//----------------------------------------------------------------------
parameter       I2CStIdle       = 3'd0;
parameter       I2CStSlaveID    = 3'd1;
parameter       I2CStWrAddr     = 3'd2;
parameter       I2CStWrData     = 3'd3;
parameter       I2CStWrData_Next= 3'd4;
parameter       I2CStRdData     = 3'd5;

wire    [6:0]   SLAVE_ID = 7'h13;

reg     [2:0]   I2CSt, NxtI2CSt;
reg     [3:0]   BitCnt;
reg             BitCnt_Eq_2;
reg     [7:0]   ShiftReg;
reg     [6:0]   TXShiftReg;
reg             Rwb;

reg             StartCmd_SDA;
reg             StartCmd;
reg             StopCmd;
reg             NackCmd;

reg     [7:0]   RtcAddr;
reg             RtcWr_b;
reg             RtcRd_b;

reg             prelat_read;
reg             Read2_Event_set;
reg             latdxy_xybuf_d1;
reg             reset_xybuf;

reg             SDAO_tmp;
wire            SDAO_tmp_d;
wire            SDAO;

wire            BitCnt_eq_1;
wire            BitCnt_eq_8;
wire            StartCmd_Rst;
wire            StopCmd_Rst;
wire            I2CSt_Rst;
wire            TX_bit;

assign  RtcDataI = ShiftReg;

GATE_BUF BUF_BitCnt_eq_1 (.O(BitCnt_eq_1), .I(BitCnt == 4'd1));
GATE_BUF BUF_BitCnt_eq_8 (.O(BitCnt_eq_8), .I(BitCnt == 4'd8));

/**********************************************************************/
/***                        positive edge                           ***/
/**********************************************************************/
//----------------------------------------------------------------------
//  start and stop command of I2C
//----------------------------------------------------------------------
GATE_BUF BUF_StartCmd_Rst (.O(StartCmd_Rst), .I(rst | BitCnt_Eq_2));

// Aki for SDA glitch issue
always @(posedge SDAI_inv or posedge StartCmd_Rst)
    if (StartCmd_Rst)
        StartCmd_SDA <= 1'b0;
    else
        StartCmd_SDA <= SCL_data;

always @(posedge SCL_inv or posedge StartCmd_Rst)
    if (StartCmd_Rst)
        StartCmd <= 1'b0;
    else if (StartCmd_SDA)
        StartCmd <= 1'b1;

GATE_BUF BUF_StopCmd_Rst (.O(StopCmd_Rst), .I(rst | StartCmd));

always @(posedge SDAI or posedge StopCmd_Rst)
    if (StopCmd_Rst)
        StopCmd <= 1'b0;
    else
        StopCmd <= SCL_data;

//----------------------------------------------------------------------
//  NACK command of I2C from Master
//----------------------------------------------------------------------
always @(posedge SCL or posedge rst)
    if (rst)
        NackCmd <= 1'b0;
    else if (SDAI_data && (BitCnt == 4'd8))
        NackCmd <= 1'b1;
    else if (NackCmd)
        NackCmd <= 1'b0;

//----------------------------------------------------------------------
//  BitCnt_Eq_2
//----------------------------------------------------------------------
always @(posedge SCL or posedge rst)
    if (rst)
        BitCnt_Eq_2 <= 1'b0;
    else
        BitCnt_Eq_2 <= (BitCnt == 4'd1);

//----------------------------------------------------------------------
//  I2CFSM
//    sample SDAI at rising edge of SCL
//----------------------------------------------------------------------
GATE_BUF BUF_I2CSt_Rst (.O(I2CSt_Rst), .I(rst | StopCmd));

// sequential logic : state transition
always @(posedge SCL or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        I2CSt <= I2CStIdle;
    else
        I2CSt <= NxtI2CSt;

// combinational logic : next state
always @(*) begin
    case (I2CSt)
        I2CStIdle:
            if (StartCmd)
                NxtI2CSt = I2CStSlaveID;
            else
                NxtI2CSt = I2CStIdle;

        I2CStSlaveID:
            if (StopCmd)
                NxtI2CSt = I2CStIdle;
            else if (StartCmd)
                NxtI2CSt = I2CStSlaveID;
            else if (BitCnt == 4'd8) begin
                if (ShiftReg[7:1] == SLAVE_ID)
                    NxtI2CSt = Rwb ? I2CStRdData : I2CStWrAddr;
                else
                    NxtI2CSt = I2CStIdle;
            end
            else
                NxtI2CSt = I2CStSlaveID;

        I2CStWrAddr:
            if (StopCmd)
                NxtI2CSt = I2CStIdle;
            else if (StartCmd)              // repeated start
                NxtI2CSt = I2CStSlaveID;
            else if (BitCnt == 4'd8)
                NxtI2CSt = I2CStWrData;
            else
                NxtI2CSt = I2CStWrAddr;

        I2CStWrData:
            if (StopCmd)
                NxtI2CSt = I2CStIdle;
            else if (StartCmd)              // repeated start
                NxtI2CSt = I2CStSlaveID;
            else if (BitCnt == 4'd8)
                NxtI2CSt = I2CStWrData_Next;
            else
                NxtI2CSt = I2CStWrData;

        I2CStWrData_Next:
            if (StopCmd)
                NxtI2CSt = I2CStIdle;
            else if (StartCmd)              // repeated start
                NxtI2CSt = I2CStSlaveID;
            else
                NxtI2CSt = I2CStWrData_Next;

        I2CStRdData:
            if (StopCmd)
                NxtI2CSt = I2CStIdle;
            else if (StartCmd)              // repeated start
                NxtI2CSt = I2CStSlaveID;
            else if (NackCmd)
                NxtI2CSt = I2CStIdle;
            else
                NxtI2CSt = I2CStRdData;

        default:
            NxtI2CSt = I2CStIdle;
    endcase
end

// slave ID matched in the 8th bit of the slave ID phase
wire    SlaveID_Ok = (I2CSt == I2CStSlaveID) && (BitCnt == 4'd8) && (ShiftReg[7:1] == SLAVE_ID);

//----------------------------------------------------------------------
//  bit number counter
//----------------------------------------------------------------------
always @(posedge SCL or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        BitCnt <= 4'd0;
    else if ((I2CSt != I2CStSlaveID) & StartCmd)                // non slave id state : resync by start
        BitCnt <= 4'd1;
    else if ((I2CSt == I2CStSlaveID) & StartCmd & BitCnt != 1)  // slave id state : resync by start
        BitCnt <= 4'd1;
    else if (BitCnt == 4'd8)
        BitCnt <= 4'd0;
    else
        BitCnt <= BitCnt + 1;

//----------------------------------------------------------------------
//  8-bit shift register, left shift
//----------------------------------------------------------------------
always @(posedge SCL or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        ShiftReg <= 8'b0;
    else if (BitCnt != 4'd8)
        ShiftReg <= {ShiftReg[6:0], SDAI_data};

//----------------------------------------------------------------------
//  Rwb
//----------------------------------------------------------------------
always @(posedge SCL or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        Rwb <= 1'b0;
    else if ((BitCnt == 4'd7) && (I2CSt == I2CStSlaveID))
        Rwb <= SDAI_data;

//----------------------------------------------------------------------
//  RtcAddr : RtcAddr[7] = 1 disables the auto increment
//----------------------------------------------------------------------
wire    [6:0]   RtcAddr_add1 = RtcAddr[6:0] + 7'd1;

always @(posedge SCL or posedge rst)
    if (rst)
        RtcAddr <= 8'b0;
    else if ((BitCnt == 4'd8) && (I2CSt == I2CStWrAddr))                                        // single mode
        RtcAddr <= ShiftReg[7:0];
    else if ((BitCnt == 4'd0) && (I2CSt == I2CStWrData_Next) && (Rwb == 0) && ~RtcAddr[7])      // write burst mode
        RtcAddr <= {RtcAddr[7], RtcAddr_add1};
    else if ((BitCnt == 4'd7) && (I2CSt == I2CStRdData) && (Rwb == 1) && ~RtcAddr[7])           // read burst mode for pre-fetch
        RtcAddr <= {RtcAddr[7], RtcAddr_add1};

/**********************************************************************/
/***                        negative edge                           ***/
/**********************************************************************/
//----------------------------------------------------------------------
//  RtcWr_b
//----------------------------------------------------------------------
always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        RtcWr_b <= 1'b1;
    else if ((BitCnt == 4'd8) && (I2CSt == I2CStWrData)      && (Rwb == 1'b0))
        RtcWr_b <= 1'b0;
    else if ((BitCnt == 4'd8) && (I2CSt == I2CStWrData_Next) && (Rwb == 1'b0))
        RtcWr_b <= 1'b0;
    else
        RtcWr_b <= 1'b1;

//----------------------------------------------------------------------
//  RtcRd_b
//----------------------------------------------------------------------
always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        RtcRd_b <= 1'b1;
    else if ((BitCnt == 4'd8) && (I2CSt == I2CStSlaveID) && (Rwb == 1'b1))
        RtcRd_b <= 1'b0;
    else if ((BitCnt == 4'd8) && (I2CSt == I2CStRdData)  && (Rwb == 1'b1))
        RtcRd_b <= 1'b0;
    else
        RtcRd_b <= 1'b1;

//----------------------------------------------------------------------
//  prelat_xybuf : high during the slave ID phase
//----------------------------------------------------------------------
always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        prelat_read <= 1'b0;
    else if (I2CSt == I2CStSlaveID) begin
        if (BitCnt_eq_1)
            prelat_read <= 1'b1;
        else if (BitCnt_eq_8)
            prelat_read <= 1'b0;
    end

assign prelat_xybuf = prelat_read;

//----------------------------------------------------------------------
//  latdxy_xybuf : read of address 2, in the slave ID phase
//----------------------------------------------------------------------
wire    Read_Event           = BitCnt[3] & Rwb & (SlaveID_Ok || ((I2CSt == I2CStRdData) & ~RtcAddr[7]));
wire    Read2_Event_set_wire = Read_Event & (RtcAddr[6:0] == 7'd2) & (I2CSt == I2CStSlaveID);

always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        Read2_Event_set <= 1'b0;
    else
        Read2_Event_set <= Read2_Event_set_wire;

assign latdxy_xybuf = Read2_Event_set;

//----------------------------------------------------------------------
//  reset_xybuf : set 2 SCL after latdxy_xybuf, cleared at the end of the byte
//----------------------------------------------------------------------
always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        latdxy_xybuf_d1 <= 1'b0;
    else if (latdxy_xybuf)
        latdxy_xybuf_d1 <= 1'b1;
    else if (latdxy_xybuf_d1)
        latdxy_xybuf_d1 <= 1'b0;

always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        reset_xybuf <= 1'b0;
    else if (latdxy_xybuf_d1)
        reset_xybuf <= 1'b1;
    else if (BitCnt[3])             // increase pulse width for xyclk CDCSync
        reset_xybuf <= 1'b0;

//----------------------------------------------------------------------
//  TXShiftReg
//----------------------------------------------------------------------
always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        TXShiftReg <= {7{1'b1}};
    else if (~RtcRd_b)
        TXShiftReg <= RtcDataO[6:0];
    else
        TXShiftReg <= {TXShiftReg[5:0], 1'b1};

assign  TX_bit = RtcRd_b ? TXShiftReg[6] : RtcDataO[7];

//----------------------------------------------------------------------
//  SDAO
//----------------------------------------------------------------------
always @(posedge SCL_inv or posedge I2CSt_Rst)
    if (I2CSt_Rst)
        SDAO_tmp <= 1'b1;
    else if (StartCmd_SDA)
        SDAO_tmp <= 1'b1;
    else if (BitCnt == 4'd8) begin
        if (I2CSt == I2CStSlaveID)
            SDAO_tmp <= ~SlaveID_Ok;                // 0: send ACK, 1: send NACK
        else if (I2CSt == I2CStIdle)                // release wrong slave ID read
            SDAO_tmp <= 1'b1;
        else if (Rwb && (I2CSt == I2CStRdData))     // receive ACK from host
            SDAO_tmp <= 1'b1;
        else                                        // send ACK to host
            SDAO_tmp <= 1'b0;
    end
    else if ((~Rwb && (BitCnt == 4'd0)) ||
             ( Rwb && (BitCnt == 4'd0) && (I2CSt == I2CStRdData) && NackCmd))
        SDAO_tmp <= 1'b1;                           // receive re-START/STOP from host
    else if (Rwb && (I2CSt == I2CStRdData))
        SDAO_tmp <= TX_bit;

// delay to avoid negedge SDAO violation => StartCmd_SDA
assign #10ps SDAO_tmp_d = SDAO_tmp;
assign #10ps SDAO       = SDAO_tmp_d;

endmodule
