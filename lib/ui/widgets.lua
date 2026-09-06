-- widgets.lua
--
-- One micro-glyph per parameter cell. Each draws inside a 26x9 box and says
-- something true about the value -- an envelope shows its actual shape, a
-- waveform cell shows the waveform, a ratio cell shows the two waves the
-- ratio is between. The point is that a page reads as a picture of the sound
-- rather than a column of numbers.
--
-- ------------------------------------------------------------ the grammar
--
-- Every glyph is built out of the same few parts, so eight cells read as one
-- page rather than as eight drawings that happen to share a screen:
--
--   ground   a magnitude sits on the bottom row of its box, always at LV_DIM.
--            If a glyph has a ground it is read upward from it.
--   axis     something bipolar, or a waveform, is read about the centre line
--            instead -- also LV_DIM, with a detent at the centre.
--   ghost    the travel a control has and has not used is drawn at LV_GHOST
--            under the value. Nothing is ever a lone mark with no scale
--            behind it: you can always see how much of the range is left.
--   value    the part that is true right now, drawn at the level the caller
--            passes -- 9 for a cell, 15 for the cell under the cursor.
--
-- A glyph never draws outside its box, and never draws a second picture of
-- the cell beside it. Where two controls really are the same kind of thing
-- -- four operator levels, three send levels -- they really do draw the same
-- shape, because saying otherwise would be a lie for the sake of variety.
--
-- ---------------------------------------------------------------- motion
--
-- Three things move, and nothing else does:
--
--   the LFO scope, always, because a page called LFO whose speed cell does
--   not move is not showing you the speed;
--
--   a field of noise -- SNAP, SIZZLE, GLITCH, LOSS, WOW -- but only while
--   the cursor is on it. Motion everywhere at once is noise; motion on the
--   one cell you are turning is feedback;
--
--   an envelope run, which brightens on the trigger and falls back, so a
--   drum page has a pulse while the sequencer is playing.

local S = include("tahned/lib/core/spec")
local C = include("tahned/lib/instruments/common")
local L = include("tahned/lib/core/lfo")

local W = {}

-- the ground, a detent, and the unreached part of a travel
local LV_DIM, LV_TICK, LV_GHOST = 2, 3, 5

local function pos(sp, v) return S.unit_pos(sp, v) end

-- ------------------------------------------------------------- primitives

local function hline(x, y, w, lv)
  screen.level(lv); screen.rect(x, y, math.max(1, w), 1); screen.fill()
end

local function vline(x, y, h, lv)
  screen.level(lv); screen.rect(x, y, 1, math.max(1, h)); screen.fill()
end

-- the row a magnitude is read up from
local function ground(x, y, w, h) hline(x, y + h - 1, w, LV_DIM) end

-- the line a bipolar value is read either side of, with its centre detent
local function axis(x, y, w, h)
  hline(x, y + math.floor(h / 2), w, LV_DIM)
  vline(x + math.floor(w / 2), y + math.floor(h / 2) - 1, 3, LV_TICK)
end

-- connected plot of f(t) over t in 0..1, f returning -1..1, about the centre.
-- Sparse pixels read as noise at this size; a line reads as a shape.
local function plot(x, y, w, h, lv, over, f)
  screen.level(lv)
  local n = math.max(2, math.floor(w * (over or 1)))
  local mid = y + (h / 2)
  local amp = (h / 2) - 0.5
  screen.move(x, mid - (util.clamp(f(0), -1, 1) * amp))
  for i = 1, n do
    local t = i / n
    screen.line(x + (t * w), mid - (util.clamp(f(t), -1, 1) * amp))
  end
  screen.stroke()
end

-- The travel a control has, and the part of it the value has reached. This
-- is the neutral member of the family: a control with no picture of its own
-- still says how far along it is, and says it the same way everywhere.
local function wedge(x, y, w, h, p, lv)
  local base, top = y + h - 1, y + 1
  local rise = base - top
  ground(x, y, w, h)
  screen.level(LV_GHOST)
  screen.move(x, base - 1)
  screen.line(x + w - 1, top)
  screen.stroke()
  local n = util.round(util.clamp(p, 0, 1) * w)
  if n > 0 then
    screen.level(lv)
    for i = 0, n - 1 do
      local hh = 1 + util.round(((i + 1) / w) * rise)
      screen.rect(x + i, base - hh, 1, hh)
    end
    screen.fill()
  end
end

-- the same travel, opening either side of a centre that means nothing
local function wedge_bi(x, y, w, h, p, lv)
  local base, top = y + h - 1, y + 1
  local rise = base - top
  local c = x + math.floor(w / 2)
  local half = w - (c - x) - 1
  ground(x, y, w, h)
  screen.level(LV_GHOST)
  screen.move(x, top); screen.line(c, base - 1); screen.line(x + w - 1, top)
  screen.stroke()
  vline(c, base - 2, 2, LV_TICK)
  local n = util.round(math.abs(util.clamp(p, -1, 1)) * half)
  if n > 0 then
    screen.level(lv)
    for i = 1, n do
      local hh = 1 + util.round((i / half) * rise)
      screen.rect(c + ((p >= 0) and i or -i), base - hh, 1, hh)
    end
    screen.fill()
  end
end

-- A discrete choice drawn as the choices: one slot a value, the one selected
-- standing up out of the row. Reads as "third of eight" without counting,
-- and every enum on every page reads the same way. Past thirteen there is no
-- room to count them, so it falls back to the choice standing on a rail.
local function ladder(x, y, w, h, n, idx, lv)
  ground(x, y, w, h)
  n = math.max(2, n)
  idx = util.clamp(idx, 0, n - 1)
  if n <= 13 then
    local pitch = (w - 1) / n
    local bw = math.max(1, math.floor(pitch) - 1)
    screen.level(LV_GHOST)
    for k = 0, n - 1 do
      if k ~= idx then screen.rect(x + util.round(k * pitch), y + h - 3, bw, 2) end
    end
    screen.fill()
    screen.level(lv)
    screen.rect(x + util.round(idx * pitch), y + 1, bw, h - 2)
    screen.fill()
  else
    screen.level(LV_GHOST)
    for k = 0, n - 1 do
      screen.rect(x + util.round(k * (w - 2) / (n - 1)), y + h - 3, 1, 2)
    end
    screen.fill()
    screen.level(lv)
    screen.rect(x + util.round(idx * (w - 2) / (n - 1)), y + 1, 2, h - 2)
    screen.fill()
  end
end

-- how many choices a spec offers, and which one this is
local function n_of(sp, v)
  local n = sp.opts and #sp.opts
    or ((sp.max and sp.min) and (sp.max - sp.min + 1)) or 2
  local i = util.round((v or 0) - (sp.min or 0))
  return n, i
end

-- A field that shimmers only while the cursor is on it. Quantised so it is a
-- shimmer rather than a blur, and frozen everywhere else on the page.
local function seed_of(base, extra)
  if extra and extra.live and extra.now then
    return (base + (math.floor(extra.now * 12) * 0.0137)) % 1
  end
  return base
end

local function noiser(seed)
  return function()
    seed = (seed * 9.13 + 0.271) % 1
    return seed
  end
end

-- ------------------------------------------------------------- generic

function W.bar(x, y, w, h, sp, v, lv)
  wedge(x, y, w, h, pos(sp, v), lv)
end

function W.bi(x, y, w, h, sp, v, lv)
  wedge_bi(x, y, w, h, (pos(sp, v) * 2) - 1, lv)
end

