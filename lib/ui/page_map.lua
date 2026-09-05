-- ui/page_map.lua
-- sixteen nodes as 2x2 quad-glyphs, and the selected node's six spectral macros
-- as bar meters. this is the page you leave it on.

local nd = include('lib/node')
local viz = include('lib/viz')

local P = {}

local TYPES = { nd.EMPTY, nd.VOICE, nd.SEQ, nd.MOD, nd.LOGIC, nd.FX, nd.MULT }

P.glyphs = { k2 = 'mute', k3 = 'a_play' }

local function node_at(cx, cy)
  if cx > 8 then return nil end
  local col = math.ceil(cx / 2)
  local row = math.ceil(cy / 2)
  return ((row - 1) * 4) + col
end

local function quad_origin(id)
  local col = ((id - 1) % 4) + 1
  local row = math.floor((id - 1) / 4) + 1
  return ((col - 1) * 2) + 1, ((row - 1) * 2) + 1
end

function P.key(ctx, cx, cy, z)
  if z == 0 then return end
  local m = ctx.m
  local ui = m.ui

  if cx <= 8 then
    local id = node_at(cx, cy)
    if id == nil then return end
    if ctx.shift then
      ctx.set_node_type(id, nd.EMPTY)
    else
      ui.sel_node = id
      local n = m.nodes[id]
      if n.voice then ui.sel_voice = n.voice end
      ui.sel_lane = id
    end
    return
  end

  local col = cx - 8            -- 1..7
  local n = m.nodes[ui.sel_node]

  if cy <= 6 then
    local v = n.voice
    if v == nil then return end
    m.voices[v].macros[cy] = col / 7
    ctx.ec.set_macro(v, cy, m.voices[v].macros[cy])
    ui.sel_macro = cy
  elseif cy == 7 then
    ctx.set_node_type(ui.sel_node, TYPES[col])
  else
    n.reg = col - 4
  end
end

function P.enc(ctx, e, d)
  local m = ctx.m
  local ui = m.ui
  if e == 1 then
    ui.sel_node = util.clamp(ui.sel_node + d, 1, nd.N)
    local n = m.nodes[ui.sel_node]
    if n.voice then ui.sel_voice = n.voice end
    ui.sel_lane = ui.sel_node
  elseif e == 2 then
    if ctx.shift then
      ui.sel_macro = util.clamp(ui.sel_macro + d, 1, 6)
    else
      local v = m.nodes[ui.sel_node].voice
      if v then
        local a = m.voices[v].macros
        a[ui.sel_macro] = util.clamp(a[ui.sel_macro] + (d * 0.01), 0, 1)
        ctx.ec.set_macro(v, ui.sel_macro, a[ui.sel_macro])
      end
    end
  elseif e == 3 then
    if ctx.shift then
      m.nodes[ui.sel_node].reg = util.clamp(m.nodes[ui.sel_node].reg + d, -3, 3)
    else
      local n = m.nodes[ui.sel_node]
      n.amp = util.clamp(n.amp + (d * 0.01), 0, 1)
    end
  end
end

function P.k2(ctx, z)
  if z == 0 then return end
  local n = ctx.m.nodes[ctx.m.ui.sel_node]
  n.mute = not n.mute
  ctx.m.lanes[ctx.m.ui.sel_node].mute = n.mute
end

function P.k3(ctx, z)
  if z == 0 then return end
  ctx.seq.fire(ctx.m, ctx.m.ui.sel_node, 1.0)
end

function P.draw(ctx, g, G)
  local m = ctx.m
  local ui = m.ui

  for id = 1, nd.N do
    local n = m.nodes[id]
    local cx, cy = quad_origin(id)
    local rest = (n.t == nd.EMPTY) and G.STRUCT or G.SET
    if n.mute then rest = G.AVAIL end
    if id == ui.sel_node then rest = G.SEL end
    G.quad(g, cx, cy, nd.QUAD[n.t], rest, viz.a_node(id))
  end

  local n = m.nodes[ui.sel_node]
  local v = n.voice

  for i = 1, 6 do
    local base = v and m.voices[v].macros[i] or 0
    local live = v and ctx.ec.macro_live(v, i) or 0
    local lit = math.floor(base * 7 + 0.5)
    local gh = math.floor(live * 7 + 0.5)
    for c = 1, 7 do
      local rest = G.STRUCT
      if v == nil then rest = G.OFF
      elseif c <= lit then rest = G.SET end
      if c == lit then rest = G.SEL end
      if c == gh and c ~= lit then rest = 6 end
      if i == ui.sel_macro and rest == G.STRUCT then rest = G.AVAIL end
      G.cled(g, 8 + c, i, rest)
    end
  end

  for c = 1, 7 do
    local rest = G.AVAIL
    if TYPES[c] == n.t then rest = G.SEL end
    G.cled(g, 8 + c, 7, rest)
  end

  for c = 1, 7 do
    local rest = G.STRUCT
    if (c - 4) == n.reg then rest = G.SEL end
    if c == 4 then rest = math.max(rest, G.AVAIL) end
    G.cled(g, 8 + c, 8, rest)
  end
end

return P
