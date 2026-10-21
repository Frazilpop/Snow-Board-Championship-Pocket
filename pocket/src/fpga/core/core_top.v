// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship for Analogue Pocket — the core top level
//
// Instantiated by Analogue's apf_top. Everything Pocket-specific lives here and
// in the pocket_* modules beside it; the board itself (rtl/top/snowboar_board.sv)
// knows nothing of APF, pins or the bridge.
//
// CLOCKS (core/mf_pllbase/mf_pllbase_0002.v has the derivation)
//
//   clk_74a        74.25 MHz  APF bridge, pad bus, I2S; PLL reference
//   clk_core       48 MHz     the board and every servant it talks to
//   clk_sdram      96 MHz     kaneko_sdram, behind kaneko_sdram_x2
//   clk_sdram_ps   96 MHz     180 deg, forwarded to dram_clk
//   clk_vid         8 MHz     APF video bus
//   clk_vid90       8 MHz     90 deg, for APF's video DDR
//
// 48, 96 and 8 come from one VCO and are synchronous; everything they share
// with clk_74a crosses through a synchroniser, a dcfifo or a dual-clock RAM,
// and core_constraints.sdc cuts exactly those.
//
// BRIDGE MAP
//
//   0x00000000-   ROM image data slot -> SDRAM          pocket_rom_loader
//   0x20000000-   EEPROM save slot, 512 bytes, r/w      pocket_nvram
//   0xF0000000    game id (instance JSON memory_writes) r/w
//   0xF1000000-   options (interact.json)               r/w, see below
//   0xF8000000-   APF command bridge                    core_bridge_cmd
//
// DATA SLOTS (dist/Cores/frazilpop.Snow Board Championship/data.json), in table order:
//
//   [0] id 0  instance JSON (APF requires the instance slot to come first)
//   [1] id 1  <set>.rom at 0x00000000
//   [2] id 2  <set>.sav at 0x20000000, nonvolatile, 512 bytes: the 93C66,
//             word w little-endian at bytes 2w, 2w+1, as MAME's nvram file

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable,

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,

///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,

output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
//
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig

);

localparam SDR_COL = 10;                    // AS4C32M16MSA: 8192 x 1024 x 4
localparam SDR_AW  = 2 + 13 + SDR_COL;      // 25: word address [25:1], 64 MB
localparam NP      = 6;                     // board ROM read ports
// One more at the controller than the board has: port NP is the shell's own
// SDRAM read-back check (see DIAGNOSTICS below). The board never sees it.
localparam NPS     = NP + 1;

// ============================================================ unused pins
// As Analogue's template leaves them.

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// tie off the PSRAMs: no frame buffer here, the CG-1V is line-buffered
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;

// ================================================================= clocks
wire clk_core, clk_sdram, clk_sdram_ps, clk_vid, clk_vid90;
wire pll_core_locked;

