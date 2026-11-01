module B_SPICtl(
    /*AUTOARG*/
    // Outputs
    r_sdo, datavalid, r_sdiotri_enh, p_bankdata, p_bankaddr,
    reset_xybuf, latdxy_xybuf, prelat_xybuf,
    // Inputs
    sclk, sclk_inv, rst_n, i_ncs, 
    i_sdi, B_bankdata
);

//=============================================================================
//                          Parameters Declaration
//-----------------------------------------------------------------------------
//Constraint1 : Upper case presents constance
//=============================================================================
parameter       STBY     = 3'b000,
                ADDR     = 3'b001,
                READ     = 3'b010,
                WRITE    = 3'b011;

//=============================================================================
//                           Input Port Declaration
//-----------------------------------------------------------------------------
//Constraint1 : Little-ediance is used
//Constraint2 : one line one declaration
//=============================================================================

input           sclk;
input           sclk_inv;
input           rst_n;
input           i_ncs;

input           i_sdi;
input   [7:0]   B_bankdata;

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
// XYBuf_Top
output          reset_xybuf;
output          latdxy_xybuf;
output          prelat_xybuf;

//=============================================================================//
//                          Registers Declaration                              //
//-----------------------------------------------------------------------------//
//Constraint1 :                                                                //
//=============================================================================//

wire            spirstb;

wire    [7:0]   p_bankdata;
reg     [6:0]   p_bankaddr;
reg     [6:0]   p_bankaddr_nxt;
wire            r_sdo;
wire            datavalid;
reg             r_sdiotri_enh;

reg     [2:0]   spistate;
reg     [2:0]   count_spi;
reg     [7:0]   ibuf;
reg     [6:0]   ibuf_d1;
reg     [7:0]   obuf;

wire            count0_flg;
wire            count7_flg;

//---------address decode
wire            Read_Event;
wire            spi_Read2_set;

//---------XYBuf_Top
reg             prelat;
reg             latdxy;
reg             latdxy_xybuf_d1;
reg             reset_xybuf;

GATE_BUF BUF_spirstb (.O(spirstb), .I(rst_n & ~i_ncs));

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
assign  count7_flg = (count_spi == 'd7);

assign  datavalid  = ((spistate == WRITE) & count7_flg);

assign Read_Event  = ~ibuf_d1[6] & count7_flg & (spistate == ADDR);

assign spi_Read2_set = Read_Event & ({ibuf_d1[5:0],i_sdi} == 7'd2);

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
                    count_spi <= 3'd0;
                    if (ibuf[7]==1) begin   // write
                        r_sdiotri_enh <= 1;
                        obuf[7:0]     <= 8'hff;
                        spistate      <= WRITE;
                    end
                    else begin              // read
                        r_sdiotri_enh <= 0;
                        obuf[7:0]     <= B_bankdata;
                        spistate      <= READ;
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
        endcase

always @ (posedge sclk or negedge spirstb) begin
    if (~spirstb)
        //        p_bankaddr <= 7'b000_0011;
        p_bankaddr <= 7'd0;
    else
        p_bankaddr <= p_bankaddr_nxt;
end

always @ (*) begin
    if(count7_flg & (spistate == ADDR))
        p_bankaddr_nxt = {ibuf_d1[5:0],i_sdi};
    else
        p_bankaddr_nxt = p_bankaddr;
end

//------------------------------------------------------------------------------
//---read motion contorller

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
    else if (spi_Read2_set)
        latdxy <= 1;
    else if (latdxy)
        latdxy <= 0;

assign latdxy_xybuf = latdxy;

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
    else if (count7_flg)                // increase pulse width for xyclk CDCSync
        reset_xybuf <= 0;
end

endmodule
