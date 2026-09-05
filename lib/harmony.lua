-- harmony.lua
-- chords are generated, not looked up. the current chord is a set of points on
-- the tuning lattice; motion is a walk constrained by a harmonic-distance
-- budget, biased by one scalar (tension) that the sequencer can modulate.

local bus = include('lib/bus')

local Harmony = {}
Harmony.__index = Harmony

-- interval targets with a rough complexity rating. tension picks which band of
-- these the walk reaches for, so one knob moves from triads to 11-limit grind.
local TARGETS = {
  { 3 / 2,   0.08 }, { 4 / 3,   0.12 }, { 5 / 4,   0.24 }, { 8 / 5,   0.28 },
  { 6 / 5,   0.30 }, { 5 / 3,   0.32 }, { 9 / 8,   0.52 }, { 7 / 4,   0.55 },
  { 7 / 5,   0.62 }, { 7 / 6,   0.66 }, { 11 / 8,  0.76 }, { 16 / 15, 0.82 },
  { 13 / 8,  0.88 }, { 11 / 6,  0.92 },
}

function Harmony.new(tuning)
  local h = setmetatable({}, Harmony)
  h.tuning = tuning
  h.tension = 0.3
  h.density = 4
  h.budget = 1.0   -- multiplier on the tension-derived limit
  h.spread = 1
  h.chord = { 0, 0, 0, 0 }
  h.prev = {}
  h.steps = {}
  h:retune(tuning)
  h:reset()
  return h
end

-- the preferred step sizes are a property of the tuning, so they are computed
-- once when the tuning changes rather than per walk
function Harmony:retune(tuning)
  self.tuning = tuning
  self.steps = {}
  for i = 1, #TARGETS do
    local d = self.tuning:nearest(TARGETS[i][1])
    if d ~= 0 then
      self.steps[#self.steps + 1] = { d = d, c = TARGETS[i][2] }
    end
  end
  if #self.steps == 0 then
    self.steps = { { d = 1, c = 0.5 } }
  end
end

function Harmony:reset(root)
  root = root or 0
  local n = self.tuning.steps
  self.chord = { root }
  for i = 2, self.density do
    self.chord[i] = root + self.steps[math.min(i - 1, #self.steps)].d
  end
  self.prev = {}
  for i = 1, #self.chord do self.prev[i] = self.chord[i] end
end

-- weighted pick of a step whose complexity matches the current tension
function Harmony:pick_step()
  local total, w = 0, {}
  for i = 1, #self.steps do
    local diff = self.steps[i].c - self.tension
    w[i] = math.exp(-(diff * diff) / 0.06) + 0.02
    total = total + w[i]
  end
  local r = math.random() * total
  for i = 1, #w do
    r = r - w[i]
    if r <= 0 then
      local d = self.steps[i].d
      if math.random() < 0.5 then d = -d end
      return d
    end
  end
  return self.steps[1].d
end

-- mean pairwise harmonic distance, so the budget means the same thing
-- whether three voices are sounding or six
function Harmony:cost(chord)
  local c, n = 0, 0
  for i = 1, #chord do
    for j = i + 1, #chord do
      c = c + self.tuning:distance(chord[i], chord[j])
      n = n + 1
    end
  end
  if n == 0 then return 0 end
  return c / n
end

function Harmony:limit()
  return (2.0 + (self.tension * 4.0)) * self.budget
end

local function copy(t)
  local o = {}
  for i = 1, #t do o[i] = t[i] end
  return o
end

-- ------------------------------------------------------------- walk operators

local ops = {}

function ops.move(h, c)
  local i = math.random(#c)
  c[i] = c[i] + h:pick_step()
end

function ops.invert(h, c)
  local pivot = c[math.random(#c)]
  for i = 1, #c do c[i] = (2 * pivot) - c[i] end
end

function ops.rotate(h, c)
  table.sort(c)
  local n = h.tuning.steps
  if math.random() < 0.5 then
    c[1] = c[1] + n
  else
    c[#c] = c[#c] - n
  end
end

function ops.contract(h, c)
  local sum = 0
  for i = 1, #c do sum = sum + c[i] end
  local mid = sum / #c
  local k = (math.random() < 0.5) and 0.6 or 1.5
  for i = 1, #c do
    c[i] = math.floor(mid + ((c[i] - mid) * k) + 0.5)
  end
end

function ops.substitute(h, c)
  local i = math.random(#c)
  local anchor = c[(i % #c) + 1]
  c[i] = anchor + h:pick_step()
end

local OP_LIST = { ops.move, ops.move, ops.move, ops.substitute, ops.invert, ops.rotate, ops.contract }

-- ---------------------------------------------------------------------- public

-- one step of the walk. a move is accepted if it stays inside the distance
-- budget, or if it does not make the chord any more complex than it already
-- was -- so the walk can always move sideways and never gets stuck.
function Harmony:step()
  self.prev = copy(self.chord)
  local here = self:cost(self.chord)
  local lim = self:limit()
  local span = self.tuning.steps * (self.spread + 1)
  local fallback = nil
  for _ = 1, 12 do
    local cand = copy(self.chord)
    OP_LIST[math.random(#OP_LIST)](self, cand)

    local lo, hi = math.huge, -math.huge
    local dup = false
    for i = 1, #cand do
      lo = math.min(lo, cand[i]); hi = math.max(hi, cand[i])
      for j = i + 1, #cand do
        if cand[i] == cand[j] then dup = true end
      end
    end

    if (not dup) and (hi - lo) <= span then
      local c = self:cost(cand)
      if c <= lim or c <= here + 0.001 then
        self.chord = cand
        bus.emit('chord', { degrees = cand, tension = self.tension })
        return true
      end
      if fallback == nil or c < fallback.c then fallback = { c = c, chord = cand } end
    end
  end
  if fallback then
    self.chord = fallback.chord
    bus.emit('chord', { degrees = self.chord, tension = self.tension })
    return true
  end
  return false
end

function Harmony:set_density(n)
  n = math.floor(util and util.clamp(n, 1, 6) or n)
  if n == self.density then return end
  local c = copy(self.chord)
  while #c > n do table.remove(c, #c) end
  while #c < n do c[#c + 1] = c[math.max(1, #c)] + self:pick_step() end
  self.density = n
  self.chord = c
end

-- voice leading: hand the chord to the voices so each moves as little as
-- possible from where it already was. greedy, which is enough for six voices.
function Harmony:assign(n_voices, last)
  local out = {}
  local taken = {}
  local chord = copy(self.chord)
  local n = math.min(n_voices, #chord)

  for i = 1, n do
    local best, bd = nil, math.huge
    for v = 1, n_voices do
      if not taken[v] then
        local prev = last and last[v]
        local d
        if prev == nil then
          d = v * 0.001
        else
          d = self.tuning:distance(prev, chord[i]) + (math.abs(prev - chord[i]) * 0.05)
        end
        if d < bd then bd = d; best = v end
      end
    end
    if best then
      taken[best] = true
      out[best] = chord[i]
    end
  end
  return out
end

-- a partner degree for the FM operator that draws its ratio from the chord,
-- so the sidebands land on pitches the harmony is already using
function Harmony:partner(degree)
  local best, bd = nil, math.huge
  for i = 1, #self.chord do
    local c = self.chord[i]
    if c ~= degree then
      local d = math.abs(c - degree)
      if d < bd then bd = d; best = c end
    end
  end
  return best
end

return Harmony
