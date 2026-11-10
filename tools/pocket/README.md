# Pocket tools

These are the scripts that make the game files for the Analogue Pocket, and
the ones that check the core against MAME. The ROMs you supply are written
into `build/`. Run anything that opens the zips with `python3 -I` so Python
can't pick up stray files from the folder you're in.

## Making the `.rom` files

```sh
python3 -I tools/pocket/build_rom.py snowboar ~/Downloads build/pocket   # one version
python3 -I tools/pocket/build_rom.py all      ~/Downloads build/pocket   # both
python3 -I tools/pocket/verify_rom.py all --zipdir ~/Downloads           # verify against MAME
```

You can also give a list of ROM ids separated by commas, e.g.
`snowboar,snowboara`. The core supports two: `snowboar` (version 2.1) and
`snowboara` (version 2.0).

Each image is exactly 0x1200000 bytes (18 MB), laid out the way the core reads
it from SDRAM: the 68000's program (MAME's `maincpu` region, 1 MB) at 0, then
1 MB of zeros, then the 20 MB `gfx` region – graphics and samples – rewritten
as 16 MB of 64-bit lines from 0x200000. One line holds the five bit planes of
an eight-pixel run, so the board gets a whole row of a tile in one read, and
two spare bytes of each line hold the samples. The top of `build_rom.py` gives
the layout byte for byte.

The script finds each chip by its CRC32 and size, and will look through every
zip in the folder (the version's own zip and its parent's first), so merged,
split and non-merged sets all work. A `<rom id>/` folder of loose files works
too. Every chip's SHA1 is checked against MAME's before anything is written.
The list of chips is copied from `ROM_START` in MAME's `gaelco2.cpp`, in the
same order. Version 2.0's graphics come on four mask ROMs instead of version
2.1's 24 EPROMs; the script splits them as MAME's driver does, so the image
holds the same region MAME ends up with.

`verify_rom.py` runs MAME with `tools/mame_snowboar_regions.lua`, which saves
MAME's own copy of each region to `build/mame/regions/<rom id>/`, then compares
them with the image byte for byte (`--no-mame` reuses the copies already
there). With both versions in one run it also says which parts of the
graphics and samples the two share.

For the simulation, `--regions` writes MAME's two regions as they are instead:

```sh
python3 -I tools/pocket/build_rom.py snowboar ~/Downloads build/roms --regions
# build/roms/snowboar_maincpu.bin, build/roms/snowboar_gfx.bin
```

## On the Analogue Pocket

Copy the image onto the SD card as

```
Assets/snowboar/common/<rom id>.rom        e.g. Assets/snowboar/common/snowboar.rom
```

Each version's instance JSON points at that file. The Pocket loads it at bridge
address 0, and byte *n* of the file ends up at SDRAM byte *n*.

The game's EEPROM is saved as `Saves/snowboar/frazilpop.Snow Board
Championship/<rom id>.sav`: 512 bytes, in the same order as MAME's
`nvram/<rom id>/eeprom`, so the two files can be swapped. A set with no save
starts from a blank EEPROM and the game writes its defaults, as it does in
MAME.

## Checking against MAME

Everything from here on is for working on the core itself.

Run MAME through `mame_oracle.sh`. It gives each run a fresh, empty nvram and
cfg folder: the board keeps every setting in its 93C66 EEPROM (it has no DIP
switches), which MAME saves when it quits and loads again when it starts, so
otherwise every run would start from wherever the last one left off.
`NVRAM_IN=<file>` starts from a saved EEPROM instead and `NVRAM_OUT=<file>`
keeps the one MAME writes. It also adds the flags autoboot needs
(`-skip_gameinfo -autoboot_delay 0`). `ROMS=` changes where it looks for ROMs
(`~/Downloads` by default) and `MAME=` changes which MAME it runs.

Every script takes `INPUTS=`: `none` (the default – power-on, then the
attract), `race` (a coin, start, Speed mode on Beginner, the first rider and a
race with the stick and all three buttons in use, to frame 9000) or `explore`
(a schedule of your own, in `EXPLORE`). `tools/mame_snowboar_inputs.lua` has
the details. `tools/snowboar_inputs_plan.py race <frames>` writes the same ride
as a plan for the harness, timed so the two runs see each input on the same
frame.

### The bus from power-on

```sh
tools/pocket/mame_oracle.sh tools/mame_snowboar_bus_trace.lua snowboar \
    BUS_TRACE_OUT=build/mame/snowboar_bus.txt BUS_TRACE_COUNT=3000000
