// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship (Pocket) — the 93C66 serial EEPROM, 16-bit mode:
// 256 words, 8 address bits, bit-banged by the 68000 through the LS259.
//
// Made to behave as MAME's eeprom_serial_93cxx_device does (eepromser.cpp,
// eeprom.cpp), so the game's reads and its polling come out access for
// access as in MAME's trace:
//
//   * locked at reset: WRITE, ERASE, WRAL and ERAL do nothing until EWEN;
//   * a READ answers its dummy 0 at once, then each rising CLK shifts out
//     the next bit, MSB first, and 1s after the 16th;
//   * WRITE takes 1,750 us, ERASE 1,000, WRAL and ERAL 8,000: until then the
//     chip is busy, DO reads 0 with CS high and no command started, and a
//     start bit is not taken. The time is counted in board ticks (15 MHz),
//     as the program's own;
//   * DO reads 1 whenever the chip is not sending (MAME's pull-up).
//
// The second port is the platform's: the save slot fills the EEPROM before
// the game runs and reads it back, and `changed` says a word was written
// since `changed_clr`.

`timescale 1ns/1ps
`default_nettype none

module snowboar_eeprom #(
    // board ticks a write, an erase and a write-all / erase-all keep it busy
    parameter int unsigned T_WRITE = 26250,
    parameter int unsigned T_ERASE = 15000,
    parameter int unsigned T_ALL   = 120000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        tick,           // one 68000 clock of board time
    input  wire        cs,             // the LS259's Q6
    input  wire        sclk,           // Q5
    input  wire        di,             // Q4
    output wire        dout,           // COIN bit 6

    input  wire [7:0]  dump_addr,
    input  wire        dump_we,
    input  wire [15:0] dump_din,
    output reg  [15:0] dump_dout,
    input  wire        changed_clr,
    output reg         changed
);

localparam [2:0] S_RESET = 3'd0, S_START = 3'd1, S_CMD = 3'd2, S_READ = 3'd3,
                 S_DATA = 3'd4, S_DONE = 3'd5;

(* ramstyle = "no_rw_check" *) reg [15:0] mem [0:255];

reg  [2:0]  st;
reg         locked;
reg  [4:0]  bits;
reg  [9:0]  acc;
reg  [7:0]  addr;
reg  [15:0] shift;
reg         wr_all;            // the S_DATA command is WRAL
reg  [16:0] busy;
reg         cs_d, sclk_d;

// the internal port: a word written at once, or a sweep of all 256 (WRAL
// ANDs each with the data, ERAL sets each to ffff), three clocks a word:
// its address out, its word in, the write
reg  [15:0] q;
reg         sw_run, sw_and;
reg  [1:0]  sw_ph;
reg  [7:0]  sw_a;
reg  [15:0] sw_d;
reg         m_we;
reg  [7:0]  m_a;
reg  [15:0] m_d;
wire [7:0]  pa = m_we ? m_a : sw_run ? sw_a : addr;
always @(posedge clk) begin
    if (m_we) mem[pa] <= m_d;
    q <= mem[pa];
end
always @(posedge clk) begin
    if (dump_we) mem[dump_addr] <= dump_din;
    dump_dout <= mem[dump_addr];
end

wire ready   = busy == 17'd0;
wire cs_rise = cs & ~cs_d;
wire cs_fall = ~cs & cs_d;
wire clk_rise = sclk & ~sclk_d;

assign dout = st == S_START ? ready :
              st == S_READ  ? shift[15] : 1'b1;

wire [9:0] acc_n = {acc[8:0], di};

