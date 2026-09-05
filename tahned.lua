-- tahned
--
-- microtonal FM groovebox
-- generative sequencing, harmony
-- and ever-evolving timbre
--
-- norns + grid 128
-- no arc, no midi needed
--
-- col 1  : page
-- K1     : shift
-- K1+K2  : stop   K1+K3 : play
-- K1+col1: sets (tap load, hold save)
--
-- E1 focus  E2/E3 values
--
-- llllllll
-- after the Programma 900

engine.name = 'Tahned'

local nd       = include('lib/node')
local model    = include('lib/model')
local bus      = include('lib/bus')
local viz      = include('lib/viz')
local glyph    = include('lib/glyph')
local Tuning   = include('lib/tuning')
local Harmony  = include('lib/harmony')
local ec       = include('lib/engine_ctl')
local patch    = include('lib/patch')
local paths    = include('lib/paths')
local gesture  = include('lib/gesture')
local field    = include('lib/field')
local seq      = include('lib/seq')
local morph    = include('lib/morph')
local regen    = include('lib/regen')
local perturb  = include('lib/perturb')
local G        = include('lib/ui/grid_ui')
local S        = include('lib/ui/screen_ui')

local m
local ctx = {}
local g = grid.connect()
local screen_dirty = true
local ui_metro, phys_metro
local tunings = {}
local last_t = 0
local resync

local FPS_UI = 30
local FPS_PHYS = 60

-- ---------------------------------------------------------------------- tuning

local function tuning_for(mm, id)
  local n = mm.nodes[id]
  if n and n.tuning and n.tuning > 0 then
    if tunings[n.tuning] == nil then tunings[n.tuning] = Tuning.preset(n.tuning) end
    local t = tunings[n.tuning]
    t.root = mm.root
    return t
  end
  return ctx.tuning
end

local function retune(idx)
  idx = ((idx - 1) % Tuning.n_presets()) + 1
  m.tuning_idx = idx
  if tunings[idx] == nil then tunings[idx] = Tuning.preset(idx) end
  ctx.tuning = tunings[idx]
  ctx.tuning.root = m.root
  ctx.harmony:retune(ctx.tuning)
  for v = 1, nd.N_VOICES do ec.mark_ratios(v) end
  screen_dirty = true
end

-- morph, perturb, scene recall and set load all rewrite base values behind the
-- engine's back. this is the one place that pushes them back out.
-- a saved set has to come back as the same patch, chord included
local function restore_chord()
  local c = m.harm.chord
  if type(c) == 'table' and #c > 0 then
    ctx.harmony.chord = { table.unpack(c) }
    ctx.harmony.density = #c
  end
end

resync = function()
  for v = 1, nd.N_VOICES do
    ec.rebase(v)
    ec.mark_env(v)
    ec.mark_tr(v)
    ec.mark_xmod(v)
  end
  regen.push(m)
  for i = 1, nd.N do
    if seq.sprockets[i] then seq.sprockets[i]:set_division(m.lanes[i].div) end
  end
  screen_dirty = true
end

-- ------------------------------------------------------------------ node types

local function set_node_type(id, t)
  local was = m.nodes[id].t
  if not model.set_type(m, id, t) then return false end
  if was == nd.VOICE and m.nodes[id].t ~= nd.VOICE then
    -- releasing a voice should not leave it hanging
    for v = 1, nd.N_VOICES do
      if model.node_of_voice(m, v) == nil then ec.off(v) end
    end
  end
  field.rebuild(m)
  bus.emit('patch', { kind = 'type', node = id, t = t })
  screen_dirty = true
  return true
end

-- ---------------------------------------------------------------------- sets

local function set_path(i)
  return norns.state.data .. 'set' .. i .. '.tah'
end

local function set_slot(i, held)
  if held and held > 0.6 then
    tab.save(model.serialise(m), set_path(i))
    params:write(norns.state.data .. 'set' .. i .. '.pset')
    bus.emit('scene', { scene = i, saved = true })
  else
    local t = tab.load(set_path(i))
    if t then
      model.deserialise(m, t)
      retune(m.tuning_idx)
      restore_chord()
      ec.init(m)
      field.rebuild(m)
      seq.build()
      seq.assign_now()
      resync()
      bus.emit('scene', { scene = i })
    end
  end
  screen_dirty = true
