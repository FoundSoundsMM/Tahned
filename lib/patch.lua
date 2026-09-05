-- patch.lua
-- the modulation matrix. thirty-two gesture lanes into a flat destination
-- table; sparse storage because a full 32x76 grid is mostly zeros.
--
-- modulation is applied on top of the model's base values, never into them, so
-- turning a lane off restores exactly what the player dialled in.

local nd = include('lib/node')
local ec = include('lib/engine_ctl')
local bus = include('lib/bus')

local patch = {}

patch.DEST = {}
patch.N_DEST = 0

local function add(glyph, tag, apply, rebase)
  patch.N_DEST = patch.N_DEST + 1
  patch.DEST[patch.N_DEST] = { g = glyph, tag = tag, apply = apply, rebase = rebase }
  return patch.N_DEST
end

local MACRO_G = { 'odd', 'even', 'partials', 'tilt', 'feedback', 'skew' }

-- destination table. order matters: the PATCH page banks through it fifteen
-- columns at a time, so related destinations stay on the same bank.
local function build()
  patch.DEST = {}
  patch.N_DEST = 0

  for v = 1, nd.N_VOICES do
    for i = 1, 6 do
      add(MACRO_G[i], 'v' .. v .. MACRO_G[i]:sub(1, 2), function(m, off)
        ec.set_macro(v, i, m.voices[v].macros[i] + off)
      end, function(m) ec.set_macro(v, i, m.voices[v].macros[i]) end)
    end
  end

  for v = 1, nd.N_VOICES do
    add('morph', 'v' .. v .. 'pan', function(m, off)
      ec.set_pan(v, m.voices[v].pan + off * 2)
    end, function(m) ec.set_pan(v, m.voices[v].pan) end)
  end

  for v = 1, nd.N_VOICES do
    add('n_mult', 'v' .. v .. 'x', function(m, off)
      ec.set_xdepth(v, m.voices[v].xdepth + off)
    end, function(m) ec.set_xdepth(v, m.voices[v].xdepth) end)
  end

  for v = 1, nd.N_VOICES do
    add('tilt', 'v' .. v .. 'drv', function(m, off)
      ec.set_drive(v, m.voices[v].drive * (1 + off * 3))
    end, function(m) ec.set_drive(v, m.voices[v].drive) end)
  end

  add('lattice', 'tension', function(m, off) m.mod_tension = off end)
  add('lattice', 'density', function(m, off) m.mod_density = off end)
  add('lattice', 'budget',  function(m, off) m.mod_budget = off end)

  add('ball', 'grav',  function(m, off) m.mod_grav = off end)
  add('ball', 'mag',   function(m, off) m.mod_mag = off end)
  add('ball', 'wave',  function(m, off) m.mod_wave = off end)
  add('speed', 'fspd', function(m, off) m.mod_fspeed = off end)

  add('morph', 'mrx', function(m, off) m.mod_mx = off end)
  add('morph', 'mry', function(m, off) m.mod_my = off end)

  for i = 1, nd.N_FX do
    add('feedback', 'r' .. i .. 'fb',   function(m, off) m.regen[i].mod_fb = off end)
    add('atten',    'r' .. i .. 'filt', function(m, off) m.regen[i].mod_filt = off end)
    add('speed',    'r' .. i .. 'rate', function(m, off) m.regen[i].mod_rate = off end)
  end

  add('clock', 'swing', function(m, off) m.mod_swing = off end)
  add('clock', 'drift', function(m, off) m.mod_drift = off end)
  add('transient', 'tr', function(m, off) m.mod_tr = off end)
end

build()

-- destinations touched last frame, so a lane going silent is cleaned up once
patch.active = {}

local function clearmods(m)
  m.mod_tension, m.mod_density, m.mod_budget = 0, 0, 0
  m.mod_grav, m.mod_mag, m.mod_wave, m.mod_fspeed = 0, 0, 0, 0
  m.mod_mx, m.mod_my = 0, 0
  m.mod_swing, m.mod_drift, m.mod_tr = 0, 0, 0
  for i = 1, nd.N_FX do
    local r = m.regen[i]
    r.mod_fb, r.mod_filt, r.mod_rate = 0, 0, 0
  end
end

-- gvals[src] is the current value of gesture lane src, in -1..1
function patch.update(m, gvals)
  local acc = nil
  local mat = m.matrix

  for src, row in pairs(mat) do
    local gv = gvals[src]
    if gv ~= nil then
      for dst, cell in pairs(row) do
        local d = patch.DEST[dst]
        if d then
          local x
          if cell.m == 2 then          -- multiply
            x = (gv * 0.5 + 0.5) * cell.d
          else                          -- add, and sample-and-hold writes here too
            x = gv * cell.d
          end
          if acc == nil then acc = {} end
          acc[dst] = (acc[dst] or 0) + x
        end
      end
    end
  end

  clearmods(m)

  -- voices are rebased to their model values by the frame loop before this
  -- runs, so there is nothing to restore here: just lay the offsets on top
  patch.active = {}
  if acc then
    for dst, off in pairs(acc) do
      local d = patch.DEST[dst]
      if d then
        d.apply(m, off)
        patch.active[dst] = true
      end
    end
  end
end

function patch.dest_bank_count()
  return math.ceil(patch.N_DEST / 15)
end

function patch.glyph(dst)
  local d = patch.DEST[dst]
  return d and d.g or 'n_empty'
end

return patch
