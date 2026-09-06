-- master.lua -- the things that are not per track
--
-- K2+K3 opens a page set of its own, and K2/K3 walk it the same way they walk
-- a track's pages:
--
--   1 OVER     the eight tracks, their machines and their patterns
--   2 SEQ      the master's own sequencer: the lane every other page locks to
--   3 PERFORM  eight offsets applied to every instrument at once
--   4 MIX      the eight track levels as faders
--   5 COLOUR   one colour chain across the whole mix
--   6 SEND FX  two controls each for the three sends and the master drive
--   7 SONG     tempo, and the key everything plays in
--   8..10      the three sends in full
--
-- Everything from PERFORM on is a norns param, so it saves with the PSET and
-- sits in the menu too -- but reaching for the menu to set a delay time in
-- the middle of a take is not a thing anybody wants to do.
--
-- The master has a sequencer of its own, one lane rather than eight, and
-- every page but the overview shares it: the grid is its steps, and holding
-- one and turning E3 locks whatever the cursor is on to that step. That is
-- what makes PERFORM PITCH a transpose track and COLOUR a lane of automation
-- rather than eight knobs you have to be holding at the right moment.

local S = include("tahned/lib/core/spec")
local C = include("tahned/lib/instruments/common")
local musicutil = require "musicutil"

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

-- KEY. The song's scale and root, which used to be eight separate copies on
-- eight HARMONY pages. Nothing here reaches the engine -- the sequencers read
-- it when they resolve a step -- but it is a norns param like the rest, so it
-- saves with the PSET and turns from the same page machinery.
--
-- These two are written with named fields rather than the positional tuple
-- the engine groups use, because an option param has no controlspec.
local SCALE_NAMES = {}
for i, sc in ipairs(musicutil.SCALES) do SCALE_NAMES[i] = sc.name end

-- Moving the key moves the music that is already written: a stored note is an
-- absolute note number, so without this a new root would leave every note in
-- the old key and the song would be in two at once. The notes belong to the
-- sequencers rather than to the master, so this only says that the key moved
-- and by how much -- tahned.lua points `on_key_change` at state.rekey, which
-- walks every track's every slot.
--
-- The previous key is remembered here rather than read back, since by the
-- time the action fires the param already holds the new one. It is nil until
-- the first bang, so building the params is not itself a key change.
M.on_key_change = nil

local key_prev = nil

local function key_changed()
  local now = { root = M.root(), scale = M.scale_index() }
  local prev = key_prev
  key_prev = now
  if not prev then return end
  if prev.root == now.root and prev.scale == now.scale then return end
  if M.on_key_change then M.on_key_change(prev, now) end
end

group("key", "KEY", key_changed, {
  { id = "root",  name = "ROOT",  opts = C.NOTE_NAMES, def = 1, g = "root" },
  { id = "scale", name = "SCALE", opts = SCALE_NAMES,  def = 1, g = "scale" },
})

group("cho", "CHORUS", function(e, v) engine.fxSet("cho", e.id, v) end, {
  { "rate",   "RATE",     cs(0.02, 8, "exp", 0, 0.4, "hz"), "rate" },
  { "depth",  "DEPTH",    cs(0, 1, "lin", 0, 0.5),  "depth" },
  { "spread", "SPREAD",   cs(0, 1, "lin", 0, 0.7),  "pan" },
  { "fbk",    "FEEDBK",   cs(0, 0.85, "lin", 0, 0.2), "fbk" },
  { "tone",   "TONE",     cs(0, 1, "lin", 0, 0.6),  "hicut" },
  { "level",  "LEVEL",    cs(0, 1, "lin", 0, 1),    "bar" },
})

