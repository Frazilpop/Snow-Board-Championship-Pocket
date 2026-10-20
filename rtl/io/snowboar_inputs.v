// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship (Pocket) — the input ports and the LS259 (MAME
// gaelco2.cpp, INPUT_PORTS_START(snowboar) and snowboar()).
//
//   P1 300000, P2 300010   bits 0-6 up, down, right, left, buttons 1-3,
//                          active low; 15:7 read 1
//   COIN 300020            coin 1, coin 2, service "NOW", service 1,
//                          start 1, start 2 (active low), the EEPROM's DO
//                          (bit 6, active high), bit 7 1; an 8-bit port,
//                          15:8 read 0
//
// The LS259 at 300000-30000f takes D0 of a low-byte write into Q(A3..A1):
// Q0, Q1 the coin counters, Q4 the EEPROM's DI, Q5 its CLK, Q6 its CS.

`default_nettype none

module snowboar_inputs (
    input  wire        clk,
    input  wire        rst,

    // active high; p = {b3, b2, b1, up, down, left, right}
    input  wire [6:0]  p1, p2,
    input  wire [1:0]  coin, start,
    input  wire        service,        // "go to service mode NOW"
    input  wire        service1,
    input  wire        eep_do,

    output wire [15:0] port_p1, port_p2, port_coin,

    input  wire        latch_we,       // a low-byte write to 300000-30000f
    input  wire [2:0]  latch_sel,      // A3..A1
    input  wire        latch_d,        // D0
    output reg  [7:0]  q
);
    function automatic [6:0] joy(input [6:0] p);
        joy = ~{p[6], p[5], p[4], p[1], p[0], p[2], p[3]};   // b3 b2 b1 left right down up
    endfunction

    assign port_p1   = {9'h1ff, joy(p1)};
    assign port_p2   = {9'h1ff, joy(p2)};
    assign port_coin = {8'h00, 1'b1, eep_do, ~start[1], ~start[0], ~service1, ~service, ~coin[1], ~coin[0]};

    always @(posedge clk) begin
        if (rst) q <= 8'd0;
        else if (latch_we) q[latch_sel] <= latch_d;
    end
endmodule

`default_nettype wire
