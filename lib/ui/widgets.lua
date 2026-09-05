-- widgets.lua
--
-- One micro-glyph per parameter cell. Each draws inside a 28x10 box and says
-- something true about the value -- an envelope shows its actual shape, a
-- waveform cell shows the waveform, a ratio cell shows the ratio. The point
-- is that a page reads as a picture of the sound, not a column of numbers.

local S = include("tahned/lib/core/spec")
local C = include("tahned/lib/instruments/common")
local L = include("tahned/lib/core/lfo")

local W = {}

local function pos(sp, v) return S.unit_pos(sp, v) end

-- connected plot of f(t) over t in 0..1, f returning -1..1. Sparse pixels
-- read as noise at this size; a line reads as a shape.
local function plot(x, y, w, h, lv, over, f)
  screen.level(lv)
  local n = math.max(2, math.floor(w * (over or 1)))
  local mid = y + (h / 2)
  local amp = (h / 2) - 0.5
  screen.move(x, mid - (f(0) * amp))
  for i = 1, n do
    local t = i / n
    screen.line(x + (t * w), mid - (f(t) * amp))
  end
  screen.stroke()
end

local function frame_line(x, y, w, lv)
  screen.level(lv)
  screen.move(x, y + 0.5)
  screen.line(x + w, y + 0.5)
  screen.stroke()
end

-- ---------------------------------------------------------------- generic

