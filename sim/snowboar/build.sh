#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the whole-board harness. Run from the repository root.
#   sim/snowboar/build.sh [extra verilator args]
# PIX=pocket builds the Pocket's frame (8 MHz, 59.19 Hz, IRQ 6 every
# 253,440 ticks); the default stretches the frame and IRQ 6 to MAME's
# 59.1 Hz so a bus trace keeps its IRQs in step (IRQ_FIRST: 68000 clocks
# to the first one, 253,805: where MAME's trace puts its first vblank
# against the core's ticks), and the CG-1V's samples to MAME's 7,812 Hz (its
# stream rate is 1 MHz / 128 in integers; the chip's own is 7,812.5 Hz).
# SDR=real times the ROM lines with the shell's SDRAM controller
# (sim/snowboar/sdr_timing.sv, built first as its own model) instead of the
# harness's fixed latency.
set -euo pipefail
mkdir -p build/obj_snowboar build/tmp build/gen
export TMPDIR="$PWD/build/tmp"
# $readmemh files, read relative to where tb_snowboar runs (--gen-dir)
[ -f build/gen/volume_table.mem ] || python3 -I tools/gen_volume_table.py build/gen/volume_table.mem
cmp -s third_party/fx68k/hdl/microrom.mem build/gen/microrom.mem || cp third_party/fx68k/hdl/microrom.mem build/gen/
cmp -s third_party/fx68k/hdl/nanorom.mem build/gen/nanorom.mem || cp third_party/fx68k/hdl/nanorom.mem build/gen/
SDRG=()
if [ "${SDR:-}" = real ]; then
  SO="${OBJ:-build/obj_snowboar}_sdr"
  verilator --cc -O3 --x-assign fast --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
    --top-module sdr_timing --prefix Vsdr_timing --Mdir "$SO" \
    sim/snowboar/sdr_timing.sv rtl/mem/kaneko_sdram_x2.sv rtl/mem/kaneko_sdram.sv sim/mem/sdram_model.sv
  make -s -C "$SO" -f Vsdr_timing.mk Vsdr_timing__ALL.a OPT_FAST=-O2
  SDRG=(-CFLAGS -DSDR_REAL -CFLAGS "-I$PWD/$SO" "$PWD/$SO/Vsdr_timing__ALL.a")
fi
if [ "${PIX:-mame}" = pocket ]; then PIXG=(-GPIX_NUM=1 -GPIX_DEN=6)
else PIXG=(-GPIX_NUM=13002 -GPIX_DEN=78125 -GIRQ_NUM=${IRQ_NUM:-591} -GIRQ_DEN=${IRQ_DEN:-150000000}
       -GIRQ_FIRST=${IRQ_FIRST:-253805} -GSND_NUM=7812 -GSND_DEN=15000000); fi
verilator --cc --exe --build -j 0 -O3 --x-assign fast --x-initial 0 \
  -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD \
  --top-module snowboar_board --Mdir "${OBJ:-build/obj_snowboar}" -o tb_snowboar \
  "${PIXG[@]}" ${SDRG[@]+"${SDRG[@]}"} -CFLAGS -O2 "$@" \
  rtl/top/snowboar_board.sv rtl/mem/snowboar_romport.sv \
  rtl/cpu/snowboar_main.v rtl/cpu/snowboar_addr_decode.v rtl/cpu/snowboar_cpu_clk.sv \
  rtl/cpu/snowboar_prot.v rtl/io/snowboar_inputs.v rtl/io/snowboar_eeprom.sv \
  rtl/mem/snowboar_vmem.v \
  rtl/video/snowboar_video_top.v rtl/video/snowboar_video_timing.v rtl/video/snowboar_gae1_video.v \
  rtl/video/snowboar_gae1_tilemap.v rtl/video/snowboar_gae1_sprite.v rtl/video/snowboar_gae1_palette.v \
  rtl/sound/snowboar_gae1_sound.v \
  third_party/fx68k/hdl/verilator/*.sv \
  sim/snowboar/tb_snowboar.cpp
