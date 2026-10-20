// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship (Pocket) — the save slot's round trip.
//
// pocket_nvram on the board's own EEPROM (snowboar_eeprom's second port):
// 512 bytes written in over the bridge as APF writes a .sav at boot, the
// EEPROM's words checked against the file (word w = bytes 2w low, 2w+1
// high, MAME's nvram order), then read back out as APF reads a slot at
// shutdown – a read takes the bus as it stands and then strobes bridge_rd,
// and the word for an address comes with the next read – through the
// registered read mux core_top has. Both directions must give the file
// back byte for byte.
//
//   sim/shell/run_nvram.sh

`timescale 1ns/1ps
`default_nettype none

module tb_nvram;

reg clk_74a = 0, clk = 0;
always #6.734 clk_74a = ~clk_74a;   // 74.25 MHz
always #10.417 clk = ~clk;          // 48 MHz

reg         bridge_wr = 0, bridge_rd = 0;
reg  [31:0] bridge_addr = 0, bridge_wr_data = 0;
wire [31:0] nv_bridge_rd;
reg  [31:0] bridge_rd_data = 0;

wire [7:0]  nv_addr;
wire [15:0] nv_din, nv_dout;
wire        nv_we, nv_dirty, nv_dirty_clr;

pocket_nvram u_nvram (
    .clk_74a(clk_74a), .bridge_wr(bridge_wr), .bridge_rd(bridge_rd),
    .bridge_endian_little(1'b0), .bridge_addr(bridge_addr),
    .bridge_wr_data(bridge_wr_data), .bridge_rd_word(nv_bridge_rd),
    .clk(clk), .nv_addr(nv_addr), .nv_din(nv_din), .nv_we(nv_we),
    .nv_dout(nv_dout), .nv_dirty(nv_dirty), .nv_dirty_clr(nv_dirty_clr)
);

snowboar_eeprom u_eep (
    .clk(clk), .rst(1'b1), .tick(1'b0), .cs(1'b0), .sclk(1'b0), .di(1'b0), .dout(),
    .dump_addr(nv_addr), .dump_we(nv_we), .dump_din(nv_din), .dump_dout(nv_dout),
    .changed_clr(nv_dirty_clr), .changed()
);
assign nv_dirty = 1'b0;

// core_top's read mux, registered
always @(posedge clk_74a)
    bridge_rd_data <= (bridge_addr[31:28] == 4'h2) ? nv_bridge_rd : 32'd0;

reg [7:0] file [0:511];
reg [7:0] back [0:511];
integer i, k, errs;
reg [31:0] w;

task automatic wait74(input integer n);
    repeat (n) @(posedge clk_74a);
endtask

initial begin
    for (i = 0; i < 512; i = i + 1) file[i] = (i * 37 + 11) ^ (i >> 3);
    errs = 0;
    wait74(20);
    // ---- in: one 32-bit write a word, big-endian (file byte 4k is [31:24])
    for (k = 0; k < 128; k = k + 1) begin
        @(posedge clk_74a);
        bridge_addr    <= 32'h2000_0000 + 4 * k;
        bridge_wr_data <= {file[4*k], file[4*k+1], file[4*k+2], file[4*k+3]};
        bridge_wr      <= 1;
        @(posedge clk_74a);
        bridge_wr      <= 0;
        wait74(80);             // APF's pace: a word every ~75 clocks
    end
    wait74(200);
    // ---- the EEPROM's words
    for (i = 0; i < 256; i = i + 1)
        if (u_eep.mem[i] != {file[2*i+1], file[2*i]}) begin
            if (errs < 8) $display("EEPROM word %0d: %04x, file says %02x%02x", i, u_eep.mem[i], file[2*i+1], file[2*i]);
            errs = errs + 1;
        end
    // let the scanner fill the shadow (a pass is 512 clocks at 48 MHz)
    wait74(2000);
    // ---- out: read k takes the bus as it stands (address k-1's word),
    // then strobes; one more read at the end collects the last word
    for (k = 0; k <= 128; k = k + 1) begin
        @(posedge clk_74a);
        bridge_addr <= 32'h2000_0000 + 4 * k;
        wait74(10);
        w = bridge_rd_data;
        if (k > 0) {back[4*k-4], back[4*k-3], back[4*k-2], back[4*k-1]} = w;
        @(posedge clk_74a);
        bridge_rd <= 1;
        @(posedge clk_74a);
        bridge_rd <= 0;
        wait74(10);
    end
    for (i = 0; i < 512; i = i + 1)
        if (back[i] != file[i]) begin
            if (errs < 16) $display("read back byte %0d: %02x, file %02x", i, back[i], file[i]);
            errs = errs + 1;
        end
    if (errs == 0) $display("PASS: 512 bytes in, the EEPROM's 256 words, 512 bytes out, byte for byte");
    else           $display("FAIL: %0d mismatches", errs);
    $finish;
end

endmodule

// dcfifo, behaviourally (lpm_showahead OFF: q is the word read on rdreq,
// a clock later); the crossing itself is not modelled.
module dcfifo #(
    parameter intended_device_family = "", parameter lpm_numwords = 4,
    parameter lpm_showahead = "OFF", parameter lpm_type = "", parameter lpm_width = 8,
    parameter lpm_widthu = 2, parameter overflow_checking = "", parameter rdsync_delaypipe = 0,
    parameter underflow_checking = "", parameter use_eab = "", parameter wrsync_delaypipe = 0,
    parameter clocks_are_synchronized = ""
)(
    input  wire [lpm_width-1:0] data,
    input  wire rdclk, rdreq, wrclk, wrreq,
    output reg  [lpm_width-1:0] q,
    output wire rdempty
);
    reg [lpm_width-1:0] m [0:15];
    reg [4:0] wp = 0, rp = 0;
    assign rdempty = (wp == rp);
    always @(posedge wrclk) if (wrreq) begin m[wp[3:0]] <= data; wp <= wp + 1; end
    always @(posedge rdclk) if (rdreq && !rdempty) begin q <= m[rp[3:0]]; rp <= rp + 1; end
endmodule

`default_nettype wire
