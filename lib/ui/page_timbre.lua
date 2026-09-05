-- ui/page_timbre.lua
-- six voices down, fifteen steps of macro value across. holding two keys in a
-- voice row sets a modulation *range* instead of a value: the midpoint becomes
-- the base and the span becomes a route from the selected gesture lane. one
-- gesture, one patch -- which is how the six macros survive having no arc.

local nd = include('lib/node')
local viz = include('lib/viz')

local P = {}

P.glyphs = { k2 = 'a_copy', k3 = 'transient' }
P.copied = nil

local function macro_dest(v, i)
  return ((v - 1) * 6) + i
end

function P.key(ctx, cx, cy, z)
  local m = ctx.m
  local G = ctx.G

  if cy <= 6 then
    if z == 0 then return end
    local v = cy
    local i = m.ui.sel_macro
    local other = G.partner_in_row(cy, cx + 1)

    if other then
      -- two fingers in a row: a range, not a value
      local a, b = math.min(cx, other - 1), math.max(cx, other - 1)
      local lo, hi = (a - 1) / 14, (b - 1) / 14
      local mid = (lo + hi) * 0.5
      m.voices[v].macros[i] = mid
      ctx.ec.set_macro(v, i, mid)
      ctx.model.mod_set(m, m.ui.sel_gest, macro_dest(v, i), (hi - lo) * 0.5, 1)
    else
      local val = (cx - 1) / 14
      m.voices[v].macros[i] = val
      ctx.ec.set_macro(v, i, val)
    end
    m.ui.sel_voice = v
    local id = ctx.model.node_of_voice(m, v)
    if id then m.ui.sel_node = id end
    return
  end

  if z == 0 then return end
  local v = m.ui.sel_voice

  if cy == 7 then
    if cx <= 6 then
      m.ui.sel_macro = cx
    elseif cx >= 8 then
      m.voices[v].tr.amt = (cx - 7) / 8
      ctx.ec.mark_tr(v)
    end
  else
    if cx <= 6 then
      local id = ctx.model.node_of_voice(m, cx)
      if id then
        m.nodes[id].mute = not m.nodes[id].mute
        m.lanes[id].mute = m.nodes[id].mute
      end
    elseif cx >= 8 then
      m.voices[v].tr.dec = 0.002 + (((cx - 7) / 8) ^ 2) * 1.2
      ctx.ec.mark_tr(v)
    end
  end
end

function P.enc(ctx, e, d)
  local m = ctx.m
  local v = m.ui.sel_voice
  if e == 1 then
    m.ui.sel_voice = util.clamp(m.ui.sel_voice + d, 1, nd.N_VOICES)
  elseif e == 2 then
    if ctx.shift then
      m.voices[v].env.rel = util.clamp(m.voices[v].env.rel * (1 + d * 0.04), 0.02, 8)
      ctx.ec.mark_env(v)
    else
      local a = m.voices[v].macros
      a[m.ui.sel_macro] = util.clamp(a[m.ui.sel_macro] + (d * 0.005), 0, 1)
      ctx.ec.set_macro(v, m.ui.sel_macro, a[m.ui.sel_macro])
    end
  elseif e == 3 then
    if ctx.shift then
      m.voices[v].tr.col = util.clamp(m.voices[v].tr.col + (d * 0.01), 0, 1)
      ctx.ec.mark_tr(v)
    else
      m.voices[v].xdepth = util.clamp(m.voices[v].xdepth + (d * 0.01), 0, 1)
      ctx.ec.set_xdepth(v, m.voices[v].xdepth)
    end
  end
end

function P.k2(ctx, z)
  if z == 0 then return end
  local m = ctx.m
  local v = m.ui.sel_voice
  if P.copied and ctx.shift then
    for i = 1, 6 do
      m.voices[v].macros[i] = P.copied[i]
      ctx.ec.set_macro(v, i, P.copied[i])
    end
  else
    P.copied = {}
    for i = 1, 6 do P.copied[i] = m.voices[v].macros[i] end
  end
end

function P.k3(ctx, z)
  if z == 0 then return end
  local m = ctx.m
  local v = m.ui.sel_voice
  -- cycle which operator the transient is injected into
  local w = m.voices[v].tr.w
  local cur = 1
  for i = 1, 4 do if w[i] > 0 then cur = i end end
  for i = 1, 4 do w[i] = 0 end
  w[(cur % 4) + 1] = 1
  ctx.ec.mark_tr(v)
end

function P.draw(ctx, g, G)
  local m = ctx.m
  local i = m.ui.sel_macro

  for v = 1, nd.N_VOICES do
    local base = m.voices[v].macros[i]
    local live = ctx.ec.macro_live(v, i)
    local n = math.floor((base * 14) + 1.5)
    local gh = math.floor((live * 14) + 1.5)
    local id = ctx.model.node_of_voice(m, v)
    local muted = id and m.nodes[id].mute
    for cx = 1, 15 do
      local rest = G.STRUCT
      if cx <= n then rest = muted and G.AVAIL or G.SET end
      if cx == n then rest = G.SEL end
      if cx == gh and cx ~= n then rest = 6 end
      G.cled(g, cx, v, rest, id and viz.a_node(id) or nil)
    end
  end

  for cx = 1, 6 do
    G.cled(g, cx, 7, (cx == i) and G.SEL or G.AVAIL)
  end
  local v = m.ui.sel_voice
  local ta = math.floor(m.voices[v].tr.amt * 8 + 0.5)
  for cx = 8, 15 do
    local rest = ((cx - 7) <= ta) and G.SET or G.STRUCT
    if (cx - 7) == ta then rest = G.SEL end
    G.cled(g, cx, 7, rest)
  end

  for cx = 1, 6 do
    local id = ctx.model.node_of_voice(m, cx)
    local rest = G.STRUCT
    if id then rest = m.nodes[id].mute and G.AVAIL or G.SET end
    if cx == v then rest = G.SEL end
    G.cled(g, cx, 8, rest)
  end
  local td = math.floor((math.sqrt(math.max(0, (m.voices[v].tr.dec - 0.002) / 1.2)) * 8) + 0.5)
  for cx = 8, 15 do
    local rest = ((cx - 7) <= td) and G.SET or G.STRUCT
    if (cx - 7) == td then rest = G.SEL end
    G.cled(g, cx, 8, rest)
  end
end

return P