end

local function set_slot_level(i)
  if util.file_exists(set_path(i)) then return G.SET end
  return G.STRUCT
end

-- ------------------------------------------------------------------- params

local function add_params()
  params:add_separator('tahned')

  params:add_group('tuning', 5)
  params:add_option('tuning_preset', 'tuning', (function()
    local o = {}
    for i = 1, Tuning.n_presets() do o[i] = Tuning.PRESETS[i].label end
    return o
  end)(), m.tuning_idx)
  params:set_action('tuning_preset', function(v) retune(v) end)
  params:add_control('root', 'root', controlspec.new(20, 400, 'exp', 0, 55, 'hz'))
  params:set_action('root', function(v) m.root = v; ctx.tuning.root = v end)
  params:add_number('transpose', 'transpose', -24, 24, 0)
  params:set_action('transpose', function(v) m.transpose = v end)
  params:add_control('mix_gain', 'gain', controlspec.new(0, 1.5, 'lin', 0, 1.0))
  params:set_action('mix_gain', function(v) m.mix.gain = v; if engine.mgain then engine.mgain(v) end end)
  params:add_number('perturb_amt', 'perturb', 1, 100, 25)
  params:set_action('perturb_amt', function(v) m.ui.perturb = v / 100 end)

  params:add_group('harmony', 6)
  params:add_control('h_tension', 'tension', controlspec.new(0, 1, 'lin', 0, 0.3))
  params:set_action('h_tension', function(v) m.harm.tension = v end)
  params:add_number('h_density', 'density', 1, 6, 4)
  params:set_action('h_density', function(v) m.harm.density = v end)
  params:add_control('h_budget', 'budget', controlspec.new(0.3, 2.5, 'lin', 0, 1.0))
  params:set_action('h_budget', function(v) m.harm.budget = v end)
  params:add_number('h_spread', 'spread', 0, 3, 1)
  params:set_action('h_spread', function(v) m.harm.spread = v; ctx.harmony.spread = v end)
  params:add_control('h_div', 'harmonic rhythm', controlspec.new(0.25, 16, 'lin', 0.25, 1, 'beat'))
  params:set_action('h_div', function(v) seq.set_harm_div(v) end)
  params:add_binary('h_on', 'auto', 'toggle', 1)
  params:set_action('h_on', function(v) m.harm.on = (v == 1) end)

  params:add_group('time', 3)
  params:add_control('swing', 'swing', controlspec.new(0, 0.7, 'lin', 0, 0))
  params:set_action('swing', function(v) m.clock.swing = v end)
  params:add_control('humanise', 'humanise', controlspec.new(0, 1, 'lin', 0, 0))
  params:set_action('humanise', function(v) m.clock.humanise = v end)
  params:add_control('drift', 'drift', controlspec.new(0, 1, 'lin', 0, 0))
  params:set_action('drift', function(v) m.clock.drift = v end)

  params:add_group('field', 6)
  params:add_binary('f_on', 'run', 'toggle', 0)
  params:set_action('f_on', function(v) m.field.on = (v == 1) end)
  params:add_control('f_grav', 'gravity', controlspec.new(-1, 1, 'lin', 0, 0))
  params:set_action('f_grav', function(v) m.field.grav = v end)
  params:add_control('f_mag', 'magnetism', controlspec.new(-1, 1, 'lin', 0, 0))
  params:set_action('f_mag', function(v) m.field.mag = v end)
  params:add_control('f_wave', 'wave', controlspec.new(0, 1, 'lin', 0, 0))
  params:set_action('f_wave', function(v) m.field.wave = v end)
  params:add_control('f_speed', 'speed', controlspec.new(0.1, 3, 'lin', 0, 1))
  params:set_action('f_speed', function(v) m.field.speed = v end)
  params:add_control('f_damp', 'damping', controlspec.new(0.9, 1, 'lin', 0, 1))
  params:set_action('f_damp', function(v) m.field.damp = v end)

  for v = 1, nd.N_VOICES do
    params:add_group('voice ' .. v, 18)
    for i = 1, 6 do
      local id = 'v' .. v .. '_m' .. i
      params:add_control(id, model.MACRO_NAMES[i],
        controlspec.new(0, 1, 'lin', 0, m.voices[v].macros[i]))
      params:set_action(id, function(x)
        m.voices[v].macros[i] = x
        ec.set_macro(v, i, x)
      end)
    end
    params:add_control('v' .. v .. '_atk', 'attack', controlspec.new(0.001, 1.5, 'exp', 0, 0.004, 's'))
    params:set_action('v' .. v .. '_atk', function(x) m.voices[v].env.atk = x; ec.mark_env(v) end)
    params:add_control('v' .. v .. '_rel', 'release', controlspec.new(0.02, 8, 'exp', 0, 0.45, 's'))
    params:set_action('v' .. v .. '_rel', function(x) m.voices[v].env.rel = x; ec.mark_env(v) end)
    params:add_control('v' .. v .. '_crv', 'curve', controlspec.new(-8, 4, 'lin', 0, -3.5))
    params:set_action('v' .. v .. '_crv', function(x) m.voices[v].env.crv = x; ec.mark_env(v) end)
    params:add_control('v' .. v .. '_tra', 'transient', controlspec.new(0, 1, 'lin', 0, 0))
    params:set_action('v' .. v .. '_tra', function(x) m.voices[v].tr.amt = x; ec.mark_tr(v) end)
    params:add_control('v' .. v .. '_trd', 'transient decay', controlspec.new(0.002, 1.2, 'exp', 0, 0.06, 's'))
    params:set_action('v' .. v .. '_trd', function(x) m.voices[v].tr.dec = x; ec.mark_tr(v) end)
    params:add_control('v' .. v .. '_trc', 'transient colour', controlspec.new(0, 1, 'lin', 0, 0.5))
    params:set_action('v' .. v .. '_trc', function(x) m.voices[v].tr.col = x; ec.mark_tr(v) end)
    params:add_control('v' .. v .. '_pan', 'pan', controlspec.new(-1, 1, 'lin', 0, 0))
    params:set_action('v' .. v .. '_pan', function(x) m.voices[v].pan = x; ec.set_pan(v, x) end)
    params:add_control('v' .. v .. '_drive', 'drive', controlspec.new(0.5, 6, 'lin', 0, 1))
    params:set_action('v' .. v .. '_drive', function(x) m.voices[v].drive = x; ec.set_drive(v, x) end)
    params:add_control('v' .. v .. '_gain', 'gain', controlspec.new(0, 1.4, 'lin', 0, 0.9))
    params:set_action('v' .. v .. '_gain', function(x) m.voices[v].gain = x; ec.set_gain(v, x) end)
    params:add_number('v' .. v .. '_xsrc', 'x source', 1, nd.N_VOICES, (v % nd.N_VOICES) + 1)
    params:set_action('v' .. v .. '_xsrc', function(x) m.voices[v].xsrc = x; ec.mark_xmod(v) end)
    params:add_control('v' .. v .. '_xd', 'x depth', controlspec.new(0, 1, 'lin', 0, 0))
    params:set_action('v' .. v .. '_xd', function(x) m.voices[v].xdepth = x; ec.set_xdepth(v, x) end)
    params:add_option('v' .. v .. '_xmode', 'x mode', { 'fm', 'ring' }, 1)
    params:set_action('v' .. v .. '_xmode', function(x) m.voices[v].xmode = x - 1; ec.mark_xmod(v) end)
  end

  for i = 1, nd.N_FX do
    params:add_group('regen ' .. i, 8)
    params:add_binary('r' .. i .. '_on', 'on', 'toggle', 0)
    params:set_action('r' .. i .. '_on', function(x) m.regen[i].on = (x == 1); regen.push(m, i) end)
    params:add_option('r' .. i .. '_mode', 'mode', model.REGEN_MODE, 1)
    params:set_action('r' .. i .. '_mode', function(x) m.regen[i].mode = x; regen.push(m, i) end)
    params:add_control('r' .. i .. '_len', 'length', controlspec.new(0.02, 60, 'exp', 0, 2, 's'))
    params:set_action('r' .. i .. '_len', function(x) m.regen[i].len = x; regen.push(m, i) end)
    params:add_control('r' .. i .. '_rate', 'rate', controlspec.new(-2, 2, 'lin', 0, 1))
    params:set_action('r' .. i .. '_rate', function(x) m.regen[i].rate = x; regen.push(m, i) end)
    params:add_control('r' .. i .. '_fb', 'feedback', controlspec.new(0, 1.1, 'lin', 0, 0.7))
    params:set_action('r' .. i .. '_fb', function(x) m.regen[i].fb = x; regen.push(m, i) end)
    params:add_control('r' .. i .. '_filt', 'filter', controlspec.new(0, 1, 'lin', 0, 0.6))
    params:set_action('r' .. i .. '_filt', function(x) m.regen[i].filt = x; regen.push(m, i) end)
    params:add_control('r' .. i .. '_res', 'resonance', controlspec.new(0, 1, 'lin', 0, 0.2))
    params:set_action('r' .. i .. '_res', function(x) m.regen[i].res = x; regen.push(m, i) end)
    params:add_control('r' .. i .. '_level', 'level', controlspec.new(0, 1, 'lin', 0, 0.6))
    params:set_action('r' .. i .. '_level', function(x) m.regen[i].level = x; regen.push(m, i) end)
  end

  params.action_write = function(filename, name, number)
    tab.save(model.serialise(m), norns.state.data .. number .. '.tah')
  end
  params.action_read = function(filename, silent, number)
    local t = tab.load(norns.state.data .. number .. '.tah')
    if t then
      model.deserialise(m, t)
      retune(m.tuning_idx)
      restore_chord()
      ec.init(m)
      field.rebuild(m)
      seq.build()
      seq.assign_now()
      resync()
    end
  end