-- a send: the level, with the arrow that says it leaves the track
function W.send(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local base = y + h - 1
  ground(x, y, w, h)
  screen.level(LV_GHOST)
  hline(x, base - 2, w, LV_GHOST)
  screen.level(lv)
  screen.rect(x, base - 3, math.max(1, util.round((w - 5) * p)), 3)
  screen.fill()
  screen.level((p > 0.01) and lv or LV_GHOST)
  screen.move(x + w - 5, y + 1)
  screen.line(x + w - 1, y + h - 4)
  screen.line(x + w - 5, base - 1)
  screen.stroke()
end

-- where the track sits in the field, on a line that is the field
function W.pan(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  axis(x, y, w, h)
  local mid = y + math.floor(h / 2)
  screen.level(LV_GHOST)
  vline(x, mid - 2, 5, LV_GHOST)
  vline(x + w - 1, mid - 2, 5, LV_GHOST)
  screen.level(lv)
  screen.rect(x + util.clamp(util.round((w - 3) * p), 0, w - 3), mid - 3, 3, 7)
  screen.fill()
end

function W.ladder(x, y, w, h, sp, v, lv)
  local n, i = n_of(sp, v)
  ladder(x, y, w, h, n, i, lv)
end

W.enum   = W.ladder
W.leader = W.ladder

-- Semitones. A plain bipolar meter said how far the knob was turned; this
-- says how far the note moved, with a detent an octave so an octave is a
-- thing you can land on rather than a number you have to read.
function W.tune(x, y, w, h, sp, v, lv)
  local mid = y + math.floor(h / 2)
  local span = math.max(math.abs(sp.min or -24), math.abs(sp.max or 24))
  hline(x, mid, w, LV_DIM)
  local c = x + math.floor(w / 2)
  screen.level(LV_TICK)
  for st = -span, span, 12 do
    local px = c + util.round((st / span) * ((w / 2) - 1))
    screen.rect(px, mid - ((st == 0) and 3 or 2), 1, (st == 0) and 7 or 5)
  end
  screen.fill()
  local px = c + util.round(((v or 0) / span) * ((w / 2) - 1))
  screen.level(lv)
  screen.rect(util.clamp(px, x, x + w - 2), y, 2, h - 1)
  screen.fill()
end

-- What a machine is, in the terms the other cells are already in: where it
-- puts its energy and for how long. Six pictures that cannot be mistaken for
-- each other -- a kick is two fat low partials, a hat six thin high ones,
-- TONE is the operator pair every one of its pages is about.
local MACH_ICON = {
  [0] = { n = 2, lo = 0.06, hi = 0.26, amp = { 1.0, 0.62 }, wide = true },
  [1] = { n = 3, lo = 0.10, hi = 0.52, amp = { 0.9, 0.7, 0.5 }, dust = 0.5 },
  [2] = { n = 6, lo = 0.42, hi = 0.96, amp = { 0.4, 0.34, 0.4, 0.3, 0.36, 0.28 } },
  [3] = { n = 3, lo = 0.08, hi = 0.40, amp = { 1.0, 0.55, 0.35 }, wide = true },
  [4] = { n = 8, lo = 0.20, hi = 0.98,
          amp = { 0.9, 0.8, 0.86, 0.72, 0.8, 0.66, 0.74, 0.6 }, dust = 0.9 },
}

function W.mach(x, y, w, h, sp, v, lv)
  ground(x, y, w, h)
  local icon = MACH_ICON[util.round(v or 0)]
  if not icon then                          -- TONE: a modulator over a carrier
    screen.level(lv)
    screen.rect(x + 6, y, 6, 3)
    screen.rect(x + 6, y + h - 4, 6, 3)
    screen.stroke()
    screen.level(math.max(3, lv - 5))
    screen.move(x + 9, y + 3); screen.line(x + 9, y + h - 4)
    screen.move(x + 14, y + h - 3); screen.line(x + 21, y + h - 3)
    screen.stroke()
    screen.level(lv)
    screen.rect(x + 6, y + h - 4, 6, 3)
    screen.fill()
    return
  end
  if icon.dust then
    screen.level(LV_GHOST)
    local rnd = noiser(0.41)
    for i = 1, w, 2 do
      local a = rnd() * icon.dust * (h - 2)
      screen.move(x + i, y + h - 2); screen.line(x + i, y + h - 2 - a)
    end
    screen.stroke()
  end
  screen.level(lv)
  for i = 1, icon.n do
    local t = (icon.n == 1) and 0 or ((i - 1) / (icon.n - 1))
    local px = x + util.round((icon.lo + (t * (icon.hi - icon.lo))) * (w - 2))
    local a = util.round((icon.amp[i] or 0.5) * (h - 2))
    screen.rect(px, y + h - 1 - a, icon.wide and 2 or 1, a)
  end
  screen.fill()
end

-- An LFO destination. Which one it is is spelled out underneath; what the
-- cell has to say is whether this half of the LFO is patched at all, so it
-- draws the patch: the LFO, the arrow, and something on the end of it.
function W.dest(x, y, w, h, sp, v, lv)
  local off = (v == nil) or (v == S.NULL_DEST)
  local mid = y + math.floor(h / 2)
  local sl = off and LV_GHOST or lv
  ground(x, y, w, h)
  plot(x, y + 1, 8, h - 3, sl, 3, function(t) return math.sin(t * 2 * math.pi) end)
  screen.level(sl)
  if off then
    screen.move(x + 10, mid); screen.line(x + 13, mid)
    screen.move(x + 17, mid); screen.line(x + 20, mid)
    screen.stroke()
    screen.level(LV_GHOST)
    screen.move(x + 14, mid - 3); screen.line(x + 19, mid + 3)
    screen.move(x + 19, mid - 3); screen.line(x + 14, mid + 3)
    screen.stroke()
    return
  end
  screen.move(x + 10, mid); screen.line(x + 19, mid)
  screen.move(x + 16, mid - 3); screen.line(x + 19, mid); screen.line(x + 16, mid + 3)
  screen.stroke()
  screen.rect(x + 21, y + 1, 4, h - 3)
  screen.fill()
end

-- ------------------------------------------------------------- envelopes
--
-- Envelope segments are drawn as the segment, going the way it goes: an
-- attack climbs, a decay or release falls. The value moves the knee across
-- the cell, so a long segment reaches the far side and a short one is over
-- in the first few pixels. Curves are fixed exponentials, matching the
-- engine -- there is nothing left to draw a curve control for. The dotted
-- ceiling is the level the shape is measured against, so a knee two pixels
-- in still reads as "almost none of the available time".

local function ceiling(x, y, w)
  screen.level(LV_TICK)
  for i = 0, w - 1, 3 do screen.rect(x + i, y, 1, 1) end
  screen.fill()
end

-- attack: rises off the floor, knee pushed right as the time grows
function W.atk(x, y, w, h, sp, v, lv)
  local n, e = 12, (w - 1) * (0.10 + (pos(sp, v) * 0.90))
  ground(x, y, w, h)
  ceiling(x, y, w)
  screen.level(lv)
  screen.move(x, y + h - 1)
  for i = 1, n do
    local t = i / n
    screen.line(x + (t * e), y + h - 1 - ((h - 2) * (t ^ 0.5)))
  end
  screen.line(x + w - 1, y + 1)
  screen.stroke()
end

-- decay / release: falls from the top, tail stretched right as it grows
function W.rel(x, y, w, h, sp, v, lv)
  local n, e = 12, (w - 1) * (0.10 + (pos(sp, v) * 0.90))
  ground(x, y, w, h)
  ceiling(x, y, w)
  screen.level(lv)
  screen.move(x, y + 1)
  for i = 1, n do
    local t = i / n
    screen.line(x + (t * e), y + 1 + ((h - 2) * (t ^ 0.5)))
  end
  screen.line(x + w - 1, y + h - 1)
  screen.stroke()
end

-- a plateau: level held for as long as the value says, then gone
function W.hold(x, y, w, h, sp, v, lv)
  local e = x + math.max(2, (w - 1) * (0.06 + (pos(sp, v) * 0.94)))
  ground(x, y, w, h)
  ceiling(x, y, w)
  screen.level(lv)
  screen.move(x, y + h - 1)
  screen.line(x, y + 1)
  screen.line(e, y + 1)
  screen.line(e, y + h - 1)
  screen.line(x + w - 1, y + h - 1)
  screen.stroke()
end

-- A gap, and then the thing. PRE is the distance before a tail starts, which
-- is not a shape that decays and is not a level either.
function W.pre(x, y, w, h, sp, v, lv)
  local g = util.round((w - 6) * pos(sp, v))
  ground(x, y, w, h)
  screen.level(LV_TICK)
  for i = 0, g, 2 do screen.rect(x + i, y + h - 3, 1, 1) end
  screen.fill()
  screen.level(lv)
  screen.move(x + g, y + h - 1)
  screen.line(x + g, y + 1)
  local n = 8
  for i = 1, n do
    local t = i / n
    screen.line(x + g + (t * (w - 1 - g)), y + 1 + ((h - 2) * (t ^ 0.5)))
  end
  screen.stroke()
end

-- How long a note is held, against the step it starts on. Past the step
-- boundary the block runs on into the next one, which is the thing GATE
-- does that a percentage on its own does not tell you.
function W.gate(x, y, w, h, sp, v, lv)
  local full = math.floor(w * 0.5)
  local n = util.clamp(util.round(full * (v or 0) / 100), 1, w)
  ground(x, y, w, h)
  screen.level(LV_TICK)
  for i = 0, h - 2, 2 do screen.rect(x + full, y + i, 1, 1) end
  screen.fill()
  screen.level(lv)
  screen.rect(x, y + 2, n, h - 4)
  screen.fill()
end

-- ---------------------------------------------------------------- pitch
--
-- SC's Env curve, a1 -> a2 over t in 0..1:
--   a1 + (a2 - a1) * (1 - exp(t*c)) / (1 - exp(c))
-- with a1 = 1, a2 = 0, c = -2.5, matching the kick and the tom.
local SWP_C   = -2.5
local SWP_DEN = 1 - math.exp(SWP_C)
local function swp_env(t)
  return 1 - ((1 - math.exp(SWP_C * t)) / SWP_DEN)
end

-- How far off the settled note the pitch starts, and which way.
--
-- A glide only ever goes one way, so the note it settles on is drawn where
-- that leaves the most room for the excursion -- low for a pitch falling
-- onto it, high for one rising -- rather than down the middle with four
-- pixels either side, which is what made a half-depth sweep look flat. The
-- dotted line at the far edge is full depth, so a small excursion reads as a
-- small part of what is there rather than as a line leaning slightly.
function W.sweep(x, y, w, h, sp, v, lv)
  local p = (pos(sp, v) * 2) - 1
  local mag = math.sqrt(math.abs(p))
  local top, bot = y + 1, y + h - 2
  local settle, start = y + math.floor(h / 2), nil
  local function dots(yy)
    screen.level(LV_TICK)
    for i = 0, w - 1, 3 do screen.rect(x + i, yy, 1, 1) end
    screen.fill()
  end
  if math.abs(p) < 0.02 then
    start = settle
    dots(top); dots(bot)
  elseif p > 0 then                       -- falls onto the note from above
    settle = bot
    start = bot - util.round(mag * (bot - top))
    dots(top)
  else                                    -- climbs onto it from below
    settle = top
    start = top + util.round(mag * (bot - top))
    dots(bot)
  end
  hline(x, settle, w, LV_DIM)
  local glide = (w - 1) * 0.55            -- the rest is the pitch it lands on
  screen.level(lv)
  screen.move(x, start)
  for i = 1, 10 do
    local t = i / 10
    screen.line(x + (t * glide), settle + ((start - settle) * swp_env(t)))
  end
  screen.line(x + w - 1, settle)
  screen.stroke()
end

-- How long that glide takes. SWEEP says how far the pitch starts out and
-- this says how long it takes to arrive, so the pair is a picture of one
-- glide rather than two pictures of two numbers. It lands on the settled
-- line at the value, and the caret is exactly where it lands.
function W.ptime(x, y, w, h, sp, v, lv)
  local mid = y + math.floor(h / 2)
  local land = 1 + util.round((w - 3) * (0.04 + (pos(sp, v) * 0.96)))
  hline(x, mid, w, LV_DIM)
  screen.level(LV_TICK)
  for i = 0, w - 1, 3 do screen.rect(x + i, y, 1, 1) end
  screen.fill()
  screen.level(lv)
  screen.move(x, y)
  for i = 1, 10 do
    local t = i / 10
    screen.line(x + (t * land), mid - ((mid - y) * swp_env(t)))
  end
  screen.line(x + w - 1, mid)
  screen.stroke()
  -- the stretch of the cell the glide takes up, so this reads as a length of
  -- time rather than as a second amplitude curve
  screen.rect(x, y + h - 2, land + 1, 2)
  screen.fill()
end

-- ------------------------------------------------------------------- FM

-- How hard one operator is driving another: a carrier whose phase is bent by
-- a modulator, bending further as the value climbs. At zero it is the clean
-- sine the operator would put out on its own.
local function fm_wave(t, idx, ratio)
  return math.sin((t * 3 * math.pi) + (idx * math.sin(t * 3 * math.pi * ratio)))
end

function W.fm(x, y, w, h, sp, v, lv)
  -- the index is curved, not proportional: a quarter turn is a sine with a
  -- kink in it rather than something already too dense to read
  local idx = (pos(sp, v) ^ 1.4) * 4.5
  axis(x, y, w, h)
  plot(x, y, w, h, lv, 5, function(t) return fm_wave(t, idx, 2) end)
end

-- The ratio drawn as the two things it is a ratio between, in two lanes: the
-- modulator on top, running at the ratio the list actually holds, and under
-- it the carrier it is a ratio to, at one cycle. Overlaid they were one
-- muddle; in lanes you count one against the other. A ratio under one is a
-- modulator slower than its carrier, and looks it.
function W.ratio(x, y, w, h, sp, v, lv)
  local r = tonumber(sp.opts and sp.opts[(v or 0) + 1]) or 1
  local lane = math.floor(h / 2)
  ground(x, y, w, h)
  hline(x, y + lane, w, LV_DIM)
  plot(x, y, w, lane, lv, 6,
    function(t) return math.sin(t * 2 * math.pi * math.min(r, 9)) end)
  plot(x, y + lane + 1, w, h - lane - 2, math.max(4, lv - 4), 3,
    function(t) return math.sin(t * 2 * math.pi) end)
end

local function opl_sample(idx, ph)
  local s = math.sin(ph * 2 * math.pi)
  local s2 = math.sin(ph * 4 * math.pi)
  local half = (ph < 0.5) and 1 or 0
  if idx == 0 then return s
  elseif idx == 1 then return s * half
  elseif idx == 2 then return math.abs(s)
  elseif idx == 3 then return (ph % 0.5 < 0.25) and math.abs(s) or 0
  elseif idx == 4 then return s2 * half
  elseif idx == 5 then return math.abs(s2) * half
  elseif idx == 6 then return (half == 1) and 1 or -1
  else return math.max(-1, 1 - (ph * 2)) end
end

function W.wave(x, y, w, h, sp, v, lv)
  axis(x, y, w, h)
  plot(x, y, w, h, lv, 3, function(t) return opl_sample(v, t % 1) end)
end

-- The chip's feedback is an operator modulating itself, and what that does
-- to a sine is bend it toward a saw. That is what the cell draws.
function W.fbkwave(x, y, w, h, sp, v, lv)
  local fb = pos(sp, v) * 3.2
  axis(x, y, w, h)
  plot(x, y, w, h, LV_GHOST, 3, function(t) return math.sin(t * 2 * math.pi) end)
  plot(x, y, w, h, lv, 5, function(t)
    local ph = t * 2 * math.pi
    return math.sin(ph + (fb * math.sin(ph)))
  end)
end

-- Two voices pulling apart. DETUNE is only ever heard as a beat, so the cell
-- is the beat: one wave against a copy of itself, further out of step as the
-- control moves either way from centre.
function W.beat(x, y, w, h, sp, v, lv)
  local d = math.abs((pos(sp, v) * 2) - 1)
  axis(x, y, w, h)
  -- the copy sits a pixel off the original, so at zero the cell still shows
  -- a pair in unison rather than the single wave every other cell draws
  plot(x, y + 1, w, h - 2, LV_GHOST, 4, function(t) return math.sin(t * 4 * math.pi) end)
  plot(x, y - 1, w, h - 2, lv, 4,
    function(t) return math.sin(t * 4 * math.pi * (1 + (d * 0.3))) end)
end

-- wavefolded sine: the glyph actually folds as the value rises
function W.fold(x, y, w, h, sp, v, lv)
  local amt = 1 + (pos(sp, v) * 8)
  axis(x, y, w, h)
  -- the rails it folds against, so a fold of nothing is still plainly a
  -- folder rather than the plain sine the WAVE cells beside it draw
  screen.level(LV_TICK)
  for i = 0, w - 1, 3 do
    screen.rect(x + i, y, 1, 1); screen.rect(x + i, y + h - 1, 1, 1)
  end
  screen.fill()
  plot(x, y, w, h, lv, 4, function(t)
    local s = math.sin(t * 2 * math.pi) * amt
    while s > 1 or s < -1 do
      if s > 1 then s = 2 - s else s = -2 - s end
    end
    return s
  end)
end

-- ------------------------------------------------------------------ LFO

function W.lfowave(x, y, w, h, sp, v, lv)
  axis(x, y, w, h)
  plot(x, y, w, h, lv, 3, function(t) return L.sample(v, t) end)
end

-- The SPD cell as a scope. It draws the wave that is actually selected, at
-- the rate SPD and MULT actually give it, scrolling in real time -- so the
-- cell answers "how fast, and moving how" rather than showing a number and a
-- generic sine. The window is a fixed two seconds, so a faster LFO fits more
-- cycles into the same box, which is what speed looks like.
local SCOPE_WINDOW = 2.0

function W.lfoscope(x, y, w, h, sp, v, lv, extra)
  extra = extra or {}
  local hz = L.hz(v, extra.mult, extra.bpm or 120)
  local cycles = util.clamp(hz * SCOPE_WINDOW, 0.08, 9)
  local phase = ((extra.now or 0) * hz) % 1
  local wave = extra.wave or 0
  axis(x, y, w, h)
  plot(x, y, w, h, lv, 3, function(t)
    return L.sample(wave, (t * cycles) - phase)
  end)
end

-- ---------------------------------------------------------------- noise

-- how much noise there is: a field whose height is the amount, inside the
-- dotted ceiling that is all of it
function W.noise(x, y, w, h, sp, v, lv, extra)
  local p = pos(sp, v)
  local rnd = noiser(seed_of(0.137, extra))
  ground(x, y, w, h)
  ceiling(x, y, w)
  -- the height is curved, not proportional: at a fifth of the way up a
  -- linear field was one pixel everywhere, which is a picture of a straight
  -- line rather than of a little noise
  local a0 = math.sqrt(p) * (h - 2)
  screen.level(lv)
  for i = 0, w - 1, 2 do
    local a = (0.35 + (rnd() * 0.65)) * a0
    if a >= 0.5 then
      screen.move(x + i, y + h - 1)
      screen.line(x + i, y + h - 1 - a)
    end
  end
  screen.stroke()
end

-- Noise character as one bipolar macro: coarse and dark on the left, fine
-- and bright on the right, which is what the engine actually does with it.
function W.ntone(x, y, w, h, sp, v, lv, extra)
  local p = pos(sp, v)
  local gap = 1 + util.round((1 - p) * 4)
  local rnd = noiser(seed_of(0.443, extra))
  hline(x, y + math.floor(h / 2), w, LV_DIM)
  screen.level(lv)
  for i = 0, w - 1, gap do
    local a = (0.35 + (rnd() * 0.65)) * (h - 1)
    screen.move(x + i, y + math.floor(h / 2) - (a / 2))
    screen.line(x + i, y + math.floor(h / 2) + (a / 2))
  end
  screen.stroke()
end

-- A balance, drawn as the two things being balanced: the shell along the top
-- and the wires along the bottom, trading height. Neither is a picture of an
-- amount of noise, which is what NOISE beside it is for.
function W.snap(x, y, w, h, sp, v, lv, extra)
  local p = pos(sp, v)
  local mid = y + math.floor(h / 2)
  local rnd = noiser(seed_of(0.719, extra))
  hline(x, mid, w, LV_DIM)
  plot(x, y, w, (mid - y) * 2, lv, 4, function(t)
    return math.sin(t * 6 * math.pi) * (1 - p) * math.exp(-t * 1.6)
  end)
  screen.level(lv)
  for i = 0, w - 1, 2 do
    local a = math.max(1, rnd() * p * (y + h - 1 - mid))
    screen.move(x + i, mid + 1)
    screen.line(x + i, mid + 1 + a)
  end
  screen.stroke()
end

-- the sharp front of a drum: the transient, against the ceiling that is all
-- the transient it could have
function W.click(x, y, w, h, sp, v, lv)
  local a = math.sqrt(pos(sp, v)) * (h - 2)
  ground(x, y, w, h)
  ceiling(x, y, w)
  screen.level(lv)
  screen.move(x, y + h - 1)
  screen.line(x + 2, y + h - 1 - a)
  screen.line(x + 4, y + h - 1 - (a * 0.30))
  screen.line(x + 7, y + h - 1 - (a * 0.08))
  screen.line(x + w - 1, y + h - 1)
  screen.stroke()
end

-- --------------------------------------------------------------- spectra

-- Where the partials are. At rest they sit on the harmonic series, evenly
-- spaced with a smooth rolloff; SPREAD walks them off it, so the picture
-- goes from a comb to a scatter -- which is the whole of the difference
-- between a bell and a cymbal.
local SPREAD_OFF = { 0, 0.34, -0.26, 0.52, -0.41, 0.22, 0.45, -0.31 }

function W.spectrum(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local n = 6
  ground(x, y, w, h)
  screen.level(lv)
  for i = 1, n do
    local px = ((i - 0.5) / n) + (p * SPREAD_OFF[i] / n * 1.7)
    -- a cluster, not a harmonic rolloff: the partials are comparable in
    -- level, so what the eye reads is where they are rather than the first
    -- one towering over the rest
    local a = (0.5 + (0.5 / (i ^ 0.5)))
              * (1 - (p * 0.35 * (((i % 2) == 0) and 1 or 0)))
    local ix = util.round(util.clamp(px, 0, 1) * (w - 1))
    screen.rect(x + ix, y + h - 1 - util.round(a * (h - 2)), 1,
      util.round(a * (h - 2)))
  end
  screen.fill()
end

-- a resonant band sitting where the value puts it, which is what a drum's
-- TONE control moves rather than a corner frequency
function W.band(x, y, w, h, sp, v, lv)
  local c = x + util.round(pos(sp, v) * (w - 3)) + 1
  ground(x, y, w, h)
  screen.level(lv)
  screen.move(x, y + h - 2)
  screen.line(c - 4, y + h - 3)
  screen.line(c, y + 1)
  screen.line(c + 4, y + h - 3)
  screen.line(x + w - 1, y + h - 2)
  screen.stroke()
end

-- Resonance is the peak, and only the peak: a flat response with a horn
-- growing out of it at a corner that stays put, because where the corner is
-- belongs to CUTOFF and how the filter is shaped belongs to TYPE.
function W.res(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local c = x + util.round(w * 0.62)
  local top = y + h - 2 - util.round(math.sqrt(p) * (h - 3))
  ground(x, y, w, h)
  ceiling(x, y, w)
  screen.level(lv)
  screen.move(x, y + h - 3)
  screen.line(c - 3, y + h - 3)
  screen.line(c, top)
  screen.line(c + 2, y + h - 2)
  screen.line(x + w - 1, y + h - 1)
  screen.stroke()
end

-- Where the corner is, on a rail that is the range it can be anywhere on --
-- the passband behind it, and the corner itself as the mark. Not a second
-- drawing of the response: TYPE has that.
function W.cutoff(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local n = util.round(p * (w - 2))
  ground(x, y, w, h)
  screen.level(LV_TICK)
  for i = 0, 4 do screen.rect(x + util.round(i * (w - 2) / 4), y + h - 3, 1, 2) end
  screen.fill()
  screen.level(LV_GHOST)
  screen.rect(x, y + h - 4, w - 1, 1)
  screen.fill()
  screen.level(lv)
  screen.rect(x, y + h - 5, math.max(1, n), 4)
  screen.fill()
  vline(x + util.clamp(n, 0, w - 2), y, h - 1, lv)
end

-- How much the note the track is playing carries the corner with it: keys
-- along the bottom, and the slope the corner takes across them.
function W.ktrk(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  ground(x, y, w, h)
  screen.level(LV_TICK)
  for i = 0, 6 do screen.rect(x + util.round(i * (w - 2) / 6), y + h - 3, 1, 2) end
  screen.fill()
  screen.level(lv)
  screen.move(x, y + h - 4)
  screen.line(x + w - 1, y + h - 4 - util.round(p * (h - 5)))
  screen.stroke()
end

-- The filter type as its own symbol, and nothing else's. This used to draw
-- the whole response with a resonant peak on it, which made it a second,
-- worse picture of RES -- and put it next to CUTOFF drawing the same peak
-- again, so two cells said one thing and neither said its own. What is left
-- is the shape of the type with nothing resonating.
function W.ftype(x, y, w, h, sp, v, lv)
  local top, bot = y + 1, y + h - 2
  local function curve(x0, x1, y0, y1, n, e)
    for i = 1, n do
      local t = i / n
      screen.line(x0 + (t * (x1 - x0)), y0 + ((y1 - y0) * (t ^ e)))
    end
  end
  ground(x, y, w, h)
  screen.level(lv)
  if v == 1 then          -- BP: one band, rounded, no spike on top of it
    screen.move(x, bot)
    for i = 1, 14 do
      local t = i / 14
      screen.line(x + (t * (w - 1)), bot - ((bot - top) * (math.sin(t * math.pi) ^ 1.3)))
    end
  elseif v == 2 then      -- HP: a rise into flat
    screen.move(x, bot)
    curve(x, x + (w * 0.55), bot, top, 8, 1.7)
    screen.line(x + w - 1, top)
  elseif v == 3 then      -- COMB: evenly spaced notches
    screen.move(x, bot)
    for i = 1, 20 do
      local t = i / 20
      screen.line(x + (t * (w - 1)),
        bot - ((bot - top) * math.abs(math.sin(t * 4 * math.pi))))
    end
  else                    -- LP: flat, then a rolloff
    screen.move(x, top)
    screen.line(x + (w * 0.45), top)
    curve(x + (w * 0.45), x + w - 1, top, bot, 8, 1.7)
  end
  screen.stroke()
end

-- A shelf coming down off the top of the band, and the same thing off the
-- bottom. These are cuts rather than filter types, so they draw the corner
-- moving rather than a shape that stands still.
local function shelf(x, y, w, h, p, lv, from_hi)
  local top, bot = y + 1, y + h - 2
  local k = 0.15 + (p * 0.7)
  ground(x, y, w, h)
  ceiling(x, y, w)
  screen.level(lv)
  if from_hi then
    local c = x + ((1 - k) * (w - 1))
    screen.move(x, top)
    screen.line(c, top)
    for i = 1, 8 do
      local t = i / 8
      screen.line(c + (t * (x + w - 1 - c)), top + ((bot - top) * (t ^ 1.7)))
    end
  else
    local c = x + (k * (w - 1))
    screen.move(x, bot)
    for i = 1, 8 do
      local t = i / 8
      screen.line(x + (t * (c - x)), bot - ((bot - top) * (t ^ 1.7)))
    end
    screen.line(x + w - 1, top)
  end
  screen.stroke()
end

function W.hicut(x, y, w, h, sp, v, lv) shelf(x, y, w, h, pos(sp, v), lv, true) end
function W.locut(x, y, w, h, sp, v, lv) shelf(x, y, w, h, pos(sp, v), lv, false) end

-- ------------------------------------------------------------- structural

-- Operator routing, drawn from the same tables the engine patches. Each
-- operator sits at its depth in the chain -- carriers on the baseline,
-- modulators stacked above -- with a line to whatever it modulates.
local function draw_algo(x, y, w, h, def, lv)
  local depth = {}
  for i = 1, def.ops do depth[i] = 0 end
  -- longest path to an output; with at most four operators a few passes settle
  for _ = 1, def.ops do
    for _, e in ipairs(def.edges) do
      if depth[e[1]] < depth[e[2]] + 1 then depth[e[1]] = depth[e[2]] + 1 end
    end
  end
  local maxd = 0
  for i = 1, def.ops do maxd = math.max(maxd, depth[i]) end

  local bw, bh = 5, 3
  local step = math.floor((w - bw) / math.max(1, def.ops - 1))
  local function cx(i) return x + ((i - 1) * step) end
  local function cy(i)
    if maxd == 0 then return y + h - 1 - bh end
    return y + h - 1 - bh - (depth[i] * ((h - 2 - bh) / maxd))
  end

  ground(x, y, w, h)
  screen.level(math.max(3, lv - 6))
  for _, e in ipairs(def.edges) do
    screen.move(cx(e[1]) + (bw / 2), cy(e[1]) + bh)
    screen.line(cx(e[2]) + (bw / 2), cy(e[2]))
  end
  screen.stroke()

  for i = 1, def.ops do
    local carrier = false
    for _, o in ipairs(def.outs) do if o == i then carrier = true end end
    screen.level(lv)
    screen.rect(cx(i), cy(i), bw, bh)
    if carrier then screen.fill() else screen.stroke() end
  end
end

function W.algo4(x, y, w, h, sp, v, lv)
  draw_algo(x, y, w, h, C.ALGO4[v + 1] or C.ALGO4[1], lv)
end

-- ------------------------------------------------------------- sequencer

function W.len(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  ground(x, y, w, h)
  screen.level(LV_GHOST)
  screen.rect(x, y + h - 4, w - 1, 1)
  screen.fill()
  screen.level(lv)
  screen.rect(x, y + h - 5, math.max(1, util.round((w - 1) * p)), 4)
  screen.fill()
  screen.level(LV_TICK)
  for i = 1, 3 do screen.rect(x + util.round(i * (w - 1) / 4), y + 1, 1, 3) end
  screen.fill()
end

-- How many steps go by in a beat. A row of pulses at the rate the setting
-- actually gives, so /4 is three sparse ticks and x8 is a picket fence.
function W.pulse(x, y, w, h, sp, v, lv)
  local r = C.SPEEDS[(util.round(v or 0)) + 1] or 1
  local n = util.clamp(util.round(r * 4), 1, 13)
  ground(x, y, w, h)
  screen.level(LV_TICK)
  for i = 0, 3 do screen.rect(x + util.round(i * (w - 1) / 4), y + h - 2, 1, 1) end
  screen.fill()
  screen.level(lv)
  local pitch = (w - 1) / n
  for i = 0, n - 1 do
    screen.rect(x + util.round(i * pitch), y + 1, math.max(1, math.min(2, math.floor(pitch) - 1)), h - 2)
  end
  screen.fill()
end

-- the metre: one tick a beat, the downbeat taller, the ticks closer together
-- as the beat unit gets shorter -- so 7/8 looks tighter and busier than 3/4
function W.tsig(x, y, w, h, sp, v, lv)
  local ts = C.TSIG[util.round(v) + 1] or C.TSIG[1]
  local pitch = (w - 1) / ts.num
  local tall = h - 1
  local short = util.round((h - 1) * math.min(1, 4 / ts.den) * 0.75) + 1
  ground(x, y, w, h)
  screen.level(lv)
  for i = 1, ts.num do
    local px = x + util.round((i - 1) * pitch)
    local hh = (i == 1) and tall or short
    if px <= x + w - 1 then screen.rect(px, y + h - 1 - hh, 1, hh) end
  end
  screen.fill()
end

-- Which way the playhead goes, drawn as the walk it takes rather than as a
-- word. RND scatters; BRN wanders, which is the difference between them.
function W.dir(x, y, w, h, sp, v, lv)
  local mid = y + math.floor(h / 2)
  local x1 = x + w - 1
  if v <= 2 then hline(x, mid, w, LV_DIM) else ground(x, y, w, h) end
  screen.level(lv)
  local function head(px, right)
    screen.move(px + (right and -3 or 3), mid - 3)
    screen.line(px, mid)
    screen.line(px + (right and -3 or 3), mid + 3)
    screen.stroke()
  end
  if v == 0 then head(x1, true)
  elseif v == 1 then head(x, false)
  elseif v == 2 then head(x1, true); head(x, false)
  elseif v == 3 then                        -- RND: unrelated steps
    local rnd = noiser(0.61)
    for i = 0, 5 do
      local a = 1 + util.round(rnd() * (h - 3))
      screen.rect(x + util.round(i * (w - 2) / 5), y + h - 1 - a, 2, a)
    end
    screen.fill()
  else                                      -- BRN: a walk, one step at a time
    local rnd = noiser(0.29)
    local yy = mid
    screen.move(x, yy)
    for i = 1, 8 do
      yy = util.clamp(yy + ((rnd() < 0.5) and -2 or 2), y + 1, y + h - 2)
      screen.line(x + util.round(i * (w - 1) / 8), yy)
    end
    screen.stroke()
  end
end

-- How often the step happens: eight of them, and how many survive.
function W.prob(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local n = 8
  local lit = util.round(p * n)
  local pitch = (w - 1) / n
  local bw = math.max(1, math.floor(pitch) - 1)
  ground(x, y, w, h)
  screen.level(LV_GHOST)
  for i = 0, n - 1 do
    if i >= lit then screen.rect(x + util.round(i * pitch), y + h - 3, bw, 2) end
  end
  screen.fill()
  screen.level(lv)
  for i = 0, n - 1 do
    if i < lit then screen.rect(x + util.round(i * pitch), y + 1, bw, h - 2) end
  end
  screen.fill()
end

-- Two steps, and where the second one actually falls. Swing is a step moving
-- off the grid, so the grid is drawn and the step is drawn off it.
function W.swing(x, y, w, h, sp, v, lv)
  local p = (pos(sp, v) * 2) - 1
  local a = x + util.round(w * 0.12)
  local grid = x + util.round(w * 0.52)
  local b = util.clamp(grid + util.round(p * (w * 0.30)), x, x + w - 3)
  ground(x, y, w, h)
  screen.level(LV_TICK)
  for i = 0, h - 3, 2 do screen.rect(grid, y + i, 1, 1) end
  screen.fill()
  screen.level(lv)
  screen.rect(a, y + 1, 3, h - 2)
  screen.rect(b, y + 1, 3, h - 2)
  screen.fill()
end

-- how many times the step is struck, evenly across the time it has
function W.ratchet(x, y, w, h, sp, v, lv)
  local n = util.clamp(util.round(v), 1, 8)
  ground(x, y, w, h)
  screen.level(lv)
  for i = 0, n - 1 do
    screen.rect(x + util.round(i * (w - 2) / n), y + 1, 2, h - 2)
  end
  screen.fill()
end

-- the notes of a chord laid out in time rather than on top of each other
function W.strum(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  ground(x, y, w, h)
  screen.level(lv)
  for k = 0, 3 do
    local px = util.round(k * p * (w - 3) / 3)
    screen.rect(x + px, y + 1 + k, 2, h - 2 - k)
  end
  screen.fill()
end

-- how many pulses a held step lasts: the cell divided into that many blocks,
-- so it reads as a subdivision rather than as a number
function W.hold_n(x, y, w, h, sp, v, lv)
  local n = util.clamp(util.round(v), 1, 16)
  local pitch = (w - 1) / n
  ground(x, y, w, h)
  screen.level(lv)
  for i = 0, n - 1 do
    screen.rect(x + util.round(i * pitch), y + 1, math.max(1, math.floor(pitch) - 1), h - 2)
  end
  screen.fill()
end

-- what the pulses of a held step do: one plateau, four even hits, four
-- climbing, four falling away
function W.htype(x, y, w, h, sp, v, lv)
  ground(x, y, w, h)
  screen.level(lv)
  if v == 0 then
    screen.move(x, y + h - 1)
    screen.line(x, y + 1)
    screen.line(x + w - 2, y + 1)
    screen.line(x + w - 2, y + h - 1)
    screen.stroke()
    return
  end
  local n = 4
  local pitch = (w - 1) / n
  for i = 1, n do
    local a = 1
    if v == 2 then a = i / n elseif v == 3 then a = 1 - ((i - 1) / n) end
    local hh = math.max(1, util.round(a * (h - 2)))
    screen.rect(x + util.round((i - 1) * pitch), y + h - 1 - hh,
      math.max(1, math.floor(pitch) - 1), hh)
  end
  screen.fill()
end

-- ---------------------------------------------------------------- harmony

-- which register the track plays in, drawn as registers
function W.octave(x, y, w, h, sp, v, lv)
  local n = (sp.max - sp.min) + 1
  local i = util.round(v - sp.min)
  local pitch = (w - 1) / n
  local bw = math.max(1, math.floor(pitch) - 1)
  ground(x, y, w, h)
  screen.level(LV_GHOST)
  for k = 0, n - 1 do
    if k ~= i then screen.rect(x + util.round(k * pitch), y + h - 3, bw, 2) end
  end
  screen.fill()
  screen.level(lv)
  local hh = 2 + util.round((i / math.max(1, n - 1)) * (h - 4))
  screen.rect(x + util.round(i * pitch), y + h - 1 - hh, bw, hh)
  screen.fill()
end

-- chord voicing drawn as the notes it actually stacks, at the intervals it
-- actually stacks them at
function W.chord(x, y, w, h, sp, v, lv)
  ground(x, y, w, h)
  local set = (v > 0) and C.CHORD_IV[v] or nil
  if not set then
    screen.level(LV_GHOST)
    screen.rect(x, y + h - 3, 5, 2)
    screen.fill()
    return
  end
  local hi = 1
  for _, n in ipairs(set) do hi = math.max(hi, n) end
  screen.level(lv)
  for i, n in ipairs(set) do
    screen.rect(x + ((i - 1) * 3), y + h - 2 - util.round((n / hi) * (h - 3)), 6, 1)
  end
  screen.fill()
end

-- ROOT and SCALE are the song's key, so they draw the same twelve chromatic
-- slots and differ only in what stands up out of them: one note for the root,
-- the scale's own degrees for the scale.
local function chroma(x, y, w, h)
  ground(x, y, w, h)
  screen.level(LV_TICK)
  for i = 0, 11 do screen.rect(x + util.round(i * (w - 2) / 11), y + h - 3, 1, 2) end
  screen.fill()
end

function W.root(x, y, w, h, sp, v, lv)
  chroma(x, y, w, h)
  screen.level(lv)
  screen.rect(x + util.round(pos(sp, v) * 11) * (w - 2) / 11, y, 2, h - 1)
  screen.fill()
end

-- `extra.intervals` is the scale's own interval list, so the cell shows which
-- notes are in the scale rather than how far down a list of names it sits
function W.scale(x, y, w, h, sp, v, lv, extra)
  chroma(x, y, w, h)
  local iv = extra and extra.intervals
  if not iv then return end
  screen.level(lv)
  for _, n in ipairs(iv) do
    local i = n % 12
    local tall = (n % 12) == 0
    screen.rect(x + util.round(i * (w - 2) / 11), y + (tall and 0 or 2),
      1, (tall and (h - 1) or (h - 3)))
  end
  screen.fill()
end

-- ----------------------------------------------------------------- master

local function tanh(z)
  local e = math.exp(2 * z)
  return (e - 1) / (e + 1)
end

function W.sat(x, y, w, h, sp, v, lv)
  local d = 1 + (pos(sp, v) * 10)
  axis(x, y, w, h)
  plot(x, y, w, h, LV_GHOST, 1, function(t) return (t * 2) - 1 end)
  plot(x, y, w, h, lv, 2, function(t)
    return tanh(((t * 2) - 1) * d) / tanh(d)
  end)
end

function W.bits(x, y, w, h, sp, v, lv)
  local n = math.max(2, math.floor(10 - (pos(sp, v) * 8)))
  ground(x, y, w, h)
  screen.level(LV_GHOST)
  screen.move(x, y + h - 1); screen.line(x + w - 1, y + 1)
  screen.stroke()
  screen.level(lv)
  for i = 0, n - 1 do
    local xs = x + util.round(i * (w - 1) / n)
    local ys = y + h - 1 - util.round((i + 1) * (h - 2) / n)
    screen.rect(xs, ys, math.max(1, util.round((w - 1) / n)), 1)
  end
  screen.fill()
end

-- a rate: the same wave, cycling faster as the value climbs
function W.rate(x, y, w, h, sp, v, lv)
  local n = 1 + (pos(sp, v) * 7)
  axis(x, y, w, h)
  plot(x, y, w, h, lv, 4, function(t) return math.sin(t * n * 2 * math.pi) end)
end

-- a depth: the same rate, reaching further as the value climbs
function W.depth(x, y, w, h, sp, v, lv)
  local d = pos(sp, v)
  axis(x, y, w, h)
  screen.level(LV_TICK)
  for i = 0, w - 1, 3 do
    screen.rect(x + i, y, 1, 1); screen.rect(x + i, y + h - 2, 1, 1)
  end
  screen.fill()
  plot(x, y, w, h, lv, 4, function(t) return math.sin(t * 4 * math.pi) * d end)
end

function W.wow(x, y, w, h, sp, v, lv, extra)
  local d = pos(sp, v)
  local ph = (extra and extra.live and extra.now) and (extra.now * 2) or 0
  axis(x, y, w, h)
  plot(x, y, w, h, lv, 2, function(t)
    return ((math.sin((t * 7.5) + ph) * 0.7) + (math.sin((t * 23) + ph) * 0.3)) * d
  end)
end

-- A delay time is a gap between repeats, not a shape that decays. Drawn as an
-- envelope it said "something fades out", which is FEEDBK's job and is the one
-- thing TIME does not control. This is the input and its echoes, spaced
-- further apart as the time grows -- so a short delay is a dense run of taps
-- and a long one is two or three.
function W.dtime(x, y, w, h, sp, v, lv)
  local gap = math.max(2, 2 + (pos(sp, v) * (w - 5)))
  ground(x, y, w, h)
  screen.level(lv)
  screen.move(x, y + h - 1)
  screen.line(x, y + 1)
  screen.stroke()
  local a, px = 0.75, x + gap
  while px < x + w - 1 do
    screen.level(math.max(3, util.round(lv * a)))
    screen.move(px, y + h - 1)
    screen.line(px, y + h - 1 - ((h - 2) * a))
    screen.stroke()
    px, a = px + gap, a * 0.72
  end
end

-- How long the repeats last, which is a different question from how far
-- apart they are: the taps are evenly spaced here and it is the tail that
-- grows, with the dotted rest of the cell as what is still available.
function W.fbk(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local decay = 0.12 + (p * 0.83)
  ground(x, y, w, h)
  ceiling(x, y, w)
  local a = 1
  for i = 0, 6 do
    local px = x + util.round(i * (w - 2) / 6)
    if a > 0.05 then
      screen.level(math.max(3, util.round(lv * a)))
      screen.move(px, y + h - 1)
      screen.line(px, y + h - 1 - ((h - 2) * a))
      screen.stroke()
    end
    a = a * decay
  end
end

-- pitch-shifted copies of the tail folded back in: the copies, stepping up
function W.shim(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local n = 1 + util.round(p * 4)
  ground(x, y, w, h)
  screen.level(LV_GHOST)
  for i = 0, 4 do screen.rect(x + util.round(i * (w - 3) / 4), y + h - 2, 2, 1) end
  screen.fill()
  screen.level(lv)
  for i = 0, n - 1 do
    local hh = 1 + util.round((i / 4) * (h - 3))
    screen.rect(x + util.round(i * (w - 3) / 4), y + h - 1 - hh, 2, hh)
  end
  screen.fill()
end

-- the repeats crossing over: taps above the line, then below it
function W.ping(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local mid = y + math.floor(h / 2)
  axis(x, y, w, h)
  screen.level(lv)
  local a = 1
  for i = 0, 5 do
    local px = x + util.round(i * (w - 2) / 5)
    local reach = util.round(((mid - y - 1) * a) * (0.15 + (p * 0.85)))
    if ((i % 2) == 0) then
      screen.rect(px, mid - reach, 1, math.max(1, reach))
    else
      screen.rect(px, mid + 1, 1, math.max(1, reach))
    end
    a = a * 0.82
  end
  screen.fill()
end

function W.tilt(x, y, w, h, sp, v, lv)
  local t = (pos(sp, v) * 2) - 1
  local n = 7
  ground(x, y, w, h)
  screen.level(LV_TICK)                   -- the pivot it turns about
  for i = 0, h - 2, 2 do screen.rect(x + util.round((w - 1) / 2), y + i, 1, 1) end
  screen.fill()
  screen.level(lv)
  for i = 0, n - 1 do
    local f = (n == 1) and 0.5 or (i / (n - 1))
    local a = 0.45 + (0.5 * t * ((f * 2) - 1))
    local hh = math.max(1, util.round(util.clamp(a, 0.06, 1) * (h - 2)))
    screen.rect(x + util.round(i * (w - 2) / (n - 1)), y + h - 1 - hh, 1, hh)
  end
  screen.fill()
end

-- A lossy codec does not shave the top off a band, it throws pieces of the
-- signal away and puts the rest back slightly wrong -- so the glyph is one
-- whole shape coming apart. At zero it is a clean wave. As the value climbs
-- the wave breaks into fragments that slip out of line, and then fragments
-- start going missing altogether.
function W.loss(x, y, w, h, sp, v, lv, extra)
  local p = pos(sp, v)
  local mid = y + (h / 2)
  local amp = (h / 2) - 1
  local rnd = noiser(seed_of(0.271, extra))
  local function at(i, slip)
    return util.clamp(mid - (math.sin((i / w) * 2 * math.pi) * amp) + slip,
                      y, y + h - 1)
  end
  axis(x, y, w, h)
  screen.level(lv)
  local i = 0
  while i < w do
    local run = 2 + math.floor(rnd() * 3)
    local gone = rnd() < (p * 0.5)
    local slip = (rnd() - 0.5) * p * (h - 1)
    if not gone then
      local e = math.min(w - 1, i + run)
      screen.move(x + i, at(i, slip))
      for k = i + 1, e do screen.line(x + k, at(k, slip)) end
      screen.stroke()
    end
    i = i + run
  end
end

-- digital dropout: a run of samples repeated, with a hole punched in it
function W.glitch(x, y, w, h, sp, v, lv, extra)
  local p = pos(sp, v)
  local rnd = noiser(seed_of(0.317, extra))
  ground(x, y, w, h)
  screen.level(lv)
  local held, hy = 0, (h - 2) * 0.5
  for i = 0, w - 1 do
    local r = rnd()
    if held <= 0 then
      held = 1 + math.floor(r * p * 6)
      hy = (0.15 + (r * 0.7)) * (h - 2)
    end
    held = held - 1
    if r > (0.94 - (p * 0.3)) then hy = 0 end
    if hy > 0 then
      screen.move(x + i, y + h - 1)
      screen.line(x + i, y + h - 1 - hy)
    end
  end
  screen.stroke()
end

-- the knee, against the line it would have been without one
function W.comp(x, y, w, h, sp, v, lv)
  local r = pos(sp, v)
  local base, top = y + h - 1, y + 1
  ground(x, y, w, h)
  screen.level(LV_GHOST)
  screen.move(x, base); screen.line(x + w - 1, top)
  screen.stroke()
  local kx, ky = x + (w * 0.45), base - ((base - top) * 0.45)
  screen.level(lv)
  screen.move(x, base)
  screen.line(kx, ky)
  screen.line(x + w - 1, ky - ((base - top) * 0.55 * (1 - r)))
  screen.stroke()
end

-- ------------------------------------------------------- joined envelope
--
-- An envelope generator is one shape, not four unrelated pictures, so the
-- ADSR is drawn once across the whole run of cells it is spread over and
-- each cell simply has part of it passing through. A long attack really does
-- push the decay into the next box, which is the thing worth seeing.
--
-- `segs` is the run in order, each { kind, p } with p the 0..1 position of
-- that cell's value. A "sus" is a level rather than a time, so it takes a
-- fixed slice of the width and sets the height everything after it lands on.

local ENV_MINW = 0.14   -- a segment at zero is still a visible corner

local function env_layout(segs, w)
  local wt, total = {}, 0
  for i, sg in ipairs(segs) do
    wt[i] = (sg.kind == "sus") and 0.85 or (ENV_MINW + sg.p)
    total = total + wt[i]
  end
  for i = 1, #segs do wt[i] = (wt[i] / total) * w end
  return wt
end

-- the points of one segment, given where it starts and at what level
local function env_seg(sg, x0, wseg, sus, lvl, y, h)
  local pts, n = {}, 9
  local function at(t, v) pts[#pts + 1] = { x0 + (t * wseg), y + h - 1 - (v * (h - 1)) } end
  at(0, lvl)
  if sg.kind == "atk" then
    for i = 1, n do local t = i / n; at(t, lvl + ((1 - lvl) * (t ^ 0.55))) end
    return pts, 1
  elseif sg.kind == "dec" then
    for i = 1, n do local t = i / n; at(t, sus + ((lvl - sus) * ((1 - t) ^ 2))) end
    return pts, sus
  elseif sg.kind == "rel" then
    for i = 1, n do local t = i / n; at(t, lvl * ((1 - t) ^ 2)) end
    return pts, 0
  end
  at(1, lvl)                      -- sus / hold: a plateau
  return pts, lvl
end

-- `sel` is the index of the segment the cursor is on, drawn bright over the
-- dim whole. `hot` is 0..1 and lifts the whole shape on a trigger, so a page
-- with an envelope on it has a pulse while the sequencer is playing.
function W.envelope(x, y, w, h, segs, sel, hot)
  local sus = 0
  for _, sg in ipairs(segs) do if sg.kind == "sus" then sus = sg.p end end

  local wt = env_layout(segs, w)
  local runs, cut = {}, {}
  local cx, lvl = x, 0
  for i, sg in ipairs(segs) do
    local pts
    pts, lvl = env_seg(sg, cx, wt[i], sus, lvl, y, h)
    runs[i] = pts
    cx = cx + wt[i]
    cut[i] = cx
  end

  -- baseline, then the boundary between one segment and the next, so the
  -- cells still read as cells even though the shape crosses them
  ground(x, y, w, h)
  ceiling(x, y, w)
  screen.level(LV_TICK)
  for i = 1, #segs - 1 do screen.rect(cut[i], y + h - 3, 1, 2) end
  screen.fill()

  local rest = 6 + util.round((hot or 0) * 8)
  local function stroke(i, lv)
    local pts = runs[i]
    screen.level(lv)
    screen.move(pts[1][1], pts[1][2])
    for k = 2, #pts do screen.line(pts[k][1], pts[k][2]) end
    screen.stroke()
  end
  for i = 1, #segs do stroke(i, rest) end
  if sel and runs[sel] then stroke(sel, 15) end
end

-- ------------------------------------------------------------------ step

-- A lock-only cell, with nothing held: the control is there but there is
-- nothing for it to be turned on, so it is struck out rather than absent.
function W.strike(x, y, w, h)
  screen.level(3)
  screen.move(x + 2, y + 1)
  screen.line(x + w - 2, y + h - 2)
  screen.move(x + w - 2, y + 1)
  screen.line(x + 2, y + h - 2)
  screen.stroke()
end

function W.draw(name, x, y, w, h, sp, v, lv, extra)
  local f = W[name] or W.bar
  f(x, y, w, h, sp, v, lv, extra)
end

return W
