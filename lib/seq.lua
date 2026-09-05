-- seq.lua
-- one clock, seventeen sprockets. every node owns a lane with its own division,
-- so polyrhythm is the default rather than a feature, and it survives tempo
-- changes because lattice does the counting.

local bus = include('lib/bus')
local nd = include('lib/node')
local field = include('lib/field')
local gesture = include('lib/gesture')
local ec = include('lib/engine_ctl')

local seq = {}

seq.lat = nil
seq.sprockets = {}
seq.harm_sprocket = nil
seq.running = false
seq.cycle = 0
seq.last_deg = {}
seq.ctx = nil
seq.m = nil

local FN = { 'and', 'or', 'xor', 'nand', 'a not b', 'a delayed' }

-- ------------------------------------------------------------ trigger sources

local function euclid(k, n, rot, pos)
  if k <= 0 or n <= 0 then return false end
  if k >= n then return true end
  local i = (pos + rot) % n
  return (((i * k) % n) < k)
end

local function ca_advance(lane)
  local n = lane.len
  local c = lane.cells
  if c == nil or #c ~= n then
    c = {}
    for i = 1, n do c[i] = (i == math.floor(n / 2)) and 1 or 0 end
    lane.cells = c
  end
  local out = {}
  local rule = lane.rule
  for i = 1, n do
    local l = c[((i - 2) % n) + 1]
    local m = c[i]
    local r = c[(i % n) + 1]
    local idx = (l * 4) + (m * 2) + r
    out[i] = (rule >> idx) & 1
  end
  lane.cells = out
end

local function markov_next(lane)
  -- order-1 chain over {rest, hit, accent}, trained by playing on the grid
  local tr = lane.mk
  if tr == nil then
    tr = { { 6, 3, 1 }, { 4, 4, 2 }, { 3, 4, 3 } }
    lane.mk = tr
    lane.mks = 1
  end
  local row = tr[lane.mks]
  local total = row[1] + row[2] + row[3]
  local r = math.random() * total
  local s = 1
  if r > row[1] then s = 2 end
  if r > row[1] + row[2] then s = 3 end
  lane.mks = s
  return s
end

function seq.markov_train(lane, state)
  if lane.mk == nil then markov_next(lane) end
  local prev = lane.mkp or 1
  lane.mk[prev][state] = math.min(24, lane.mk[prev][state] + 2)
  lane.mkp = state
end

-- ------------------------------------------------------------------ conditions

local function conditions(lane)
  local cyc = lane.cyc or 0
  if lane.prob < 1.0 and math.random() > lane.prob then return false end
  if lane.every > 1 then
    if (cyc % lane.every) ~= ((lane.ever_n or 1) % lane.every) then return false end
  end
  if lane.notn > 1 then
    if (cyc % lane.notn) == 0 then return false end
  end
  return true
end

-- ---------------------------------------------------------------------- firing

local function voice_note(m, id, vel)
  local n = m.nodes[id]
  local v = n.voice
  if v == nil then return end
  local ctx = seq.ctx
  local t = ctx.tuning_for(m, id)

  local deg = (m.voices[v].degree or 0) + (n.reg * t.steps) + m.transpose
  local hz = t:fold_hz(t:hz(deg, m.root))

  -- the operator that draws its ratio from the chord, so the sidebands land on
  -- pitches the harmony is already using
  local partner = ctx.harmony:partner(m.voices[v].degree or 0)
  local r2, r3, r4 = t:op_ratios(deg, partner and (partner + (n.reg * t.steps)) or nil)
  local vo = m.voices[v]
  if vo.r[1] ~= r2 or vo.r[2] ~= r3 or vo.r[3] ~= r4 then
    vo.r[1], vo.r[2], vo.r[3] = r2, r3, r4
    ec.mark_ratios(v)
  end

  vo.hz = hz
  vo.on = true
  ec.gate(v, hz, n.amp * vel)
  bus.emit('note', { node = id, voice = v, hz = hz, amp = vel, degree = deg })
end