end

-- --------------------------------------------------------------------- default

-- a patch that makes sound the moment the script loads, because an instrument
-- that boots silent teaches you nothing
local function seed()
  for i = 1, 4 do
    set_node_type(i, nd.VOICE)
    m.lanes[i].src = 2
    m.lanes[i].div = ({ 1/16, 1/8, 1/4, 1/6 })[i]
    m.lanes[i].k = ({ 5, 3, 2, 4 })[i]
    m.lanes[i].n = ({ 16, 8, 8, 12 })[i]
    m.lanes[i].len = m.lanes[i].n
    m.nodes[i].reg = ({ 0, -1, 1, 0 })[i]
  end
  m.voices[1].tr.amt = 0.45
  m.voices[1].env.rel = 0.12
  m.voices[2].macros = { 0.7, 0.2, 0.5, 0.35, 0.1, 0.0 }
  m.voices[3].macros = { 0.2, 0.6, 0.25, 0.7, 0.0, 0.05 }
  m.voices[4].macros = { 0.45, 0.45, 0.6, 0.5, 0.25, 0.12 }

  set_node_type(5, nd.MOD)
  m.gest[5].gen = 2
  m.gest[5].rate = 0.07
  m.gest[5].playing = true
  model.mod_set(m, 5, 3, 0.35, 1)          -- lane 5 -> voice 1 partials

  set_node_type(6, nd.LOGIC)
  m.lanes[6].src = 6
  m.lanes[6].a, m.lanes[6].b, m.lanes[6].fn = 1, 2, 3

  set_node_type(7, nd.FX)
  m.regen[1].on = true

  -- spread the nodes across the arena, inside it
  for i = 1, nd.N do
    local n = m.nodes[i]
    n.x = (((i - 1) % 5) * 3) + 2
    n.y = (math.floor((i - 1) / 5) * 2) + 2
  end
