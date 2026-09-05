-- paths.lua
-- one declarative registry of every interpolatable and perturbable value in the
-- model. morph and perturb both walk it, so a parameter added here is
-- immediately morphable and immediately mutable, and cannot be forgotten by one
-- and remembered by the other.

local nd = include('lib/node')

local paths = {}

paths.list = {}
paths.index = {}

-- kind: 'c' continuous (lerps, walks), 'd' discrete (switches with hysteresis,
-- steps when perturbed), 'i' integer continuous (lerps then rounds)
local function reg(key, kind, lo, hi, cls, get, set)
  local e = { key = key, k = kind, lo = lo, hi = hi, cls = cls, get = get, set = set }
  paths.list[#paths.list + 1] = e
  paths.index[key] = e
end

local function build()
  paths.list = {}
  paths.index = {}

  for v = 1, nd.N_VOICES do
    for i = 1, 6 do
      reg('v' .. v .. '.m' .. i, 'c', 0, 1, 'macro',
        function(m) return m.voices[v].macros[i] end,
        function(m, x) m.voices[v].macros[i] = x end)
    end
    reg('v' .. v .. '.pan', 'c', -1, 1, 'voice',
      function(m) return m.voices[v].pan end,
      function(m, x) m.voices[v].pan = x end)
    reg('v' .. v .. '.drive', 'c', 0.5, 6, 'voice',
      function(m) return m.voices[v].drive end,
      function(m, x) m.voices[v].drive = x end)
    reg('v' .. v .. '.xd', 'c', 0, 1, 'voice',
      function(m) return m.voices[v].xdepth end,
      function(m, x) m.voices[v].xdepth = x end)
    reg('v' .. v .. '.gain', 'c', 0, 1.4, 'voice',
      function(m) return m.voices[v].gain end,
      function(m, x) m.voices[v].gain = x end)
    reg('v' .. v .. '.xsrc', 'd', 1, nd.N_VOICES, 'voice',
      function(m) return m.voices[v].xsrc end,
      function(m, x) m.voices[v].xsrc = x end)
    reg('v' .. v .. '.xmode', 'd', 0, 1, 'voice',
      function(m) return m.voices[v].xmode end,
      function(m, x) m.voices[v].xmode = x end)
    reg('v' .. v .. '.atk', 'c', 0.001, 1.5, 'env',
      function(m) return m.voices[v].env.atk end,
      function(m, x) m.voices[v].env.atk = x end)
    reg('v' .. v .. '.rel', 'c', 0.02, 8, 'env',
      function(m) return m.voices[v].env.rel end,
      function(m, x) m.voices[v].env.rel = x end)
    reg('v' .. v .. '.crv', 'c', -8, 4, 'env',
      function(m) return m.voices[v].env.crv end,
      function(m, x) m.voices[v].env.crv = x end)
    reg('v' .. v .. '.tra', 'c', 0, 1, 'trans',
      function(m) return m.voices[v].tr.amt end,
      function(m, x) m.voices[v].tr.amt = x end)
    reg('v' .. v .. '.trd', 'c', 0.002, 1.2, 'trans',
      function(m) return m.voices[v].tr.dec end,
      function(m, x) m.voices[v].tr.dec = x end)
    reg('v' .. v .. '.trc', 'c', 0, 1, 'trans',
      function(m) return m.voices[v].tr.col end,
      function(m, x) m.voices[v].tr.col = x end)
    for c = 1, 16 do
      reg('v' .. v .. '.man' .. c, 'c', -6, 6, 'matrix',
        function(m) return m.voices[v].man[c] end,
        function(m, x) m.voices[v].man[c] = x end)
    end
  end

  for i = 1, nd.N do
    reg('l' .. i .. '.src', 'd', 1, 7, 'lane',
      function(m) return m.lanes[i].src end,
      function(m, x) m.lanes[i].src = x end)
    reg('l' .. i .. '.k', 'i', 0, 32, 'lane',
      function(m) return m.lanes[i].k end,
      function(m, x) m.lanes[i].k = x end)
    reg('l' .. i .. '.n', 'i', 1, 32, 'lane',
      function(m) return m.lanes[i].n end,
      function(m, x) m.lanes[i].n = x end)
    reg('l' .. i .. '.rot', 'i', 0, 31, 'lane',
      function(m) return m.lanes[i].rot end,
      function(m, x) m.lanes[i].rot = x end)
    reg('l' .. i .. '.len', 'i', 1, 64, 'lane',
      function(m) return m.lanes[i].len end,
      function(m, x) m.lanes[i].len = x end)
    reg('l' .. i .. '.rule', 'd', 0, 255, 'lane',
      function(m) return m.lanes[i].rule end,
      function(m, x) m.lanes[i].rule = x end)
    reg('l' .. i .. '.prob', 'c', 0, 1, 'cond',
      function(m) return m.lanes[i].prob end,
      function(m, x) m.lanes[i].prob = x end)
    reg('l' .. i .. '.ratchet', 'i', 1, 6, 'cond',
      function(m) return m.lanes[i].ratchet end,
      function(m, x) m.lanes[i].ratchet = x end)
    reg('l' .. i .. '.every', 'i', 1, 8, 'cond',
      function(m) return m.lanes[i].every end,
      function(m, x) m.lanes[i].every = x end)
    reg('l' .. i .. '.drift', 'c', 0, 1, 'time',
      function(m) return m.lanes[i].drift end,
      function(m, x) m.lanes[i].drift = x end)
    reg('n' .. i .. '.reg', 'i', -3, 3, 'reg',
      function(m) return m.nodes[i].reg end,
      function(m, x) m.nodes[i].reg = x end)
    reg('n' .. i .. '.amp', 'c', 0, 1, 'reg',
      function(m) return m.nodes[i].amp end,
      function(m, x) m.nodes[i].amp = x end)
  end

  reg('h.tension', 'c', 0, 1, 'harm',
    function(m) return m.harm.tension end, function(m, x) m.harm.tension = x end)
  reg('h.density', 'i', 1, 6, 'harm',
    function(m) return m.harm.density end, function(m, x) m.harm.density = x end)
  reg('h.budget', 'c', 0.3, 2.5, 'harm',
    function(m) return m.harm.budget end, function(m, x) m.harm.budget = x end)
  reg('h.spread', 'i', 0, 3, 'harm',
    function(m) return m.harm.spread end, function(m, x) m.harm.spread = x end)

  reg('f.grav', 'c', -1, 1, 'field',
    function(m) return m.field.grav end, function(m, x) m.field.grav = x end)
  reg('f.mag', 'c', -1, 1, 'field',
    function(m) return m.field.mag end, function(m, x) m.field.mag = x end)
  reg('f.wave', 'c', 0, 1, 'field',
    function(m) return m.field.wave end, function(m, x) m.field.wave = x end)
  reg('f.speed', 'c', 0.1, 3, 'field',
    function(m) return m.field.speed end, function(m, x) m.field.speed = x end)
  reg('f.damp', 'c', 0.9, 1.0, 'field',
    function(m) return m.field.damp end, function(m, x) m.field.damp = x end)

  for i = 1, nd.N_FX do
    reg('r' .. i .. '.len', 'c', 0.02, 60, 'regen',
      function(m) return m.regen[i].len end, function(m, x) m.regen[i].len = x end)
    reg('r' .. i .. '.rate', 'c', -2, 2, 'regen',
      function(m) return m.regen[i].rate end, function(m, x) m.regen[i].rate = x end)
    reg('r' .. i .. '.fb', 'c', 0, 1.1, 'regen',
      function(m) return m.regen[i].fb end, function(m, x) m.regen[i].fb = x end)
    reg('r' .. i .. '.filt', 'c', 0, 1, 'regen',
      function(m) return m.regen[i].filt end, function(m, x) m.regen[i].filt = x end)
    reg('r' .. i .. '.level', 'c', 0, 1, 'regen',
      function(m) return m.regen[i].level end, function(m, x) m.regen[i].level = x end)
    reg('r' .. i .. '.mode', 'd', 1, 4, 'regen',
      function(m) return m.regen[i].mode end, function(m, x) m.regen[i].mode = x end)
  end

  reg('c.swing', 'c', 0, 0.7, 'time',
    function(m) return m.clock.swing end, function(m, x) m.clock.swing = x end)
  reg('c.hum', 'c', 0, 1, 'time',
    function(m) return m.clock.humanise end, function(m, x) m.clock.humanise = x end)
  reg('c.drift', 'c', 0, 1, 'time',
    function(m) return m.clock.drift end, function(m, x) m.clock.drift = x end)
end

build()

paths.CLASSES = { 'macro', 'voice', 'env', 'trans', 'matrix', 'lane', 'cond',
                  'time', 'reg', 'harm', 'field', 'regen' }

function paths.count() return #paths.list end

-- scope filters, used by both morph snapshots and perturb
function paths.scope_node(id)
  local vpre = nil
  return function(e)
    if e.key:match('^l' .. id .. '%.') then return true end
    if e.key:match('^n' .. id .. '%.') then return true end
    return vpre ~= nil and e.key:match('^v' .. vpre .. '%.') ~= nil
  end, function(v) vpre = v end
end

function paths.capture(m, filter)
  local snap = {}
  for i = 1, #paths.list do
    local e = paths.list[i]
    if filter == nil or filter(e) then
      snap[e.key] = e.get(m)
    end
  end
  return snap
end

function paths.restore(m, snap)
  if snap == nil then return end
  for k, v in pairs(snap) do
    local e = paths.index[k]
    if e then e.set(m, v) end
  end
end

return paths
