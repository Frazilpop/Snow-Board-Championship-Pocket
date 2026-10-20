#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# The save slot's round trip (tb_nvram.sv). Run from the repository root.
set -eu
mkdir -p build/obj_nvram
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
  --top-module tb_nvram --Mdir build/obj_nvram -o tb_nvram \
  sim/shell/tb_nvram.sv pocket/src/fpga/core/pocket_nvram.sv rtl/io/snowboar_eeprom.sv \
  pocket/src/fpga/apf/common.v third_party/pocket-utils/ip/data_loader.sv > build/obj_nvram/build.log 2>&1 \
  || { tail -30 build/obj_nvram/build.log; exit 1; }
build/obj_nvram/tb_nvram
