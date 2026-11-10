# Third-party code and licences

This core is **GPL-3.0-only** as a whole: alphanu1's SDRAM port adapter
(`rtl/mem/kaneko_sdram_x2.sv`) is GPL-3.0-only, and jlrh's Gaelco cores carry
their repository's GPL-3.0 with no "or later". Everything else is
GPL-3.0-or-later or compatible with it. This file lists each dependency and
what its licence asks for.

## Fetched by `tools/bootstrap.sh`

These land in `third_party/`, pinned in `deps.lock`, and are never committed.

| Component | Licence | Used for |
|---|---|---|
| [jlrh/gaelco-fpga](https://github.com/jlrh/gaelco-fpga) | GPL-3.0 | The reference for the board: World Rally 2 (`cores/wrally2`) and Alligator Hunt (`cores/aligator`) |
| [jtfpga/fx68k](https://github.com/jtfpga/fx68k) | GPL-3.0-or-later | The 68000 main CPU |
| [agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils) | MIT | Pocket shell IP: data loader, I2S audio, sync FIFO |
| [mamedev/mame](https://github.com/mamedev/mame) (`src/mame/gaelco/gaelco2*` and a few devices only) | BSD-3-Clause (those files) | The reference |

### fx68k – GPL-3.0-or-later
`deps.lock` pins `jtfpga/fx68k`, which is ijor's code (© Jorge Cwik)
repackaged for jtframe. The licence is in `fx68k.txt`: version 3 "or (at
your option) any later version". Synthesis takes `hdl/` unchanged; the
simulation takes `hdl/verilator/`, the same CPU with the nanocode struct
flattened for Verilator. The bootstrap symlinks `microrom.mem` and
`nanorom.mem` into the repo root, where fx68k loads them from.

### analogue-pocket-utils – MIT
© 2022 Adam Gastineau. `data_loader.sv`, `sound_i2s.sv` and `sync_fifo.sv`
are built into the bitstream from `third_party/`. Keep the notice: the core's
folder on the card carries it in `licences.txt`.

### MAME – BSD-3-Clause (these files only)
The only public documentation of this board. Each file used is BSD-3-Clause:

- `src/mame/gaelco/gaelco2.cpp` and `gaelco2_v.cpp` (© Manuel Abadia, David
  Haywood) – the board, its clocks and memory map, and the CG-1V's video;
- `src/mame/gaelco/gaelco2_m.cpp` (© Manuel Abadia) – the protection and
  snowboara's ROM loading. The protection's three bit shuffles are
  transcribed from it, in `tools/snowboar_prot.py` and
  `rtl/cpu/snowboar_prot.v`, which say so in their headers;
- `src/devices/sound/gaelco.cpp` (© Manuel Abadia, David Haywood) – the
  CG-1V's sound. `tools/gen_volume_table.py` computes its volume table from
  the same formula;
- `src/devices/machine/eepromser.cpp` and `eeprom.cpp` (© Aaron Giles) – the
  93C66 EEPROM. `rtl/io/snowboar_eeprom.sv` is written to behave as they do,
  not copied from them.

MAME as a whole is GPL-2.0, and `src/devices/` and `src/emu/` are a mix, so
check each file's header before transcribing anything else. The bitstream
carries the transcribed parts, so the core's folder on the card carries
MAME's notice for them in `licences.txt`.

## In the tree

### jlrh/gaelco-fpga – GPL-3.0
The board is built from jlrh's World Rally 2 core (by way of the World Rally 2
Pocket core) and jlrh's Alligator Hunt core: the CG-1V's tilemaps, sprites,
palette, video timing and sound in `rtl/video/` and `rtl/sound/`, the video
memories, and the 68000's bus, all reworked for this board. Most of these
files say in their headers which of jlrh's they follow.
`rtl/video/snowboar_video_timing.v` is World Rally 2's `wrally2_video_timing.v`
renamed, and `snowboar_gae1_palette.v` its palette with eight bits a colour;
like upstream's files, they carry no header of their own. Upstream's
`LICENSE` is the GPL, version 3.

### alphanu1's SDRAM controller – GPL-3.0-only and GPL-3.0-or-later
`rtl/mem/kaneko_sdram.sv` (GPL-3.0-or-later), `rtl/mem/kaneko_sdram_x2.sv`
(GPL-3.0-only) and the simulation's `sim/mem/sdram_model.sv`
(GPL-3.0-or-later) are alphanu1's, © 2026, from the
[Kaneko16 MiSTer core](https://github.com/alphanu1/kaneko16-mister) by way of
the Great 1000 Miles Rally Pocket core. Each keeps its header.

### Analogue openFPGA core template – Analogue's APF Software License Agreement
`pocket/src/fpga/apf/`, `core_bridge_cmd.v` and the Quartus project files are
Analogue's, under the licence in their headers (with Analogue's Pocket EULA),
which yields to the MIT or GNU licence wherever the two disagree. The
Quartus megafunction output beside them (`mf_pllbase`, `pin_ddio_clk`,
`mf_datatable`, `mf_ddio_bidir_12`) is Intel's generated code, and
`build_id_gen.tcl` is Altera's reference design (Altera Reference Design
License), trimmed by Analogue.

## Written for this core

Everything else under `rtl/`, `sim/`, `tools/` and `pocket/`, under the
licence in each file's header (GPL-3.0-or-later; the combination is
GPL-3.0-only).

`pocket/art/snowboar-banner.png`, the platform image, is made from the game's
logo, © Gaelco / OMK.

## ROMs

No ROM images, or anything taken from them, are ever committed or distributed.
They're loaded at runtime, and tools that read them write only to `build/`.