mf_pllbase mp1 (
    .refclk   ( clk_74a ),
    .rst      ( 1'b0 ),
    .outclk_0 ( clk_core ),
    .outclk_1 ( clk_sdram ),
    .outclk_2 ( clk_sdram_ps ),
    .outclk_3 ( clk_vid ),
    .outclk_4 ( clk_vid90 ),
    .locked   ( pll_core_locked )
);

// ================================================================= resets
//
// Three, because three things are being reset for different reasons:
//
//   sdram_rst_n   96 MHz, PLL lock only. kaneko_sdram's reset is synchronous
//                 (so its pins pack into I/O cells) and it runs its own
//                 power-up sequence; it must never be reset again after that.
//   rst_por       48 MHz, PLL lock only: every servant here.
//   board_rst     48 MHz: rst_por, or APF holding the core in reset (from
//                 boot to [0011 Reset Exit], and again from [0010 Reset
//                 Enter]), or the Reset action in the menu. The CPUs are
//                 also held until the ROM is in and a frame begins (board_go,
//                 below).

wire pll_core_locked_s;                     // clk_74a
synch_3 s_lock74 (.i(pll_core_locked), .o(pll_core_locked_s), .clk(clk_74a), .rise(), .fall());

wire locked_96;
synch_3 s_lock96 (.i(pll_core_locked), .o(locked_96), .clk(clk_sdram), .rise(), .fall());
wire sdram_rst_n = locked_96;

wire locked_48;
synch_3 s_lock48 (.i(pll_core_locked), .o(locked_48), .clk(clk_core), .rise(), .fall());
reg [7:0] por_cnt = 8'd0;
always @(posedge clk_core)
    if (!locked_48)            por_cnt <= 8'd0;
    else if (por_cnt != 8'hff) por_cnt <= por_cnt + 8'd1;
wire rst_por = (por_cnt != 8'hff);

wire reset_n;                               // clk_74a, from core_bridge_cmd
wire reset_n_48;
synch_3 s_rstn48 (.i(reset_n), .o(reset_n_48), .clk(clk_core), .rise(), .fall());

// ================================================================== bridge
//
// Writes are broadcast: the data_loaders inside pocket_rom_loader and
// pocket_nvram pick out their own regions; the registers below pick out
// theirs. Reads are muxed and REGISTERED: APF buffers bridge reads by one
// word, taking each read's bus value before it strobes bridge_rd, so a
// region backed by memory answers the address of the last strobe
// (pocket_nvram).

wire [31:0] cmd_bridge_rd_data;
wire [31:0] nv_bridge_rd;

// ---- settings written by APF (instance JSON, interact.json)
//
// Every field is laid out so that ZERO IS THE DEFAULT: APF writes persisted
// interact values only when there are some, so on a first boot the core's
// reset value IS the setting.
//
//   0xF0000000 [2:0]   game: 0 snowboar, 1 snowboara. One board for both,
//                      which differ only in the ROM image; the id is shown
//                      on the diagnostic overlay, so the set loaded can be
//                      read off the screen.
//   0xF100000C         write: reset the game (1 ms)
//   0xF1000010         write: Test Mode, a press of the "go to service mode
//                      NOW" bit (COIN bit 2; see TEST MODE below)
//   0xF1000014 [0]     diagnostic overlay (pocket_diag), see DIAGNOSTICS
//   0xF1000018 [0]     swap left and right on both pads (persisted; off is
//                      the arcade's own: see INPUTS)
//
// The board has no DIP switches: every setting is in the EEPROM, set in the
// game's own test menu.

reg  [2:0]  game_74  = 3'd0;
reg         diag_74  = 1'b0;
reg         swap_74  = 1'b0;
reg         test_74  = 1'b0;                // toggles on each Test Mode press
reg  [16:0] hrst_cnt = 17'd0;               //   1 ms at 74.25 MHz = 74,250
wire        hrst_74  = (hrst_cnt != 17'd0);

always @(posedge clk_74a) begin
    if (hrst_cnt != 17'd0) hrst_cnt <= hrst_cnt - 17'd1;
    if (bridge_wr) begin
        case (bridge_addr)
        32'hF0000000: game_74  <= bridge_wr_data[2:0];
        32'hF100000C: hrst_cnt <= 17'd74250;
        32'hF1000010: test_74  <= ~test_74;
        32'hF1000014: diag_74  <= bridge_wr_data[0];
        32'hF1000018: swap_74  <= bridge_wr_data[0];
        default: ;
        endcase
    end
end

always @(posedge clk_74a) begin
    casez (bridge_addr)
    32'h2???????: bridge_rd_data <= nv_bridge_rd;
    32'hF0000000: bridge_rd_data <= {29'd0, game_74};
    32'hF1000014: bridge_rd_data <= {31'd0, diag_74};
    32'hF1000018: bridge_rd_data <= {31'd0, swap_74};
    32'hF8??????: bridge_rd_data <= cmd_bridge_rd_data;
    default:      bridge_rd_data <= 32'd0;
    endcase
end

// ---- the APF command bridge, as the template wires it
wire            status_boot_done  = pll_core_locked_s;
// "Setup" means ready to take memory writes, which here means the SDRAM has
// finished its power-up sequence.
wire            mem_ready;
wire            mem_ready_74;
synch_3 s_memrdy74 (.i(mem_ready), .o(mem_ready_74), .clk(clk_74a), .rise(), .fall());
wire            status_setup_done = pll_core_locked_s & mem_ready_74;
wire            status_running    = reset_n;

wire            dataslot_requestread;
wire    [15:0]  dataslot_requestread_id;
wire            dataslot_requestread_ack = 1;
wire            dataslot_requestread_ok  = 1;

wire            dataslot_requestwrite;
wire    [15:0]  dataslot_requestwrite_id;
wire    [31:0]  dataslot_requestwrite_size;
wire            dataslot_requestwrite_ack = 1;
wire            dataslot_requestwrite_ok  = 1;

wire            dataslot_update;
wire    [15:0]  dataslot_update_id;
wire    [31:0]  dataslot_update_size;

wire            dataslot_allcomplete;

wire     [31:0] rtc_epoch_seconds;
wire     [31:0] rtc_date_bcd;
wire     [31:0] rtc_time_bcd;
wire            rtc_valid;

wire            savestate_supported   = 1'b0;
wire    [31:0]  savestate_addr        = 32'd0;
wire    [31:0]  savestate_size        = 32'd0;
wire    [31:0]  savestate_maxloadsize = 32'd0;

wire            savestate_start;
wire            savestate_start_ack   = 1'b0;
wire            savestate_start_busy  = 1'b0;
wire            savestate_start_ok    = 1'b0;
wire            savestate_start_err   = 1'b0;

wire            savestate_load;
wire            savestate_load_ack    = 1'b0;
wire            savestate_load_busy   = 1'b0;
wire            savestate_load_ok     = 1'b0;
wire            savestate_load_err    = 1'b0;

wire            osnotify_inmenu;

wire            target_dataslot_read      = 1'b0;
wire            target_dataslot_write     = 1'b0;
wire            target_dataslot_getfile   = 1'b0;
wire            target_dataslot_openfile  = 1'b0;

wire            target_dataslot_ack;
wire            target_dataslot_done;
wire    [2:0]   target_dataslot_err;

wire    [15:0]  target_dataslot_id         = 16'd0;
wire    [31:0]  target_dataslot_slotoffset = 32'd0;
wire    [31:0]  target_dataslot_bridgeaddr = 32'd0;
wire    [31:0]  target_dataslot_length     = 32'd0;

wire    [31:0]  target_buffer_param_struct = 32'd0;
wire    [31:0]  target_buffer_resp_struct  = 32'd0;

// THE SAVE FILE'S SIZE. APF writes back as many bytes as the Dataslot
// ID/Size table says, and when no .sav existed yet that entry is zero — the
// game would save into the EEPROM and nothing would ever reach the card. So
// the core keeps writing 512 into the size word of the save slot's entry,
// which is table index 2 (data.json order), word 2*2+1.
reg     [9:0]   datatable_addr;
reg             datatable_wren;
reg     [31:0]  datatable_data;
wire    [31:0]  datatable_q;

always @(posedge clk_74a) begin
    datatable_addr <= 10'd5;
    datatable_wren <= 1'b1;
    datatable_data <= 32'd512;
end

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),

    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),

    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),

    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),

    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),

    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),

    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);