end

-- ------------------------------------------------------------------------ init

function init()
  math.randomseed(os.time())

  m = model.new()
  ctx.m = m
  ctx.model = model
  ctx.node = nd
  ctx.ec = ec
  ctx.patch = patch
  ctx.paths = paths
  ctx.gesture = gesture
  ctx.field = field
  ctx.seq = seq
  ctx.morph = morph
  ctx.regen = regen
  ctx.perturb = perturb
  ctx.viz = viz
  ctx.glyph = glyph
  ctx.shift = false
  ctx.tuning_for = tuning_for
  ctx.tuning_count = Tuning.n_presets
  ctx.retune = retune
  ctx.set_node_type = set_node_type
  ctx.set_slot = set_slot
  ctx.set_slot_level = set_slot_level
  ctx.dirty = function() screen_dirty = true end

  Tuning.scan({ norns.state.path .. 'data/tunings/', norns.state.data .. 'tunings/' })

  tunings[m.tuning_idx] = Tuning.preset(m.tuning_idx)
  ctx.tuning = tunings[m.tuning_idx]
  ctx.harmony = Harmony.new(ctx.tuning)

  viz.init()
  gesture.init()
  morph.init()
  field.init(m)
  ec.init(m)

  seed()

  seq.init(m, ctx)
  ctx.G = G
  G.init(ctx)
  add_params()
  params:bang()

  regen.init(m)
  field.rebuild(m)
  seq.assign_now()

  clock.transport.start = function() seq.start() end
  clock.transport.stop = function() seq.stop() end

  -- the engine's master level, for the screen only
  local pl = poll.set('level', function(v) m.level = v end)
  if pl then pl.time = 0.1; pl:start() end

  last_t = util.time()

  phys_metro = metro.init(function()
    local t = util.time()
    local dt = math.min(0.1, t - last_t)
    last_t = t

    field.step(m, dt)
    local gv = gesture.update(m, dt)
    morph.update(m, dt)
    -- reset every voice to its unmodulated base, then apply the matrix on top,
    -- so a lane going to zero restores exactly what was dialled in
    for v = 1, nd.N_VOICES do ec.rebase(v) end
    patch.update(m, gv)
    regen.push(m)
    ec.flush()
  end, 1 / FPS_PHYS)
  phys_metro:start()

  ui_metro = metro.init(function()
    viz.update(1 / FPS_UI)
    G.redraw(g)
    if screen_dirty or viz.count > 0 then
      S.redraw(ctx, G)
      screen_dirty = false
    end
    seq.apply_drift()
  end, 1 / FPS_UI)
  ui_metro:start()

  seq.start()
