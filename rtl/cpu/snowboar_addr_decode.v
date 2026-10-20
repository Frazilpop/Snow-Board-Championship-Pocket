// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship (Pocket) — the 68000's map (MAME gaelco2.cpp,
// snowboar_map).
//
//   000000-0fffff  program ROM
//   200000-20ffff  VRAM, with the CG-1V's registers at 202890-2028ff
//   210000-211fff  palette
//   212000-213fff  extra RAM
//   218004-218009  video registers
//   300000         P1 (read), the LS259 at 300000-30000f (write)
//   300010         P2
//   300020         COIN
//   310000-31ffff  the protection
//   fe0000-feffff  work RAM

`default_nettype none

module snowboar_addr_decode (
    input  wire [23:0] addr,
    input  wire        as,

    output wire        cs_rom,
    output wire        cs_vram,
    output wire        cs_sound,
    output wire        cs_pal,
    output wire        cs_xram,
    output wire        cs_vregs,
    output wire        cs_p1,
    output wire        cs_p2,
    output wire        cs_coin,
    output wire        cs_latch,
    output wire        cs_prot,
    output wire        cs_wram
);
    assign cs_rom  = as & (addr[23:20] == 4'h0);

    wire blk_20    = as & (addr[23:16] == 8'h20);
    assign cs_sound= blk_20 & (addr[15:8] == 8'h28) & (addr[7:1] >= 7'h48);
    assign cs_vram = blk_20 & ~cs_sound;

    assign cs_pal  = as & (addr[23:16] == 8'h21) & (addr[15:13] == 3'b0);
    assign cs_xram = as & (addr[23:13] == 11'h109);

    wire blk_218   = as & (addr[23:12] == 12'h218);
    assign cs_vregs= blk_218 & (addr[11:1] >= 11'h002) & (addr[11:1] <= 11'h004);

    assign cs_p1   = as & (addr[23:1] == 23'h180000);
    assign cs_p2   = as & (addr[23:1] == 23'h180008);
    assign cs_coin = as & (addr[23:1] == 23'h180010);
    assign cs_latch= as & (addr[23:4] == 20'h30000);

    assign cs_prot = as & (addr[23:16] == 8'h31);
    assign cs_wram = as & (addr[23:16] == 8'hfe);
endmodule

`default_nettype wire
