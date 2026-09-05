-- spec.lua -- parameter descriptors
--
-- Every editable cell on every page is one of these. `ch` is the channel on
-- the track's control bus; sequencer settings live in lua and carry an `id`
-- instead. Kinds:
--
--   cont   continuous, shown over min..max, sent to the engine as 0..1
--   int    integer, sent raw
--   enum   discrete choice, sent raw
--   dest   an LFO destination -- the value *is* a bus channel number
--   depth  an LFO depth -- scaled by whatever its destination's range is
--   mach   machine select, handled by the track rather than the bus
--   ftype  filter type, picks a compiled synthdef variant
--   seq    lua-side sequencer setting, never reaches the engine

local S = {}

S.NULL_DEST = 88   -- a channel nothing reads

-- the YMF262's eight waveforms, in chip order
S.WAVES   = {"SIN","HSIN","ASIN","PSIN","ESIN","CAML","SQR","SAW"}
-- the chip's frequency multipliers; it repeats 10, 12 and 15, dropped here
S.MULTS   = {"0.5","1","2","3","4","5","6","7","8","9","10","12","15"}
-- percussion gets inharmonic ratios the chip never had
S.RATIOS  = {"0.25","0.5","0.75","1","1.25","1.5","1.75","2",
             "2.5","3","3.5","4","5","6","8","11"}
S.FILTERS = {"LP","BP","HP","COMB"}
S.LFOWAVE = {"TRI","SIN","SQR","SAW","RMP","EXP","RND","S&H"}
S.LFOMODE = {"FREE","TRIG","HOLD","ONE"}
S.LFOMULT = {"x1","x2","x4","x8","x16","x32","x64","x128"}
S.MACHINE = {"PERC","TONE","AMB"}
S.DIRS    = {"FWD","REV","PNG","RND","BRN"}
S.TRANS   = {"CLICK","TICK","THUMP","METAL"}

local function base(ch, name, o)
  o = o or {}
  return { ch = ch, name = name, g = o.g or "bar", unit = o.unit, fmt = o.fmt }
end

-- continuous, 0..127 by default
function S.c(ch, name, o)
  o = o or {}
  local s = base(ch, name, o)
  s.k, s.min, s.max, s.def = "cont", o.min or 0, o.max or 127, o.def or 64
  return s
end

-- Bipolar continuous. The range is symmetric on purpose: with -64..63 the
-- centre normalises to 64/127, so a control sitting at 0 still reaches the
-- engine as 0.0079 rather than nothing. That is inaudible on most of them
-- and a six second beat on DETUNE, which is worse than either.
function S.b(ch, name, o)
  o = o or {}
  o.min, o.max, o.def = o.min or -63, o.max or 63, o.def or 0
  o.g = o.g or "bi"
  return S.c(ch, name, o)
end

-- integer, sent raw
function S.i(ch, name, min, max, def, o)
  local s = base(ch, name, o)
  s.k, s.min, s.max, s.def = "int", min, max, def
  return s
end

-- discrete choice, sent raw
function S.e(ch, name, opts, o)
  o = o or {}
  local s = base(ch, name, o)
  s.k, s.opts, s.min, s.max, s.def = "enum", opts, 0, #opts - 1, o.def or 0
  s.g = o.g or "enum"
  return s
end

function S.dest(ch, name)
  local s = base(ch, name, { g = "dest" })
  s.k, s.min, s.max, s.def = "dest", 0, 95, S.NULL_DEST
  return s
end

function S.depth(ch, name)
  local s = base(ch, name, { g = "bi" })
  s.k, s.min, s.max, s.def = "depth", -63, 63, 0
  return s
end

-- lua-side sequencer setting
function S.seq(id, name, o)
  o = o or {}
  local s = base(nil, name, o)
  s.k, s.id = "seq", id
  s.min, s.max, s.def = o.min or 0, o.max or 127, o.def or 0
  s.opts, s.step = o.opts, o.step or 1
  if o.opts then s.min, s.max = 0, #o.opts - 1 end
  return s
end

-- ------------------------------------------------------------------ values

-- what actually goes over OSC for this spec at this value
function S.encode(sp, v, destspec)
  if sp.k == "cont" then
    return (v - sp.min) / (sp.max - sp.min)
  elseif sp.k == "depth" then
    -- destinations hold either a 0..1 normalised value or a raw enum index,
    -- so a depth only means something once scaled by its target's range
    local range = 1
    if destspec and (destspec.k == "enum" or destspec.k == "int") then
      range = destspec.max - destspec.min
    end
    return (v / 64) * range
  end
  return v
end

function S.clamp(sp, v)
  return util.clamp(v, sp.min, sp.max)
end

function S.text(sp, v)
  if sp.fmt then return sp.fmt(v) end
  if sp.opts then return sp.opts[v + 1] or "-" end
  if sp.k == "cont" and (sp.max - sp.min) <= 2 then
    return string.format("%.2f", v)
  end
  return string.format("%d", util.round(v))
end

-- 0..1 position of a value inside its range, for drawing
function S.unit_pos(sp, v)
  if sp.max == sp.min then return 0 end
  return (v - sp.min) / (sp.max - sp.min)
end

return S
