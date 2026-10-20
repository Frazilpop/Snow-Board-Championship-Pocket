-- SPDX-License-Identifier: GPL-3.0-or-later
-- Snow Board Championship (Pocket): trace the 68000's first N bus accesses
-- from power-on, as the oracle for the core's own trace.
--
--   tools/pocket/mame_oracle.sh tools/mame_snowboar_bus_trace.lua snowboar \
--       BUS_TRACE_OUT=build/mame/snowboar_bus.txt BUS_TRACE_COUNT=3000000
--
-- One access per line, the format of Mille Miglia's trace
-- (tools/diff_bus_trace.py reads it):
--     <addr:06x> <R|W> <data:04x> <mask:04x>
-- addr is the byte address of the 16-bit word (even), mask the lanes the
-- 68000 drove (ffff word, ff00 even byte, 00ff odd byte). Lines starting '#'
-- mark frame boundaries ("# frame N" = MAME's frame notification N, at the
-- screen's vblank; 3 fields, so a 4-field reader skips them).
--
-- Environment:
--   BUS_TRACE_OUT        output file (default snowboar_bus_trace.txt)
--   BUS_TRACE_COUNT      accesses to record (default 3000000)
--   BUS_TRACE_FROM       start at this frame's notification ("# frame N"
--                        first; default: power-on). The taps go in only
--                        then, so the frames before run at MAME's own speed.
--   BUS_TRACE_DATA_ONLY  1 = skip instruction fetches: tap only 100000-ffffff
--                        (everything but the program ROM). ~5x fewer Lua calls.
--   BUS_TRACE_TICKS      a file: the machine time of each access, in 15 MHz
--                        clocks from power-on, one line each (the harness's
--                        --ticks)
--   INPUTS               none (default) | race | explore,
--                        mame_snowboar_inputs.lua
-- The EEPROM is whatever tools/pocket/mame_oracle.sh gives MAME: blank (all
-- 0xFF) by default, or NVRAM_IN's file.
--
-- FROM POWER-ON, NO SYNTHETIC RESET. With -autoboot_delay 0 the script runs at
-- machine time 0, before the CPU has executed a cycle, so the first two
-- accesses are the reset vector reads at 000000/000002 and every RAM holds
-- its power-on content (MAME zero-fills).
--
-- WHAT THIS BOARD RETURNS THAT A CORE MUST MATCH
--   300000  P1, 300010 P2 (active low, bits 0-6), 300020 COIN: bit 6 is the
--           93C66's DOUT (active high), bit 2 the service "NOW" bit.
--   300000-30000f writes: the LS259, D0 of the low byte (mask 00ff), Q = A3..A1:
--           Q0/Q1 coin counters, Q4 EEPROM DI, Q5 CLK, Q6 CS.
--   310000-31ffff  the protection: a write shifts the word into a 32-bit
--           latch, a read returns mangle(latch) byte-swapped.
--   202890-2028ff  CG-1V sound registers, inside the VRAM window: reads return
--           the registers, which the chip itself rewrites as a channel plays.
--   IRQ 6 at vblank, autovectored: the vector read at 000078. There is no
--   IACK cycle on the program bus.
--
-- Taps and notifiers are GLOBALS: a local is collected and the callback stops
-- with no error. The file is streamed, so a crashed run keeps what it had.

local MAX  = tonumber(os.getenv("BUS_TRACE_COUNT") or "3000000")
local FROM = tonumber(os.getenv("BUS_TRACE_FROM") or "0")
local OUT  = os.getenv("BUS_TRACE_OUT") or "snowboar_bus_trace.txt"
local DATA_ONLY = (os.getenv("BUS_TRACE_DATA_ONLY") or "0") ~= "0"
local TICKS     = os.getenv("BUS_TRACE_TICKS")

local sb = dofile((os.getenv("SB_TOOLS") or debug.getinfo(1, "S").source:match("^@(.*)/"))
                  .. "/mame_snowboar_inputs.lua")

local mach  = manager.machine
local cpu   = mach.devices[":maincpu"]
local space = cpu.spaces["program"]
local romname = emu.romname()
local fmt = string.format

local fh = assert(io.open(OUT, "w"))
local th = TICKS and assert(io.open(TICKS, "w")) or nil
local n, done, frames = 0, false, 0
local t0 = os.clock()

local function record(rw, offset, data, mask)
  if done then return end
  n = n + 1
  fh:write(fmt("%06x %s %04x %04x\n", offset & 0xffffff, rw, data & 0xffff, mask & 0xffff))
  if th then th:write(fmt("%d\n", math.floor(mach.time:as_double() * 15e6 + 0.5))) end
  if (n & 0x3fff) == 0 then fh:flush() end
  if n >= MAX then done = true end
end

print(fmt("bus trace: %s, script at machine time %.6f, PC %06x, %s",
          romname, mach.time:as_double(), cpu.state["PC"].value,
          DATA_ONLY and "data only" or "all accesses"))

local ranges = DATA_ONLY and { { 0x100000, 0xffffff } } or { { 0x000000, 0xffffff } }
_G.sb_taps = {}
local function keep(t) _G.sb_taps[#_G.sb_taps + 1] = t end
local function install()
  for i, r in ipairs(ranges) do
    keep(space:install_read_tap(r[1], r[2], "sb_bt_r" .. i,
      function(offset, data, mask) record("R", offset, data, mask) end))
    keep(space:install_write_tap(r[1], r[2], "sb_bt_w" .. i,
      function(offset, data, mask) record("W", offset, data, mask) end))
  end
end
local started = FROM <= 0
if started then install() end

-- Finishing happens here, never inside a tap: exiting from a tap tears the
-- machine down under the access in flight, and taps left installed keep
-- costing a Lua call per access after the limit.
_G.sb_bt_frame = emu.add_machine_frame_notifier(function()
  frames = frames + 1
  sb.frame(frames)
  if not started and frames >= FROM then started = true; install() end
  if started and not done then fh:write(fmt("# frame %d\n", frames)) end
  if done or frames > 20000 then
    for _, t in ipairs(_G.sb_taps) do t:remove() end
    fh:flush(); fh:close()
    if th then th:flush(); th:close() end
    print(fmt("bus trace: %d accesses in %d frames (%.3f s emulated), %.1f s CPU -> %s",
              n, frames, mach.time:as_double(), os.clock() - t0, OUT))
    mach:exit()
  end
end)
