-- gesture.lua
-- thirty-two modulation lanes. the descendant of the Programma 900's CV
-- buffers: six minutes each, independent speed and attenuation, recorded from
-- the surface or generated.
--
-- storage is delta-encoded into two flat arrays per lane rather than a table of
-- points -- 32 lanes x 6 minutes x 100Hz would be 1.15M tables otherwise.

local bus = include('lib/bus')

local gesture = {}

gesture.N = 32
gesture.MAXLEN = 360.0        -- seconds
gesture.EPS = 0.004           -- write threshold
gesture.MAXGAP = 0.25         -- force a point at least this often
gesture.POINT_CEIL = 240000   -- across all lanes; ~8MB with headroom

gesture.lanes = {}
gesture.total_points = 0
gesture.vals = {}

local function newlane(i)
  return {
    ts = {}, vs = {}, n = 0,
    len = 0,
    pos = 0,
    dir = 1,
    playing = false,
    rec = false,
    rec_t = 0,
    last_v = 0,
    last_w = 0,
    out = 0,
    emit = 0,
    -- generator state
    ph = (i * 0.137) % 1,
    sh = 0,
    sh_t = 0,
    lx = 0.1 + i * 0.01, ly = 0, lz = 0,
  }
end

function gesture.init()
  gesture.lanes = {}
  gesture.total_points = 0
  for i = 1, gesture.N do
    gesture.lanes[i] = newlane(i)
    gesture.vals[i] = 0
  end
end

-- ------------------------------------------------------------------- recording

function gesture.rec_start(m, i)
  local l = gesture.lanes[i]
  if l == nil then return end
  gesture.total_points = gesture.total_points - l.n
  l.ts, l.vs, l.n, l.len = {}, {}, 0, 0
  l.rec = true
  l.rec_t = 0
  l.last_w = -99
  m.gest[i].rec = true
end

-- called at input rate from whatever the lane is recording from
function gesture.rec_write(m, i, v)
  local l = gesture.lanes[i]
  if l == nil or not l.rec then return end
  if gesture.total_points >= gesture.POINT_CEIL then
    gesture.rec_stop(m, i)
    return
  end
  local t = l.rec_t
  if l.n == 0
    or math.abs(v - l.last_w) > gesture.EPS
    or (t - l.ts[l.n]) > gesture.MAXGAP then
    l.n = l.n + 1
    l.ts[l.n] = t
    l.vs[l.n] = v
    l.last_w = v
    gesture.total_points = gesture.total_points + 1
  end
  l.len = t
end

function gesture.rec_stop(m, i)
  local l = gesture.lanes[i]
  if l == nil then return end
  l.rec = false
  m.gest[i].rec = false
  if l.n > 1 then
    l.playing = true
    m.gest[i].playing = true
    m.gest[i].len = l.len
  end
  l.pos = 0
end

function gesture.clear(m, i)
  local l = gesture.lanes[i]
  if l == nil then return end
  gesture.total_points = gesture.total_points - l.n
  gesture.lanes[i] = newlane(i)
  m.gest[i].playing = false
  m.gest[i].rec = false
  m.gest[i].len = 0
end

-- ------------------------------------------------------------------- playback

local function sample(l, t)
  if l.n == 0 then return 0 end
  if l.n == 1 then return l.vs[1] end
  if t <= l.ts[1] then return l.vs[1] end
  if t >= l.ts[l.n] then return l.vs[l.n] end
  -- running index: playback is almost always sequential
  local i = l.idx or 1
  if l.ts[i] > t then i = 1 end
  while i < l.n and l.ts[i + 1] < t do i = i + 1 end
  l.idx = i
  local t0, t1 = l.ts[i], l.ts[i + 1]
  local span = t1 - t0
  if span <= 0 then return l.vs[i] end
  local f = (t - t0) / span
  return l.vs[i] + ((l.vs[i + 1] - l.vs[i]) * f)
end

-- ------------------------------------------------------------------ generators

local function gen_lfo(l, g, dt)
  l.ph = (l.ph + (g.rate * dt)) % 1
  local p = l.ph
  local s = g.shape or 0
  if s < 0.33 then
    return math.sin(p * 2 * math.pi)
  elseif s < 0.66 then
    return (p < 0.5) and (p * 4 - 1) or (3 - p * 4)     -- triangle
  else
    return (p * 2) - 1                                   -- saw
  end
end

