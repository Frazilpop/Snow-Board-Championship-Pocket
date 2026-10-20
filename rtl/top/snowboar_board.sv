// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship (Pocket) — the board, Gaelco REF 960419/1.
//
// Platform-neutral: no pins, no framework. The Pocket shell (pocket/) and
// the simulation harness (sim/snowboar/) both host this module. World Rally
// 2's board (itself built on jlrh's MiSTer core) without the DS5002FP, its
// shared RAM, the wheel's ADC and the DIP switches, with what this board
// has instead:
//
//   MC68000 @ 15 MHz      snowboar_main: fx68k, the bus, the protection, the
//                         LS259 and the 93C66 EEPROM; work and extra RAM
//                         on the platform's SRAM
//   CG-1V video           snowboar_video_top, one screen: both tilemaps and
//                         every sprite; snowboar_vmem, the VRAM, the sprite
//                         buffer and the palette
//   CG-1V sound           snowboar_gae1_sound, 7 channels, stereo
//
// SDRAM line ports (64-bit lines, in the layout tools/pocket/build_rom.py
// writes): 0 the 68000's program, 1 tilemap 0, 2 tilemap 1, 3 sprites,
// 4 sound. A tile row half – all five planes of eight pixels – is one line;
// the samples are in bytes 5 and 6 of the same lines.

`timescale 1ns/1ps
`default_nettype none

module snowboar_board #(
    parameter int unsigned SDR_AW  = 25,
    parameter int unsigned NP      = 5,
    // Pixel clock = clk * PIX_NUM / PIX_DEN. 1/6 is jlrh's 8 MHz, a
    // 512 x 264 frame at 59.19 Hz. The harness sets 13002/78125 to stretch
    // the same frame to MAME's 59.1 Hz, so its IRQs fall where MAME's do.
    parameter int unsigned PIX_NUM = 1,
    parameter int unsigned PIX_DEN = 6,
    // IRQ 6 every IRQ_DEN / IRQ_NUM 68000 clocks of board time, the first
    // IRQ_FIRST clocks after reset. 1/253440 is the video frame above
    // (811,008 clocks at 48 MHz); MAME's 59.1 Hz is 591/150000000, its
    // first vblank 253,805 ticks from reset as the power-on trace places it
    // (sim/snowboar/build.sh).
    parameter int unsigned IRQ_NUM   = 1,
    parameter int unsigned IRQ_DEN   = 253440,
    parameter int unsigned IRQ_FIRST = 253440
)(
    input  wire        clk,            // 48 MHz
    input  wire        rst,            // core reset; the board adds !rom_loaded

    // ROM read ports (SDRAM controller, slow side)
    output wire [NP-1:0]             rom_req,
    output wire [NP-1:0][SDR_AW:1]   rom_addr,
    input  wire [NP-1:0]             rom_ack,
    input  wire [NP-1:0][63:0]       rom_dout,

    // Work RAM and extra RAM: one SRAM word port, req held until a one-clock
    // ack (dout valid with it), the next req no sooner than the clock after.
    output wire        sram_req,
    output wire        sram_we,
    output wire [16:0] sram_addr,
    output wire [15:0] sram_din,
    output wire [1:0]  sram_be,         // [1] the upper byte
    input  wire        sram_ack,
    input  wire [15:0] sram_dout,

    input  wire        rom_loaded,

    // The EEPROM's own port, for the save slot: 256 words, MAME's nvram
    // file is word w little-endian at bytes 2w, 2w + 1. Any time; the
    // platform fills it before rom_loaded. eep_changed: a word written
    // since eep_changed_clr.
    input  wire [7:0]  eep_addr,
    input  wire        eep_we,
    input  wire [15:0] eep_din,
    output wire [15:0] eep_dout,
    input  wire        eep_changed_clr,
    output wire        eep_changed,

    // Video: 384 x 240 of a 512 x 264 frame
    output wire        ce_pix,
    output wire        hs, vs, hblank, vblank,
    output wire [7:0]  r, g, b,        // MAME's palette: pal5bit, shadow/highlight steps

    // Audio: the CG-1V's two outputs, 7812.5 Hz (MAME routes the first to
    // the left speaker, the second to the right)
    output wire signed [15:0] snd_l, snd_r,
    output wire        snd_sample,

    // Inputs, active high. p1/p2 = {b3, b2, b1, up, down, left, right}.
    input  wire [6:0]  p1, p2,
    input  wire [1:0]  coin, start,
    input  wire        service,        // "go to service mode NOW" (COIN bit 2)
    input  wire        service1,       // COIN bit 3

    // Freezes the game: board time stops (no credit, no ticks), so the
    // 68000 and IRQ 6 stand still. Video keeps running.
    input  wire        pause,

    // For the platform's diagnostics: board time behind wall time (ticks),
    // IRQ 6's tick, the sprite buffer's copy running, and one clock each for
    // a sprite or tilemap line its next line's start found unfinished.
    output wire [11:0] diag_owed,
    output wire        diag_irq,
    output wire        diag_copying,
    output wire        diag_spr_cut,
    output wire        diag_tm_ovr
);