python3 -I tools/diff_bus_trace.py core.txt build/mame/snowboar_bus.txt snowboar
python3 -I tools/snowboar_prot.py build/mame/snowboar_bus.txt
```

One line for each access of the 68000 (`addr R|W data mask`), plus
`# frame N` lines that the readers skip. The trace starts at machine time 0,
before the 68000's first cycle. `diff_bus_trace.py` compares the core's trace
with MAME's access for access, strictly and then allowing for where an
interrupt lands, and counts each region's accesses. `snowboar_prot.py` checks
every read of the protection in a trace against a model of it.

### What's on screen

```sh
tools/pocket/mame_oracle.sh tools/mame_snowboar_dump.lua snowboar \
    DUMP_DIR=build/mame/dump/snowboar DUMP_FRAME=600,1800 INPUTS=race
python3 -I tools/pocket/render_dump.py build/mame/dump/snowboar/f01800 build/pocket/snowboar.rom out.ppm
tools/pocket/mame_oracle.sh tools/mame_snowboar_screens.lua snowboar \
    SCREENS_DIR=build/mame/screens/snowboar FROM=200 TO=700 INPUTS=race
```

`mame_snowboar_dump.lua` saves the video memories, the palette and the video
registers at each frame asked for, with MAME's own picture as `screen.png`.
Frame *N* is the *N*th frame notification from power-on, and the picture is
`screen:snapshot()`, not `screen:pixels()`, which lags a frame inside the
notification. `render_dump.py` draws the screen from a dump the way MAME's
`gaelco2_v.cpp` does, so a picture that differs from the core's but not from
MAME's points at the core. `mame_snowboar_screens.lua` writes MAME's picture
for every frame in a range, and `mame_snowboar_tilecodes.lua` checks no frame
shows a tile from the part of the graphics region that holds samples.

## The simulation

```sh
sim/snowboar/build.sh
build/obj_snowboar/tb_snowboar build/pocket/snowboar.rom 700 build/sim/boot 300,500,700
python3 -I tools/pocket/match_frames.py build/sim/boot build/mame/screens/snowboar --same
tools/pocket/match_scenes.sh build/pocket/snowboar.rom build/mame/dump/snowboar/f*
```

`build.sh` builds the whole board in Verilator. By default its frame and
interrupts run at MAME's 59.1 Hz and its sound at MAME's 7,812 Hz, so traces,
frames and samples line up with MAME's; `PIX=pocket` builds the Pocket's
timing instead, and `SDR=real` times the ROM's lines with the core's own SDRAM
controller rather than a fixed latency.

`tb_snowboar <rom> <frames> <outdir> [frame list]` runs the board from
power-on for that many frames, writes the frames in the list as PPMs and a
line a frame to `stats.csv` (the sprite engine's busiest line, any line it
cut short, how much board time the SDRAM held up). `--trace` writes a bus trace in MAME's format, `--inputs`
plays a plan, `--audio` saves the sound, `--eeprom` and `--eeprom-out` load
and keep the EEPROM, and `--scene <dump>` draws a MAME dump with the board's
time stopped. `match_frames.py` compares the frames with MAME's, and
`match_scenes.sh` draws each MAME dump on the board and compares it with
MAME's picture, so the video is checked on any state MAME reaches.
`match_audio.py` compares the sound with MAME's `-wavwrite`, sample for
sample when MAME runs at `-samplerate 7812`. `ppm2png.py` turns the frames
into PNGs.

`sim/shell/run_nvram.sh` checks the Pocket's save slot: an EEPROM loaded in,
read back out the way the Pocket reads a save at shutdown, and both
directions checked byte for byte against the file.
