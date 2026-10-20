// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship (Pocket) — the protection, the ispLSI 1016 at
// 310000-31ffff.
//
// A word written anywhere in the window shifts into a 32-bit latch,
// latch = (latch << 16) | data; a read returns mangle(latch) with its bytes
// swapped:
//
//   mangle(x) = get_out(((get_lo(x) ^ 0x0010) - (get_hi(x) ^ 0x0024)) ^ 0x5496)
//
// get_lo, get_hi and get_out are fixed bit shuffles, transcribed from MAME's
// gaelco2_m.cpp (BSD-3-Clause, Manuel Abadia) as tools/snowboar_prot.py
// has them: here they are wiring, the rest two XORs and a subtractor. MAME
// takes a byte write's data whole; the game writes only words.

`default_nettype none

module snowboar_prot (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,             // one clock a write
    input  wire [15:0] din,
    output wire [15:0] dout
);

reg [31:0] latch;
always @(posedge clk) begin
    if (rst)     latch <= 32'd0;
    else if (we) latch <= {latch[15:0], din};
end

wire [15:0] lo = {latch[6],  latch[11], latch[18], latch[20], latch[3],  latch[26], latch[14], latch[2],
                  latch[17], latch[0],  latch[4],  latch[5],  latch[30], latch[13], latch[15], latch[23]};
wire [15:0] hi = {latch[31], latch[22], latch[1],  latch[12], latch[29], latch[10], latch[19], latch[21],
                  latch[8],  latch[27], latch[24], latch[16], latch[7],  latch[28], latch[25], latch[9]};
wire [15:0] d  = ((lo ^ 16'h0010) - (hi ^ 16'h0024)) ^ 16'h5496;
wire [15:0] m  = {d[15], d[14], d[0],  d[4], d[11], d[1], d[7],  d[3],
                  d[13], d[6],  d[2],  d[12], d[5], d[10], d[8], d[9]};

assign dout = {m[7:0], m[15:8]};

endmodule

`default_nettype wire
