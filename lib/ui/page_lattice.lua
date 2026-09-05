-- ui/page_lattice.lua
-- the harmonic lattice, drawn as it actually is: fifths across, thirds (or
-- sevenths, or elevenths) up. lit cells are in the chord; the generative walk
-- animates across the same grid you are pressing.

local viz = include('lib/viz')

local P = {}

P.glyphs = { k2 = 'lattice', k3 = 'a_play' }

P.map = nil          -- cache of cell -> degree
P.key_axis = 5
P.AXES = { 5, 7, 11, 13 }

local function fold(r, period)
  while r >= period do r = r / period end
  while r < 1 do r = r * period end
  return r
end

-- rebuilt only when the tuning or the axis changes: 120 nearest() searches is
-- fine once, and not fine every frame
function P.rebuild(ctx)
  local t = ctx.tuning
  local p = P.AXES[(ctx.m.ui.lat_bank % #P.AXES) + 1]
  P.key_axis = p
  P.map = {}
  for cy = 1, 8 do
    P.map[cy] = {}
    local b = 4 - cy                -- +3 at the top down to -4
    for cx = 1, 15 do
      local a = cx - 8              -- -7 .. +7
      local r = 1.0
      for _ = 1, math.abs(a) do r = (a > 0) and (r * 3) or (r / 3) end
      for _ = 1, math.abs(b) do r = (b > 0) and (r * p) or (r / p) end
      r = fold(r, t.period)
      P.map[cy][cx] = t:nearest(r)
    end
  end
  P.built_for = t
  P.built_axis = p
end

local function ensure(ctx)
  if P.map == nil or P.built_for ~= ctx.tuning
     or P.built_axis ~= P.AXES[(ctx.m.ui.lat_bank % #P.AXES) + 1] then
    P.rebuild(ctx)
  end
end

local function in_chord(h, t, deg)
  local n = t.steps
  local target = deg % n
  for i = 1, #h.chord do
    if (h.chord[i] % n) == target then return i end
  end
  return nil
end

function P.key(ctx, cx, cy, z)
  if z == 0 then return end
  ensure(ctx)
  local m = ctx.m
  local h = ctx.harmony
  local t = ctx.tuning

  if ctx.shift then
    -- shift turns the page into the tuning selector
    local idx = ((m.ui.lat_bank * 8) + cy)
    if cx <= 2 then
      ctx.retune(idx + 1)
    else
      m.ui.lat_bank = (m.ui.lat_bank + 1) % 4
      P.map = nil
    end
    return
  end

  local deg = P.map[cy][cx]
  local at = in_chord(h, t, deg)
  if at then
    if #h.chord > 1 then table.remove(h.chord, at) end
  else
    if #h.chord >= 6 then table.remove(h.chord, 1) end
    h.chord[#h.chord + 1] = deg
  end
  m.harm.density = #h.chord
  ctx.seq.assign_now()
end

function P.enc(ctx, e, d)
  local m = ctx.m
  if e == 1 then
    m.ui.lat_bank = (m.ui.lat_bank + d) % 4
    P.map = nil
  elseif e == 2 then
    m.harm.tension = util.clamp(m.harm.tension + (d * 0.01), 0, 1)
  elseif e == 3 then
    if ctx.shift then
      m.harm.budget = util.clamp(m.harm.budget + (d * 0.02), 0.3, 2.5)
    else
      m.harm.density = util.clamp(m.harm.density + d, 1, 6)
    end
  end
end

function P.k2(ctx, z)
  if z == 0 then return end
  ctx.seq.harm_step()
end

function P.k3(ctx, z)
  if z == 0 then return end
  ctx.m.harm.on = not ctx.m.harm.on
end

function P.draw(ctx, g, G)
  ensure(ctx)
  local m = ctx.m
  local h = ctx.harmony
  local t = ctx.tuning

  if ctx.shift then
    local n = ctx.tuning_count()
    for cy = 1, 8 do
      local idx = (m.ui.lat_bank * 8) + cy + 1
      local rest = (idx <= n) and G.AVAIL or G.OFF
      if idx == m.tuning_idx then rest = G.SEL end
      for cx = 1, 2 do G.cled(g, cx, cy, rest) end
    end
    for cy = 1, 8 do
      for cx = 4, 15 do
        G.cled(g, cx, cy, (cy == (m.ui.lat_bank + 1)) and G.SET or G.STRUCT)
      end
    end
    return
  end

  for cy = 1, 8 do
    for cx = 1, 15 do
      local deg = P.map[cy][cx]
      local rest = G.STRUCT
      -- the lattice origin is always visible so you know where you are
      if cx == 8 and cy == 4 then rest = G.AVAIL end
      if in_chord(h, t, deg) then rest = G.SET end
      G.cled(g, cx, cy, rest, viz.a_deg(deg))
    end
  end
end

return P
