-- master.lua -- the things that are not per track
--
-- K2+K3 opens a page set of its own, and K2/K3 walk it the same way they walk
-- a track's pages:
--
--   1 OVER     the eight tracks, their machines and their patterns
--   2 PERFORM  eight offsets applied to every instrument at once
--   3 MIX      the eight track levels as faders
--   4 COLOUR   one colour chain across the whole mix
--   5 SEND FX  two controls each for the three sends and the master drive
--   6 CLOCK    tempo
--   7..9       the three sends in full
--
-- Everything from PERFORM on is a norns param, so it saves with the PSET and
-- sits in the menu too -- but reaching for the menu to set a delay time in
-- the middle of a take is not a thing anybody wants to do.

local M = {}

local function cs(lo, hi, warp, step, def, unit)
  return controlspec.new(lo, hi, warp or "lin", step or 0, def, unit or "")
end

-- a bipolar performance offset: centred, and doing nothing at the centre
local function off(def) return cs(-1, 1, "lin", 0, def or 0) end

-- ------------------------------------------------------------------ groups
--
-- Each entry is { id, name, spec, glyph }. `id` is what the engine is told
-- and, prefixed with the group key, what the norns param is called.

M.groups = {}
M.order  = {}

local function group(key, name, send, p)
  M.groups[key] = { key = key, name = name, send = send, p = p }
  table.insert(M.order, key)
  return M.groups[key]
end

-- PERFORM. Eight offsets that land on every voice on every track at once,
-- through one global control bus the synthdefs read alongside their own.
-- Centre is no change, so the page is safe to leave where it is.
group("perf", "PERFORM", function(e, v) engine.perf(e.ch, v) end, {
  { "pitch",  "PITCH",  off(), "bi" },
  { "attack", "ATTACK", off(), "bi" },
  { "decay",  "DECAY",  off(), "bi" },
  { "timbre", "TIMBRE", off(), "bi" },
  { "cutoff", "CUTOFF", off(), "bi" },
  { "res",    "RES",    off(), "bi" },
  { "fold",   "FOLD",   off(), "bi" },
  { "drive",  "DRIVE",  off(), "bi" },
})
for i, e in ipairs(M.groups.perf.p) do e.ch = i - 1 end

-- COLOUR. One chain over the summed mix, sends included, rather than eight
-- of them a track deep. CRUSH still walks bit depth and sample rate down
-- together and COMP still carries ratio, attack and wet mix, because nothing
-- was ever gained from setting either pair apart.
group("col", "COLOUR", function(e, v) engine.colSet(e.id, v) end, {
  { "crush",  "CRUSH",  cs(0, 1, "lin", 0, 0),    "bits" },
  { "wow",    "WOW",    cs(0, 1, "lin", 0, 0),    "wow" },
  { "wrate",  "W.RATE", cs(0, 1, "lin", 0, 0.3),  "rate" },
  { "saturn", "SATURN", cs(0, 1, "lin", 0, 0),    "sat" },
  { "tilt",   "TILT",   cs(-1, 1, "lin", 0, 0),   "tilt" },
  { "loss",   "LOSS",   cs(0, 1, "lin", 0, 0),    "loss" },
  { "glitch", "GLITCH", cs(0, 1, "lin", 0, 0),    "glitch" },
  { "comp",   "COMP",   cs(0, 1, "lin", 0, 0),    "comp" },
})

-- DRIVE. Two more controls on the colour chain, at the head of it, but they
-- belong to the SEND FX page rather than to COLOUR.
group("drv", "DRIVE", function(e, v) engine.colSet(e.id, v) end, {
  { "drive", "DRIVE", cs(0, 1, "lin", 0, 0),   "sat" },
  { "dtone", "TONE",  cs(0, 1, "lin", 0, 0.5), "tilt" },
})

group("cho", "CHORUS", function(e, v) engine.fxSet("cho", e.id, v) end, {
  { "rate",   "RATE",     cs(0.02, 8, "exp", 0, 0.4, "hz"), "rate" },
  { "depth",  "DEPTH",    cs(0, 1, "lin", 0, 0.5),  "bar" },
  { "spread", "SPREAD",   cs(0, 1, "lin", 0, 0.7),  "pan" },
  { "fbk",    "FEEDBK",   cs(0, 0.85, "lin", 0, 0.2), "bar" },
  { "tone",   "TONE",     cs(0, 1, "lin", 0, 0.6),  "band" },
  { "level",  "LEVEL",    cs(0, 1, "lin", 0, 1),    "bar" },
})

group("dly", "DELAY", function(e, v) engine.fxSet("dly", e.id, v) end, {
  { "time",  "TIME",   cs(0.01, 4, "exp", 0, 0.375, "s"), "rel" },
  { "fbk",   "FEEDBK", cs(0, 0.98, "lin", 0, 0.45), "bar" },
  { "hp",    "HICUT",  cs(0, 1, "lin", 0, 0.15), "band" },
  { "lp",    "LOCUT",  cs(0, 1, "lin", 0, 0.75), "band" },
  { "ping",  "PING",   cs(0, 1, "lin", 0, 0),    "pan" },
  { "mod",   "MOD",    cs(0, 1, "lin", 0, 0.1),  "wow" },
  { "level", "LEVEL",  cs(0, 1, "lin", 0, 1),    "bar" },
})

