-- ui/page_groove.lua
-- eight lanes at a time, thirteen steps across. lanes that are not pattern
-- lanes still draw what they are about to do, and touching one converts it to
-- a pattern lane seeded with that shape -- so you can always grab a generated
-- rhythm and pin it down.

local nd = include('lib/node')
local viz = include('lib/viz')

local P = {}

P.glyphs = { k2 = 'mute', k3 = 'prob' }
P.SW = 13

local function lane_id(m, cy)
  return ((m.ui.bank_lane or 0) * 8) + cy
end

local function shape(ctx, m, id, i)
  local lane = m.lanes[id]
  local pos = (i - 1) % math.max(1, lane.len)
  if lane.src == 5 and lane.steps then
    return lane.steps[pos + 1] or 0
  elseif lane.src == 2 then
    return ctx.seq.euclid(lane.k, lane.n, lane.rot, pos) and 1 or 0
  elseif lane.src == 3 then
    return (lane.cells and lane.cells[pos + 1]) or 0
  end
  return 0
end

local function to_pattern(ctx, m, id)
  local lane = m.lanes[id]
  if lane.src == 5 and lane.steps then return end
  local st = {}
  for i = 1, math.max(1, lane.len) do
    st[i] = shape(ctx, m, id, i)
  end
  lane.steps = st
  lane.src = 5
end

function P.key(ctx, cx, cy, z)
  if z == 0 then return end
  local m = ctx.m
  local id = lane_id(m, cy)
  if id > nd.N then return end

  if cx <= P.SW then
    m.ui.sel_lane = id
    m.ui.sel_node = id
    if ctx.shift then
      -- shift cycles the trigger source rather than editing steps
      m.lanes[id].src = (m.lanes[id].src % 7) + 1
      return
    end
    to_pattern(ctx, m, id)
    local lane = m.lanes[id]
    local i = ((cx - 1) % math.max(1, lane.len)) + 1
    local v = lane.steps[i] or 0
    lane.steps[i] = (v > 0) and 0 or 1
    ctx.seq.markov_train(lane, (v > 0) and 1 or 2)
    return
  end

  if cx == P.SW + 1 then
    m.nodes[id].mute = not m.nodes[id].mute
    m.lanes[id].mute = m.nodes[id].mute
  else
    -- the fill key: one bar of a denser version of this lane
    local lane = m.lanes[id]
    lane.ratchet = (lane.ratchet >= 4) and 1 or (lane.ratchet + 1)
  end
end

function P.enc(ctx, e, d)
  local m = ctx.m
  local lane = m.lanes[m.ui.sel_lane]
  if e == 1 then
    m.ui.bank_lane = util.clamp((m.ui.bank_lane or 0) + d, 0, 1)
  elseif e == 2 then
    if ctx.shift then
      lane.len = util.clamp(lane.len + d, 1, 64)
    else
      -- division steps through a table so it always lands on something musical
      local divs = { 1/32, 1/24, 1/16, 1/12, 1/8, 1/6, 3/16, 1/4, 1/3, 3/8, 1/2, 2/3, 1, 3/2, 2 }
      local cur = 3
      for i = 1, #divs do if math.abs(divs[i] - lane.div) < 1e-6 then cur = i end end
      cur = util.clamp(cur + d, 1, #divs)
      ctx.seq.set_div(m.ui.sel_lane, divs[cur])
    end
  elseif e == 3 then
    if ctx.shift then
      lane.drift = util.clamp(lane.drift + (d * 0.02), 0, 1)
    else
      lane.prob = util.clamp(lane.prob + (d * 0.02), 0, 1)
    end
  end
end

function P.k2(ctx, z)
  if z == 0 then return end
  local m = ctx.m
  local n = m.nodes[m.ui.sel_lane]
  n.mute = not n.mute
  m.lanes[m.ui.sel_lane].mute = n.mute
end

function P.k3(ctx, z)
  if z == 0 then return end
  local lane = ctx.m.lanes[ctx.m.ui.sel_lane]
  lane.every = (lane.every >= 4) and 1 or (lane.every + 1)
end

function P.draw(ctx, g, G)
  local m = ctx.m

  for cy = 1, 8 do
    local id = lane_id(m, cy)
    if id <= nd.N then
      local lane = m.lanes[id]
      local n = m.nodes[id]
      local live = (lane.pos % math.max(1, lane.len))

      for cx = 1, P.SW do
        local pos = (cx - 1) % math.max(1, lane.len)
        local v = shape(ctx, m, id, cx)
        local rest = G.STRUCT
        if n.t == nd.EMPTY then rest = G.OFF end
        if v > 0 then rest = lane.mute and G.AVAIL or G.SET end
        if pos == live then rest = math.max(rest, G.AVAIL + 2) end
        if lane.prob < 1 and v > 0 then rest = math.max(G.AVAIL, rest - 2) end
        if rest > 0 then G.cled(g, cx, cy, rest, viz.a_node(id)) end
      end

      G.cled(g, P.SW + 1, cy, n.mute and G.STRUCT or G.SET)
      local r = lane.ratchet
      G.cled(g, P.SW + 2, cy, (r > 1) and (G.AVAIL + (r * 2)) or G.STRUCT)
    end
  end
end

return P