function W.bar(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  screen.level(2)
  screen.rect(x, y + h - 3, w, 2)
  screen.fill()
  screen.level(lv)
  screen.rect(x, y + h - 3, math.max(1, w * p), 2)
  screen.fill()
end

function W.bi(x, y, w, h, sp, v, lv)
  local c = x + (w / 2)
  local p = (pos(sp, v) * 2) - 1
  screen.level(2)
  screen.rect(x, y + h - 3, w, 2)
  screen.fill()
  screen.level(lv)
  if p >= 0 then screen.rect(c, y + h - 3, math.max(1, (w / 2) * p), 2)
  else screen.rect(c + ((w / 2) * p), y + h - 3, math.max(1, (w / 2) * -p), 2) end
  screen.fill()
  screen.level(15)
  screen.rect(c, y + h - 4, 1, 4)
  screen.fill()
end

function W.send(x, y, w, h, sp, v, lv)
  W.bar(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  if p > 0.02 then
    screen.level(lv)
    screen.move(x + (w * p) - 3, y + h - 6)
    screen.line(x + (w * p), y + h - 4)
    screen.line(x + (w * p) - 3, y + h - 2)
    screen.stroke()
  end
end

function W.pan(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  frame_line(x, y + h - 4, w, 2)
  screen.level(lv)
  screen.rect(x + util.clamp(w * p - 1, 0, w - 3), y + h - 6, 3, 5)
  screen.fill()
end

-- ---------------------------------------------------------------- shapes

-- Envelope segments are drawn as the segment, going the way it goes: an
-- attack climbs, a decay or release falls. The value moves the knee across
-- the cell, so a long segment reaches the far side and a short one is over
-- in the first few pixels. Curves are fixed exponentials, matching the
-- engine -- there is nothing left to draw a curve control for.

-- attack: rises off the floor, knee pushed right as the time grows
function W.atk(x, y, w, h, sp, v, lv)
  local n, e = 12, w * (0.12 + (pos(sp, v) * 0.88))
  screen.level(lv)
  screen.move(x, y + h)
  for i = 1, n do
    local t = i / n
    screen.line(x + (t * e), y + h - (h * (t ^ 0.5)))
  end
  screen.line(x + w, y)
  screen.stroke()
end

-- decay / release: falls from the top, tail stretched right as the time grows
function W.rel(x, y, w, h, sp, v, lv)
  local n, e = 12, w * (0.12 + (pos(sp, v) * 0.88))
  screen.level(lv)
  screen.move(x, y)
  for i = 1, n do
    local t = i / n
    screen.line(x + (t * e), y + (h * (t ^ 0.5)))
  end
  screen.line(x + w, y + h)
  screen.stroke()
end

-- a plateau: level held for as long as the value says, then gone
function W.hold(x, y, w, h, sp, v, lv)
  local e = x + math.max(2, w * (0.08 + (pos(sp, v) * 0.92)))
  screen.level(lv)
  screen.move(x, y + h)
  screen.line(x, y)
  screen.line(e, y)
  screen.line(e, y + h)
  screen.line(x + w, y + h)
  screen.stroke()
end

-- rising or falling sweep
function W.sweep(x, y, w, h, sp, v, lv)
  local p = (pos(sp, v) * 2) - 1
  screen.level(lv)
  local n = 12
  screen.move(x, y + (h / 2) - ((h / 2) * p))
  for i = 1, n do
    local t = i / n
    screen.line(x + (t * w), y + (h / 2) - ((h / 2) * p * (1 - t)))
  end
  screen.stroke()
  frame_line(x, y + (h / 2), w, 1)
end

-- ---------------------------------------------------------------- OPL waves

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
  plot(x, y, w, h, lv, 2, function(t) return opl_sample(v, t % 1) end)
end

function W.lfowave(x, y, w, h, sp, v, lv)
  plot(x, y, w, h, lv, 2, function(t) return L.sample(v, t) end)
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

  -- a still centre line, so a very slow LFO still reads as a line that moves
  frame_line(x, y + (h / 2), w, 1)
  plot(x, y, w, h, lv, 3, function(t)
    return L.sample(wave, (t * cycles) - phase)
  end)
end

-- wavefolded sine: the glyph actually folds as the value rises
function W.fold(x, y, w, h, sp, v, lv)
  local amt = 1 + (pos(sp, v) * 8)
  plot(x, y, w, h, lv, 4, function(t)
    local s = math.sin(t * 2 * math.pi) * amt
    while s > 1 or s < -1 do
      if s > 1 then s = 2 - s else s = -2 - s end
    end
    return s
  end)
end

-- amplitude of a noise field
function W.noise(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local seed = 0.137
  screen.level(lv)
  for i = 0, w, 2 do
    seed = (seed * 9.13 + 0.271) % 1
    local a = seed * p * h
    screen.move(x + i, y + (h / 2) - (a / 2))
    screen.line(x + i, y + (h / 2) + (a / 2))
  end
  screen.stroke()
end

-- Noise character as one bipolar macro: coarse and dark on the left, fine
-- and bright on the right, which is what the engine actually does with it.
function W.ntone(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local gap = 1 + util.round((1 - p) * 5)
  local seed = 0.443
  screen.level(lv)
  for i = 0, w, gap do
    seed = (seed * 9.13 + 0.271) % 1
    local a = (0.3 + (seed * 0.7)) * h
    screen.move(x + i, y + (h / 2) - (a / 2))
    screen.line(x + i, y + (h / 2) + (a / 2))
  end
  screen.stroke()
end

local function tanh(z)
  local e = math.exp(2 * z)
  return (e - 1) / (e + 1)
end

function W.sat(x, y, w, h, sp, v, lv)
  local d = 1 + (pos(sp, v) * 10)
  screen.level(lv)
  screen.move(x, y + h)
  for i = 1, 12 do
    local t = (i / 12)
    local s = tanh(((t * 2) - 1) * d) / tanh(d)
    screen.line(x + (t * w), y + (h / 2) - (s * (h / 2 - 1)))
  end
  screen.stroke()
end

function W.bits(x, y, w, h, sp, v, lv)
  local n = math.max(2, math.floor(10 - (pos(sp, v) * 8)))
  screen.level(lv)
  for i = 0, n - 1 do
    local xs = x + (i * w / n)
    local ys = y + h - ((i + 1) * h / n)
    screen.rect(xs, ys, w / n, 1)
  end
  screen.fill()
end

-- a rate: the same wave, cycling faster as the value climbs
function W.rate(x, y, w, h, sp, v, lv)
  local n = 1 + (pos(sp, v) * 7)
  plot(x, y, w, h, lv, 3, function(t) return math.sin(t * n * 2 * math.pi) end)
end

function W.wow(x, y, w, h, sp, v, lv)
  local d = pos(sp, v)
  plot(x, y, w, h, lv, 2, function(t)
    return ((math.sin(t * 7.5) * 0.7) + (math.sin(t * 23) * 0.3)) * d
  end)
end

-- A delay time is a gap between repeats, not a shape that decays. Drawn as an
-- envelope it said "something fades out", which is FEEDBK's job and is the one
-- thing TIME does not control. This is the input and its echoes, spaced
-- further apart as the time grows -- so a short delay is a dense run of taps
-- and a long one is two or three.
function W.dtime(x, y, w, h, sp, v, lv)
  local gap = math.max(2, 2 + (pos(sp, v) * (w - 4)))
  frame_line(x, y + h, w, 2)
  screen.level(lv)
  screen.move(x, y + h)
  screen.line(x, y)
  screen.stroke()
  local a, px = 0.68, x + gap
  while px < x + w do
    screen.level(math.max(2, util.round(lv * a)))
    screen.move(px, y + h)
    screen.line(px, y + h - (h * a))
    screen.stroke()
    px, a = px + gap, a * 0.6
  end
end

function W.comp(x, y, w, h, sp, v, lv)
  local r = pos(sp, v)
  screen.level(lv)
  screen.move(x, y + h)
  screen.line(x + (w * 0.45), y + (h * 0.55))
  screen.line(x + w, y + (h * 0.55) - ((h * 0.55) * (1 - r)))
  screen.stroke()
end

-- The filter type as its own symbol, and nothing else's. This used to draw
-- the whole response with a resonant peak on it, which made it a second, worse
-- picture of RES -- and put it next to CUTOFF drawing the same peak again, so
-- two cells said one thing and neither said its own. What is left is the shape
-- of the type with nothing resonating: the corner is where it is because that
-- is where a symbol puts it, not because CUTOFF is anywhere near it.
function W.ftype(x, y, w, h, sp, v, lv)
  local top, bot = y + 0.5, y + h - 0.5
  local function curve(x0, x1, y0, y1, n, e)
    for i = 1, n do
      local t = i / n
      screen.line(x0 + (t * (x1 - x0)), y0 + ((y1 - y0) * (t ^ e)))
    end
  end
  screen.level(lv)
  if v == 1 then          -- BP: one band, rounded, no spike on top of it
    screen.move(x, bot)
    for i = 1, 14 do
      local t = i / 14
      screen.line(x + (t * w), bot - ((bot - top) * (math.sin(t * math.pi) ^ 1.3)))
    end
  elseif v == 2 then      -- HP: a rise into flat
    screen.move(x, bot)
    curve(x, x + (w * 0.55), bot, top, 8, 1.7)
    screen.line(x + w, top)
  elseif v == 3 then      -- COMB: evenly spaced notches
    screen.move(x, bot)
    for i = 1, 20 do
      local t = i / 20
      screen.line(x + (t * w),
        bot - ((bot - top) * math.abs(math.sin(t * 4 * math.pi))))
    end
  else                    -- LP: flat, then a rolloff
    screen.move(x, top)
    screen.line(x + (w * 0.45), top)
    curve(x + (w * 0.45), x + w, top, bot, 8, 1.7)
  end
  screen.stroke()
end

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

  local step, bw, bh = (def.ops > 3) and 7 or 9, 5, 3
  local function cx(i) return x + ((i - 1) * step) end
  local function cy(i)
    if maxd == 0 then return y + h - bh end
    return y + h - bh - (depth[i] * ((h - bh) / maxd))
  end

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

function W.ratio(x, y, w, h, sp, v, lv)
  screen.level(2)
  screen.rect(x, y + h - 2, w, 1)
  screen.fill()
  screen.level(lv)
  screen.rect(x + ((v / 15) * (w - 2)), y + h - 3, 2, 3)
  screen.fill()
end

function W.spectrum(x, y, w, h, sp, v, lv)
  local sp_amt = pos(sp, v)
  screen.level(lv)
  for i = 1, 6 do
    local px = x + ((i - 1) * (w / 6)) + (sp_amt * i * 0.8)
    if px < x + w then
      screen.move(px, y + h)
      screen.line(px, y + h - (h * (1 / (i ^ 0.9))))
    end
  end
  screen.stroke()
end

function W.tilt(x, y, w, h, sp, v, lv)
  local t = (pos(sp, v) * 2) - 1
  screen.level(lv)
  for i = 1, 6 do
    local px = x + ((i - 1) * (w / 6))
    local a = 0.2 + (0.8 * ((t >= 0) and (i / 6) or (1 - (i / 6))) * math.abs(t))
              + (0.3 * (1 - math.abs(t)))
    screen.move(px, y + h)
    screen.line(px, y + h - (h * util.clamp(a, 0.05, 1)))
  end
  screen.stroke()
end

function W.ratchet(x, y, w, h, sp, v, lv)
  local n = util.round(v)
  screen.level(lv)
  for i = 1, n do
    local px = x + ((i - 1) * (w / math.max(n, 1)))
    screen.move(px, y + h)
    screen.line(px, y)
  end
  screen.stroke()
end

function W.dir(x, y, w, h, sp, v, lv)
  screen.level(lv)
  local cy = y + (h / 2)
  frame_line(x, cy, w, 3)
  local function arrow(px, right)
    screen.move(px + (right and -3 or 3), cy - 3)
    screen.line(px, cy)
    screen.line(px + (right and -3 or 3), cy + 3)
    screen.stroke()
  end
  if v == 0 then arrow(x + w, true)
  elseif v == 1 then arrow(x, false)
  elseif v == 2 then arrow(x + w, true); arrow(x, false)
  else
    for i = 0, 4 do
      screen.rect(x + (i * 5), cy - 2 + ((i * 7) % 5), 2, 2)
    end
    screen.fill()
  end
end

function W.len(x, y, w, h, sp, v, lv)
  screen.level(2)
  screen.rect(x, y + h - 3, w, 2)
  screen.fill()
  screen.level(lv)
  screen.rect(x, y + h - 3, math.max(1, w * pos(sp, v)), 2)
  screen.fill()
  screen.level(6)
  for i = 1, 3 do screen.rect(x + (i * w / 4), y + h - 5, 1, 1) end
  screen.fill()
end

-- chord voicing drawn as the notes it actually stacks
function W.chord(x, y, w, h, sp, v, lv)
  local set = (v > 0) and C.CHORD_IV[v] or nil
  if not set then
    screen.level(3)
    screen.rect(x + 2, y + h - 2, 6, 1)
    screen.fill()
    return
  end
  local hi = 1
  for _, n in ipairs(set) do hi = math.max(hi, n) end
  screen.level(lv)
  for i, n in ipairs(set) do
    screen.rect(x + 1 + ((i - 1) * 2), y + h - 2 - (n * (h - 3) / hi), 5, 1)
  end
  screen.fill()
end

function W.mach(x, y, w, h, sp, v, lv) end
function W.enum(x, y, w, h, sp, v, lv) end
function W.dest(x, y, w, h, sp, v, lv) end
function W.leader(x, y, w, h, sp, v, lv) end

-- ROOT and SCALE are the song's key, so they draw the same twelve chromatic
-- slots and differ only in what stands up out of them: one note for the root,
-- the scale's own degrees for the scale.
local function chroma(x, y, w, h)
  screen.level(2)
  for i = 0, 11 do screen.rect(x + (i * (w - 1) / 11), y + h - 1, 1, 1) end
  screen.fill()
end

function W.root(x, y, w, h, sp, v, lv)
  chroma(x, y, w, h)
  screen.level(lv)
  screen.rect(x + (util.round(pos(sp, v) * 11) * (w - 1) / 11), y, 1, h)
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
    screen.rect(x + (i * (w - 1) / 11), y + (tall and 0 or 2),
      1, tall and h or (h - 2))
  end
  screen.fill()
end
-- the sharp front of a drum: a spike whose height is the transient level
function W.click(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  screen.level(lv)
  screen.move(x, y + h)
  screen.line(x + 2, y + h - (h * p))
  screen.line(x + 4, y + h - (h * p * 0.25))
  screen.line(x + w, y + h)
  screen.stroke()
  frame_line(x, y + h, w, 2)
end

-- a resonant band sitting where the value puts it, which is what a drum's
-- TONE control moves rather than a corner frequency
function W.band(x, y, w, h, sp, v, lv)
  local c = x + (pos(sp, v) * (w - 2)) + 1
  screen.level(lv)
  screen.move(x, y + h)
  screen.line(c - 4, y + h - 1)
  screen.line(c, y)
  screen.line(c + 4, y + h - 1)
  screen.line(x + w, y + h)
  screen.stroke()
end

-- A lossy codec does not shave the top off a band, it throws pieces of the
-- signal away and puts the rest back slightly wrong -- so the glyph is one
-- whole shape coming apart. At zero it is a clean wave. As the value climbs
-- the wave breaks into fragments that slip out of line, and then fragments
-- start going missing altogether.
function W.loss(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local mid = y + (h / 2)
  local amp = (h / 2) - 1
  local seed = 0.271
  local function rnd() seed = (seed * 9.13 + 0.271) % 1 return seed end
  local function at(i, slip)
    return util.clamp(mid - (math.sin((i / w) * 2 * math.pi) * amp) + slip,
                      y, y + h)
  end
  screen.level(lv)
  local i = 0
  while i < w do
    local run = 2 + math.floor(rnd() * 3)
    local gone = rnd() < (p * 0.5)
    local slip = (rnd() - 0.5) * p * (h - 1)
    if not gone then
      local e = math.min(w, i + run)
      screen.move(x + i, at(i, slip))
      for k = i + 1, e do screen.line(x + k, at(k, slip)) end
      screen.stroke()
    end
    i = i + run
  end
end

-- digital dropout: a run of samples repeated, with a hole punched in it
function W.glitch(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local seed = 0.317
  screen.level(lv)
  local held, hy = 0, h * 0.5
  for i = 0, w - 1, 1 do
    seed = (seed * 9.13 + 0.271) % 1
    if held <= 0 then
      held = 1 + math.floor(seed * p * 6)
      hy = (0.15 + (seed * 0.7)) * h
    end
    held = held - 1
    if seed > (0.94 - (p * 0.3)) then hy = 0 end
    if hy > 0 then
      screen.move(x + i, y + h)
      screen.line(x + i, y + h - hy)
    end
  end
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
  local function at(t, v) pts[#pts + 1] = { x0 + (t * wseg), y + h - (v * h) } end
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
-- dim whole. Returns nothing; the caller has already placed the labels.
function W.envelope(x, y, w, h, segs, sel)
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
  frame_line(x, y + h, w, 1)
  screen.level(2)
  for i = 1, #segs - 1 do screen.rect(cut[i], y + h - 2, 1, 2) end
  screen.fill()

  local function stroke(i, lv)
    local pts = runs[i]
    screen.level(lv)
    screen.move(pts[1][1], pts[1][2])
    for k = 2, #pts do screen.line(pts[k][1], pts[k][2]) end
    screen.stroke()
  end
  for i = 1, #segs do stroke(i, 6) end
  if sel and runs[sel] then stroke(sel, 15) end
end

-- ------------------------------------------------------------------ step

-- how many pulses a held step lasts: the cell divided into that many blocks,
-- so it reads as a subdivision rather than as a number
function W.hold_n(x, y, w, h, sp, v, lv)
  local n = util.clamp(util.round(v), 1, 16)
  local bw = w / n
  screen.level(2)
  screen.rect(x, y + h - 1, w, 1)
  screen.fill()
  screen.level(lv)
  for i = 1, n do
    screen.rect(x + ((i - 1) * bw), y + h - 6, math.max(1, bw - 1), 6)
  end
  screen.fill()
end

-- what the pulses of a held step do: one plateau, four even hits, four
-- climbing, four falling away
function W.htype(x, y, w, h, sp, v, lv)
  screen.level(lv)
  if v == 0 then
    screen.move(x, y + h)
    screen.line(x, y + 1)
    screen.line(x + w - 1, y + 1)
    screen.line(x + w - 1, y + h)
    screen.stroke()
    return
  end
  local n, bw = 4, w / 4
  for i = 1, n do
    local a = 1
    if v == 2 then a = i / n elseif v == 3 then a = 1 - ((i - 1) / n) end
    screen.rect(x + ((i - 1) * bw), y + h - (h * a), math.max(1, bw - 2), h * a)
  end
  screen.fill()
end

-- the metre: one tick a beat, the downbeat taller, the ticks closer together
-- as the beat unit gets shorter -- so 7/8 looks tighter and busier than 3/4
function W.tsig(x, y, w, h, sp, v, lv)
  local ts = C.TSIG[util.round(v) + 1] or C.TSIG[1]
  local gap = util.clamp((w / ts.num) * math.min(1, 4 / ts.den) * 1.6, 1.5, w / ts.num)
  frame_line(x, y + h - 1, w, 2)
  screen.level(lv)
  for i = 1, ts.num do
    local px = x + ((i - 1) * gap)
    if px < x + w then
      screen.rect(px, y + h - ((i == 1) and h or (h * 0.55)), 1,
        (i == 1) and h or (h * 0.55))
    end
  end
  screen.fill()
end

-- A lock-only cell, with nothing held: the control is there but there is
-- nothing for it to be turned on, so it is struck out rather than absent.
function W.strike(x, y, w, h)
  screen.level(3)
  screen.move(x + 2, y + 1)
  screen.line(x + w - 2, y + h - 1)
  screen.move(x + w - 2, y + 1)
  screen.line(x + 2, y + h - 1)
  screen.stroke()
end

function W.draw(name, x, y, w, h, sp, v, lv, extra)
  local f = W[name] or W.bar
  f(x, y, w, h, sp, v, lv, extra)
end

return W