local function gen_sh(l, g, dt)
  l.sh_t = l.sh_t + dt
  local period = 1 / math.max(g.rate, 0.01)
  if l.sh_t >= period then
    l.sh_t = l.sh_t - period
    l.sh = (math.random() * 2) - 1
  end
  return l.sh
end

local function gen_drunk(l, g, dt)
  local step = (math.random() - 0.5) * g.rate * dt * 8
  l.sh = math.max(-1, math.min(1, l.sh + step))
  return l.sh
end

-- correlated, aperiodic, and it stays bounded: the useful chaos
local function gen_lorenz(l, g, dt)
  local h = math.min(dt, 0.02) * g.rate * 8
  local a, b, c = 10.0, 28.0, 8.0 / 3.0
  local x, y, z = l.lx, l.ly, l.lz
  local dx = a * (y - x)
  local dy = x * (b - z) - y
  local dz = (x * y) - (c * z)
  l.lx = x + dx * h * 0.02
  l.ly = y + dy * h * 0.02
  l.lz = z + dz * h * 0.02
  if l.lx ~= l.lx then l.lx, l.ly, l.lz = 0.1, 0, 0 end   -- nan guard
  local s = (g.shape or 0)
  local v = (s < 0.33) and l.lx or ((s < 0.66) and l.ly or (l.lz - 25))
  return math.max(-1, math.min(1, v / 20))
end

-- ---------------------------------------------------------------------- update

function gesture.update(m, dt)
  for i = 1, gesture.N do
    local l = gesture.lanes[i]
    local g = m.gest[i]
    local v = 0

    if l.rec then
      l.rec_t = l.rec_t + dt
      if l.rec_t > gesture.MAXLEN then gesture.rec_stop(m, i) end
      v = l.last_w
    elseif g.gen == 1 then
      if l.playing and l.len > 0 then
        l.pos = l.pos + (dt * g.speed * l.dir)
        local mode = g.mode
        if mode == 1 then                                  -- loop
          if l.pos > l.len then l.pos = l.pos % l.len end
          if l.pos < 0 then l.pos = l.len + (l.pos % l.len) end
        elseif mode == 2 then                              -- once
          if l.pos > l.len or l.pos < 0 then
            l.pos = math.max(0, math.min(l.len, l.pos))
            l.playing = false
            g.playing = false
          end
        elseif mode == 3 then                              -- ping-pong
          if l.pos > l.len then l.pos = l.len - (l.pos - l.len); l.dir = -l.dir end
          if l.pos < 0 then l.pos = -l.pos; l.dir = -l.dir end
        else                                               -- trigger-locked
          if l.pos > l.len then l.pos = l.len; l.playing = false; g.playing = false end
        end
        v = sample(l, l.pos)
      end
    elseif g.gen == 2 then v = gen_lfo(l, g, dt)
    elseif g.gen == 3 then v = gen_sh(l, g, dt)
    elseif g.gen == 4 then v = gen_drunk(l, g, dt)
    elseif g.gen == 5 then v = gen_lorenz(l, g, dt)
    elseif g.gen == 6 then v = (m.level or 0) * 2 - 1
    end

    v = (v * g.atten) + g.offset
    if v > 1 then v = 1 elseif v < -1 then v = -1 end

    l.out = v
    g.value = v
    gesture.vals[i] = v

    -- the bus is not a sample stream: only publish when it is worth drawing
    if math.abs(v - l.emit) > 0.02 then
      l.emit = v
      bus.emit('gesture', { lane = i, value = v, state = l.playing })
    end
  end
  return gesture.vals
end

-- lane retrigger, for trigger-locked mode and for MOD nodes in the field
function gesture.retrig(m, i)
  local l = gesture.lanes[i]
  if l == nil then return end
  l.pos = 0
  l.dir = 1
  l.idx = 1
  if l.n > 1 then
    l.playing = true
    m.gest[i].playing = true
  end
end

function gesture.toggle(m, i)
  local l = gesture.lanes[i]
  if l == nil then return end
  if l.n > 1 or m.gest[i].gen > 1 then
    l.playing = not l.playing
    m.gest[i].playing = l.playing
  end
end

function gesture.value(i) return gesture.vals[i] or 0 end
function gesture.has(i)
  local l = gesture.lanes[i]
  return l ~= nil and l.n > 1
end
function gesture.mem()
  return gesture.total_points / gesture.POINT_CEIL
end

return gesture
