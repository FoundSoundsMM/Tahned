-- ui/page_field.lua
-- the arena. tap a cell to cycle what is in it, drag from one cell to another
-- to launch a ball along that vector, shift-tap to drop the selected node.

local nd = include('lib/node')
local viz = include('lib/viz')
local field = include('lib/field')

local P = {}

P.glyphs = { k2 = 'a_clear', k3 = 'ball' }
P.down = nil

local CYCLE = { field.EMPTY, field.WALL, field.MIRRORA, field.MIRRORB,
                field.ATTRACT, field.REPEL }

local function cycle(c)
  for i = 1, #CYCLE do
    if CYCLE[i] == c then return CYCLE[(i % #CYCLE) + 1] end
  end
  return field.WALL
end

function P.key(ctx, cx, cy, z)
  local m = ctx.m

  if z == 1 then
    P.down = { x = cx, y = cy, t = (util.time and util.time() or os.clock()) }

    if ctx.shift then
      -- drop the selected node here
      local n = m.nodes[m.ui.sel_node]
      n.x, n.y = cx, cy
      field.rebuild(m)
      P.down = nil
    end
    return
  end

  if P.down == nil then return end
  local dx, dy = cx - P.down.x, cy - P.down.y
  local dt = (util.time and util.time() or os.clock()) - P.down.t

  if dx == 0 and dy == 0 then
    local id = field.nodemap[cy] and field.nodemap[cy][cx]
    if id then
      m.ui.sel_node = id
      m.ui.sel_lane = id
      if m.nodes[id].voice then m.ui.sel_voice = m.nodes[id].voice end
      -- a node sitting in the field is triggered by balls, so give it the
      -- source that means that
      if dt > 0.4 then m.lanes[id].src = 1 end
    else
      m.field.walls[cy][cx] = cycle(m.field.walls[cy][cx])
    end
  else
    local sp = math.sqrt((dx * dx) + (dy * dy))
    local k = math.min(3.0, 0.6 + (sp * 0.5)) / math.max(sp, 0.001)
    field.launch(P.down.x, P.down.y, dx * k * 2, dy * k * 2)
    m.field.on = true
  end

  P.down = nil
end

function P.enc(ctx, e, d)
  local m = ctx.m
  if e == 1 then
    m.ui.sel_node = util.clamp(m.ui.sel_node + d, 1, nd.N)
  elseif e == 2 then
    if ctx.shift then
      m.field.wave = util.clamp(m.field.wave + (d * 0.01), 0, 1)
    else
      m.field.grav = util.clamp(m.field.grav + (d * 0.01), -1, 1)
    end
  elseif e == 3 then
    if ctx.shift then
      m.field.speed = util.clamp(m.field.speed + (d * 0.02), 0.1, 3)
    else
      m.field.mag = util.clamp(m.field.mag + (d * 0.01), -1, 1)
    end
  end
end

function P.k2(ctx, z)
  if z == 0 then return end
  if ctx.shift then
    for y = 1, 8 do for x = 1, 15 do ctx.m.field.walls[y][x] = 0 end end
  else
    field.clear_balls()
  end
end

function P.k3(ctx, z)
  if z == 0 then return end
  ctx.m.field.on = not ctx.m.field.on
  if ctx.m.field.on and field.n_balls() == 0 then
    field.launch(4, 3, 3.2, 2.1)
  end
end

function P.draw(ctx, g, G)
  local m = ctx.m

  for cy = 1, 8 do
    for cx = 1, 15 do
      local c = m.field.walls[cy][cx]
      local rest = G.OFF
      if c == field.WALL then rest = G.SET
      elseif c == field.MIRRORA or c == field.MIRRORB then rest = G.AVAIL
      elseif c == field.ATTRACT then rest = G.SEL
      elseif c == field.REPEL then rest = G.STRUCT end
      if rest > 0 then G.cled(g, cx, cy, rest) end
    end
  end

  -- nodes sit in the arena at their type's resting level
  for id = 1, nd.N do
    local n = m.nodes[id]
    if n.t ~= nd.EMPTY then
      local rest = (id == m.ui.sel_node) and G.SEL or G.SET
      local x = util.clamp(math.floor(n.x), 1, 15)
      local y = util.clamp(math.floor(n.y), 1, 8)
      G.cled(g, x, y, rest, viz.a_node(id))
    end
  end

  -- balls and their trails
  for i = 1, #field.balls do
    local b = field.balls[i]
    local tr = b.trail
    for t = 1, #tr do
      local lvl = G.STRUCT + math.floor((t / #tr) * 4)
      local x, y = math.floor(tr[t][1] + 0.5), math.floor(tr[t][2] + 0.5)
      if x >= 1 and x <= 15 and y >= 1 and y <= 8 then
        G.cled(g, x, y, lvl)
      end
    end
    local x, y = math.floor(b.x + 0.5), math.floor(b.y + 0.5)
    if x >= 1 and x <= 15 and y >= 1 and y <= 8 then
      G.cled(g, x, y, G.FIRE, viz.a_ball(b.id))
    end
  end
end

return P
