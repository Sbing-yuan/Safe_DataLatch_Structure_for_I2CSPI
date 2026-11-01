// ChipTop SPI test (IF_SEL = 1). Directed test, tasks are in task_spi.v
// SPI mode 3 : SCK idles high, MOSI changes on the falling edge, sampled on the rising edge.
`timescale 1ns/1ps
module tb_spi;

localparam HALF = 250;                  // SCK half period, 2 MHz

reg             sck     = 1'b1;
reg             ncs     = 1'b1;
reg             mosi    = 1'b0;
reg             if_sel  = 1'b1;

wire            SCK     = sck;
wire            NCS     = ncs;
wire            IF_SEL  = if_sel;
wire            MOSI    = mosi;
wire            MISO;

ChipTop dut (.MOSI(MOSI), .MISO(MISO), .SCK(SCK), .NCS(NCS), .IF_SEL(IF_SEL));

integer errors = 0;
integer checks = 0;

`include "task_spi.v"


//-----------------------------------------------------------------------------
//  test sequence (register n resets to A5 ^ n)
//-----------------------------------------------------------------------------
initial begin
    // power-on reset (1 us) and settling. NCS is high at time 0, so the SPI slave is held in
    // reset by NCS from the very start and sees no falling edge of its reset: pulse NCS once.
    #2000;
    ncs = 1'b0;
    #(HALF);
    ncs = 1'b1;
    #3000;

    // ---- reset values
    spi_rd_chk(7'h00, 8'h5A);  spi_end;
    spi_rd_chk(7'h01, 8'hA5);  spi_end;
    spi_rd_chk(7'h02, 8'hFF);  spi_end;
    spi_rd_chk(7'h03, 8'h00);  spi_end;
    spi_rd_chk(7'h04, 8'h77);  spi_end;
    spi_rd_chk(7'h05, 8'h99);  spi_end;
    spi_rd_chk(7'h06, 8'hAA);  spi_end;
    spi_rd_chk(7'h07, 8'hCC);  spi_end;

    spi_write (7'h08, 8'h5A);  spi_end;
    spi_rd_chk(7'h08, 8'h5A);  spi_end;
    spi_write (7'h08, 8'hA5);  spi_end;
    spi_rd_chk(7'h08, 8'hA5);  spi_end;
    spi_write (7'h08, 8'h00);  spi_end;
    spi_rd_chk(7'h08, 8'h00);  spi_end;
    spi_write (7'h08, 8'hFF);  spi_end;
    spi_rd_chk(7'h08, 8'hFF);  spi_end;

    //// ---- write / read back
    //spi_write(7'h10, 8'h5A);   spi_end;
    //spi_rd_chk(7'h10, 8'h5A);  spi_end;
    //spi_write(7'h00, 8'hFF);   spi_end;
    //spi_rd_chk(7'h00, 8'h5A);   // write ignored  spi_end;
    //spi_write(7'h7F, 8'h00);   spi_end;
    //spi_rd_chk(7'h7F, 8'h00);  spi_end;
    //// overwrite
    //spi_write(7'h55, 8'hAA);   spi_end;
    //spi_write(7'h55, 8'h55);   spi_end;
    //spi_rd_chk(7'h55, 8'h55);  spi_end;

    //// ---- several transfers in one NCS frame
    //spi_write(7'h30, 8'h12);
    //spi_write(7'h31, 8'h34);
    //spi_rd_chk(7'h30, 8'h12);
    //spi_rd_chk(7'h31, 8'h34);  spi_end;
    //// neighbour untouched (A5 ^ 32 = 97)
    //spi_rd_chk(7'h32, 8'h97);  spi_end;
//
    //// ---- xybuf handshake : only a read of address 2 pulses latdxy / reset_xybuf
    //pulse_clr;
    //spi_rd_chk(7'h03, 8'h00);  spi_end;
    //pulse_chk(0, 1, 0);
    //pulse_clr;
    //spi_rd_chk(7'h02, 8'hFF);  spi_end;
    //pulse_chk(1, 1, 1);
    //pulse_clr;
    //spi_write(7'h02, 8'h11);   spi_end;
    //pulse_chk(0, 1, 0);
    //pulse_clr;
    //spi_rd_chk(7'h02, 8'hFF);  spi_end;
    //pulse_chk(1, 1, 1);
    //// two reads of address 2 in one frame
    //pulse_clr;
    //spi_rd_chk(7'h02, 8'hFF);
    //spi_rd_chk(7'h02, 8'hFF);  spi_end;
    //pulse_chk(2, 2, 2);

    if (!ncs) spi_end;
    #5000;
    if (errors == 0)
        $display("RESULT: PASS (%0d checks)", checks);
    else
        $display("RESULT: FAIL (%0d of %0d checks failed)", errors, checks);
    $finish;
end

// waveform dump : vvp ... +dump
initial begin
    if ($test$plusargs("dump")) begin
        $dumpfile("build/tb_spi.vcd");
        $dumpvars(0, tb_spi);
    end
end

// watchdog
initial begin
    #50_000_000;
    $display("RESULT: FAIL (timeout)");
    $finish;
end

endmodule
