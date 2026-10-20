// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship (Pocket) — the CG-1V's two tilemaps and their
// scroll, as MAME's one-screen screen_update draws them (gaelco2_v.cpp):
//
//   y scroll   VRAM 0x2800 + 1 (layer 0), 0x2804 + 1 (layer 1)
//   x scroll   0x2802 + 0x14, 0x2806 + 0x10; with vreg n bit 15, the
//              512-entry linescroll table at 0x2000 / 0x2400 indexed by the
//              tilemap's own row, (screen line + y scroll) & 0x1ff, plus the
//              same offsets
//   order      layer 1, then layer 0 over it; pen 0 transparent
//
// No rowscroll-mode y (that is the dual-screen update's). World Rally 2's
// one-layer reader with jlrh's two-layer mix from Alligator Hunt
// (aligator_gae1_video.v).

`default_nettype none

module snowboar_gae1_video (
    input  wire        clk,
    input  wire        ce,
    input  wire [9:0]  hpos,
    input  wire [8:0]  vpos,
    input  wire        frame_end,

    input  wire [15:0] vreg0, vreg1,

    output wire [14:0] wrd_a,
    input  wire [15:0] wrd_q,

    output wire [13:0] tp0_idx, output wire tp0_rd,
    output wire [13:0] tp1_idx, output wire tp1_rd, input wire tp1_gnt,
    input  wire [31:0] tp_q,
    output wire [20:0] rom_a0,  input wire [63:0] d0_line, input wire gfx0_ok,
    output wire [20:0] rom_a1,  input wire [63:0] d1_line, input wire gfx1_ok,

    output reg  [11:0] pal_index,
    output reg         opaque,

    output wire        tm_ovr
);

    localparam [8:0] VLAST = 9'd263;    // snowboar_video_timing's last line

    reg [8:0] vpos_d;
    always @(posedge clk) vpos_d <= vpos;
    wire        line_change = (vpos != vpos_d);
    wire [8:0]  next_vpos   = frame_end ? 9'd0 : vpos + 9'd1;

    wire [8:0]  render_line = next_vpos + 9'd16;
    wire        rbank = vpos[0];
    wire        wbank = next_vpos[0];
    // the line the tilemaps start on at the next line change
    wire [8:0]  next2_vpos  = (vpos == VLAST) ? 9'd1 : (vpos == VLAST - 9'd1) ? 9'd0 : vpos + 9'd2;
    wire [8:0]  ahead_line  = next2_vpos + 9'd16;

    reg start_r;
    always @(posedge clk) start_r <= line_change;

    // The scroll words, one read a pixel in turn: each layer's y and x, and
    // its linescroll entry for the line ahead.
    reg [2:0] scnt = 3'd0;
    reg [8:0] scroll0y, scroll1y;
    reg [9:0] scroll0x, scroll1x, ls0, ls1;

    assign wrd_a = (scnt == 3'd0) ? 15'h1400 :
                   (scnt == 3'd1) ? 15'h1401 :
                   (scnt == 3'd2) ? 15'h1402 :
                   (scnt == 3'd3) ? 15'h1403 :
                   (scnt == 3'd4) ? (15'h1000 + {6'd0, (ahead_line + scroll0y) & 9'h1ff}) :
                                    (15'h1200 + {6'd0, (ahead_line + scroll1y) & 9'h1ff});
    always @(posedge clk) if (ce) begin
        scnt <= (scnt == 3'd5) ? 3'd0 : scnt + 3'd1;
        case (scnt)
            3'd0: scroll0y <= wrd_q[8:0] + 9'd1;
            3'd1: scroll0x <= wrd_q[9:0] + 10'h14;
            3'd2: scroll1y <= wrd_q[8:0] + 9'd1;
            3'd3: scroll1x <= wrd_q[9:0] + 10'h10;
            3'd4: ls0      <= wrd_q[9:0] + 10'h14;
            default: ls1   <= wrd_q[9:0] + 10'h10;
        endcase
    end
    wire [9:0] sc0x = (vreg0[15] ? ls0 : scroll0x) & 10'h3ff;
    wire [9:0] sc1x = (vreg1[15] ? ls1 : scroll1x) & 10'h3ff;

    wire [11:0] lb_q0, lb_q1;
    wire        l0_ovr, l1_ovr;
    assign tm_ovr = l0_ovr | l1_ovr;

    wire [9:0] lb_rx = (hpos - 10'd14) & 10'h1ff;

    snowboar_gae1_tilemap u_l0 (
        .clk(clk), .ce(1'b1), .start(start_r), .line(render_line),
        .scroll_x(sc0x), .scroll_y(scroll0y), .bank(vreg0[11:9]), .busy(),
        .tp_idx(tp0_idx), .tp_rd(tp0_rd), .tp_gnt(1'b1), .tp_q(tp_q),
        .rom_a(rom_a0), .d_line(d0_line), .gfx_ok(gfx0_ok),
        .lb_x(lb_rx), .lb_q(lb_q0), .wbank(wbank), .rbank(rbank), .ovr(l0_ovr)
    );
    snowboar_gae1_tilemap u_l1 (
        .clk(clk), .ce(1'b1), .start(start_r), .line(render_line),
        .scroll_x(sc1x), .scroll_y(scroll1y), .bank(vreg1[11:9]), .busy(),
        .tp_idx(tp1_idx), .tp_rd(tp1_rd), .tp_gnt(tp1_gnt), .tp_q(tp_q),
        .rom_a(rom_a1), .d_line(d1_line), .gfx_ok(gfx1_ok),
        .lb_x(lb_rx), .lb_q(lb_q1), .wbank(wbank), .rbank(rbank), .ovr(l1_ovr)
    );

    wire [4:0] pen0 = lb_q0[4:0]; wire [6:0] color0 = lb_q0[11:5];
    wire [4:0] pen1 = lb_q1[4:0]; wire [6:0] color1 = lb_q1[11:5];

    always @(posedge clk) if (ce) begin
        if (pen0 != 5'd0)      begin pal_index <= {color0, pen0}; opaque <= 1'b1; end
        else if (pen1 != 5'd0) begin pal_index <= {color1, pen1}; opaque <= 1'b1; end
        else                   begin pal_index <= 12'd0;          opaque <= 1'b0; end
    end
endmodule

`default_nettype wire
