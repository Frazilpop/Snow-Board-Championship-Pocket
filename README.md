![Snow Board Championship banner](pocket/art/snowboar-banner.png)

# Snow Board Championship for the Analogue Pocket

Get ready to speed down the mountain in this isometric snowboarding game. Now on the Analogue Pocket!

## Supported ROMs

| ROM id | game | notes |
| --- | --- | --- |
| `snowboar` | Snow Board Championship (version 2.1) | The latest version |
| `snowboara` | Snow Board Championship (version 2.0) | The earlier version |

## Installation

No game data comes with this core – you will need to supply your own MAME ROM
sets (`snowboar.zip`, plus `snowboara.zip` for version 2.0 if your sets are
split).

### Make the game files

You can't just drag and drop your MAME files. The Analogue Pocket can't read
zips, and the core needs each game as one file with every chip in its correct
place. There's a script in the repository that puts this all together for you,
or you can use a tool like Pocket Updater.

1. Download this repository (**Code → Download ZIP**, then unzip it) or clone it. You'll need Python 3 to run the build script.
2. Put your MAME zips in a folder.
3. In a terminal, from the repository's folder, run the script with the ROM ids you want from the table above, separated by commas:
   
   ```sh
   python3 tools/pocket/build_rom.py snowboar,snowboara ~/path/to/roms build/pocket
   ```
   
   So this will write `build/pocket/snowboar.rom` and `build/pocket/snowboara.rom`. The script finds the right chips in whatever zips you have, merged or split, and checks them against MAME's checksums.

[`tools/pocket/README.md`](tools/pocket/README.md) includes more info on this.

### Copy to the Pocket

1. Copy the `Cores`, `Platforms` and `Assets` folders from a release onto your Pocket's SD card.
2. Copy your `.rom` files into `Assets/snowboar/common/` – for example `Assets/snowboar/common/snowboar.rom`.
3. On the Pocket: openFPGA → Arcade → Snow Board Championship, and pick your rom (version 2.0 is in `_alternatives`).

## Controls

| Input | Action |
| --- | --- |
| D-pad | steer |
| A | run |
| B | grab 1 |
| Y | grab 2 |
| Select | insert coin |
| Start | start |

By default the d-pad matches the original arcade controls, where right turns
your rider towards the right of the screen. This can be fairly confusing if
you're used to playing other isometric games, in particular Gaelco's World
Rally, which has a similar perspective but inverse left/right controls. If
you'd rather steer from the rider's point of view, turn on **Swap Left/Right**
in the core settings.

A second controller in the Dock is player 2, and its Start is player 2's
start. On the Pocket alone it's a one-player game.

The Pocket's own menu has the usual **Display Mode** and **Controls** entries,
and opening it pauses the game. Under **Core Settings** there are four
options:

- **Test Mode** – the arcade cabinet's operator menu, where the game's settings are
- **Reset Game** – also the way to come out of the test screen
- **Swap Left/Right** – inverts the d-pad's left and right
- **Diagnostic overlay** – probably best to ignore this

## Saves

The arcade board keeps its settings in an EEPROM, which the Analogue Pocket
saves when you quit, so changes made in the operator menu will persist.

## Technical details

- The core recreates Gaelco's arcade board in hardware logic – a 68000 at 15 MHz, the CG-1V video and sound chip and the board's protection – built on [jlrh's Gaelco MiSTer cores](https://github.com/jlrh/gaelco-fpga) (World Rally 2 and Alligator Hunt), with a Pocket shell.
- It's been checked against MAME in simulation – three million moves of the game's main processor matched from power-on, and a whole race pixel for pixel and sample for sample, on both versions.
- To build it yourself: `tools/bootstrap.sh`, then `sh pocket/build.sh` (Quartus Prime Lite 21.1 in Docker, about ten minutes). The finished SD card layout can be found in `pocket/dist/`.

## Credits and licence

- **jlrh** – the Gaelco MiSTer cores this is built on.
- **Jorge Cwik (ijor)** – fx68k, the 68000 processor.
- **alphanu1** – the SDRAM controller, from the Kaneko16 MiSTer core.
- **agg23** – the Pocket utilities used for loading and audio.
- **Analogue** – the openFPGA core framework.
- **The MAME team** – whose work on the Gaelco boards was referenced.
- Pocket port by **Frazilpop**.

GPL-3.0-only. [`THIRD-PARTY.md`](THIRD-PARTY.md) lists every dependency and its
licence.

Snow Board Championship is © Gaelco / OMK. This project contains no game data.
