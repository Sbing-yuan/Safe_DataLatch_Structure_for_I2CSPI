// SPI bus / check tasks for tb_spi.v. Included inside module tb_spi,
// so it uses the testbench signals, dut, errors and checks declared there.

//-----------------------------------------------------------------------------
//  xybuf handshake counters
//-----------------------------------------------------------------------------
integer lat_cnt = 0, pre_cnt = 0, rst_cnt = 0;
always @(posedge dut.u_spi.latdxy_xybuf) lat_cnt = lat_cnt + 1;
always @(posedge dut.u_spi.prelat_xybuf) pre_cnt = pre_cnt + 1;
always @(posedge dut.u_spi.reset_xybuf)  rst_cnt = rst_cnt + 1;

//-----------------------------------------------------------------------------
//  bus tasks
//-----------------------------------------------------------------------------
task spi_bit (input b, output o);
    begin
        sck = 1'b0;
        mosi = b;
        #HALF;
        o = MISO;
        sck = 1'b1;
        #HALF;
    end
endtask

task spi_begin;
    begin
        if (ncs) begin
            ncs = 1'b0;
            #HALF;
        end
    end
endtask

task spi_end;
    begin
        ncs = 1'b1;
        mosi = 1'b0;
        #(HALF * 4);
    end
endtask

task spi_cmd (input rw, input [6:0] addr);
    integer k;
    reg     dummy;
    reg [7:0] c;
    begin
        c = {rw, addr};
        for (k = 7; k >= 0; k = k - 1)
            spi_bit(c[k], dummy);
    end
endtask

task spi_write (input [6:0] addr, input [7:0] data);
    integer k;
    reg     dummy;
    begin
        spi_begin;
        spi_cmd(1'b1, addr);
        for (k = 7; k >= 0; k = k - 1)
            spi_bit(data[k], dummy);
    end
endtask

task spi_read (input [6:0] addr, output [7:0] data);
    integer k;
    reg     b;
    begin
        spi_begin;
        spi_cmd(1'b0, addr);
        for (k = 7; k >= 0; k = k - 1) begin
            spi_bit(1'b0, b);
            data[k] = b;
        end
    end
endtask

//-----------------------------------------------------------------------------
//  checking tasks (call these from the test sequence in tb_spi.v)
//    spi_write (addr, data)              write one byte
//    spi_read  (addr, data)              read one byte
//    spi_rd_chk(addr, want)            read one byte and compare
//    spi_end                             release NCS; calls without it are chained in one frame
//    pulse_clr / pulse_chk(lat,pre,rst)  zero / compare the xybuf pulse counters
//-----------------------------------------------------------------------------
task spi_rd_chk (input [6:0] addr, input [7:0] want);
    reg [7:0] rdata;
    begin
        spi_read(addr, rdata);
        checks = checks + 1;
        if (rdata !== want) begin
            errors = errors + 1;
            $display("FAIL: read [%h] = %h, expected %h", addr, rdata, want);
        end else
            $display("pass: read [%h] = %h", addr, rdata);
    end
endtask

task pulse_clr;
    begin
        lat_cnt = 0; pre_cnt = 0; rst_cnt = 0;
    end
endtask

task pulse_chk (input integer lat, input integer pre, input integer rst);
    begin
        checks = checks + 1;
        if (lat_cnt !== lat || pre_cnt !== pre || rst_cnt !== rst) begin
            errors = errors + 1;
            $display("FAIL: latdxy/prelat/reset_xybuf pulses = %0d/%0d/%0d, expected %0d/%0d/%0d",
                     lat_cnt, pre_cnt, rst_cnt, lat, pre, rst);
        end else
            $display("pass: latdxy/prelat/reset_xybuf pulses = %0d/%0d/%0d", lat_cnt, pre_cnt, rst_cnt);
    end
endtask