local function fire(m, id, vel)
  local n = m.nodes[id]
  local lane = m.lanes[id]
  vel = vel or 1.0

  if n.t == nd.VOICE then
    voice_note(m, id, vel)
  elseif n.t == nd.MOD then
    if n.gest then gesture.retrig(m, n.gest) end
    bus.emit('trig', { node = id, lane = id, vel = vel })
  elseif n.t == nd.MULT then
    local target = m.lanes[id].a
    if target and m.nodes[target] and target ~= id then
      local r = math.max(1, lane.ratchet)
      if r == 1 then
        fire(m, target, vel)
      else
        clock.run(function()
          local step = (lane.div * 4) / r
          for i = 1, r do
            fire(m, target, vel * (1 - ((i - 1) / (r * 1.5))))
            if i < r then clock.sleep(step) end
          end
        end)
      end
    end
    bus.emit('trig', { node = id, lane = id, vel = vel })
  elseif n.t == nd.FX then
    if seq.ctx.regen then seq.ctx.regen.trigger(m, n.fx) end
    bus.emit('trig', { node = id, lane = id, vel = vel })
  else
    bus.emit('trig', { node = id, lane = id, vel = vel })
  end
end

seq.fire = fire

-- ------------------------------------------------------------------ lane step

local function evaluate(m, id)
  local lane = m.lanes[id]
  local src = lane.src
  local vel = 1.0

  if src == 1 then
    local p = field.consume(id)
    if p == nil then return false, 0 end
    lane.ang = p.ang
    return true, p.vel

  elseif src == 2 then
    return euclid(lane.k, lane.n, lane.rot, lane.pos), vel

  elseif src == 3 then
    if lane.pos == 0 then ca_advance(lane) end
    local c = lane.cells and lane.cells[lane.pos + 1] or 0
    return c == 1, vel

  elseif src == 4 then
    local s = markov_next(lane)
    if s == 1 then return false, 0 end
    return true, (s == 3) and 1.0 or 0.7

  elseif src == 5 then
    local st = lane.steps
    if st == nil then return false, 0 end
    local v = st[lane.pos + 1]
    if v == nil or v == 0 then return false, 0 end
    return true, v

  elseif src == 6 then
    local a = m.lanes[lane.a] and m.lanes[lane.a].last or 0
    local b = m.lanes[lane.b] and m.lanes[lane.b].last or 0
    local f = lane.fn
    local out
    if f == 1 then out = (a == 1 and b == 1)
    elseif f == 2 then out = (a == 1 or b == 1)
    elseif f == 3 then out = (a ~= b)
    elseif f == 4 then out = not (a == 1 and b == 1)
    elseif f == 5 then out = (a == 1 and b == 0)
    else out = (lane.prev_a == 1) end
    lane.prev_a = a
    return out, vel

  elseif src == 7 then
    local g = gesture.value(lane.gest)
    local was = lane.gwas or false
    local now = g > lane.thresh
    lane.gwas = now
    return (now and not was), math.min(1, math.abs(g))
  end

  return false, 0
end

local function step_lane(m, id)
  local lane = m.lanes[id]
  local n = m.nodes[id]
  if n.t == nd.EMPTY and lane.src ~= 6 then
    lane.last = 0
    return
  end

  lane.pos = (lane.pos + 1) % math.max(1, lane.len)
  if lane.pos == 0 then lane.cyc = (lane.cyc or 0) + 1 end

  local ok, vel = evaluate(m, id)
  lane.last = ok and 1 or 0

  if lane.mute or not ok then return end
  if not conditions(lane) then return end

  local hum = m.clock.humanise + (m.mod_swing or 0)
  local swing = m.clock.swing
  local delay = 0
  if swing > 0 and (lane.pos % 2) == 1 then
    delay = delay + (lane.div * 4 * swing * 0.5)
  end
  if hum > 0 then
    delay = delay + ((math.random() - 0.5) * hum * lane.div * 2)
    vel = vel * (1 - (math.random() * hum * 0.4))
  end

  local r = lane.ratchet
  if r > 1 and n.t ~= nd.MULT then
    clock.run(function()
      if delay > 0 then clock.sleep(delay) end
      local gap = (lane.div * 4) / r
      for i = 1, r do
        fire(m, id, vel * (1 - ((i - 1) / (r * 1.5))))
        if i < r then clock.sleep(gap) end
      end
    end)
  elseif delay > 0 then
    clock.run(function()
      clock.sleep(delay)
      fire(m, id, vel)
    end)
  else
    fire(m, id, vel)
  end
