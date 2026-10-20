// SPDX-License-Identifier: GPL-3.0-or-later
// Snow Board Championship (Pocket) — the 68000 and its bus: fx68k, the map
// (snowboar_addr_decode), the video registers, IRQ 6, the protection, the
// LS259 and the EEPROM, work and extra RAM on the platform's SRAM.

`default_nettype none

module snowboar_main (
    input  wire        clk,
    input  wire        rst,
    input  wire        game_run,
    input  wire        vblank_irq,

    output wire [19:1] prog_addr,
    output wire        prog_cs,
    input  wire [15:0] prog_data,
    input  wire        prog_data_ok,

    // active high; p = {b3, b2, b1, up, down, left, right}
    input  wire [6:0]  p1, p2,
    input  wire [1:0]  coin, start,
    input  wire        service, service1,

    output wire [15:0] vmem_addr,
    output wire        vmem_uds, vmem_lds,
    output wire        vmem_we,
    output wire        vmem_cs_vram,
    output wire        vmem_cs_pal,
    output wire [15:0] vmem_wdata,
    input  wire [15:0] vmem_vram_rdata,
    input  wire [15:0] vmem_pal_rdata,

    output wire [15:0] vreg0, vreg1, vreg2,

    output wire        sndreg_cs,
    output wire        sndreg_we,
    input  wire [15:0] snd_rdata,

    output wire        cpu_tick,       // one 68000 clock of board time (snowboar_cpu_clk)
    input  wire        cpu_hold,       // board time stands still (the CG-1V computing a sample, the copy)
    output wire [11:0] cpu_owed,       // board time behind wall time, in ticks
    output wire        cpu_lost,       // a tick dropped with the credit full (snowboar_cpu_clk)

    // Work RAM (fe0000-feffff, SRAM words 0-7fff) and extra RAM (212000-
    // 213fff, words 8000-8fff) on the platform's SRAM: req held until a
    // one-clock ack, dout valid with it. Board time waits for it.
    output reg         sram_req,
    output reg         sram_we,
    output reg  [16:0] sram_addr,
    output reg  [15:0] sram_din,
    output reg  [1:0]  sram_be,
    input  wire        sram_ack,
    input  wire [15:0] sram_dout,

    // the EEPROM's second port (snowboar_eeprom)
    input  wire [7:0]  eep_addr,
    input  wire        eep_we,
    input  wire [15:0] eep_din,
    output wire [15:0] eep_dout,
    input  wire        eep_changed_clr,
    output wire        eep_changed
);

    wire [23:1] eab;
    wire        ASn, LDSn, UDSn, eRWn;
    wire [15:0] oEdb;
    reg  [15:0] iEdb;
    wire        DTACKn;
    reg         VPAn;
    wire        FC0, FC1, FC2;
    reg         IPL_n;
    wire [2:0]  fc = {FC2, FC1, FC0};
    wire        cpu_cen, cpu_cenb, cpu_mid;

    fx68k u_cpu (
        .clk(clk), .HALTn(1'b1),
        .extReset(rst), .pwrUp(rst),
        .enPhi1(cpu_cen), .enPhi2(cpu_cenb),
        .eRWn(eRWn), .ASn(ASn), .LDSn(LDSn), .UDSn(UDSn),
        .E(), .VMAn(), .FC0(FC0), .FC1(FC1), .FC2(FC2),
        .BGn(), .oRESETn(), .oHALTEDn(),
        .DTACKn(DTACKn), .VPAn(VPAn), .BERRn(1'b1),
        .BRn(1'b1), .BGACKn(1'b1),

        .IPL0n(1'b1), .IPL1n(IPL_n), .IPL2n(IPL_n),
        .iEdb(iEdb), .oEdb(oEdb), .eab(eab)
    );

    wire [23:0] addr  = {eab, 1'b0};
    wire        uds   = ~UDSn;
    wire        lds   = ~LDSn;
    wire        rw_rd = eRWn;

    wire cs_rom, cs_vram, cs_sound, cs_pal, cs_xram, cs_vregs, cs_p1, cs_p2, cs_coin,
         cs_latch, cs_prot, cs_wram;
    snowboar_addr_decode u_dec (
        .addr(addr), .as(~ASn),
        .cs_rom(cs_rom), .cs_vram(cs_vram), .cs_sound(cs_sound), .cs_pal(cs_pal), .cs_xram(cs_xram),
        .cs_vregs(cs_vregs), .cs_p1(cs_p1), .cs_p2(cs_p2), .cs_coin(cs_coin),
        .cs_latch(cs_latch), .cs_prot(cs_prot), .cs_wram(cs_wram)
    );

    // wr_ack: every clock of a bus cycle after its first (writes repeat, which
    // the registers do not mind)
    reg  asn_d;
    wire wr_ack     = (~ASn) & (~asn_d);

    // ---------------------------------------------------------- inputs, LS259, EEPROM
    wire [15:0] port_p1, port_p2, port_coin;
    wire [7:0]  lq;
    wire        eep_do;
    snowboar_inputs u_in (
        .clk(clk), .rst(rst),
        .p1(p1), .p2(p2), .coin(coin), .start(start),
        .service(service), .service1(service1), .eep_do(eep_do),
        .port_p1(port_p1), .port_p2(port_p2), .port_coin(port_coin),
        .latch_we(wr_ack & ~rw_rd & cs_latch & lds), .latch_sel(addr[3:1]), .latch_d(oEdb[0]),
        .q(lq)
    );
    snowboar_eeprom u_eep (
        .clk(clk), .rst(rst), .tick(cpu_tick),
        .cs(lq[6]), .sclk(lq[5]), .di(lq[4]), .dout(eep_do),
        .dump_addr(eep_addr), .dump_we(eep_we), .dump_din(eep_din), .dump_dout(eep_dout),
        .changed_clr(eep_changed_clr), .changed(eep_changed)
    );

    // ---------------------------------------------------------- protection
    // shifts once a write cycle, on the first clock its data strobes are out
    wire [15:0] prot_q;
    reg         prot_done;
    wire        prot_we = ~ASn & ~rw_rd & cs_prot & (uds | lds) & ~prot_done;
    always @(posedge clk) prot_done <= rst ? 1'b0 : ASn ? 1'b0 : prot_done | prot_we;
    snowboar_prot u_prot (
        .clk(clk), .rst(rst), .we(prot_we), .din(oEdb), .dout(prot_q)
    );

    // ---------------------------------------------------------- board time
    assign prog_addr = eab[19:1];
    assign prog_cs   = cs_rom & rw_rd;

    wire bus_busy  = cs_rom & rw_rd & ~prog_data_ok;
    wire sram_wait;
    wire dtack_raw;
    snowboar_cpu_clk u_clk (
        .rst(rst), .clk(clk), .run(game_run),
        .ASn(ASn), .rom_wait(bus_busy | (sram_wait & rw_rd)), .hold((sram_wait & ~rw_rd) | cpu_hold),
        .cpu_cen(cpu_cen), .cpu_cenb(cpu_cenb), .tick(cpu_tick), .mid(cpu_mid),
        .DTACKn(dtack_raw), .owed(cpu_owed), .lost(cpu_lost)
    );

    assign DTACKn = (fc == 3'd7) ? 1'b1 : dtack_raw;

    // ---------------------------------------------------------- video registers
    reg [15:0] vregs[0:7];
`ifdef VERILATOR
    // the harness's scene mode: vreg sc_vsel = sc_vdata
    reg        sc_vwe   /*verilator public_flat_rw*/ = 1'b0;
    reg [2:0]  sc_vsel  /*verilator public_flat_rw*/ = 3'd0;
    reg [15:0] sc_vdata /*verilator public_flat_rw*/ = 16'd0;