// ======================================================= settings -> 48 MHz
wire [2:0]  game;
wire        host_rst, diag_opt, swap_lr;

pocket_sync_bus #(.W(6), .INIT(6'd0)) s_cfg48 (
    .clk (clk_core),
    .d   ({game_74, hrst_74, diag_74, swap_74}),
    .q   ({game,    host_rst, diag_opt, swap_lr})
);

// A press, not a level: the toggle crosses, and each of its edges is one.
wire        test_tgl;
synch_3 s_test48 (.i(test_74), .o(test_tgl), .clk(clk_core), .rise(), .fall());

wire board_rst = rst_por | ~reset_n_48 | host_rst;

// ================================================================== inputs
//
// The pad bus is on clk_74a. Each button is an independent level, so a
// per-bit synchroniser is enough: a press that lands one cycle earlier on one
// bit than another is invisible to a game polling at 60 Hz.
//
//   p1/p2 = {b3, b2, b1, up, down, left, right}: A is button 1 (Run, and
//   the menus' pick), B and X buttons 2 and 3 (the grabs in the air). Select
//   is the coin, Start is start. Y is player 2's start as well: the game's
//   test screens leave only by "P1+P2", start 1 and start 2 together. A
//   second controller (docked) is player 2, its Select coin 2.
//
//   Left and right are the arcade's by default: the game's own Controls
//   test shows the d-pad's right as the stick's right, and in a race it
//   sends the rider towards the screen's right – his own left as he comes
//   down towards the viewer. "Swap Left/Right" trades the two for anyone
//   who steers as the rider does.
wire [15:0] k1, k2;
synch_3 #(.WIDTH(16)) s_k1 (.i(cont1_key[15:0]), .o(k1), .clk(clk_core), .rise(), .fall());
synch_3 #(.WIDTH(16)) s_k2 (.i(cont2_key[15:0]), .o(k2), .clk(clk_core), .rise(), .fall());

wire [6:0] in_p1    = {k1[6], k1[5], k1[4], k1[0], k1[1],
                       swap_lr ? k1[3] : k1[2], swap_lr ? k1[2] : k1[3]};
wire [6:0] in_p2    = {k2[6], k2[5], k2[4], k2[0], k2[1],
                       swap_lr ? k2[3] : k2[2], swap_lr ? k2[2] : k2[3]};
wire [1:0] in_coin  = {k2[14], k1[14]};
wire [1:0] in_start = {k2[15] | k1[7], k1[15]};

wire inmenu_48;
synch_3 s_inmenu48 (.i(osnotify_inmenu), .o(inmenu_48), .clk(clk_core), .rise(), .fall());

// ========================================================= ROM -> SDRAM
wire allcomplete_48;
synch_3 s_allc48 (.i(dataslot_allcomplete), .o(allcomplete_48), .clk(clk_core), .rise(), .fall());

wire              ldr_wr_req, ldr_wr_ack;
wire [SDR_AW:1]   ldr_wr_addr;
wire [15:0]       ldr_wr_din;
wire [1:0]        ldr_wr_be;
wire              dl_wr;
wire [24:1]       dl_addr;
wire [15:0]       dl_data;
wire              rom_loaded;
wire              ldr_overflow;

