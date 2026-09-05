-- widgets.lua
--
-- One micro-glyph per parameter cell. Each draws inside a 28x10 box and says
-- something true about the value -- an envelope shows its actual shape, a
-- waveform cell shows the waveform, a ratio cell shows the ratio. The point
-- is that a page reads as a picture of the sound, not a column of numbers.

local S = include("tahned/lib/core/spec")
local C = include("tahned/lib/instruments/common")

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

-- attack/decay shape; `v` drives the decay length
function W.env(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local pk = x + 2
  screen.level(lv)
  screen.move(x, y + h)
  screen.line(pk, y)
  local n = 10
  for i = 1, n do
    local t = i / n
    local dx = pk + (t * (w - 2) * (0.15 + (p * 0.85)))
    screen.line(dx, y + (h * (t ^ 0.55)))
  end
  screen.stroke()
end

-- exponential ramp, for time-shaped values
function W.time(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  screen.level(lv)
  screen.move(x, y + h)
  local n = 12
  for i = 1, n do
    local t = i / n
    screen.line(x + (t * w), y + h - (h * (t ^ (0.2 + ((1 - p) * 3)))))
  end
  screen.stroke()
end

-- curve amount, drawn as the curve itself
function W.curve(x, y, w, h, sp, v, lv)
  local p = (pos(sp, v) * 2) - 1
  screen.level(lv)
  screen.move(x, y + h)
  local n = 12
  for i = 1, n do
    local t = i / n
    local e = (p >= 0) and (1 + (p * 3)) or (1 / (1 + (-p * 3)))
    screen.line(x + (t * w), y + h - (h * (t ^ e)))
  end
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
  plot(x, y, w, h, lv, 2, function(t)
    if v == 0 then return 1 - (4 * math.abs(t - 0.5))
    elseif v == 1 then return math.sin(t * 2 * math.pi)
    elseif v == 2 then return (t < 0.5) and 1 or -1
    elseif v == 3 then return 1 - (t * 2)
    elseif v == 4 then return (t * 2) - 1
    elseif v == 5 then return (((1 - t) ^ 3) * 2) - 1
    else return math.sin(t * 17.3) * math.cos(t * 7.1) end
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

-- density of a noise field: white on the left, grainy on the right
function W.grain(x, y, w, h, sp, v, lv)
  local p = pos(sp, v)
  local gap = 1 + util.round(p * 5)
  local seed = 0.611
  screen.level(lv)
  for i = 0, w, gap do
    seed = (seed * 9.13 + 0.271) % 1
    local a = (0.35 + (seed * 0.65)) * h
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

function W.wow(x, y, w, h, sp, v, lv)
  local d = pos(sp, v)
  plot(x, y, w, h, lv, 2, function(t)
    return ((math.sin(t * 7.5) * 0.7) + (math.sin(t * 23) * 0.3)) * d
  end)
end

function W.comp(x, y, w, h, sp, v, lv)
  local r = pos(sp, v)
  screen.level(lv)
  screen.move(x, y + h)
  screen.line(x + (w * 0.45), y + (h * 0.55))
  screen.line(x + w, y + (h * 0.55) - ((h * 0.55) * (1 - r)))
  screen.stroke()
end

-- filter response, shaped by the type sitting on channel 40
function W.filt(x, y, w, h, sp, v, lv, ftype)
  local c = pos(sp, v)
  screen.level(lv)
  local cx = x + (c * w)
  ftype = ftype or 0
  screen.move(x, y + h - 1)
  if ftype == 0 then
    screen.line(math.min(cx, x + w - 4), y + h - 1)
    screen.line(math.min(cx + 2, x + w - 2), y)
    screen.line(math.min(cx + 5, x + w), y + h)
  elseif ftype == 2 then
    screen.move(x, y + h)
    screen.line(math.max(cx - 5, x), y + h)
    screen.line(math.max(cx - 2, x + 2), y)
    screen.line(x + w, y + h - 1)
  elseif ftype == 1 then
    screen.move(x, y + h)
    screen.line(cx - 3, y + h)
    screen.line(cx, y)
    screen.line(cx + 3, y + h)
    screen.line(x + w, y + h)
  else
    for i = 0, 4 do
      local px = x + (i * w / 4) + (c * 2)
      screen.move(px, y + h)
      screen.line(px, y + (h * (i % 2) * 0.5))
    end
  end
  screen.stroke()
end

function W.ftype(x, y, w, h, sp, v, lv)
  W.filt(x, y, w, h, { min = 0, max = 1 }, 0.55, lv, v)
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

function W.algo3(x, y, w, h, sp, v, lv)
  draw_algo(x, y, w, h, C.ALGO3[v + 1] or C.ALGO3[1], lv)
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

function W.voices(x, y, w, h, sp, v, lv)
  local n = util.round(1 + (pos(sp, v) * 5))
  for i = 1, 6 do
    screen.level(i <= n and lv or 2)
    screen.rect(x + ((i - 1) * 4), y + h - 4, 3, 3)
    screen.fill()
  end
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

function W.lane(x, y, w, h, sp, v, lv)
  for i = 1, 8 do
    screen.level(i == v and 15 or 3)
    screen.rect(x + ((i - 1) * 3), y + h - 4, 2, 3)
    screen.fill()
  end
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

-- start phase of an operator, or free running
function W.phase(x, y, w, h, sp, v, lv)
  local free = (S.unit_pos(sp, v) > 0.99)
  local mid = y + (h / 2)
  screen.level(free and 4 or lv)
  for i = 0, w do
    screen.pixel(x + i, util.round(mid - (math.sin((i / w) * 2 * math.pi) * (h / 2 - 1))))
  end
  screen.fill()
  if not free then
    local px = x + (S.unit_pos(sp, v) / 0.99 * 0.25 * w)
    screen.level(15)
    screen.move(px, y); screen.line(px, y + h); screen.stroke()
  end
end

function W.mach(x, y, w, h, sp, v, lv) end
function W.enum(x, y, w, h, sp, v, lv) end
function W.dest(x, y, w, h, sp, v, lv) end
function W.leader(x, y, w, h, sp, v, lv) end
function W.scale(x, y, w, h, sp, v, lv) end
function W.trans(x, y, w, h, sp, v, lv)
  screen.level(lv)
  if v == 0 then
    screen.move(x + 4, y + h); screen.line(x + 4, y); screen.stroke()
  elseif v == 1 then
    for i = 0, 6, 2 do screen.pixel(x + i, y + ((i * 3) % h)) end
    screen.fill()
  elseif v == 2 then
    screen.move(x, y + 1)
    for i = 1, 10 do screen.line(x + (i * 2), y + 1 + ((h - 2) * (i / 10))) end
    screen.stroke()
  else
    for i = 0, 4 do
      screen.move(x + (i * 4), y + h)
      screen.line(x + (i * 4), y + (h * ((i % 2) * 0.6)))
    end
    screen.stroke()
  end
end
W.lfo = W.lfowave

function W.draw(name, x, y, w, h, sp, v, lv, extra)
  local f = W[name] or W.bar
  f(x, y, w, h, sp, v, lv, extra)
end

return W