`endif
    assign vreg0 = vregs[2]; assign vreg1 = vregs[3]; assign vreg2 = vregs[4];

    assign vmem_addr    = addr[15:0];
    assign vmem_uds     = uds;
    assign vmem_lds     = lds;
    assign vmem_cs_vram = cs_vram;
    assign vmem_cs_pal  = cs_pal;
    assign vmem_we      = wr_ack & ~rw_rd & (cs_vram | cs_pal);
    assign vmem_wdata   = oEdb;

    assign sndreg_cs    = cs_sound;
    assign sndreg_we    = wr_ack & ~rw_rd & cs_sound;

    // MAME's unmapped reads are 0
    always @(*) begin
        case (1'b1)
            cs_rom:   iEdb = prog_data;
            cs_vram:  iEdb = vmem_vram_rdata;
            cs_pal:   iEdb = vmem_pal_rdata;
            cs_xram:  iEdb = sram_q;
            cs_vregs: iEdb = vregs[addr[3:1]];
            cs_p1:    iEdb = port_p1;
            cs_p2:    iEdb = port_p2;
            cs_coin:  iEdb = port_coin;
            cs_prot:  iEdb = prot_q;
            cs_wram:  iEdb = sram_q;
            cs_sound: iEdb = snd_rdata;
            default:  iEdb = 16'h0000;
        endcase
    end

    reg irq_pending;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            asn_d       <= 1'b1;
            VPAn        <= 1'b1;
            irq_pending <= 1'b0;
            IPL_n       <= 1'b1;
        end else begin
            asn_d <= ASn;

            if (vblank_irq) irq_pending <= 1'b1;
            // IPL moves with phi2's clock or after it, never between phi1 and
            // phi2: where it lands against the phases decides which instruction
            // takes the IRQ, and a hold of board time (a ROM miss, the SRAM,
            // the sprite copy, the CG-1V) can come between them
            if (!cpu_mid) IPL_n <= ~irq_pending;
`ifdef VERILATOR
            if (sc_vwe) vregs[sc_vsel] <= sc_vdata;