pocket_rom_loader #(.SDR_AW(SDR_AW)) u_loader (
    .clk_74a             (clk_74a),
    .bridge_wr           (bridge_wr),
    .bridge_endian_little(bridge_endian_little),
    .bridge_addr         (bridge_addr),
    .bridge_wr_data      (bridge_wr_data),

    .clk                 (clk_core),
    .rst                 (rst_por),
    .mem_ready           (mem_ready),
    .allcomplete_s       (allcomplete_48),

    .wr_req              (ldr_wr_req),
    .wr_addr             (ldr_wr_addr),
    .wr_din              (ldr_wr_din),
    .wr_be               (ldr_wr_be),
    .wr_ack              (ldr_wr_ack),

    .dl_wr               (dl_wr),
    .dl_addr             (dl_addr),
    .dl_data             (dl_data),
    .rom_loaded          (rom_loaded),
    .overflow            (ldr_overflow)
);

// ================================================================== SDRAM
//
// The board's NP read ports and the loader on kaneko_sdram_x2's 48 MHz side,
// kaneko_sdram on the 96 MHz side, as Mille Miglia wires them. Two Pocket
// differences, both at the pins:
//
//   - The Pocket's SDRAM has no CS# pin (it is tied active on the board).
//     kaneko_sdram never issues DESELECT — every command it encodes has
//     cs_n = 0 — so dropping sd_cs_n loses nothing.
//   - dram_clk is clk_sdram_ps forwarded through a DDIO output register
//     rather than routed to the pin as a clock; see mf_pllbase_0002.v.

// Port NP (the last) is the shell's read-back check (DIAGNOSTICS below);
// the board owns 0..NP-1.
wire [NPS-1:0]         rom_req;
wire [NPS*SDR_AW-1:0]  rom_addr;
wire [NPS-1:0]         rom_ack;
wire [NPS*64-1:0]      rom_dout;

wire [NPS-1:0]         f_req, f_ack, f_we;
wire [NPS*SDR_AW-1:0]  f_addr;
wire [NPS*64-1:0]      f_dout;
wire [NPS*16-1:0]      f_din;
wire [NPS*2-1:0]       f_be;
wire                   f_wr_req, f_wr_ack;
wire [SDR_AW:1]        f_wr_addr;
wire [15:0]            f_wr_din;
wire [1:0]             f_wr_be;
wire [NPS-1:0]         sdr_dbg_req, sdr_dbg_grant;

