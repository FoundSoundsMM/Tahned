-- ui/page_morph.lua
-- the barycentric pad. A bottom-left, B bottom-right, C top-centre; the cell
-- under the interpolation position stays lit as it moves, including when a
-- gesture lane is driving it rather than a finger.

local viz = include('lib/viz')

local P = {}

P.glyphs = { k2 = 'snapshot', k3 = 'morph' }
P.PW = 13

local RATES = { 0, 0.25, 0.6, 1.4 }

function P.key(ctx, cx, cy, z)
  if z == 0 then return end
  local m = ctx.m

  if cx <= P.PW then
    local x = (cx - 1) / (P.PW - 1)
    local y = (cy - 1) / 7
    if ctx.shift then
      -- shift on the pad nudges the auto-morph centre without jumping to it
      m.morph.x, m.morph.y = x, y
    else
      ctx.morph.apply(m, x, y)
      m.morph.x, m.morph.y = x, y
    end
    return
  end

  local col = cx - P.PW           -- 1 or 2

  if cy <= 4 then
    local slot = ((cy - 1) * 2) + col
    if ctx.shift then
      ctx.morph.scene_store(m, slot)
    else
      ctx.morph.scene_recall(m, slot)
    end
    return
  end

  if cy == 5 then
    local i = col                  -- A, B
    if ctx.shift or not ctx.morph.has(i) then ctx.morph.store(m, i) end
  elseif cy == 6 then
    if col == 1 then
      if ctx.shift or not ctx.morph.has(3) then ctx.morph.store(m, 3) end
    else
      m.morph.rate = (m.morph.rate > 0) and 0 or 0.6
    end
  else
    local i = ((cy - 7) * 2) + col
    m.morph.rate = RATES[i] or 0
  end
end

function P.enc(ctx, e, d)
  local m = ctx.m
  if e == 1 then
    m.morph.rate = util.clamp(m.morph.rate + (d * 0.02), 0, 2)
  elseif e == 2 then
    m.morph.x = util.clamp(m.morph.x + (d * 0.008), 0, 1)
    ctx.morph.apply(m, m.morph.x, m.morph.y)
  elseif e == 3 then
    m.morph.y = util.clamp(m.morph.y + (d * 0.008), 0, 1)
    ctx.morph.apply(m, m.morph.x, m.morph.y)
  end
end

function P.k2(ctx, z)
  if z == 0 then return end
  -- store all three corners from where the patch currently is, so a morph can
  -- be set up from one state and then pulled apart with perturb
  local m = ctx.m
  for i = 1, 3 do ctx.morph.store(m, i) end
end

function P.k3(ctx, z)
  if z == 0 then return end
  ctx.m.morph.rate = (ctx.m.morph.rate > 0) and 0 or 0.6
end

function P.draw(ctx, g, G)
  local m = ctx.m
  local w = ctx.morph.cur
  local px = math.floor((m.morph.x * (P.PW - 1)) + 1.5)
  local py = math.floor((m.morph.y * 7) + 1.5)

  for cy = 1, 8 do
    for cx = 1, P.PW do
      local x = (cx - 1) / (P.PW - 1)
      local y = (cy - 1) / 7
      local ww = ctx.morph.weights(x, y)
      -- the pad is shaded by how much of each corner is in play, so the
      -- triangle draws itself
      local rest = G.OFF
      local top = math.max(ww[1], math.max(ww[2], ww[3]))
      if top < 0.98 then rest = G.STRUCT end
      if cx == px and cy == py then rest = G.FIRE end
      if rest > 0 then G.cled(g, cx, cy, rest) end
    end
  end

  -- corners
  G.cled(g, 1, 8, ctx.morph.has(1) and G.SET or G.AVAIL)
  G.cled(g, P.PW, 8, ctx.morph.has(2) and G.SET or G.AVAIL)
  G.cled(g, math.ceil(P.PW / 2), 1, ctx.morph.has(3) and G.SET or G.AVAIL)

  for cy = 1, 4 do
    for col = 1, 2 do
      local slot = ((cy - 1) * 2) + col
      local rest = m.scenes[slot] and G.SET or G.STRUCT
      if m.scene_cur == slot then rest = G.SEL end
      G.cled(g, P.PW + col, cy, rest)
    end
  end

  G.cled(g, P.PW + 1, 5, ctx.morph.has(1) and G.SET or G.AVAIL)
  G.cled(g, P.PW + 2, 5, ctx.morph.has(2) and G.SET or G.AVAIL)
  G.cled(g, P.PW + 1, 6, ctx.morph.has(3) and G.SET or G.AVAIL)
  G.cled(g, P.PW + 2, 6, (m.morph.rate > 0) and G.FIRE or G.STRUCT)

  for i = 1, 4 do
    local cy = 7 + math.floor((i - 1) / 2)
    local col = ((i - 1) % 2) + 1
    local rest = (math.abs(m.morph.rate - RATES[i]) < 0.05) and G.SEL or G.STRUCT
    G.cled(g, P.PW + col, cy, rest)
  end
end

return P