// SDRAM regions, word addresses
localparam [SDR_AW:1] W_MAINCPU = SDR_AW'(25'h0000000);
localparam [SDR_AW:1] W_GFX     = SDR_AW'(25'h0100000);    // byte 0x0200000

// ================================================================ resets
wire cpu_rst = rst | ~rom_loaded;

// ================================================================ clocks
reg [31:0] pix_acc = 32'd0;
reg        ce_pix_r = 1'b0;
always @(posedge clk) begin
    if (pix_acc + PIX_NUM >= PIX_DEN) begin
        pix_acc  <= pix_acc + PIX_NUM - PIX_DEN;
        ce_pix_r <= 1'b1;
    end else begin
        pix_acc  <= pix_acc + PIX_NUM;
        ce_pix_r <= 1'b0;
    end
end
assign ce_pix = ce_pix_r;

// Board time: one tick per 68000 clock (snowboar_cpu_clk), 15 MHz on
// average. IRQ 6, the CG-1V's samples and the EEPROM's busy time are
// counted in ticks: the program and they keep MAME's lockstep whatever the
// SDRAM does.
wire cpu_tick, cpu_lost;
// The CG-1V holds board time while it computes a sample
// (snowboar_gae1_sound, TICKDIV): the 68000 reads the channels' positions,
// so they must move when MAME's do. The sprite buffer's copy at vblank
// holds it too (snowboar_vmem).
wire snd_busy;
wire vram_copying;
wire cpu_hold = snd_busy | vram_copying;