kaneko_sdram_x2 #(.NP(NPS), .AW(SDR_AW)) u_sdr_x2 (
    .clk_fast (clk_sdram),

    // NOBODY READS SDRAM UNTIL THE ROM IS IN IT: readers running during the
    // download starve the loader's writes. Requesters hold req until
    // acknowledged, so masking here parks them and they resume the moment
    // rom_loaded rises.
    .s_req    (rom_loaded ? rom_req : {NPS{1'b0}}),
    .s_addr   (rom_addr),
    .s_we     ({NPS{1'b0}}),
    .s_din    ({NPS{16'd0}}),
    .s_be     ({NPS{2'b11}}),
    .s_ack    (rom_ack),
    .s_dout   (rom_dout),

    .s_wr_req (ldr_wr_req),  .s_wr_addr(ldr_wr_addr), .s_wr_din(ldr_wr_din),
    .s_wr_be  (ldr_wr_be),   .s_wr_ack (ldr_wr_ack),

    .f_req    (f_req),  .f_addr(f_addr), .f_ack(f_ack), .f_dout(f_dout),
    .f_we     (f_we),   .f_din (f_din),  .f_be (f_be),
    .f_wr_req (f_wr_req), .f_wr_addr(f_wr_addr), .f_wr_din(f_wr_din),
    .f_wr_be  (f_wr_be),  .f_wr_ack (f_wr_ack)
);

// READ CAPTURE DEPTH (kaneko_sdram rd_lat_sel), fixed at CL+2: measured on
// the Pocket's SDRAM with Mille Miglia (9 Oct 2026; the paper's CL+3
// returned each line one word early). The overlay's read-back of line 0
// (flag 7, counters 6 and 7) checks it on every frame.
wire [1:0] rd_lat_sel = 2'd2;       // CL+2

wire        sd_cs_n_unused;
wire        sd_dq_oe;
wire [15:0] sd_dq_o;
assign dram_dq = sd_dq_oe ? sd_dq_o : 16'bZ;

kaneko_sdram #(
    .COL_BITS (SDR_COL),
    .NP       (NPS),
    // 8192 rows per 64 ms = one refresh per 7.8 us = 750 cycles at 96 MHz;
    // 700 keeps margin for a transfer in flight when the timer fires.
    .T_REFI   (700),
    // T_RC is what kaneko_sdram waits after AUTO REFRESH, so it must cover
    // tRFC (80 ns for the Pocket's mobile SDRAM family): 11 = 115 ns.
    .T_RC     (11),
    // JEDEC power-up: 200 us of NOP before the first command; the init
    // sequence counts down from here and starts at 400, so 25000 is 256 us.
    .INIT_NOP (25000),
    // Every board port has a deadline: 0 the 68000's program and 4 the
    // CG-1V's sound hold board time while they wait; 1 and 2 the tilemaps
    // and 3 and 5 the sprite cells' two halves must finish a line in a
    // line. Only 6, the read-back check, waits.
    .URGENT   (7'b011_1111)
) u_sdram (
    .clk       (clk_sdram),
    .rst_n     (sdram_rst_n),
    .ready     (mem_ready),
    .rd_lat_sel(rd_lat_sel),

    .sd_cke    (dram_cke),
    .sd_cs_n   (sd_cs_n_unused),
    .sd_ras_n  (dram_ras_n),
    .sd_cas_n  (dram_cas_n),
    .sd_we_n   (dram_we_n),
    .sd_ba     (dram_ba),
    .sd_a      (dram_a),
    .sd_dqm    (dram_dqm),
    .sd_dq_o   (sd_dq_o),
    .sd_dq_oe  (sd_dq_oe),
    .sd_dq_i   (dram_dq),

    .wr_req    (f_wr_req), .wr_addr(f_wr_addr), .wr_din(f_wr_din),
    .wr_be     (f_wr_be),  .wr_ack (f_wr_ack),

    .p_req     (f_req),
    .p_we      (f_we),
    .p_addr    (f_addr),
    .p_din     (f_din),
    .p_be      (f_be),
    .p_dout    (f_dout),
    .p_ack     (f_ack),
    .dbg_req   (sdr_dbg_req),
    .dbg_grant (sdr_dbg_grant)
);

pin_ddio_clk u_dram_clk (
    .datain_h ( 1'b1 ),
    .datain_l ( 1'b0 ),
    .outclock ( clk_sdram_ps ),
    .dataout  ( dram_clk )
);

// =================================================================== SRAM
// Work RAM (words 0-7fff) and extra RAM (8000-8fff), as the board asks.
wire        ram_req, ram_we, ram_ack;
wire [16:0] ram_addr;
wire [15:0] ram_din, ram_dout;
wire [1:0]  ram_be;

pocket_sram u_sram (
    .clk      (clk_core),
    .rst      (rst_por),
    .req      (ram_req),
    .we       (ram_we),
    .addr     (ram_addr),
    .din      (ram_din),
    .be       (ram_be),
    .ack      (ram_ack),
    .dout     (ram_dout),
    .sram_a   (sram_a),
    .sram_dq  (sram_dq),
    .sram_oe_n(sram_oe_n),
    .sram_we_n(sram_we_n),
    .sram_ub_n(sram_ub_n),
    .sram_lb_n(sram_lb_n)
);

// ======================================================= release and pause
//
// IRQ 6 is counted in board time (the 68000's ticks) and the video runs on
// wall time; the game must see IRQ 6 where the picture's vblank begins,
// because IRQ 6 is the instant the sprite buffer is copied (holding board
// time for ~10,000 clocks) and the copy has to land in vblank. The board's
// IRQ_DEN is exactly one video frame of ticks, so the two never drift apart
// once they are in step (ticks board time has to drop, when the SDRAM's
// waits run its credit out, IRQ 6 counts as given: snowboar_board); what
// puts them in step is WHEN board time starts and stops:
//
//   - The CPUs are released (board_go) on the first vblank after the ROM is
//     in and the reset is over, so the first IRQ 6, one frame of ticks
//     later, falls just after the next vblank begins (behind it only by the
//     credit board time owes, a few microseconds), as in the harness.
//   - Pause (the Pocket's own menu open, APF's OS notify 0x00B0) starts and
//     ends at the beginning of a vblank too, so the frames it takes out of
//     board time are whole ones and IRQ 6 keeps its place in the picture.
//     The picture goes black at once (below); the board stops at the next
//     vblank and starts again at the first one after the menu closes.
//
// The video itself never stops or resets: snowboar_video_timing has no
// reset, so a Reset Game keeps the frame where it was.
wire        ce_pix, hs, vs, hblank, vblank_b;
reg         vb_q     = 1'b0;
wire        vb_rise  = vblank_b & ~vb_q;
reg         board_go = 1'b0;
reg         pause_b  = 1'b0;
always @(posedge clk_core) begin
    vb_q <= vblank_b;
    if (board_rst)                  board_go <= 1'b0;
    else if (vb_rise && rom_loaded) board_go <= 1'b1;
    if (vb_rise) pause_b <= inmenu_48;
end

// ============================================================== TEST MODE
//
// The board has no service DIP. Its "go to service mode NOW" bit (COIN bit
// 2) opens TEST OPTIONS once the game has seen it held for six frames
// (MAME), so the menu's Test Mode is a press of it, TEST_FRAMES frames of
// board time long. The press is chosen with the Pocket's menu open, when
// the board stands still, so it waits (test_pend) until the menu has closed
// and board time runs again; counted while the board stands, it would run
// out unseen.
localparam [3:0] TEST_FRAMES = 4'd8;
reg        test_tgl_q = 1'b0;
reg        test_pend  = 1'b0;
reg  [3:0] test_cnt   = 4'd0;
wire       in_service = (test_cnt != 4'd0);
always @(posedge clk_core) begin
    test_tgl_q <= test_tgl;
    if (test_tgl != test_tgl_q) test_pend <= 1'b1;
    if (board_rst) test_cnt <= 4'd0;
    else if (test_pend && board_go && !inmenu_48 && !pause_b) begin
        test_pend <= 1'b0;
        test_cnt  <= TEST_FRAMES;
    end else if (vb_rise && in_service && !pause_b) test_cnt <= test_cnt - 4'd1;
end

// ================================================================= EEPROM
// The 93C66's second port and the save slot (pocket_nvram's header). APF
// writes the .sav in before the ROM is loaded, so the EEPROM is filled
// before the 68000 runs; a missing .sav is filled with 0xFF (data.json
// parameters 0x24), the blank chip from which the game writes its own
// defaults.
wire [7:0]  nv_addr;
wire [15:0] nv_din, nv_dout;
wire        nv_we, nv_dirty, nv_dirty_clr;

pocket_nvram u_nvram (
    .clk_74a             (clk_74a),
    .bridge_wr           (bridge_wr),
    .bridge_rd           (bridge_rd),
    .bridge_endian_little(bridge_endian_little),
    .bridge_addr         (bridge_addr),
    .bridge_wr_data      (bridge_wr_data),
    .bridge_rd_word      (nv_bridge_rd),
    .clk                 (clk_core),
    .nv_addr             (nv_addr),
    .nv_din              (nv_din),
    .nv_we               (nv_we),
    .nv_dout             (nv_dout),
    .nv_dirty            (nv_dirty),
    .nv_dirty_clr        (nv_dirty_clr)
);

// ================================================================== board
wire [7:0]  r, g, b;
wire signed [15:0] snd_l, snd_r;
wire        snd_sample;
wire [12:0] diag_owed;
wire        diag_irq, diag_copying, diag_spr_cut, diag_tm_ovr;

snowboar_board #(.SDR_AW(SDR_AW), .NP(NP)) u_board (
    .clk        (clk_core),
    .rst        (board_rst),

    .rom_req    (rom_req[NP-1:0]),
    .rom_addr   (rom_addr[NP*SDR_AW-1:0]),
    .rom_ack    (rom_ack[NP-1:0]),
    .rom_dout   (rom_dout[NP*64-1:0]),

    .sram_req   (ram_req),
    .sram_we    (ram_we),
    .sram_addr  (ram_addr),
    .sram_din   (ram_din),
    .sram_be    (ram_be),
    .sram_ack   (ram_ack),
    .sram_dout  (ram_dout),

    .rom_loaded (board_go),

    .eep_addr       (nv_addr),
    .eep_we         (nv_we),
    .eep_din        (nv_din),
    .eep_dout       (nv_dout),
    .eep_changed_clr(nv_dirty_clr),
    .eep_changed    (nv_dirty),

    .ce_pix     (ce_pix),
    .hs         (hs),
    .vs         (vs),
    .hblank     (hblank),
    .vblank     (vblank_b),
    .r          (r),
    .g          (g),
    .b          (b),

    .snd_l      (snd_l),
    .snd_r      (snd_r),
    .snd_sample (snd_sample),

    .p1         (in_p1),
    .p2         (in_p2),
    .coin       (in_coin),
    .start      (in_start),
    .service    (in_service),       // Test Mode's press (TEST MODE above)
    .service1   (1'b0),             // no service coin: Select is the coin
    .pause      (pause_b),

    .diag_owed    (diag_owed),
    .diag_irq     (diag_irq),
    .diag_copying (diag_copying),
    .diag_spr_cut (diag_spr_cut),
    .diag_tm_ovr  (diag_tm_ovr)
);

// ============================================================ DIAGNOSTICS
//
// pocket_diag draws the shell's state over the picture (its header says
// what, where). It is on whenever the menu's "Diagnostic overlay" is, and on
// its own while the ROM is not yet loaded, when colour bars stand in for the
// picture: a core that never gets past loading says so on screen instead of
// staying black.
//
// Flags (left to right, green = 1):
//   0 PLL locked            1 SDRAM initialised (mem_ready)
//   2 APF reset released    3 APF "all slots loaded" seen
//   4 rom_loaded            5 loader FIFO overflowed (should stay red)
//   6 CPU held (reset, or waiting for the ROM and a vblank)
//   7 SDRAM read-back of words 0-3 == what was written
//   8 the game has written the EEPROM (a setting saved, or its defaults
//     on a first boot)
//   9 blinks about once a second (frame counter)
//   10 board time stopped (pause)
//   11 a sprite line was cut short: its SDRAM fetches did not finish in
//      the line (should stay red)
//   12 a tilemap line was cut short (should stay red)
//   13 the sprite buffer's copy ran outside vblank (should stay red)
//   14 board time fell a whole credit (8,191 ticks) behind and lost ticks,
//      which moves IRQ 6 in the picture (should stay red)
//   15 the audio FIFO ran dry or overflowed while the game ran (should
//      stay red)
//
// Counters (hex):
//   0 high half: game id; low half: the most board time has owed, ticks
//   1 high half: longest wait on SDRAM port 0 (the 68000's program);
//     low half: on the SRAM (work and extra RAM), clocks
//   2 high half: port 1 (tilemap 0); low half: port 2 (tilemap 1)
//   3 high half: port 3 (sprite cells' left halves); low half: port 5
//     (their right halves)
//   4 high half: port 4 (sound); low half: EEPROM writes seen
//   5 high half: sprite lines cut short; low half: the line of the picture
//     (counted from vblank's start, 0 = its first line) the last IRQ 6 fell on
//   6 words 1,0 of line 0 as SDRAM reads them back    7 words 3,2 as read back
//
// Peaks, counts and flags 8 and 11-15 hold until the overlay is turned OFF
// in the menu (diag_clr), so the routine is: overlay on to see the baseline,
// off to clear, play until the moment, overlay on and photograph.
//
// The read-back is port NP of the controller: once per frame, after
// rom_loaded, it reads line 0 (the 68000's reset vector) and flag 7
// compares it with the loader's copy.
wire        mem_ready_48;
synch_3 s_memrdy48 (.i(mem_ready), .o(mem_ready_48), .clk(clk_core), .rise(), .fall());

wire        aud_under, aud_over;

reg  [15:0] exp_w0 = 16'd0, exp_w1 = 16'd0, exp_w2 = 16'd0, exp_w3 = 16'd0;
reg         diag_opt_q = 1'b0;
wire        diag_clr = diag_opt_q & ~diag_opt;    // overlay turned off

// Request-to-ack waits. Each request is a level that rises once per
// transfer and falls on its ack.
function automatic [15:0] sat_inc(input [15:0] v);
    sat_inc = (v == 16'hffff) ? v : v + 16'd1;
endfunction
reg  [NP-1:0] rq_q = {NP{1'b0}};
reg  [15:0]   w_cnt [0:NP-1];
reg  [15:0]   w_max [0:NP-1];
reg  [15:0]   w_ram = 16'd0, w_ram_max = 16'd0;
reg           ram_req_q = 1'b0;
reg  [12:0]   owed_max = 13'd0;
reg  [15:0]   spr_cuts = 16'd0;
reg  [15:0]   eep_writes = 16'd0;
reg           eep_q = 1'b0;
reg  [8:0]    vline = 9'd0, irq_line = 9'd0;
reg           hb_q = 1'b0;
reg           f_spr = 1'b0, f_tm = 1'b0, f_copy = 1'b0, f_owed = 1'b0, f_aud = 1'b0;
reg           f_eep = 1'b0;
reg  [63:0]   rb_line = 64'd0;
reg           rb_req  = 1'b0;
reg  [7:0]    frame   = 8'd0;
wire          rb_ack  = rom_ack[NP];
assign rom_req[NP]  = rb_req;
assign rom_addr[NP*SDR_AW +: SDR_AW] = {SDR_AW{1'b0}};
integer pi;
always @(posedge clk_core) begin
    diag_opt_q <= diag_opt;
    rq_q       <= rom_req[NP-1:0];
    ram_req_q  <= ram_req;
    hb_q       <= hblank;
    eep_q      <= nv_dirty;
    // lines since vblank began
    if (vb_rise)                         vline <= 9'd0;
    else if (hblank && !hb_q)            vline <= vline + 9'd1;
    if (diag_irq) irq_line <= vline;
    if (board_rst || diag_clr) begin
        for (pi = 0; pi < NP; pi = pi + 1) begin w_cnt[pi] <= 16'd0; w_max[pi] <= 16'd0; end
        w_ram <= 16'd0; w_ram_max <= 16'd0; owed_max <= 13'd0; spr_cuts <= 16'd0;
        f_spr <= 1'b0; f_tm <= 1'b0; f_copy <= 1'b0; f_owed <= 1'b0; f_aud <= 1'b0;
    end else begin
        for (pi = 0; pi < NP; pi = pi + 1) begin
            if (rom_req[pi] && !rq_q[pi]) w_cnt[pi] <= 16'd1;
            else if (rom_req[pi])         w_cnt[pi] <= sat_inc(w_cnt[pi]);
            if (rom_req[pi] && w_cnt[pi] > w_max[pi]) w_max[pi] <= w_cnt[pi];
        end
        if (ram_req && !ram_req_q) w_ram <= 16'd1;
        else if (ram_req)          w_ram <= sat_inc(w_ram);
        if (ram_req && w_ram > w_ram_max) w_ram_max <= w_ram;
        if (diag_owed > owed_max)   owed_max <= diag_owed;
        if (diag_owed == 13'h1fff)  f_owed   <= 1'b1;
        if (diag_spr_cut) begin f_spr <= 1'b1; spr_cuts <= sat_inc(spr_cuts); end
        if (diag_tm_ovr)            f_tm     <= 1'b1;
        if (diag_copying && !vblank_b) f_copy <= 1'b1;
        if (aud_under || aud_over)  f_aud    <= 1'b1;
    end
    // The EEPROM's are kept across a Reset Game, which is not a save.
    if (diag_clr) begin
        f_eep <= 1'b0; eep_writes <= 16'd0;
    end else if (nv_dirty && !eep_q && board_go) begin
        f_eep <= 1'b1; eep_writes <= sat_inc(eep_writes);
    end
    if (dl_wr && dl_addr[24:3] == 22'd0) begin
        case (dl_addr[2:1])
        2'd0: exp_w0 <= dl_data;
        2'd1: exp_w1 <= dl_data;
        2'd2: exp_w2 <= dl_data;
        2'd3: exp_w3 <= dl_data;
        endcase
    end
    if (vb_rise) frame <= frame + 8'd1;
    if (rb_req) begin
        if (rb_ack) begin
            rb_req  <= 1'b0;
            rb_line <= rom_dout[NP*64 +: 64];
        end
    end else if (rom_loaded && vb_rise) begin
        rb_req <= 1'b1;
    end
end
wire [63:0] exp_line = {exp_w3, exp_w2, exp_w1, exp_w0};
wire [15:0] diag_flags = {f_aud, f_owed, f_copy, f_tm, f_spr, pause_b,
                          frame[5], f_eep,
                          (rb_line == exp_line), board_rst | ~board_go, ldr_overflow, rom_loaded,
                          allcomplete_48, reset_n_48, mem_ready_48, locked_48};
wire [7:0]  dr, dg, db, mr, mg, mb;
pocket_diag u_diag (
    .clk    (clk_core),
    .ce_pix (ce_pix),
    .hblank (hblank),
    .vblank (vblank_b),
    .r_in   (r), .g_in (g), .b_in (b),
    .enable (diag_opt | ~rom_loaded),
    .bars   (~rom_loaded),
    .flags  (diag_flags),
    .cnt    ({rb_line[63:32], rb_line[31:0],
              spr_cuts, 7'd0, irq_line,
              w_max[4], eep_writes,
              w_max[3], w_max[5],
              w_max[1], w_max[2],
              w_max[0], w_ram_max,
              13'd0, game, 3'd0, owed_max}),
    .r_out  (dr), .g_out (dg), .b_out (db)
);

// Black behind the Pocket's menu: the game is paused under it.
assign {mr, mg, mb} = inmenu_48 ? 24'd0 : {dr, dg, db};

// ================================================================== video
assign video_rgb_clock    = clk_vid;
assign video_rgb_clock_90 = clk_vid90;

pocket_video u_video (
    .clk       (clk_core),
    .ce_pix    (ce_pix),
    .hs        (hs),
    .vs        (vs),
    .hblank    (hblank),
    .vblank    (vblank_b),
    .r         (mr),
    .g         (mg),
    .b         (mb),
    .clk_vid   (clk_vid),
    .video_rgb (video_rgb),
    .video_de  (video_de),
    .video_hs  (video_hs),
    .video_vs  (video_vs),
    .video_skip(video_skip)
);

// ================================================================== audio
//
// The CG-1V's two outputs, stereo: output 0 to the left, output 1 to the
// right, as MAME routes them for this game (gaelco2.cpp, snowboar). The
// board makes a pair every 1,920 ticks of board time, which keeps 15 MHz on
// average but not from moment to moment (it stands still for the sprite
// copy, then catches up at 24 MHz), so pocket_audio smooths the pairs out
// at exactly 7812.5 Hz of wall time (48 MHz / 6144) through a short FIFO.
// sound_i2s (agg23, MIT) generates MCLK/SCLK/LRCK from clk_74a as Analogue's
// example does and moves the levels across from the core clock.
wire signed [15:0] aud_l, aud_r;
pocket_audio u_audio (
    .clk    (clk_core),
    .rst    (board_rst | ~board_go),
    .sample (snd_sample),
    .din_l  (snd_l),
    .din_r  (snd_r),
    .paused (pause_b),
    .dout_l (aud_l),
    .dout_r (aud_r),
    .under  (aud_under),
    .over   (aud_over)
);

sound_i2s #(
    .CHANNEL_WIDTH(16),
    .SIGNED_INPUT (1)
) u_i2s (
    .clk_74a   (clk_74a),
    .clk_audio (clk_core),
    .audio_l   (aud_l),
    .audio_r   (aud_r),
    .audio_mclk(audio_mclk),
    .audio_lrck(audio_lrck),
    .audio_dac (audio_dac)
);

endmodule

`default_nettype wire
