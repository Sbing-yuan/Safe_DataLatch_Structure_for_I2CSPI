module B_SpiCtl(
   /*AUTOARG*/
   // Outputs
   r_sdo, datavalid, r_sdiotri_enh, p_bankdata, p_bankaddr,
   RdPix_Done, RdPix_Rst, RdPix_Rst_pxck, write3, reset_xybuf,
   latdxy_xybuf, prelat_xybuf, DirSum_reset, busy_protect, cpd_r_spi,
   cpd_raddr_upd_spi,
   // Inputs
   ATPG_TM, ATPG_RSTB, sclk, sclk_inv, rst_n, i_ncs, B_4wspi_ncs0,
   sysclk, C_purstb_px, i_sdi, B_bankdata, B_banksel, B_w3clr_enh,
   B_ppg_enh, B_spo2_enh, B_spi_burstrd_enh, B_burstrd_1dummy,
   B_burstrd_saddr, B_burstrd_waddr, B_burstrd_1addr, B_burstrd_2addr,
   lpoclk, B_rstspi_th, D_direction
   );

//=============================================================================
//                          Parameters Declaration
//-----------------------------------------------------------------------------
//Constraint1 : Upper case presents constance
//=============================================================================
parameter       STBY     = 3'b000,
                ADDR     = 3'b001,
                READ     = 3'b010,
                WRITE    = 3'b011,
                BURST    = 3'b101,	// Add by YaoHsuan 2019.4.1 Seperate with READ
                DUMMY    = 3'b110;	// Add by Littlerice 2023.3.29 Seperate from BURST

`include "./def_para.v"
//=============================================================================
//                           Input Port Declaration
//-----------------------------------------------------------------------------
//Constraint1 : Little-ediance is used
//Constraint2 : one line one declaration
//=============================================================================

input           ATPG_TM;
input           ATPG_RSTB;

input           sclk;
input           sclk_inv;
input		rst_n;
input           i_ncs;
input		B_4wspi_ncs0;

input           sysclk;
input           C_purstb_px;

input           i_sdi;
input   [7:0]   B_bankdata;
input   [2:0]   B_banksel;

input           B_w3clr_enh;
input		B_ppg_enh;
input		B_spo2_enh;

// Burst read
input           B_spi_burstrd_enh;
input		B_burstrd_1dummy;
input	[7:0]	B_burstrd_saddr;
input           B_burstrd_waddr;
input		B_burstrd_1addr;
input		B_burstrd_2addr;

input		lpoclk;
input   [7:0]   B_rstspi_th;

input		D_direction;

//=============================================================================//
//                          Output Port Declaration                            //
//-----------------------------------------------------------------------------//
//Constraint1 : Little-ediance is used                                         //
//Constraint2 : one line one declaration                                       //
//=============================================================================//
output          r_sdo;
output          datavalid;
output          r_sdiotri_enh;

output  [7:0]   p_bankdata;
output  [6:0]   p_bankaddr;
//-- RdPix
output          RdPix_Done;
output          RdPix_Rst;
output          RdPix_Rst_pxck;

// XYBuf_Top
output          write3;
output		reset_xybuf;
output          latdxy_xybuf;
output		prelat_xybuf;

output          DirSum_reset;
output          busy_protect;

output		cpd_r_spi;
output		cpd_raddr_upd_spi;

//=============================================================================//
//                          Registers Declaration                              //
//-----------------------------------------------------------------------------//
//Constraint1 :                                                                //
//=============================================================================//

wire		spirstb;
wire		ATPG_spirstb;

wire	[7:0]	p_bankdata;
reg	[6:0]	p_bankaddr;
reg	[6:0]	p_bankaddr_nxt;
reg		r_sdiotri_enh;
reg		reset_xybuf;

reg	[2:0]	spistate;
reg	[2:0]	count_spi;
reg	[7:0]	ibuf;
reg	[6:0]	ibuf_d1;
reg	[7:0]	obuf;

reg		burstrd_2addr_init;
reg             DirSum_reset;
reg             busy_protect;
reg             Dir0x02_issue;

//-- RdPix
wire		r_sdo;
wire		datavalid;

//---------burst mode
wire		burstrd_by_waddr;
wire		burstrd_by_raddr;

//negedge sync set
wire		latdxy_set;
wire		spi_Read2_set;
wire		spi_Write2_set;
reg		spi_Write2;
reg		spi_Read2;
//posedge sync set
wire		spi_Write3_set;
wire		spi_Read15_set;
wire		spi_Write15_set;
//negedge sync set
wire		RdPix_Done;
wire		RdPix_Rst;
reg		spi_RdPix_Done;
reg		spi_RdPix_Rst;

reg		prelat;
reg		latdxy;
wire		prelat_vld;

reg		write3;
reg		rstspi_flg;
reg	[7:0]	resync_timer;
reg		spi_WriteBRSA;
reg		spi_ReadBRSA;
reg		cpd_r_spi;
reg		cpd_raddr_upd_spi;

assign burstrd_by_raddr = B_spi_burstrd_enh & ~B_burstrd_waddr;
assign burstrd_by_waddr = B_spi_burstrd_enh &  B_burstrd_waddr;

assign  ATPG_spirstb = rst_n & (B_4wspi_ncs0 | ~i_ncs) & ~rstspi_flg;

GATE_MUX2 MUX_spirstb (.O(spirstb  ), .S(ATPG_TM), .A( ATPG_spirstb  ), .B( ATPG_RSTB ));

assign r_sdo = obuf[7];

// delay half cycle to meet data protocol
always @ (posedge sclk_inv or negedge spirstb)
    if (~spirstb)
        ibuf_d1[6:0] <= 0;
    else
        ibuf_d1[6:0] <= ibuf[6:0];

// data input buffer
always @ (posedge sclk or negedge spirstb)
    if (~spirstb)
        ibuf[7:0] <= 0;
    else
        ibuf[7:0] <= {ibuf[6:0], i_sdi};

assign  p_bankdata = {ibuf_d1,i_sdi};

assign  count0_flg = (count_spi == 'd0);
assign  count6_flg = (count_spi == 'd6);
assign  count7_flg = (count_spi == 'd7);

`ifdef FPGA
// Because GATE_GCK is DFF-based in FPGA, not latch-based
// GCK/en timing margin for p_storedata is only 0.5T
// for this reason, datavalid needs to early toggle 1T for FPGA
assign  datavalid  = ((spistate == WRITE) & count6_flg);
`else
assign  datavalid  = ((spistate == WRITE) & count7_flg);
`endif

