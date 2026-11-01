// Behavioral models of the cells that are not part of this repository.
// Simulation only. List this file first so that its `timescale applies to rtl/.
`timescale 1ns/1ps

// ---------------------------------------------------------------- std cells
module GATE_BUF (output O, input I);
    assign O = I;
endmodule

// ---------------------------------------------------------- on-chip macros
// power-on reset, asserted at 1 ns (after all always blocks are armed), released after 1 us
module POR_CELL (output reg PURSTB);
    initial begin
        PURSTB = 1'b1;
        #1    PURSTB = 1'b0;
        #1000 PURSTB = 1'b1;
    end
endmodule

// system clock generator : SYSCLK stays 0, then runs at 50 MHz T_START after PURSTB is
// released. Asserting PURSTB again stops the clock and drives it back to 0.
module CLKGEN_CELL (input PURSTB, output reg SYSCLK);
    parameter T_START = 1_000_000;      // ns, 1 ms
    parameter T_HALF  = 10;             // ns, 50 MHz

    integer epoch = 0;
    reg     run   = 1'b0;

    initial SYSCLK = 1'b0;

    always @(negedge PURSTB) begin
        disable gen;
        epoch  = epoch + 1;
        run    = 1'b0;
        SYSCLK = 1'b0;
    end

    always @(posedge PURSTB) begin : start
        integer e;
        e = epoch;
        #(T_START);
        if (e == epoch && PURSTB)
            run = 1'b1;
    end

    always @(posedge run) begin : gen
        SYSCLK = 1'b1;                  // first rising edge at T_START
        forever #(T_HALF) SYSCLK = ~SYSCLK;
    end
endmodule