end

-- ---------------------------------------------------------------------- harmony

function seq.harm_step()
  local m, ctx = seq.m, seq.ctx
  if m == nil or not m.harm.on then return end
  local h = ctx.harmony
  h.tension = math.max(0, math.min(1, m.harm.tension + (m.mod_tension or 0)))
  h.budget = m.harm.budget
  h:set_density(math.floor(m.harm.density + ((m.mod_density or 0) * 3) + 0.5))
  h:step()
  m.harm.chord = { table.unpack(h.chord) }

  local a = h:assign(nd.N_VOICES, seq.last_deg)
  for v = 1, nd.N_VOICES do
    if a[v] then
      m.voices[v].degree = a[v]
      seq.last_deg[v] = a[v]
    end
  end
end

-- push the current chord to the voices without advancing the walk, for when
-- the player edits the chord by hand on the lattice page
function seq.assign_now()
  local m, ctx = seq.m, seq.ctx
  if m == nil then return end
  m.harm.chord = { table.unpack(ctx.harmony.chord) }
  local a = ctx.harmony:assign(nd.N_VOICES, seq.last_deg)
  for v = 1, nd.N_VOICES do
    if a[v] then
      m.voices[v].degree = a[v]
      seq.last_deg[v] = a[v]
    end
  end
end

-- ------------------------------------------------------------------- transport

function seq.init(m, ctx)
  seq.m = m
  seq.ctx = ctx
  seq.last_deg = {}
  for i = 1, nd.N do
    m.lanes[i].pos = -1
    m.lanes[i].cyc = 0
    m.lanes[i].last = 0
  end
  seq.build()
end

function seq.build()
  if seq.lat then seq.lat:destroy() end
  local lattice = require('lattice')
  seq.lat = lattice:new{ auto = true, ppqn = 96 }
  seq.sprockets = {}
  local m = seq.m

  for i = 1, nd.N do
    local id = i
    seq.sprockets[i] = seq.lat:new_sprocket{
      action = function() step_lane(m, id) end,
      division = m.lanes[i].div,
      enabled = true,
    }
  end

  seq.harm_sprocket = seq.lat:new_sprocket{
    action = function() seq.harm_step() end,
    division = m.harm.div / 4,
    enabled = true,
  }

  -- a rebuild happens on load and on set recall; if the transport was running
  -- before, it has to still be running after
  if seq.running then seq.lat:start() end
end

function seq.set_div(i, div)
  seq.m.lanes[i].div = div
  if seq.sprockets[i] then seq.sprockets[i]:set_division(div) end
end

function seq.set_harm_div(d)
  seq.m.harm.div = d
  if seq.harm_sprocket then seq.harm_sprocket:set_division(d / 4) end
end

-- per-lane tempo deviation. this is why it does not sound like a step sequencer.
function seq.apply_drift()
  local m = seq.m
  if m == nil then return end
  local amt = m.clock.drift + (m.mod_drift or 0)
  if amt <= 0 then return end
  for i = 1, nd.N do
    local s = seq.sprockets[i]
    if s then
      local d = m.lanes[i].drift
      if d ~= 0 then
        local w = math.sin((seq.cycle * 0.11) + (i * 0.7)) * amt * d * 0.06
        s:set_division(m.lanes[i].div * (1 + w))
      end
    end
  end
  seq.cycle = seq.cycle + 1
end

function seq.start()
  if seq.lat then seq.lat:start() end
  seq.running = true
end

function seq.stop()
  if seq.lat then seq.lat:stop() end
  seq.running = false
  ec.panic()
  local m = seq.m
  if m then
    for v = 1, nd.N_VOICES do m.voices[v].on = false end
  end
end

function seq.reset()
  local m = seq.m
  if m == nil then return end
  for i = 1, nd.N do
    m.lanes[i].pos = -1
    m.lanes[i].cyc = 0
  end
  if seq.lat then seq.lat:hard_restart() end
end

function seq.toggle()
  if seq.running then seq.stop() else seq.start() end
end

seq.FN = FN
seq.euclid = euclid

return seq