group("rev", "REVERB", function(e, v) engine.fxSet("rev", e.id, v) end, {
  { "size",     "SIZE",   cs(0, 0.97, "lin", 0, 0.7),  "bar" },
  { "damp",     "DAMP",   cs(0, 1, "lin", 0, 0.4),     "band" },
  { "shim",     "SHIM",   cs(0, 1, "lin", 0, 0.3),     "bar" },
  { "interval", "SH.INT", cs(-12, 24, "lin", 1, 12, "st"), "bi" },
  { "shimfb",   "SH.FBK", cs(0, 1, "lin", 0, 0.5),     "bar" },
  { "pre",      "PRE",    cs(0, 0.45, "lin", 0, 0.02, "s"), "rel" },
  { "lowcut",   "LOCUT",  cs(0, 1, "lin", 0, 0.1),     "band" },
  { "level",    "LEVEL",  cs(0, 1, "lin", 0, 1),       "bar" },
})

-- name the fields, now that every entry is in place
for _, key in ipairs(M.order) do
  for _, e in ipairs(M.groups[key].p) do
    e.id, e.name, e.spec, e.g = e[1], e[2], e[3], e[4]
    e.param = key .. "_" .. e.id
    e[1], e[2], e[3], e[4] = nil, nil, nil, nil
  end
end

-- ------------------------------------------------------------------- pages

-- The clock is not an engine group -- norns owns it -- but it reads and turns
-- like one, so it gets a page of the same shape.
local clock_page = { name = "CLOCK", p = {
  { param = "clock_tempo", name = "BPM", spec = { minval = 20, maxval = 300 }, g = "bar" },
}}

-- SEND FX is a shortcut, not a fourth copy of anything: it points at the same
-- params the full pages hold, two of each, under labels that say which effect
-- they belong to. Turning one here and turning it there are the same act.
local function pick(key, id, name)
  for _, e in ipairs(M.groups[key].p) do
    if e.id == id then
      return { param = e.param, name = name, spec = e.spec, g = e.g }
    end
  end
  error("no such master param: " .. key .. "_" .. id)
end

local sendfx = {
  pick("rev", "size",  "R.SIZE"),
  pick("rev", "shim",  "R.SHIM"),
  pick("dly", "time",  "D.TIME"),
  pick("dly", "fbk",   "D.FBK"),
  pick("cho", "rate",  "C.RATE"),
  pick("cho", "depth", "C.DEP"),
  pick("drv", "drive", "DRIVE"),
  pick("drv", "dtone", "TONE"),
}

M.pages = {
  { name = "OVER",    kind = "over" },
  { name = "PERFORM", kind = "params", p = M.groups.perf.p },
  { name = "MIX",     kind = "mix" },
  { name = "COLOUR",  kind = "params", p = M.groups.col.p },
  { name = "SEND FX", kind = "params", p = sendfx },
  { name = "CLOCK",   kind = "params", p = clock_page.p },
  { name = "CHORUS",  kind = "params", p = M.groups.cho.p },
  { name = "DELAY",   kind = "params", p = M.groups.dly.p },
  { name = "REVERB",  kind = "params", p = M.groups.rev.p },
}

function M.page(i) return M.pages[util.clamp(i, 1, #M.pages)] end

-- how many cells a page has under the cursor: eight tracks on MIX, the
-- parameter count on a params page, and nothing to walk on the overview
function M.page_cells(i)
  local pg = M.page(i)
  if pg.kind == "mix" then return 8 end
  if pg.kind == "params" then return #pg.p end
  return 1
end

function M.param(i, c)
  local pg = M.page(i)
  if pg.kind ~= "params" then return nil end
  return pg.p[util.clamp(c, 1, #pg.p)]
end

-- ------------------------------------------------------------------ values

-- params:string is the formatted, unit-carrying readout norns already keeps
function M.text(e)
  local ok, s = pcall(function() return params:string(e.param) end)
  if ok and type(s) == "string" and #s > 0 then return s end
  local v = params:get(e.param)
  if type(v) == "number" then
    return (v == math.floor(v)) and string.format("%d", v) or string.format("%.2f", v)
  end
  return "-"
end

-- 0..1 position inside the spec, for the glyph. Monotonic on an exp warp
-- rather than exact, which is all a 28px picture needs.
function M.norm(e)
  local sp = e.spec
  local v = params:get(e.param)
  if not (sp and type(v) == "number") then return 0 end
  local lo, hi = sp.minval or 0, sp.maxval or 1
  if hi == lo then return 0 end
  return util.clamp((v - lo) / (hi - lo), 0, 1)
end

return M