group("dly", "DELAY", function(e, v) engine.fxSet("dly", e.id, v) end, {
  { "time",  "TIME",   cs(0.01, 4, "exp", 0, 0.375, "s"), "dtime" },
  { "fbk",   "FEEDBK", cs(0, 0.98, "lin", 0, 0.45), "fbk" },
  -- `hp` is a high-pass and `lp` a low-pass, so the labels were the wrong
  -- way round against the engine: the high-pass is the one that cuts lows.
  { "hp",    "LOCUT",  cs(0, 1, "lin", 0, 0.15), "locut" },
  { "lp",    "HICUT",  cs(0, 1, "lin", 0, 0.75), "hicut" },
  { "ping",  "PING",   cs(0, 1, "lin", 0, 0),    "ping" },
  { "mod",   "MOD",    cs(0, 1, "lin", 0, 0.1),  "wow" },
  { "level", "LEVEL",  cs(0, 1, "lin", 0, 1),    "bar" },
})

group("rev", "REVERB", function(e, v) engine.fxSet("rev", e.id, v) end, {
  { "size",     "SIZE",   cs(0, 0.97, "lin", 0, 0.7),  "rel" },
  { "damp",     "DAMP",   cs(0, 1, "lin", 0, 0.4),     "hicut" },
  { "shim",     "SHIM",   cs(0, 1, "lin", 0, 0.3),     "shim" },
  { "interval", "SH.INT", cs(-12, 24, "lin", 1, 12, "st"), "bi" },
  { "shimfb",   "SH.FBK", cs(0, 1, "lin", 0, 0.5),     "fbk" },
  { "pre",      "PRE",    cs(0, 0.45, "lin", 0, 0.02, "s"), "pre" },
  { "lowcut",   "LOCUT",  cs(0, 1, "lin", 0, 0.1),     "locut" },
  { "level",    "LEVEL",  cs(0, 1, "lin", 0, 1),       "bar" },
})

-- name the fields, now that every entry is in place. An entry written with
-- named fields already (the KEY pair) is left as it is.
for _, key in ipairs(M.order) do
  for _, e in ipairs(M.groups[key].p) do
    if e[1] then
      e.id, e.name, e.spec, e.g = e[1], e[2], e[3], e[4]
      e[1], e[2], e[3], e[4] = nil, nil, nil, nil
    end
    e.group = key
    e.param = key .. "_" .. e.id
  end
end

-- param name -> the canonical entry, so a page that only holds a copy of one
-- (SEND FX does) can still find the group whose send command it belongs to
M.by_param = {}
for _, key in ipairs(M.order) do
  for _, e in ipairs(M.groups[key].p) do M.by_param[e.param] = e end
end

-- ------------------------------------------------------------------- pages

-- The clock is not an engine group -- norns owns it -- but it reads and turns
-- like one, so it sits in a page of the same shape. Tempo and key are the two
-- things that are true of the whole song rather than of a track, so they share
-- it rather than each having a page with one cell on it.
local song_page = { name = "SONG", p = {
  { param = "clock_tempo", name = "BPM", spec = { minval = 20, maxval = 300 }, g = "bar" },
}}
for _, e in ipairs(M.groups.key.p) do table.insert(song_page.p, e) end

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

-- The master's own sequencer settings. The same seven a track's SEQ page
-- carries, minus the two that are about making a sound: this lane never
-- sounds, so there is nothing for a ratchet or a strum to do to it. They are
-- lua-side S.seq specs rather than norns params, exactly like a track's, and
-- they are drawn by the same cell code.
M.seqpage = { name = "SEQ", kind = "seq", params = {
  S.seq("length", "LENGTH", { min = 1, max = 128, def = 16, g = "len" }),
  S.seq("speed",  "SPEED",  { opts = C.SPEED_NAMES, def = 5, g = "pulse" }),
  S.seq("tsig",   "TSIG",   { opts = C.TSIG_NAMES, def = 0, g = "tsig" }),
  S.seq("swing",  "SWING",  { min = -50, max = 50, def = 0, g = "swing" }),
  S.seq("dir",    "DIR",    { opts = S.DIRS, g = "dir" }),
  S.seq("rotate", "ROTATE", { min = -64, max = 64, def = 0, g = "bi" }),
  S.seq("prob",   "PROB",   { min = 0, max = 100, def = 100, g = "prob" }),
  -- the reach gesture on the grid writes this; the cell is where you see what
  -- it wrote and where you change it by hand. Lock-only, like a track's, since
  -- a stage on every step of the lane would just be a slower lane.
  S.seq("hold",   "HOLD",   { min = 1, max = 16, def = 1, g = "hold_n",
                              lock = true }),
}}

