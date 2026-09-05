-- model.lua
-- the single state table. plain data wherever possible so that saving a set is
-- a table dump; the live subsystem objects hang off it but are never serialised.

local node = include('lib/node')

local model = {}

model.VERSION = 1

model.N_GEST = 32
model.N_MACRO = 6
model.MACRO_NAMES = { 'odd', 'even', 'partials', 'tilt', 'feedback', 'skew' }

model.LANE_SRC = { 'field', 'euclid', 'ca', 'markov', 'pattern', 'derived', 'gesture' }
model.GEST_MODE = { 'loop', 'once', 'pingpong', 'trig' }
model.GEST_GEN = { 'rec', 'lfo', 'sh', 'drunk', 'lorenz', 'follow' }
model.MOD_MODE = { 'add', 'mul', 'sh' }
model.REGEN_MODE = { 'dub', 'gran', 'freeze', 'stretch' }

local function default_voice(i)
  return {
    macros = { 0.30, 0.35, 0.35, 0.50, 0.0, 0.0 },
    r = { 1, 2, 3 },
    env = { atk = 0.004, rel = 0.45, crv = -3.5 },
    tr = { amt = 0.0, dec = 0.06, col = 0.5, w = { 0, 1, 0, 0 } },
    xsrc = (i % node.N_VOICES) + 1,
    xdepth = 0.0,
    xmode = 0,
    pan = 0.0,
    gain = 0.9,
    drive = 1.0,
    lag = 0.01,
    man = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    degree = 0,
    hz = 110,
    on = false,
  }
end

local function default_lane(i)
  return {
    src = 2,            -- euclid
    div = 1 / 16,
    len = 16,
    off = 0,
    k = 4, n = 16, rot = 0,
    rule = 90,
    cells = nil,
    steps = nil,
    prob = 1.0,
    every = 1, ever_n = 1, notn = 0,
    ratchet = 1,
    swing = 0.0,
    drift = 0.0,
    a = 1, b = 2, fn = 1,   -- derived: lane a, lane b, boolean function
    thresh = 0.5,           -- when driven from a gesture lane
    gest = 0,
    mute = false,
    pos = 0,
    cyc = 0,
    last = 0,
  }
end

local function default_gesture(i)
  return {
    gen = 1,            -- rec
    mode = 1,           -- loop
    speed = 1.0,
    atten = 1.0,
    offset = 0.0,
    quant = false,
    playing = false,
    rec = false,
    value = 0.0,
    pos = 0.0,
    len = 0.0,
    seg = nil,          -- delta-encoded segments {t, v}
    src = 0,            -- what it records from
    rate = 0.25,        -- for generators
    shape = 0.0,
    seed = i * 0.137,
  }
end

local function default_regen(i)
  return {
    on = false,
    mode = 1,
    len = 2.0,
    rate = 1.0,
    fb = 0.7,
    filt = 0.6,
    res = 0.2,
    spread = 0.3,
    level = 0.6,
    pos = 0,
  }
end

function model.new()
  local m = {}

  m.nodes = {}
  for i = 1, node.N do m.nodes[i] = node.new(i) end

  m.voices = {}
  for i = 1, node.N_VOICES do m.voices[i] = default_voice(i) end

  m.lanes = {}
  for i = 1, node.N do m.lanes[i] = default_lane(i) end

  m.gest = {}
  for i = 1, model.N_GEST do m.gest[i] = default_gesture(i) end

  m.regen = {}
  for i = 1, node.N_FX do m.regen[i] = default_regen(i) end

  -- sparse mod matrix: matrix[src][dst] = {d = depth, m = mode}
  m.matrix = {}

  m.tuning_idx = 13          -- ji5 in the preset list
  m.root = 55.0
  m.transpose = 0

  m.harm = {
    chord = { 0, 0, 0, 0 },
    tension = 0.3,
    density = 4,
    budget = 1.0,
    spread = 1,
    div = 1,               -- harmonic rhythm, in beats
    on = true,
  }

  m.field = {
    on = false,
    balls = {},
    walls = {},            -- walls[y][x] = 0 none, 1 wall, 2 mirror /, 3 mirror \
    grav = 0.0,
    mag = 0.0,
    wave = 0.0,
    damp = 1.0,
    speed = 1.0,
  }
  for y = 1, 8 do
    m.field.walls[y] = {}
    for x = 1, 15 do m.field.walls[y][x] = 0 end
  end

  m.morph = { x = 0.5, y = 0.5, rate = 0.0, snap = {}, active = false }
  m.scenes = {}
  m.scene_cur = 0

  m.clock = { swing = 0.0, humanise = 0.0, drift = 0.0 }

  m.mix = { gain = 1.0 }

  m.ui = {
    page = 1,
    shift = false,
    sel_node = 1,
    sel_lane = 1,
    sel_gest = 1,
    sel_macro = 3,
    sel_voice = 1,
    bank_src = 0,
    bank_dst = 0,
    bank_gest = 0,
    lat_bank = 0,
    perturb = 0.25,
  }

  return m
