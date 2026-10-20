#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Run one of the tools/mame_snowboar_*.lua oracle scripts on a Snow Board
# Championship set, reproducibly.
#
#   tools/pocket/mame_oracle.sh <script.lua> <set> [VAR=value ...] [-- mame args]
#
#   tools/pocket/mame_oracle.sh tools/mame_snowboar_bus_trace.lua snowboar \
#       BUS_TRACE_OUT=build/mame/snowboar_bus.txt BUS_TRACE_COUNT=3000000
#   tools/pocket/mame_oracle.sh tools/mame_snowboar_dump.lua snowboar \
#       DUMP_DIR=build/mame/dump/snowboar DUMP_FRAME=600,1800 INPUTS=race
#
# What it fixes, every run:
#   * the nvram directory — MAME keeps the 93C66 EEPROM (every setting the
#     game has; the board has no DIPs) as nvram/<set>/eeprom: it saves it at
#     exit and loads it at start. By default each run starts from a FRESH,
#     EMPTY directory, so the EEPROM is blank (all 0xFF, as MAME makes it)
#     and no run inherits the last one's settings or high scores.
#     NVRAM_IN=<file> seeds nvram/<set>/eeprom from a saved file instead;
#     NVRAM_OUT=<file> keeps the EEPROM MAME writes at exit;
#   * a fresh cfg directory, so no saved input setting leaks in;
#   * -skip_gameinfo -autoboot_delay 0: without them the script either never
#     loads (warning screen) or installs late;
#   * -snapview native, so screen:snapshot() writes the screen at 384 x 240;
#   * ROMS (default ~/Downloads) as -rompath; MAME (default mame);
#   * SB_TOOLS, where the scripts find mame_snowboar_inputs.lua.
# Relative paths in VAR=value are made absolute (the scripts run with MAME's
# own working directory).

set -eu
[ $# -ge 2 ] || { sed -n '3,11p' "$0"; exit 2; }
script=$1; set_name=$2; shift 2

repo=$(cd "$(dirname "$0")/../.." && pwd)
case $script in /*) ;; *) script=$PWD/$script ;; esac
export SB_TOOLS="$repo/tools"

nv_in=; nv_out=
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  case $1 in
    NVRAM_IN=*|NVRAM_OUT=*)
      k=${1%%=*}; v=${1#*=}
      case $v in /*) ;; *) v=$PWD/$v ;; esac
      [ "$k" = NVRAM_IN ] && nv_in=$v || nv_out=$v ;;
    *=/*|*=) export "$1" ;;
    *_DIR=*|*_OUT=*) k=${1%%=*}; v=${1#*=}; export "$k=$PWD/$v" ;;
    *=*) export "$1" ;;
    *) echo "mame_oracle.sh: expected VAR=value, got '$1'" >&2; exit 2 ;;
  esac
  shift
done
[ "${1:-}" = "--" ] && shift

mkdir -p "$repo/build/mame/run"
run=$(mktemp -d "$repo/build/mame/run/$set_name.XXXXXX")
trap 'rm -r "$run"' EXIT
mkdir -p "$run/cfg" "$run/nvram/$set_name" "$run/snap"
[ -z "$nv_in" ] || cp "$nv_in" "$run/nvram/$set_name/eeprom"

start=$(date +%s)
"${MAME:-mame}" -rompath "${ROMS:-$HOME/Downloads}" "$set_name" \
  -autoboot_script "$script" -skip_gameinfo -autoboot_delay 0 \
  -video none -sound none -nothrottle -seconds_to_run 3600 -snapview native \
  -cfg_directory "$run/cfg" -nvram_directory "$run/nvram" \
  -snapshot_directory "$run/snap" "$@"
if [ -n "$nv_out" ]; then
  if [ -f "$run/nvram/$set_name/eeprom" ]; then
    mkdir -p "$(dirname "$nv_out")"; cp "$run/nvram/$set_name/eeprom" "$nv_out"
    echo "mame_oracle.sh: EEPROM -> $nv_out"
  else
    echo "mame_oracle.sh: MAME wrote no nvram/$set_name/eeprom" >&2
  fi
fi
echo "mame_oracle.sh: $set_name finished in $(( $(date +%s) - start )) s"