// board_irq is the tick's own clock, not a register after it: snowboar_main
// takes it to IPL in two clocks, so IPL always changes after this tick's phi2
// and before the next phi1, whether the CPU is running at 15 MHz or catching
// up at 24. A clock later and that would depend on the SDRAM.
//
// Ticks board time had to drop (cpu_lost: the SDRAM's waits ran the credit
// out) are counted too, one with each tick given until none is left, so
// IRQ 6 stays on the picture's vblank (World Rally 2: uncounted, they moved
// IRQ 6 later for good and the picture tore). Nothing is dropped while the
// SDRAM keeps up.
reg  [31:0] irq_acc, irq_first;
reg         irq_run;
reg  [15:0] irq_lost;
wire        irq_two   = irq_lost != 16'd0;     // this tick counts a lost one too
wire [31:0] irq_step  = irq_two ? 2 * IRQ_NUM : IRQ_NUM;
wire [31:0] irq_fstep = irq_two ? 32'd2 : 32'd1;
wire        irq_wrap  = irq_acc + irq_step >= IRQ_DEN;
wire        irq_fwrap = irq_first <= irq_fstep;
wire        board_irq = cpu_tick && (irq_run ? irq_wrap : irq_fwrap);
always @(posedge clk) begin
    if (cpu_rst) begin
        irq_first <= IRQ_FIRST; irq_run <= 1'b0; irq_acc <= 32'd0; irq_lost <= 16'd0;
    end else begin
        if (cpu_tick) begin
            if (!irq_run) begin
                irq_first <= irq_first - irq_fstep;
                if (irq_fwrap) begin
                    irq_run <= 1'b1;
                    // a lost tick taken past the first IRQ starts the count
                    irq_acc <= irq_fstep - irq_first;
                end
            end else irq_acc <= irq_wrap ? irq_acc + irq_step - IRQ_DEN : irq_acc + irq_step;
        end
        if (cpu_lost && !(cpu_tick && irq_two)) begin
            if (irq_lost != 16'hffff) irq_lost <= irq_lost + 16'd1;
        end else if (!cpu_lost && cpu_tick && irq_two) irq_lost <= irq_lost - 16'd1;
    end
end

// ================================================================ ROM ports
wire        main_cs, main_ok;
wire [19:1] main_addr;
wire [63:0] main_line;
snowboar_romport #(.AW(SDR_AW), .WAYS(2)) u_rp_main (
    .clk(clk), .rst(cpu_rst),
    .cs(main_cs), .line(W_MAINCPU + {main_addr[19:3], 2'b00}),
    .ok(main_ok), .data(main_line),
    .rom_req(rom_req[0]), .rom_addr(rom_addr[0]), .rom_ack(rom_ack[0]), .rom_dout(rom_dout[0])
);
// SDRAM words are {byte 2w+1, byte 2w}; the 68000's are big-endian
wire [15:0] main_sw   = main_line[16*main_addr[2:1] +: 16];
wire [15:0] main_data = {main_sw[7:0], main_sw[15:8]};

// Tile row half o is the line at W_GFX + 4o.
function automatic [SDR_AW:1] gfx_line(input [20:0] o);
    gfx_line = W_GFX + {o, 2'b00};
endfunction

wire [20:0] tm0_a;   wire tm0_ok;   wire [63:0] tm0_line;
wire [20:0] tm1_a;   wire tm1_ok;   wire [63:0] tm1_line;
wire [20:0] spr_ra;  wire spr_ok;   wire [63:0] spr_line;
wire [23:0] snd_ra;  wire snd_cs;   wire snd_ok;  wire [63:0] snd_line;

snowboar_romport #(.AW(SDR_AW)) u_rp_tm0 (
    .clk(clk), .rst(cpu_rst),
    .cs(1'b1), .line(gfx_line(tm0_a)), .ok(tm0_ok), .data(tm0_line),
    .rom_req(rom_req[1]), .rom_addr(rom_addr[1]), .rom_ack(rom_ack[1]), .rom_dout(rom_dout[1])
);
snowboar_romport #(.AW(SDR_AW)) u_rp_tm1 (
    .clk(clk), .rst(cpu_rst),
    .cs(1'b1), .line(gfx_line(tm1_a)), .ok(tm1_ok), .data(tm1_line),
    .rom_req(rom_req[2]), .rom_addr(rom_addr[2]), .rom_ack(rom_ack[2]), .rom_dout(rom_dout[2])
);
snowboar_romport #(.AW(SDR_AW)) u_rp_spr (
    .clk(clk), .rst(cpu_rst),
    .cs(1'b1), .line(gfx_line(spr_ra)), .ok(spr_ok), .data(spr_line),
    .rom_req(rom_req[3]), .rom_addr(rom_addr[3]), .rom_ack(rom_ack[3]), .rom_dout(rom_dout[3])
);
// A sample byte at gfx offset G is in plane P = G >> 22 at o = G & 0x3fffff:
// byte P of line o in the lower half of the plane, byte 5 + P of line
// o - 0x200000 in the upper half of planes 0 and 1, zero elsewhere.
wire [1:0]  snd_p   = snd_ra[23:22];
wire        snd_up  = snd_ra[21];
wire        snd_in  = !snd_up ? 1'b1 : snd_p <= 2'd1;
snowboar_romport #(.AW(SDR_AW)) u_rp_snd (
    .clk(clk), .rst(cpu_rst),
    .cs(snd_cs), .line(gfx_line(snd_ra[20:0])), .ok(snd_ok), .data(snd_line),
    .rom_req(rom_req[4]), .rom_addr(rom_addr[4]), .rom_ack(rom_ack[4]), .rom_dout(rom_dout[4])
);
wire [2:0]  snd_b    = snd_up ? 3'd5 + {1'b0, snd_p} : {1'b0, snd_p};
wire [7:0]  snd_byte = snd_in ? snd_line[8*snd_b +: 8] : 8'd0;

// ================================================================ main board
wire [15:0] vmem_addr; wire vmem_uds, vmem_lds, vmem_we;
wire        vmem_cs_vram, vmem_cs_pal;
wire [15:0] vmem_wdata;
wire [15:0] cpu_vram_rd, cpu_pal_rd;
wire [15:0] vreg0, vreg1, vreg2;
wire        sndreg_cs, sndreg_we; wire [15:0] snd_rdata;

snowboar_main u_main (
    .clk(clk), .rst(cpu_rst), .game_run(~pause),
    .vblank_irq(board_irq),
    .prog_addr(main_addr), .prog_cs(main_cs), .prog_data(main_data), .prog_data_ok(main_ok),
    .p1(p1), .p2(p2), .coin(coin), .start(start), .service(service), .service1(service1),
    .vmem_addr(vmem_addr), .vmem_uds(vmem_uds), .vmem_lds(vmem_lds), .vmem_we(vmem_we),
    .vmem_cs_vram(vmem_cs_vram), .vmem_cs_pal(vmem_cs_pal),
    .vmem_wdata(vmem_wdata),
    .vmem_vram_rdata(cpu_vram_rd), .vmem_pal_rdata(cpu_pal_rd),
    .vreg0(vreg0), .vreg1(vreg1), .vreg2(vreg2),
    .sndreg_cs(sndreg_cs), .sndreg_we(sndreg_we), .snd_rdata(snd_rdata),
    .cpu_tick(cpu_tick), .cpu_hold(cpu_hold), .cpu_owed(diag_owed), .cpu_lost(cpu_lost),
    .sram_req(sram_req), .sram_we(sram_we), .sram_addr(sram_addr), .sram_din(sram_din),
    .sram_be(sram_be), .sram_ack(sram_ack), .sram_dout(sram_dout),
    .eep_addr(eep_addr), .eep_we(eep_we), .eep_din(eep_din), .eep_dout(eep_dout),
    .eep_changed_clr(eep_changed_clr), .eep_changed(eep_changed)
);

// ================================================================ sound
snowboar_gae1_sound #(.TICKDIV(1920)) u_snd (
    .clk(clk), .rst(cpu_rst), .tick(cpu_tick), .busy(snd_busy),
    .cs_sound(sndreg_cs), .cpu_aw(vmem_addr[7:1]), .cpu_we(sndreg_we),
    .cpu_uds(vmem_uds), .cpu_lds(vmem_lds), .cpu_wdata(vmem_wdata), .cpu_rdata(snd_rdata),
    .rom_addr(snd_ra), .rom_cs(snd_cs), .rom_data(snd_byte), .rom_ok(snd_ok),
    .snd_l(snd_l), .snd_r(snd_r), .sample(snd_sample)
);

// ================================================================ video
wire [13:0] tp0_idx, tp1_idx; wire tp0_rd, tp1_rd, tp1_gnt; wire [31:0] tp_q;
wire [14:0] wrd_a;   wire [15:0] wrd_q;
wire [14:0] spr_a;   wire [15:0] spr_q;
wire [11:0] pal_a;   wire [15:0] pal_q;
snowboar_vmem u_vmem (
    .clk(clk), .rst(cpu_rst),
    .cpu_addr(vmem_addr), .cpu_uds(vmem_uds), .cpu_lds(vmem_lds), .cpu_we(vmem_we),
    .cs_vram(vmem_cs_vram), .cs_pal(vmem_cs_pal),
    .cpu_wdata(vmem_wdata),
    .cpu_vram_rdata(cpu_vram_rd), .cpu_pal_rdata(cpu_pal_rd),
    .tp0_rd(tp0_rd), .tp0_idx(tp0_idx), .tp1_rd(tp1_rd), .tp1_idx(tp1_idx), .tp1_gnt(tp1_gnt),
    .tp_q(tp_q),
    .wrd_a(wrd_a), .wrd_q(wrd_q),
    .snap(board_irq), .copying(vram_copying), .spr_a(spr_a), .spr_q(spr_q),
    .pal_a(pal_a), .pal_q(pal_q)
);

// The sprite engine's vregs change only at IRQ 6, with the buffer (World
// Rally 2, 6f2f90a). The game double-buffers its sprite list: it writes
// the half not on show, then points vreg1 bit 4 at it partway down the
// picture. Read live, the engine changed halves at that line, and the
// sprites below it came from the buffer's other half, a list two frames
// older than those above. MAME draws each frame whole at vblank, before
// that vblank's copy, with the vregs as they stand; so the picture after
// IRQ 6 takes the buffer copied at it and the half vreg1 chose by the IRQ
// before (the game flips every frame), as below.
reg [15:0] spr_vreg0 = 16'd0, spr_vreg1 = 16'd0;    // for this frame
reg [15:0] spr_vnext0 = 16'd0, spr_vnext1 = 16'd0;  // for the next
`ifdef VERILATOR
reg        sc_vfollow /*verilator public_flat_rw*/ = 1'b0;  // scene mode: take them as loaded
`else
wire       sc_vfollow = 1'b0;
`endif
always @(posedge clk) if (board_irq || sc_vfollow) begin
    spr_vnext0 <= vreg0;
    spr_vnext1 <= vreg1;
    spr_vreg0  <= sc_vfollow ? vreg0 : spr_vnext0;
    spr_vreg1  <= sc_vfollow ? vreg1 : spr_vnext1;
end

// The video's own vblank IRQ is left unused: IRQ 6 is board time's (above),
// and its tick is also the instant the sprite buffer is taken.
wire vblank_irq;
snowboar_video_top u_video (
    .clk(clk), .rst(rst), .ce_pix(ce_pix),
    .vreg0(vreg0), .vreg1(vreg1), .spr_vreg0(spr_vreg0), .spr_vreg1(spr_vreg1),
    .tp0_idx(tp0_idx), .tp0_rd(tp0_rd), .tp1_idx(tp1_idx), .tp1_rd(tp1_rd), .tp1_gnt(tp1_gnt),
    .tp_q(tp_q),
    .wrd_a(wrd_a), .wrd_q(wrd_q), .spr_a(spr_a), .spr_q(spr_q),
    .pal_a(pal_a), .pal_q(pal_q),
    .rom_a0(tm0_a), .gfx0_line(tm0_line), .gfx0_ok(tm0_ok),
    .rom_a1(tm1_a), .gfx1_line(tm1_line), .gfx1_ok(tm1_ok),
    .rom_as(spr_ra), .gfxs_line(spr_line), .gfxs_ok(spr_ok),
    .vga_r(r), .vga_g(g), .vga_b(b),
    .hsync(hs), .vsync(vs), .hblank(hblank), .vblank(vblank), .de(),
    .vblank_irq(vblank_irq),
    .spr_cut(diag_spr_cut), .tm_ovr(diag_tm_ovr)
);
assign diag_irq     = board_irq;
assign diag_copying = vram_copying;

// ================================================================ harness probes
// Read by sim/snowboar/tb_snowboar.cpp for the bus traces; nothing uses them.
// Hierarchical, so Verilator only.
`ifdef VERILATOR
wire        dbg_as     /*verilator public_flat_rd*/ = ~u_main.ASn & ~(u_main.fc == 3'd7);
wire        dbg_rw     /*verilator public_flat_rd*/ = u_main.eRWn;
wire [23:1] dbg_eab    /*verilator public_flat_rd*/ = u_main.eab;
wire [15:0] dbg_dout   /*verilator public_flat_rd*/ = u_main.oEdb;
wire [15:0] dbg_din    /*verilator public_flat_rd*/ = u_main.iEdb;
wire [1:0]  dbg_ds     /*verilator public_flat_rd*/ = {~u_main.UDSn, ~u_main.LDSn};
wire        dbg_irq    /*verilator public_flat_rd*/ = board_irq;
wire        dbg_vbirq  /*verilator public_flat_rd*/ = vblank_irq;
wire        dbg_cen    /*verilator public_flat_rd*/ = cpu_tick;
wire        dbg_lost   /*verilator public_flat_rd*/ = cpu_lost;
`endif

endmodule

`default_nettype wire
