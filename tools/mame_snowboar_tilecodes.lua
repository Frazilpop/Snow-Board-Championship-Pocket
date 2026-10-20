-- SPDX-License-Identifier: GPL-3.0-or-later
-- Snow Board Championship (Pocket): every frame, whether a tile or sprite
-- cell code >= 0x10000 is on screen. Those codes name the upper halves of
-- the gfx planes, which hold the samples (planes 0, 1) or zeros (2-4), and
-- the Pocket's fetch lines keep only tiles 0-65535 as graphics.
--
--   tools/pocket/mame_oracle.sh tools/mame_snowboar_tilecodes.lua snowboar \
--       TILECODES_OUT=build/mame/snowboar_tilecodes.txt TO=9000 INPUTS=race
--
-- Reads what screen_update (gaelco2_v.cpp, one monitor) reads, in the frame
-- notifier, right after picture N: each layer's bank (vreg bits 11:9), its
-- y scroll (+1) and x scroll (+0x14 layer 0, +0x10 layer 1) or, with vreg
-- bit 15, the linescroll table (0x2000 / 0x2400) indexed by the tilemap row;
-- visible lines 16-255, columns 0-383. Sprites from the buffer the picture
-- was drawn from (mame_snowboar_dump.lua's FRAME ALIGNMENT), enabled entries
-- only, every cell. One line per frame where anything is found, and a
-- summary: frames with linescroll on per layer, the largest codes seen.

local OUT = os.getenv("TILECODES_OUT") or "snowboar_tilecodes.txt"
local TO  = tonumber(os.getenv("TO") or "9000")
local sb  = dofile((os.getenv("SB_TOOLS") or debug.getinfo(1, "S").source:match("^@(.*)/"))
                   .. "/mame_snowboar_inputs.lua")
local mach = manager.machine
local vram, vregs = mach.memory.shares[":spriteram"], mach.memory.shares[":vregs"]
local buf = emu.item(mach.devices[":spriteram"].items["0/m_buffered"])
local fh = assert(io.open(OUT, "w"))
local fmt = string.format
local function w(i) return vram:read_u16(i * 2) end

local n, hits, ls, maxt, maxs = 0, 0, { 0, 0 }, { 0, 0 }, 0
local XOFF = { [0] = 0x14, [1] = 0x10 }

local function visible(L, vr, col, row)
  local sy = (w(0x1400 + 2 * L) + 1) & 0x1ff
  for y = 16, 255 do
    local r = ((y + sy) & 0x1ff) >> 4
    if r == row then
      local trow = (y + sy) & 0x1ff
      local sx = ((vr & 0x8000) ~= 0) and (w(0x1000 + 0x200 * L + trow) + XOFF[L])
                 or (w(0x1401 + 2 * L) + XOFF[L])
      sx = sx & 0x3ff
      -- the tile spans tilemap x col*16 .. col*16+15; the screen shows sx .. sx+383
      local x0 = (col * 16 - sx) & 0x3ff
      if x0 < 384 or x0 > 0x3ff - 15 then return true end
    end
  end
  return false
end

_G.sb_tilecodes = emu.add_machine_frame_notifier(function()
  n = n + 1
  sb.frame(n)
  local found = {}
  for L = 0, 1 do
    local vr = vregs:read_u16(L * 2)
    if (vr & 0x8000) ~= 0 then ls[L + 1] = ls[L + 1] + 1 end
    local base = ((vr >> 9) & 7) * 0x1000
    for t = 0, 2047 do
      local hi = w(base + 2 * t) & 7
      if hi ~= 0 then
        local code = (hi << 16) | w(base + 2 * t + 1)
        if code > maxt[L + 1] then maxt[L + 1] = code end
        if visible(L, vr, t % 64, t // 64) then
          found[#found + 1] = fmt("layer %d col %d row %d code %05x", L, t % 64, t // 64, code)
        end
      elseif w(base + 2 * t + 1) > maxt[L + 1] then maxt[L + 1] = w(base + 2 * t + 1) end
    end
  end
  local start = (vregs:read_u16(2) & 0x10) * 0x80
  for j = start, start + 0x7fc, 4 do
    local d0, d2, d3, d4 = buf:read(j), buf:read(j + 1), buf:read(j + 2), buf:read(j + 3)
    if (d2 & 0x200) ~= 0 then
      local cells = (((d3 >> 12) & 15) + 1) * (((d2 >> 12) & 15) + 1)
      for k = 0, cells - 1 do
        local num = ((d0 & 0x1ff) << 10) + (buf:read(((d4 // 2) + k) & 0x7fff) & 0x0fff)
        if num > maxs then maxs = num end
        if num >= 0x10000 then found[#found + 1] = fmt("sprite %d cell %d code %05x", (j - start) // 4, k, num) end
      end
    end
  end
  if #found > 0 then
    hits = hits + 1
    fh:write(fmt("frame %d: %s\n", n, table.concat(found, "; ")))
  end
  if n % 1000 == 0 then print(n .. " of " .. TO) end
  if n >= TO then
    local s = fmt("%d frames, %d with a code >= 0x10000 on screen; linescroll on: layer 0 %d frames, "
                  .. "layer 1 %d; largest tile code layer 0 %05x, layer 1 %05x; largest sprite cell %05x",
                  n, hits, ls[1], ls[2], maxt[1], maxt[2], maxs)
    fh:write("# " .. s .. "\n"); fh:close(); print(s)
    mach:exit()
  end
end)
