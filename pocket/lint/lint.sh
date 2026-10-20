#!/bin/sh
# Verilator lint of the Pocket shell around the real board, controller and
# agg23 IP, with Intel primitives stubbed (altera_stubs.v). Run from anywhere.
# The board's own files are linted for errors only (lint.vlt); its behaviour
# is checked by its harness, sim/snowboar. fx68k is its hdl/verilator/
# variant, as the harness has it (Verilator cannot take the synthesis one).
set -e
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
fpga=$repo/pocket/src/fpga
tp=$repo/third_party/pocket-utils/ip
r=$repo/rtl
verilator --lint-only -Wall --top-module core_top \
  -Wno-DECLFILENAME -Wno-MULTITOP -Wno-TIMESCALEMOD -Wno-EOFNEWLINE \
  "$here/lint.vlt" \
  "$here/altera_stubs.v" \
  "$fpga/apf/common.v" \
  "$fpga/core/mf_pllbase.v" "$fpga/core/mf_pllbase/mf_pllbase_0002.v" \
  "$fpga/core/pin_ddio_clk.v" \
  "$fpga/core/core_bridge_cmd.v" \
  "$tp/data_loader.sv" "$tp/sync_fifo.sv" "$tp/sound_i2s.sv" \
  "$r/mem/kaneko_sdram.sv" "$r/mem/kaneko_sdram_x2.sv" \
  "$r/top/snowboar_board.sv" "$r/mem/snowboar_romport.sv" "$r/mem/snowboar_vmem.v" \
  "$r/cpu/snowboar_main.v" "$r/cpu/snowboar_addr_decode.v" "$r/cpu/snowboar_cpu_clk.sv" \
  "$r/cpu/snowboar_prot.v" "$r/io/snowboar_inputs.v" "$r/io/snowboar_eeprom.sv" \
  "$r/video/snowboar_video_top.v" "$r/video/snowboar_video_timing.v" "$r/video/snowboar_gae1_video.v" \
  "$r/video/snowboar_gae1_tilemap.v" "$r/video/snowboar_gae1_sprite.v" "$r/video/snowboar_gae1_palette.v" \
  "$r/sound/snowboar_gae1_sound.v" \
  "$repo"/third_party/fx68k/hdl/verilator/*.sv \
  "$fpga/core/pocket_sync.sv" "$fpga/core/pocket_rom_loader.sv" \
  "$fpga/core/pocket_sram.sv" "$fpga/core/pocket_video.sv" "$fpga/core/pocket_diag.sv" \
  "$fpga/core/pocket_audio.sv" "$fpga/core/pocket_nvram.sv" \
  "$fpga/core/core_top.v" "$@"