`endif

            if (~ASn) VPAn <= (fc == 3'd7) ? 1'b0 : 1'b1;
            else      VPAn <= 1'b1;

            if (wr_ack) begin
                if (fc == 3'd7) begin
                    irq_pending <= 1'b0;
                end else if (~rw_rd) begin
                    if (cs_vregs) begin
                        if (uds) vregs[addr[3:1]][15:8] <= oEdb[15:8];
                        if (lds) vregs[addr[3:1]][7:0]  <= oEdb[7:0];
                    end
                end
            end
        end
    end

    // One request a bus cycle, once its data strobes are out (a write's come
    // a phase after AS); `sram_done` until they fall, so a read-modify-write
    // cycle makes two. The CPU is not clocked meanwhile, as for a ROM miss;
    // a read's DTACK waits for the data, a write's does not.
    wire        cs_sram   = cs_wram | cs_xram;
    wire        sram_need = cs_sram & ~ASn & (uds | lds);
    reg         sram_done;
    reg  [15:0] sram_q;
    assign      sram_wait = sram_need & ~sram_done;
    always @(posedge clk) begin
        if (rst) begin
            sram_req <= 1'b0; sram_done <= 1'b0;
        end else begin
            if (ASn || !(uds || lds)) sram_done <= 1'b0;
            if (!sram_req && sram_wait) begin
                sram_req  <= 1'b1;
                sram_we   <= ~rw_rd;
                sram_addr <= cs_wram ? {2'b00, addr[15:1]} : {5'b01000, addr[12:1]};
                sram_din  <= oEdb;
                sram_be   <= {uds, lds};
            end
            if (sram_req && sram_ack) begin
                sram_req  <= 1'b0;
                sram_done <= 1'b1;
                sram_q    <= sram_dout;
            end
        end
    end
endmodule

`default_nettype wire
