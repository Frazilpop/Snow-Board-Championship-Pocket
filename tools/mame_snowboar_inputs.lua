-- SPDX-License-Identifier: GPL-3.0-or-later
-- Snow Board Championship (Pocket): the inputs every oracle script runs
-- with, loaded by tools/mame_snowboar_{bus_trace,dump,screens}.lua with
-- dofile. The board has no DIP switches: every setting is in the EEPROM,
-- which tools/pocket/mame_oracle.sh starts blank unless NVRAM_IN is given.
--
-- INPUTS (environment):
--   none     (default) nothing pressed: power-on, then the attract
--   race     a coin at frame 600, start at 700, button 1 at 900 (Select
--            Mode: Speed, Beginner) and 1300 (Choose Surfer: the first),
--            the race from ~2100 (GO at ~1700): button 1 (Run) tapped 8 on
--            8 off from 2000, the stick right then left 40 frames each in
--            every 120 from 2100, button 2 tapped every 300 frames from 2100
--            and button 3 from 2250 (the grabs in the air), all to 9000. The
--            rider is disqualified at 1:15 (~6400), then Continue, Game Over
--            and the attract again (~7400)
--   explore  EXPLORE's list, below (for finding out what the game does)
--
-- What the inputs do (seen 20 Oct 2026, snowboar): button 1 is Run (the
-- game prompts "RUN" with a red button when the rider stops; it also picks
-- in the menus and the test menu), buttons 2 and 3 change the rider's grab
-- in the air; the stick steers. A press of the service bit ("NOW") for 6
-- frames opens TEST OPTIONS. Select Mode and Choose Surfer time out by
-- themselves if nothing is pressed.
--
-- Frame n is the nth machine frame notification from power-on (frame 1 is
-- the first picture MAME renders); an input set in notifier n is seen by the
-- program from frame n's vblank on. The Verilator harness applies the same
-- schedule at the same vblanks (tools/snowboar_inputs_plan.py).
--
-- Returns a table: sb.frame(n) applies frame n's inputs (call it first in
-- the script's own frame notifier), sb.mode is the INPUTS value.

local mach  = manager.machine
local ports = mach.ioport.ports
local function field(port, name)
  local f = ports[port] and ports[port].fields[name]
  assert(f, "mame_snowboar_inputs.lua: no field " .. port .. " " .. name)
  return f
end

local mode = os.getenv("INPUTS") or "none"

local P = {
  coin  = field(":COIN", "Coin 1"),
  start = field(":COIN", "1 Player Start"),
  test  = field(":COIN", "Service Mode"),
  up    = field(":P1", "P1 Up"),
  down  = field(":P1", "P1 Down"),
  left  = field(":P1", "P1 Left"),
  right = field(":P1", "P1 Right"),
  b1    = field(":P1", "P1 Button 1"),
  b2    = field(":P1", "P1 Button 2"),
  b3    = field(":P1", "P1 Button 3"),
}

-- SCHEDULE: mode -> function(n) returning the pressed set for frame n.
local function every(n, from, to, per, on)
  return n >= from and n <= to and (n - from) % per < on
end
local SCHEDULE = {
  none = function(n) return {} end,
  race = function(n)
    return {
      coin  = every(n, 600, 609, 1, 1),
      start = every(n, 700, 709, 1, 1),
      b1    = every(n, 900, 905, 1, 1) or every(n, 1300, 1305, 1, 1)
              or every(n, 2000, 9000, 16, 8),
      right = every(n, 2100, 9000, 120, 40),
      left  = every(n, 2160, 9000, 120, 40),
      b2    = every(n, 2100, 9000, 300, 6),
      b3    = every(n, 2250, 9000, 300, 6),
    }
  end,
}
-- EXPLORE: a comma list of name@from-to[/period:on] (frames, inclusive),
-- e.g. coin@600-609,start@700-709,b1@3300-4500/20:10 (b1 pressed for the
-- first 10 of every 20 frames from 3300 to 4500).
local EXPLORE = os.getenv("EXPLORE")
if mode == "explore" then
  local list = {}
  for item in (EXPLORE or ""):gmatch("[^,]+") do
    local name, a, b, per, on = item:match("^(%w+)@(%d+)%-(%d+)/(%d+):(%d+)$")
    if not name then name, a, b = item:match("^(%w+)@(%d+)%-(%d+)$") end
    assert(name and P[name], "EXPLORE: bad item " .. item)
    list[#list + 1] = { name, tonumber(a), tonumber(b), tonumber(per), tonumber(on) }
  end
  SCHEDULE.explore = function(n)
    local s = {}
    for _, e in ipairs(list) do
      if n >= e[2] and n <= e[3] and (not e[4] or (n - e[2]) % e[4] < e[5]) then s[e[1]] = true end
    end
    return s
  end
end
assert(SCHEDULE[mode], "INPUTS must be one of none, race, explore, not " .. mode)

local sb = { mode = mode }

function sb.frame(n)
  local s = SCHEDULE[mode](n)
  for name, f in pairs(P) do f:set_value(s[name] and 1 or 0) end
end

print(string.format("snowboar inputs: INPUTS=%s", mode))
return sb