assign Read_Event		= ~ibuf_d1[6] & count7_flg & (spistate == ADDR);
assign Write_Event		=  ibuf_d1[6] & count7_flg & (spistate == ADDR);

assign spi_Read2_set	= Read_Event  & ({ibuf_d1[5:0],i_sdi} == 7'd2 ) & (B_banksel == 'd0);
assign spi_Read15_set	= Read_Event  & ({ibuf_d1[5:0],i_sdi} == 7'd15) & (B_banksel == 'd0);
assign spi_Write2_set	= Write_Event & ({ibuf_d1[5:0],i_sdi} == 7'd2 ) & (B_banksel == 'd0);
assign spi_Write3_set	= Write_Event & ({ibuf_d1[5:0],i_sdi} == 7'd3 ) & (B_banksel == 'd0);
assign spi_Write15_set	= Write_Event & ({ibuf_d1[5:0],i_sdi} == 7'd15) & (B_banksel == 'd0);

assign spi_Read80_set	= ~B_burstrd_waddr & Read_Event  & ({ibuf_d1[5:0],i_sdi} == 7'd80) & (B_banksel == 'd0);
assign spi_Write80_set	=  B_burstrd_waddr & Write_Event & ({ibuf_d1[5:0],i_sdi} == 7'd80) & (B_banksel == 'd0);

assign spi_ReadBRSA_set = Read_Event  & ({ibuf_d1[5:0],i_sdi} == B_burstrd_saddr[6:0]) & burstrd_by_raddr;
assign spi_WriteBRSA_set= Write_Event & ({ibuf_d1[5:0],i_sdi} == B_burstrd_saddr[6:0]) & burstrd_by_waddr;

