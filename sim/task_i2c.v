// I2C bus / check tasks for tb_i2c.v. Included inside module tb_i2c,
// so it uses the testbench signals, dut, errors and checks declared there.

//-----------------------------------------------------------------------------
//  xybuf handshake counters
//-----------------------------------------------------------------------------
integer lat_cnt = 0, pre_cnt = 0, rst_cnt = 0;
always @(posedge dut.u_i2c.latdxy_xybuf) lat_cnt = lat_cnt + 1;
always @(posedge dut.u_i2c.prelat_xybuf) pre_cnt = pre_cnt + 1;
always @(posedge dut.u_i2c.reset_xybuf)  rst_cnt = rst_cnt + 1;

//-----------------------------------------------------------------------------
//  bus tasks (all tasks start and end with SCL low, except i2c_stop)
//-----------------------------------------------------------------------------
task i2c_start;                         // also used as repeated START
    begin
        sda_o = 1'b1; #QT;
        scl   = 1'b1; #QT;
        sda_o = 1'b0; #QT;
        scl   = 1'b0; #QT;
    end
endtask

task i2c_stop;
    begin
        sda_o = 1'b0; #QT;
        scl   = 1'b1; #QT;
        sda_o = 1'b1; #(QT * 2);
    end
endtask

task i2c_wbit (input b);
    begin
        sda_o = b; #QT;
        scl   = 1'b1; #(QT * 2);
        scl   = 1'b0; #QT;
    end
endtask

task i2c_rbit (output b);
    begin
        sda_o = 1'b1; #QT;
        scl   = 1'b1; #QT;
        b     = MISO; #QT;
        scl   = 1'b0; #QT;
    end
endtask

task i2c_wbyte (input [7:0] data, output nack);
    integer k;
    begin
        for (k = 7; k >= 0; k = k - 1)
            i2c_wbit(data[k]);
        i2c_rbit(nack);
    end
endtask

task i2c_rbyte (input nack_in, output [7:0] data);
    integer k;
    reg     b;
    begin
        for (k = 7; k >= 0; k = k - 1) begin
            i2c_rbit(b);
            data[k] = b;
        end
        i2c_wbit(nack_in);
    end
endtask

//-----------------------------------------------------------------------------
//  checking tasks (call these from the test sequence in tb_i2c.v)
//    i2c_write  (slave, addr, n, data)   START, slave+W, addr, n data bytes, STOP
//    i2c_rd_chk (slave, addr, n, want) write addr, repeated START, slave+R, read n bytes and
//                                        compare (master ACKs all but the last), STOP
//    i2c_nack_chk(slave)                 address phase only, want NACK, STOP
//    pulse_clr / pulse_chk(lat,pre,rst)  zero / compare the xybuf pulse counters
//  data / want hold up to 4 bytes, first byte in [31:24]; n = 1..4 uses the top n bytes
//-----------------------------------------------------------------------------
task i2c_write (input [6:0] sl, input [7:0] ad, input integer n, input [31:0] data);
    integer j;
    reg     nack;
    reg [7:0] b;
    begin
        i2c_start;
        i2c_wbyte({sl, 1'b0}, nack);
        checks = checks + 1;
        if (nack) begin errors = errors + 1; $display("FAIL: slave %h NACK on write", sl); end
        i2c_wbyte(ad, nack);
        checks = checks + 1;
        if (nack) begin errors = errors + 1; $display("FAIL: NACK on address"); end
        for (j = 0; j < n; j = j + 1) begin
            b = data >> (24 - 8*j);
            i2c_wbyte(b, nack);
            checks = checks + 1;
            if (nack) begin errors = errors + 1; $display("FAIL: NACK on data %0d", j); end
        end
        i2c_stop;
        $display("done: write [%h] <= %0d byte(s)", ad, n);
    end
endtask

task i2c_rd_chk (input [6:0] sl, input [7:0] ad, input integer n, input [31:0] want);
    integer j;
    reg     nack;
    reg [7:0] rdata, e;
    begin
        i2c_start;
        i2c_wbyte({sl, 1'b0}, nack);
        checks = checks + 1;
        if (nack) begin errors = errors + 1; $display("FAIL: slave %h NACK on write", sl); end
        i2c_wbyte(ad, nack);
        checks = checks + 1;
        if (nack) begin errors = errors + 1; $display("FAIL: NACK on address"); end
        i2c_start;                      // repeated START
        i2c_wbyte({sl, 1'b1}, nack);
        checks = checks + 1;
        if (nack) begin errors = errors + 1; $display("FAIL: slave %h NACK on read", sl); end
        for (j = 0; j < n; j = j + 1) begin
            e = want >> (24 - 8*j);
            i2c_rbyte((j == n - 1), rdata);
            checks = checks + 1;
            if (rdata !== e) begin
                errors = errors + 1;
                $display("FAIL: read [%h+%0d] = %h, expected %h", ad, j, rdata, e);
            end else
                $display("pass: read [%h+%0d] = %h", ad, j, rdata);
        end
        i2c_stop;
    end
endtask

task i2c_nack_chk (input [6:0] sl);
    reg nack;
    begin
        i2c_start;
        i2c_wbyte({sl, 1'b0}, nack);
        i2c_stop;
        checks = checks + 1;
        if (!nack) begin errors = errors + 1; $display("FAIL: slave %h ACKed, expected NACK", sl); end
        else $display("pass: slave %h NACK", sl);
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

