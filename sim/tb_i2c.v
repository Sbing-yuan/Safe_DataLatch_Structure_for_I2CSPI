// ChipTop I2C test (IF_SEL = 0). Directed test, tasks are in task_i2c.v
// SCK is SCL, MISO is SDA (open-drain with pull-up), MOSI unused, slave ID 7'h13.
`timescale 1ns/1ps
module tb_i2c;

localparam QT = 2500;                   // quarter bit time, 100 kHz

reg             scl     = 1'b1;
reg             sda_o   = 1'b1;         // 0: master pulls SDA low, 1: released
reg             if_sel  = 1'b0;

wire            SCK     = scl;
wire            IF_SEL  = if_sel;
tri1            MISO;                   // SDA with pull-up
wire            MOSI    = 1'b0;         // unused in I2C mode
wire            NCS     = 1'b1;

assign MISO = sda_o ? 1'bz : 1'b0;

ChipTop dut (.MOSI(MOSI), .MISO(MISO), .SCK(SCK), .NCS(NCS), .IF_SEL(IF_SEL));

integer errors = 0;
integer checks = 0;

`include "task_i2c.v"


//-----------------------------------------------------------------------------
//  test sequence (register n resets to A5 ^ n, slave ID 7'h13)
//-----------------------------------------------------------------------------
initial begin
    #5000;                              // power-on reset (1 us) and settling

    // ---- reset values (single read)
    i2c_rd_chk(7'h13, 8'h00, 1, 32'h5A000000);
    i2c_rd_chk(7'h13, 8'h20, 1, 32'h85000000);
    i2c_rd_chk(7'h13, 8'h7F, 1, 32'hDA000000);

    // ---- write / read back
    i2c_write (7'h13, 8'h10, 1, 32'hA6000000);
    i2c_rd_chk(7'h13, 8'h10, 1, 32'hA6000000);
    i2c_write (7'h13, 8'h00, 1, 32'h5A000000);
    i2c_rd_chk(7'h13, 8'h00, 1, 32'h5A000000);
    i2c_write (7'h13, 8'h7F, 1, 32'h00000000);
    i2c_rd_chk(7'h13, 8'h7F, 1, 32'h00000000);

    // ---- burst write / burst read (address auto-increments)
    i2c_write (7'h13, 8'h40, 4, 32'h11223344);
    i2c_rd_chk(7'h13, 8'h40, 4, 32'h11223344);
    // read burst across untouched registers (A5 ^ 44 = E1 ...)
    i2c_rd_chk(7'h13, 8'h44, 3, 32'hE1E0E300);
    // overwrite one byte in the middle
    i2c_write (7'h13, 8'h41, 1, 32'h99000000);
    i2c_rd_chk(7'h13, 8'h40, 4, 32'h11993344);

    // ---- wrong slave IDs get NACK (7'h33 is the slave ID only when B_slaveID_state = 1)
    i2c_nack_chk(7'h44);
    i2c_nack_chk(7'h53);
    i2c_nack_chk(7'h33);
    // the bus still works afterwards
    i2c_rd_chk(7'h13, 8'h60, 1, 32'hC5000000);

    // ---- xybuf handshake : only a read of address 2 pulses latdxy / reset_xybuf
    // prelat_xybuf rises once per slave-ID phase : a write has one, a read (write phase of the
    // address + repeated START + read phase) has two
    pulse_clr;
    i2c_rd_chk(7'h13, 8'h03, 1, 32'h00000000);
    pulse_chk(0, 2, 0);
    pulse_clr;
    i2c_rd_chk(7'h13, 8'h02, 1, 32'hFF000000);
    pulse_chk(1, 2, 1);
    pulse_clr;
    i2c_write (7'h13, 8'h02, 1, 32'h11000000);
    pulse_chk(0, 1, 0);
    pulse_clr;
    i2c_rd_chk(7'h13, 8'h02, 1, 32'hFF000000);
    pulse_chk(1, 2, 1);

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
        $dumpfile("build/tb_i2c.vcd");
        $dumpvars(0, tb_i2c);
    end
end

// watchdog
initial begin
    #100_000_000;
    $display("RESULT: FAIL (timeout)");
    $finish;
end

endmodule