end

-- --------------------------------------------------------------------- input

g.key = function(x, y, z)
  G.key(x, y, z)
  screen_dirty = true
end

local kdown = { false, false, false }
local combo = false
local sent = { false, false, false }

function key(n, z)
  kdown[n] = (z == 1)

  if n == 1 then
    ctx.shift = (z == 1)
    screen_dirty = true
    return
  end

  -- K2 and K3 together is perturb, scoped to the page you are looking at, and
  -- undo with shift held. it is the one performance gesture that has to reach
  -- every page, so it gets the one key combination no page uses.
  if z == 1 and kdown[2] and kdown[3] then
    combo = true
    if ctx.shift then
      perturb.undo(m)
    else
      perturb.apply(m, m.ui.perturb, nil, perturb.PAGE_MASK[m.ui.page])
    end
    resync()
    screen_dirty = true
    return
  end

  if ctx.shift then
    if z == 1 then
      if n == 2 then
        seq.stop()
        seq.reset()
      else
        seq.toggle()
      end
      screen_dirty = true
    end
    return
  end

  if z == 1 then
    if combo then return end
    sent[n] = true
    if n == 2 then G.k2(1) else G.k3(1) end
  else
    if combo then
      if not kdown[2] and not kdown[3] then combo = false end
      sent[n] = false
      return
    end
    if sent[n] then
      sent[n] = false
      if n == 2 then G.k2(0) else G.k3(0) end
    end
  end
  screen_dirty = true
end

function enc(n, d)
  if n == 1 and ctx.shift then
    G.set_page(util.clamp(m.ui.page + d, 1, 8))
    screen_dirty = true
    return
  end

  G.enc(n, d)

  -- whatever the encoders are doing is also what an armed gesture lane records
  local gp = G.pages[6]
  if gp and gp.feed and n ~= 1 then
    gp.feed(ctx, util.clamp((d > 0 and 1 or -1) * 0.5 + (gp.acc or 0), -1, 1))
  end

  screen_dirty = true
end

function redraw()
  S.redraw(ctx, G)
end

-- perturb is a performance control, so it lives on a key combination that
-- works from every page rather than in a menu
function keyboard_or_perturb() end

function cleanup()
  if ui_metro then ui_metro:stop() end
  if phys_metro then phys_metro:stop() end
  seq.stop()
  ec.panic()
  clock.transport.start = nil
  clock.transport.stop = nil
end
