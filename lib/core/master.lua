-- master.lua -- the things that are not per track
--
-- The three sends and the clock. They are norns params, so they save with
-- the PSET and show up in the params menu, but they are also editable from
-- the track select screen (K2+K3) where E2 walks them and E3 turns them.
-- Reaching for the params menu to set a delay time in the middle of a take
-- is not a thing anybody wants to do.

local M = {}

M.fx = {
  cho = { name = "CHORUS", p = {
    { "rate",   "RATE",     controlspec.new(0.02, 8, "exp", 0, 0.4, "hz") },
    { "depth",  "DEPTH",    controlspec.new(0, 1, "lin", 0, 0.5, "") },
    { "spread", "SPREAD",   controlspec.new(0, 1, "lin", 0, 0.7, "") },
    { "fbk",    "FEEDBACK", controlspec.new(0, 0.85, "lin", 0, 0.2, "") },
    { "tone",   "TONE",     controlspec.new(0, 1, "lin", 0, 0.6, "") },
    { "level",  "LEVEL",    controlspec.new(0, 1, "lin", 0, 1, "") },
  }},
  dly = { name = "DELAY", p = {
    { "time",  "TIME",      controlspec.new(0.01, 4, "exp", 0, 0.375, "s") },
    { "fbk",   "FEEDBACK",  controlspec.new(0, 0.98, "lin", 0, 0.45, "") },
    { "hp",    "HIGHPASS",  controlspec.new(0, 1, "lin", 0, 0.15, "") },
    { "lp",    "LOWPASS",   controlspec.new(0, 1, "lin", 0, 0.75, "") },
    { "ping",  "PING PONG", controlspec.new(0, 1, "lin", 0, 0, "") },
    { "mod",   "MOD",       controlspec.new(0, 1, "lin", 0, 0.1, "") },
    { "level", "LEVEL",     controlspec.new(0, 1, "lin", 0, 1, "") },
  }},
  rev = { name = "REVERB", p = {
    { "size",     "SIZE",     controlspec.new(0, 0.97, "lin", 0, 0.7, "") },
    { "damp",     "DAMP",     controlspec.new(0, 1, "lin", 0, 0.4, "") },
    { "shim",     "SHIMMER",  controlspec.new(0, 1, "lin", 0, 0.3, "") },
    { "interval", "SHIM INT", controlspec.new(-12, 24, "lin", 1, 12, "st") },
    { "shimfb",   "SHIM FBK", controlspec.new(0, 1, "lin", 0, 0.5, "") },
    { "pre",      "PREDELAY", controlspec.new(0, 0.45, "lin", 0, 0.02, "s") },
    { "lowcut",   "LOW CUT",  controlspec.new(0, 1, "lin", 0, 0.1, "") },
    { "level",    "LEVEL",    controlspec.new(0, 1, "lin", 0, 1, "") },
  }},
}

M.order = { "cho", "dly", "rev" }

-- What E2 walks in select mode. The clock comes first so E3 still lands on
-- the tempo the moment you get there, the way it always did.
M.groups = { { name = "CLOCK", p = { { id = "clock_tempo", name = "BPM" } } } }

for _, key in ipairs(M.order) do
  local fx = M.fx[key]
  local g = { name = fx.name, p = {} }
  for _, e in ipairs(fx.p) do
    table.insert(g.p, { id = key .. "_" .. e[1], name = e[2] })
  end
  table.insert(M.groups, g)
end

function M.group(i) return M.groups[util.clamp(i, 1, #M.groups)] end

function M.param(gi, pi)
  local g = M.group(gi)
  return g.p[util.clamp(pi, 1, #g.p)]
end

-- params:string is the formatted, unit-carrying readout norns already keeps
function M.text(id)
  local ok, s = pcall(function() return params:string(id) end)
  if ok and type(s) == "string" and #s > 0 then return s end
  local v = params:get(id)
  if type(v) == "number" then
    return (v == math.floor(v)) and string.format("%d", v) or string.format("%.2f", v)
  end
  return "-"
end

return M