M.pages = {
  { name = "OVER",    kind = "over" },
  M.seqpage,
  { name = "PERFORM", kind = "params", p = M.groups.perf.p },
  { name = "MIX",     kind = "mix" },
  { name = "COLOUR",  kind = "params", p = M.groups.col.p },
  { name = "SEND FX", kind = "params", p = sendfx },
  { name = "SONG",    kind = "params", p = song_page.p },
  { name = "CHORUS",  kind = "params", p = M.groups.cho.p },
  { name = "DELAY",   kind = "params", p = M.groups.dly.p },
  { name = "REVERB",  kind = "params", p = M.groups.rev.p },
}

function M.page(i) return M.pages[util.clamp(i, 1, #M.pages)] end

-- how many cells a page has under the cursor: eight tracks on MIX, the
-- parameter count on a params page, the setting count on the sequencer's own,
-- and nothing to walk on the overview
function M.page_cells(i)
  local pg = M.page(i)
  if pg.kind == "mix" then return 8 end
  if pg.kind == "params" then return #pg.p end
  if pg.kind == "seq" then return #pg.params end
  return 1
end

-- The overview is the one master page the grid does not give to the master
-- sequencer: it is where tracks, machines, mutes and transport live, and it
-- was never going to be steps.
function M.has_steps(i) return M.page(i).kind ~= "over" end

function M.param(i, c)
  local pg = M.page(i)
  if pg.kind ~= "params" then return nil end
  return pg.p[util.clamp(c, 1, #pg.p)]
end

-- ------------------------------------------------------------------ values

-- a param read that survives being called before build_params has run
local function pget(id, dflt)
  local ok, v = pcall(function() return params:get(id) end)
  return (ok and type(v) == "number") and v or dflt
end

-- params:string is the formatted, unit-carrying readout norns already keeps.
-- A cell is 32px wide, which is about six characters, so a long scale name is
-- cut rather than allowed to run into the cell beside it.
local MAXTEXT = 6

function M.text(e)
  local ok, s = pcall(function() return params:string(e.param) end)
  if not (ok and type(s) == "string" and #s > 0) then
    local v = params:get(e.param)
    if type(v) ~= "number" then return "-" end
    s = (v == math.floor(v)) and string.format("%d", v)
                             or string.format("%.2f", v)
  end
  return (#s > MAXTEXT) and s:sub(1, MAXTEXT) or s
end

-- 0..1 position inside the spec, for the glyph. Takes the value rather than
-- reading it, so a step's locked value draws in the same cell the master's
-- own one would.
function M.norm_of(e, v)
  if e.opts then
    local n = #e.opts
    if n < 2 then return 0 end
    return util.clamp(((tonumber(v) or 1) - 1) / (n - 1), 0, 1)
  end
  local sp = e.spec
  if not (sp and type(v) == "number") then return 0 end
  -- a controlspec knows its own warp, and unmap is the position it maps from.
  -- Reading an exp control linearly crowded everything musical into the first
  -- couple of pixels -- a 375ms delay sat at 9% of a cell that reaches 4s.
  if sp.unmap then
    local ok, u = pcall(function() return sp:unmap(v) end)
    if ok and type(u) == "number" then return util.clamp(u, 0, 1) end
  end
  local lo, hi = sp.minval or 0, sp.maxval or 1
  if hi == lo then return 0 end
  return util.clamp((v - lo) / (hi - lo), 0, 1)
end

function M.norm(e)
  if e.opts then return M.norm_of(e, pget(e.param, 1)) end
  return M.norm_of(e, params:get(e.param))
end

-- The readout for a value that is not the param's own. params:string is the
-- formatted, unit-carrying one norns keeps and it can only speak for what the
-- param currently holds, so a locked value falls back to plain formatting.
function M.text_of(e, v)
  if e.opts then return e.opts[util.clamp(util.round(v), 1, #e.opts)] or "-" end
  if type(v) ~= "number" then return "-" end
  local s = (v == math.floor(v)) and string.format("%d", v)
                                 or string.format("%.2f", v)
  return (#s > MAXTEXT) and s:sub(1, MAXTEXT) or s
end

-- --------------------------------------------------------------- locking
--
-- The master's sequencer locks a master parameter to a step the way a track's
-- locks a channel. A lock is never written into the param: the master keeps
-- its own value and the locked one goes straight to the engine for as long as
-- the step is current, so what you hear is the lane playing rather than the
-- whole instrument following the last step that went by.
--
-- Two groups are deliberately not lockable. BPM is the norns clock, which the
-- engine has no say over, and the key is what every stored note was written
-- against -- moving root or scale per step would rewrite the song eight times
-- a bar rather than perform it. The MIX page is eight track faders, and each
-- of those already locks on its own track's sequencer.
local NO_LOCK = { key = true }

local function canon(e)
  return e and e.param and M.by_param[e.param] or nil
end

function M.lockable(e)
  local c = canon(e)
  return (c ~= nil) and not NO_LOCK[c.group]
end

-- push a value at the engine without storing it anywhere
function M.send_lock(param, v)
  local c = M.by_param[param]
  if not (c and not NO_LOCK[c.group]) then return end
  M.groups[c.group].send(c, v)
end

-- put the master's own value back, when the locked step passes
function M.send_now(param)
  local c = M.by_param[param]
  if not (c and not NO_LOCK[c.group]) then return end
  local v = pget(param, nil)
  if type(v) == "number" then M.groups[c.group].send(c, v) end
end

-- One encoder click on a locked value, in the param's own units. An option
-- steps by one; a control moves a hundredth of its travel, through the warp
-- where the spec has one, which is what params:delta would have done.
function M.lock_delta(e, v, d)
  if e.opts then
    return util.clamp(util.round(v) + d, 1, #e.opts)
  end
  local sp = e.spec
  if not sp then return v + d end
  local lo, hi = sp.minval or 0, sp.maxval or 1
  if sp.unmap and sp.map then
    local ok, u = pcall(function() return sp:unmap(v) end)
    if ok and type(u) == "number" then
      local ok2, mapped = pcall(function()
        return sp:map(util.clamp(u + (d / 100), 0, 1))
      end)
      if ok2 and type(mapped) == "number" then return util.clamp(mapped, lo, hi) end
    end
  end
  return util.clamp(v + (d * (hi - lo) / 100), lo, hi)
end

-- the master's own value for a param, which is what a lock starts from
function M.value(e)
  if e.opts then return pget(e.param, 1) end
  return pget(e.param, (e.spec and e.spec.minval) or 0)
end

-- what a glyph needs beyond the number. SCALE draws the notes the scale
-- actually contains, which is in musicutil rather than in the param.
function M.glyph_extra(e)
  if e.id == "scale" then
    local sc = musicutil.SCALES[M.scale_index()]
    return { intervals = sc and sc.intervals }
  end
  return nil
end

-- ---------------------------------------------------------------- the key
--
-- One scale and one root for the whole song. The sequencers read these when
-- they resolve a step, and the grid keyboard reads them to lay itself out.

function M.root()
  return util.clamp(util.round(pget("key_root", 1)), 1, 12) - 1
end

function M.scale_index()
  return util.clamp(util.round(pget("key_scale", 1)), 1, #SCALE_NAMES)
end

function M.scale_name() return SCALE_NAMES[M.scale_index()] end

return M