end

-- ------------------------------------------------------------ node bookkeeping

function model.voice_of(m, id)
  local n = m.nodes[id]
  if n == nil or n.t ~= node.VOICE then return nil end
  return n.voice
end

function model.node_of_voice(m, v)
  for i = 1, node.N do
    local n = m.nodes[i]
    if n.t == node.VOICE and n.voice == v then return i end
  end
  return nil
end

function model.n_of_type(m, t)
  local c = 0
  for i = 1, node.N do if m.nodes[i].t == t then c = c + 1 end end
  return c
end

-- assign the next free engine voice, or nil when all six are spoken for
function model.free_voice(m)
  local used = {}
  for i = 1, node.N do
    local n = m.nodes[i]
    if n.t == node.VOICE and n.voice then used[n.voice] = true end
  end
  for v = 1, node.N_VOICES do if not used[v] then return v end end
  return nil
end

function model.free_fx(m)
  local used = {}
  for i = 1, node.N do
    local n = m.nodes[i]
    if n.t == node.FX and n.fx then used[n.fx] = true end
  end
  for v = 1, node.N_FX do if not used[v] then return v end end
  return nil
end

function model.set_type(m, id, t)
  local n = m.nodes[id]
  if n == nil then return false end
  if t == n.t then return true end

  n.voice, n.fx, n.gest = nil, nil, nil

  if t == node.VOICE then
    local v = model.free_voice(m)
    if v == nil then return false end
    n.voice = v
  elseif t == node.FX then
    local f = model.free_fx(m)
    if f == nil then return false end
    n.fx = f
  elseif t == node.MOD then
    n.gest = ((id - 1) % model.N_GEST) + 1
  end

  n.t = t
  return true
end

-- ---------------------------------------------------------------- mod matrix

function model.mod_set(m, src, dst, depth, mode)
  if m.matrix[src] == nil then m.matrix[src] = {} end
  if depth == 0 then
    m.matrix[src][dst] = nil
    if next(m.matrix[src]) == nil then m.matrix[src] = nil end
  else
    m.matrix[src][dst] = { d = depth, m = mode or 1 }
  end
end

function model.mod_get(m, src, dst)
  local r = m.matrix[src]
  if r == nil then return nil end
  return r[dst]
end

-- ------------------------------------------------------------- serialisation

local function deep(t, seen)
  if type(t) ~= 'table' then return t end
  seen = seen or {}
  if seen[t] then return nil end
  seen[t] = true
  local o = {}
  for k, v in pairs(t) do
    if type(v) ~= 'function' and type(v) ~= 'userdata' then
      o[k] = deep(v, seen)
    end
  end
  seen[t] = nil
  return o
end

-- everything that does not belong in a PSET, dumped as one table
function model.serialise(m)
  return {
    version = model.VERSION,
    nodes = deep(m.nodes),
    voices = deep(m.voices),
    lanes = deep(m.lanes),
    gest = deep(m.gest),
    regen = deep(m.regen),
    matrix = deep(m.matrix),
    field = deep(m.field),
    harm = deep(m.harm),
    morph = deep(m.morph),
    scenes = deep(m.scenes),
    clock = deep(m.clock),
    tuning_idx = m.tuning_idx,
    root = m.root,
    transpose = m.transpose,
  }
end

model.MIGRATIONS = {
  -- [n] = function(t) ... end   -- migrate a version-n file to n+1
}

function model.deserialise(m, t)
  if type(t) ~= 'table' then return false end
  local v = t.version or 1
  while v < model.VERSION do
    local mig = model.MIGRATIONS[v]
    if mig then mig(t) end
    v = v + 1
  end
  for _, k in ipairs({ 'nodes', 'voices', 'lanes', 'gest', 'regen', 'matrix',
                       'field', 'harm', 'morph', 'scenes', 'clock' }) do
    if t[k] then m[k] = t[k] end
  end
  m.tuning_idx = t.tuning_idx or m.tuning_idx
  m.root = t.root or m.root
  m.transpose = t.transpose or m.transpose
  return true
end

return model