// -------------------- 2-wire SPI resync Design --------------------
GATE_MUX2 MUX_reset_sclk_inv (.O(sync_sclk_inv_rstb), .S(ATPG_TM), .A(rst_n & sclk_inv), .B(ATPG_RSTB));
CDCSync_Signal_ResetL  CDCSync_sclk_inv  (.CLK(lpoclk), .RSTn(sync_sclk_inv_rstb), .DI(1'b1), .DO(sync_sclk_inv));

GATE_MUX2 MUX_resync_rstb (.O(resync_rstb), .S(ATPG_TM), .A(sync_sclk_inv), .B(ATPG_RSTB) );

//       LPO : 32K (11.2 K~52.8 K)
// spec. is 10 ms
// use LPO
// B_rstspi_th = 105, tspi_resync = 1.99ms ~ 9.37ms

assign resync_timer_over = (resync_timer[7:0] >= B_rstspi_th);

always @(posedge lpoclk or negedge resync_rstb)
    if (~resync_rstb)
        resync_timer <= 'd0;
    else if (~resync_timer_over)
        resync_timer <= resync_timer + 'd1;

always @(posedge lpoclk or negedge resync_rstb)
    if (~resync_rstb)
        rstspi_flg <= 'd0;
    else if (resync_timer_over)
        rstspi_flg <= 'd1;

// -------------------- end of design --------------------

always @ (posedge sclk_inv or negedge spirstb)
    if (~spirstb) begin
        count_spi <= 3'd0;
        r_sdiotri_enh <= 1;
        obuf[7:0] <= 8'hff;
        spistate <= STBY;
    end else
        case (spistate) // SPI1--------------------------------------
        STBY:
        begin
            count_spi <= 3'd0;
            r_sdiotri_enh <= 1;
            obuf[7:0] <= 8'hff;
            spistate <= ADDR;
        end
        ADDR:
	begin
            if (count7_flg) begin
                if (ibuf[7]==1) begin  // write
                    count_spi <= 3'd0;
                    if(burstrd_by_waddr) begin
                        r_sdiotri_enh <= (spi_WriteBRSA) ? 0 : 1;
                        obuf[7:0]     <= (spi_WriteBRSA) ? B_bankdata : 8'hff;
                        spistate      <= (spi_WriteBRSA) ? (B_burstrd_1dummy ? DUMMY : BURST) : WRITE;
                    end
                    else begin
                        r_sdiotri_enh <= 1;
                        obuf[7:0]     <= 8'hff;
                        spistate      <= WRITE;
                    end
                end
                else begin		// read
                    count_spi <= 3'd0;
                    r_sdiotri_enh <= 0;
                    obuf[7:0] <= B_bankdata;
                    if(burstrd_by_raddr) begin
                        spistate <= (spi_ReadBRSA) ? (B_burstrd_1dummy ? DUMMY : BURST) : READ;
                    end
                    else
                        spistate <= READ;
                end
            end
            else begin
                count_spi <= count_spi + 1;
                r_sdiotri_enh <= 1;
                obuf[7:0] <= 8'hff;
                spistate <= ADDR;
            end
        end
        WRITE:
	begin
            if (count7_flg) begin
                count_spi <= 3'd0;
                r_sdiotri_enh <= 1;
                obuf[7:0] <= 8'hff;
                spistate <= ADDR;
            end
            else begin
                count_spi <= count_spi + 1;
                r_sdiotri_enh <= 1;
                obuf[7:0] <= 8'hff;
                spistate <= WRITE;
            end
	end
        READ:
	begin
            if (count7_flg) begin
                count_spi <= 3'd0;
                r_sdiotri_enh <= 1;
                obuf[7:0] <= 8'hff;
                spistate <= ADDR;
            end
            else begin
                count_spi <= count_spi + 1;
                r_sdiotri_enh <= 0;
                obuf[0] <= 1;
                obuf[7:1] <= obuf[6:0];
                spistate <= READ;
            end
	end
	DUMMY:
        begin
            if (count7_flg) begin
                count_spi <= 3'd0;
                obuf[7:0] <= B_bankdata;
                spistate  <= BURST;
            end
            else begin
              count_spi <= count_spi + 1;
              obuf[0] <= 1;
              obuf[7:1] <= obuf[6:0];
              spistate <= DUMMY;
            end
        end
	BURST:
	begin
            if (count7_flg) begin
                count_spi <= 3'd0;
                if(B_spi_burstrd_enh) begin
                    obuf[7:0]     <= B_bankdata;
                    spistate      <= BURST;
                    r_sdiotri_enh <= 0;
                end
                else begin
                    obuf[7:0] <= 8'hff;
                    spistate  <= ADDR;
                    r_sdiotri_enh <= 1;
                end
            end
            else begin
              count_spi <= count_spi + 1;
              r_sdiotri_enh <= 0;
              obuf[0] <= 1;
              obuf[7:1] <= obuf[6:0];
              spistate <= BURST;
            end
	end

        endcase

always @ (posedge sclk or negedge spirstb) begin
    if (~spirstb)
//        p_bankaddr <= 7'b000_0011;
        p_bankaddr <= 7'd0;
    else
        p_bankaddr <= p_bankaddr_nxt;
end

always @ (*) begin
    if(count7_flg & (spistate == ADDR)) begin
        if(spi_WriteBRSA_set | spi_ReadBRSA_set)
            p_bankaddr_nxt = B_burstrd_saddr;
        else
            p_bankaddr_nxt = {ibuf_d1[5:0],i_sdi};
    end else if(count7_flg & (spistate == DUMMY)) begin
        p_bankaddr_nxt = p_bankaddr;
    end else if(count7_flg & (spistate == BURST)) begin
        if (B_burstrd_1addr)
            p_bankaddr_nxt = p_bankaddr;
        else if (B_burstrd_2addr) begin
            if (~burstrd_2addr_init)
                p_bankaddr_nxt = B_burstrd_saddr + 1;
            else
                p_bankaddr_nxt = B_burstrd_saddr;
        end
        else
            p_bankaddr_nxt = p_bankaddr + 1;
    end else begin
        p_bankaddr_nxt = p_bankaddr;
    end
end

always @ (posedge sclk or negedge spirstb) begin
    if (spirstb == 0)
        burstrd_2addr_init <= 1'b0;
    else if (count7_flg & (spistate == BURST))
        burstrd_2addr_init <= ~burstrd_2addr_init;
end
//------------------------------------------------------------------------------
//---read motion contorller

assign  latdxy_set = burstrd_by_waddr ? spi_Write2_set : spi_Read2_set;

always @ (posedge sclk or negedge spirstb)
    if (~spirstb)
        spi_Write2 <= 0;
    else if(spi_Write2_set)
        spi_Write2 <= 1;
    else if (spi_Write2)
        spi_Write2 <= 0;

always @ (posedge sclk or negedge spirstb)
    if (~spirstb)
        spi_Read2 <= 0;
    else if(spi_Read2_set)
        spi_Read2 <= 1;
    else if (spi_Read2)
        spi_Read2 <= 0;

always @ (posedge sclk or negedge spirstb)
    if (~spirstb)
        spi_WriteBRSA <= 0;
    else if(spi_WriteBRSA_set)
        spi_WriteBRSA <= 1;
    else if (spi_WriteBRSA)
        spi_WriteBRSA <= 0;

always @ (posedge sclk or negedge spirstb)
    if (~spirstb)
        spi_ReadBRSA <= 0;
    else if(spi_ReadBRSA_set)
        spi_ReadBRSA <= 1;
    else if (spi_ReadBRSA)
        spi_ReadBRSA <= 0;

always @ (posedge sclk or negedge spirstb)
    if (~spirstb) begin
        prelat  <= 0;
    end else if (spistate == ADDR) begin
        if (count0_flg) begin
            prelat  <= 1;
        end else if (count7_flg) begin
            prelat  <= 0;
        end
    end

assign prelat_xybuf = prelat;

always @ (posedge sclk or negedge spirstb)
    if (~spirstb)
        latdxy <= 0;
    else if (latdxy_set)
        latdxy <= 1;
    else if (latdxy)
        latdxy <= 0;

assign latdxy_xybuf = latdxy;

reg	latdxy_xybuf_d1;
always @ (posedge sclk or negedge spirstb) begin
    if (~spirstb)
        latdxy_xybuf_d1 <= 0;
    else if (latdxy_xybuf)
        latdxy_xybuf_d1 <= 1;
    else if (latdxy_xybuf_d1)
        latdxy_xybuf_d1 <= 0;
end

always @ (posedge sclk or negedge spirstb) begin
    if (~spirstb)
        reset_xybuf <= 0;
    else if (latdxy_xybuf_d1)
        reset_xybuf <= 1;
    else if (count7_flg)		// increase pulse width for xyclk CDCSync
        reset_xybuf <= 0;
end

//----------------------------------------------------------------------
//  Dir0x02_issue, DirSum_reset, busy_protect
//----------------------------------------------------------------------
always @ (posedge sclk or negedge spirstb)
    if (~spirstb)
        Dir0x02_issue     <= 1'b0;
    else if(Dir0x02_issue)
        Dir0x02_issue     <= 1'b0;
    else if(latdxy_xybuf)
        Dir0x02_issue     <= D_direction;

always @(posedge sclk or negedge spirstb)
    if (~spirstb)
        DirSum_reset <= 1'b0;
    else if (Dir0x02_issue)
        DirSum_reset <= 1'b1;
    else if (count7_flg)
        DirSum_reset <= 1'b0;

always @ (posedge sclk or negedge spirstb)
    if (~spirstb)
        busy_protect  <= 0;
    else if (spistate == ADDR)
        busy_protect  <= count0_flg ? 1 : busy_protect;
    else if (count7_flg)
        busy_protect  <= 0;

// Write 3 triggers D_XYBuf & B_SpiCtl motion buffers to reset motion value
always @ (posedge sclk or negedge spirstb)
    if (~spirstb)
        write3 <=0;
    else if (spi_Write3_set)
        write3 <= B_w3clr_enh;
    else if (count7_flg)		// increase pulse width for xyclk CDCSync
        write3 <=0;

//----------------------------------------
//---            CPD                   ---
//----------------------------------------
always @ (posedge sclk or negedge spirstb) begin
    if (~spirstb)
        cpd_r_spi <= 0;
    else if ((B_ppg_enh | B_spo2_enh) & (spi_Read80_set | spi_Write80_set))
        cpd_r_spi <= 1;
end

always @ (posedge sclk or negedge spirstb) begin
    if (~spirstb)
        cpd_raddr_upd_spi <= 0;
    else if (spistate == BURST) begin
        if (count0_flg)
            cpd_raddr_upd_spi <= 1;
        else if (count6_flg)
            cpd_raddr_upd_spi <= 0;
    end
end

//----------------------------------------
//---            Pixel Dump            ---
//----------------------------------------
// Read 15 triggers D_RdPix to get new pxo to output
always @ (posedge sclk or negedge spirstb) begin
    if (~spirstb)
        spi_RdPix_Done <= 0;
    else if(spi_Read15_set)
        spi_RdPix_Done <= 1;
    else if(count7_flg)
        spi_RdPix_Done <= 0;
end

assign RdPix_Done = spi_RdPix_Done;

// Write 15 triggers D_RdPix to reset pxo addr to 0
always @ (posedge sclk or negedge spirstb) begin
    if (~spirstb)
        spi_RdPix_Rst <= 0;
    else if (spi_Write15_set | spi_Write2_set)
        spi_RdPix_Rst <= 1;
    else
        spi_RdPix_Rst <= 0;
end

Sync_Pulse sync_spi_RdPix_Rst (
        // Outputs
        .b_pulseout	(spi_RdPix_Rst_pxck),
        // Inputs
        .a_pulsein	(spi_RdPix_Rst),
        .a_clk		(sclk),
        .a_rstn		(rst_n),
        .b_clk		(sysclk),
        .b_rstn		(C_purstb_px));

assign RdPix_Rst = spi_RdPix_Rst;
assign RdPix_Rst_pxck = spi_RdPix_Rst_pxck;

endmodule
