// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship (Pocket) — one fetcher's view of an SDRAM line
// port (World Rally 2's).
//
// jlrh's fetchers present an address and wait for `ok`, which means "the
// data for the address now on the bus" (jtframe's convention). The platform
// hands out 64-bit lines: a level request held until a one-clock ack.
// This keeps the last line fetched; `ok` is a hit on it, so a fetcher that
// moves between words of one line (the 68000 running through code, the
// fifth plane of a tile row that sits in the same line as the other four)
// waits only for the first.
//
// `line` may come from the 96 MHz domain (the sprite engine): it is compared
// combinationally and sampled here on the 48 MHz edge, which is also a
// 96 MHz edge (one PLL).

`timescale 1ns/1ps
`default_nettype none

module snowboar_romport #(
    parameter int unsigned AW   = 25,
    parameter int unsigned WAYS = 1     // lines kept: 1 or 2
)(
    input  wire          clk,
    input  wire          rst,       // forgets the line (held until the ROM is loaded)

    input  wire          cs,
    input  wire [AW:1]   line,      // word address of the wanted line, addr[2:1] == 0
    output wire          ok,
    output wire [63:0]   data,

    output reg           rom_req,
    output reg  [AW:1]   rom_addr,
    input  wire          rom_ack,
    input  wire [63:0]   rom_dout
);

// WAYS = 2 keeps the last two lines, the older one replaced: the 68000's
// port, where a loop reading ROM data (the self-test's checksum) moves
// between its own line and the data's on every access. With one line each
// access waited for the SDRAM, more than board time's catch-up can give
// back: at a line latency of 10 clocks the boot dropped 15,000 ticks a
// frame, where MAME's 68000 never waits.
reg  [1:0]   valid;
reg  [AW:1]  have [0:1];
reg  [63:0]  held [0:1];
reg          older;             // the way to fill next

wire hit0 = valid[0] && (have[0] == line);
wire hit1 = WAYS > 1 && valid[1] && (have[1] == line);
wire hit  = hit0 | hit1;
assign ok   = cs && hit;
assign data = hit1 ? held[1] : held[0];

always @(posedge clk) begin
    if (rst) begin
        valid   <= 2'b00;
        older   <= 1'b0;
        rom_req <= 1'b0;
    end else begin
        if (WAYS > 1 && cs && hit) older <= hit0;
        if (!rom_req && cs && !hit) begin
            rom_req  <= 1'b1;
            rom_addr <= line;
        end
        if (rom_req && rom_ack) begin
            rom_req <= 1'b0;
            valid[older] <= 1'b1;
            have[older]  <= rom_addr;
            held[older]  <= rom_dout;
            if (WAYS > 1) older <= ~older;
        end
    end
end

endmodule

`default_nettype wire