always @(posedge clk) begin
    if (rst) begin
        st <= S_RESET; locked <= 1'b1; bits <= 5'd0; acc <= 10'd0; addr <= 8'd0;
        shift <= 16'd0; wr_all <= 1'b0; busy <= 17'd0; cs_d <= 1'b0; sclk_d <= 1'b0;
        sw_run <= 1'b0; m_we <= 1'b0; changed <= 1'b0;
    end else begin
        cs_d <= cs; sclk_d <= sclk;
        m_we <= 1'b0;
        if (tick && busy != 17'd0) busy <= busy - 17'd1;
        if (changed_clr) changed <= 1'b0;
        if (m_we) changed <= 1'b1;

        // the sweep: read a word, then write it
        if (sw_run) begin
            sw_ph <= sw_ph == 2'd2 ? 2'd0 : sw_ph + 2'd1;
            if (sw_ph == 2'd1) begin
                m_we <= 1'b1; m_a <= sw_a; m_d <= sw_and ? (q & sw_d) : 16'hffff;
            end
            if (sw_ph == 2'd2) begin
                sw_a <= sw_a + 8'd1;
                if (sw_a == 8'hff) sw_run <= 1'b0;
            end
        end

        case (st)
            S_RESET: if (cs_rise) st <= S_START;
            S_START:
                if (cs_fall) st <= S_RESET;
                else if (clk_rise && di && ready) begin acc <= 10'd0; bits <= 5'd0; st <= S_CMD; end
            S_CMD:
                if (cs_fall) st <= S_RESET;
                else if (clk_rise) begin
                    acc  <= acc_n;
                    bits <= bits + 5'd1;
                    if (bits == 5'd9) begin
                        bits <= 5'd0;
                        addr <= acc_n[7:0];
                        case (acc_n[9:8])
                            2'b10: begin shift <= 16'd0; st <= S_READ; end
                            2'b01: begin shift <= 16'd0; wr_all <= 1'b0; st <= S_DATA; end
                            2'b11: if (locked) st <= S_RESET;
                                   else begin
                                       m_we <= 1'b1; m_a <= acc_n[7:0]; m_d <= 16'hffff;
                                       busy <= 17'(T_ERASE); st <= S_DONE;
                                   end
                            2'b00: begin
                                addr <= 8'd0;
                                case (acc_n[7:6])
                                    2'd0: begin locked <= 1'b1; st <= S_RESET; end
                                    2'd1: begin shift <= 16'd0; wr_all <= 1'b1; st <= S_DATA; end
                                    2'd2: if (locked) st <= S_RESET;
                                          else begin
                                              sw_run <= 1'b1; sw_and <= 1'b0; sw_ph <= 2'd0; sw_a <= 8'd0;
                                              busy <= 17'(T_ALL); st <= S_DONE;
                                          end
                                    2'd3: begin locked <= 1'b0; st <= S_RESET; end
                                endcase
                            end
                        endcase
                    end
                end
            S_READ:
                if (cs_fall) st <= S_RESET;
                else if (clk_rise) begin
                    bits  <= bits == 5'd31 ? bits : bits + 5'd1;
                    shift <= bits == 5'd0 ? q : {shift[14:0], 1'b1};
                end
            S_DATA:
                if (cs_fall) st <= S_RESET;
                else if (clk_rise) begin
                    shift <= {shift[14:0], di};
                    bits  <= bits + 5'd1;
                    if (bits == 5'd15) begin
                        if (locked) st <= S_RESET;
                        else if (wr_all) begin
                            sw_run <= 1'b1; sw_and <= 1'b1; sw_ph <= 2'd0; sw_a <= 8'd0;
                            sw_d <= {shift[14:0], di};
                            busy <= 17'(T_ALL); st <= S_DONE;
                        end else begin
                            m_we <= 1'b1; m_a <= addr; m_d <= {shift[14:0], di};
                            busy <= 17'(T_WRITE); st <= S_DONE;
                        end
                    end
                end
            S_DONE: if (cs_fall) st <= S_RESET;
            default: st <= S_RESET;
        endcase
    end
end

// a blank chip, as MAME makes one without an nvram file
// synthesis translate_off
integer k;
initial for (k = 0; k < 256; k = k + 1) mem[k] = 16'hffff;
// synthesis translate_on

endmodule

`default_nettype wire
