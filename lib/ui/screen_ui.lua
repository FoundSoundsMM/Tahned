-- ui/screen_ui.lua
-- no words. the patch graph on the left with signal travelling the edges, the
-- selected voice's actual spectrum on the right, and the two context actions
-- as glyphs in the bottom corners.
--
-- the rake is not decoration: it is computed from the same macros the engine
-- is using, so it teaches the synthesis while you play it.

local nd = include('lib/node')
local viz = include('lib/viz')
local glyph = include('lib/glyph')

local S = {}

S.NX = { 4, 18, 32, 46 }
S.NY = { 14, 24, 34, 44 }

local function node_pos(id)
  local col = ((id - 1) % 4) + 1
  local row = math.floor((id - 1) / 4) + 1
  return S.NX[col], S.NY[row]
end

-- ------------------------------------------------------------------ the rake

-- approximate sideband energy: FM spreads power out to about k = index, so a
-- gaussian around the index reads the same as a bessel at this size
local function band_amp(k, idx)
  local d = k - idx
  return math.exp(-(d * d) / (2 * (idx + 0.9))) / (1 + (k * 0.12))
end

local function rake(ctx, v, x0, y0, w, h)
  local m = ctx.m
  local mac = {}
  for i = 1, 6 do mac[i] = ctx.ec.macro_live(v, i) end
  local r = m.voices[v].r
  local idx = (mac[3] ^ 1.6) * 9

  local pairs_ = {
    { r[1], idx * mac[2] },
    { r[2], idx * mac[1] },
    { r[3], idx * mac[1] * mac[2] * 0.6 },
  }

  local parts = {}
  parts[1] = { 1.0, 1.0 }
  for p = 1, 3 do
    local ratio, ii = pairs_[p][1], pairs_[p][2]
    if ii > 0.05 then
      for k = 1, 9 do
        local a = band_amp(k, ii) * 0.9
        if a > 0.02 then
          parts[#parts + 1] = { 1 + (k * ratio), a }
          local lo = math.abs(1 - (k * ratio))
          if lo > 0.05 then parts[#parts + 1] = { lo, a } end
        end
      end
    end
  end

  -- TILT redistributes, so the drawing has to show it redistributing
  local tilt = (mac[4] * 2) - 1
  local maxr = 1
  for i = 1, #parts do maxr = math.max(maxr, parts[i][1]) end
  local sc = w / math.max(4, math.min(maxr, 26))

  screen.level(2)
  screen.rect(x0, y0 + h, w, 1)
  screen.fill()

  for i = 1, #parts do
    local f, a = parts[i][1], parts[i][2]
    a = a * (f ^ (tilt * 0.7))
    if a > 0.015 then
      local x = math.floor(x0 + (f * sc))
      if x >= x0 and x < (x0 + w) then
        local hh = math.max(1, math.floor(math.min(1, a) * h))
        screen.level(math.max(1, math.min(15, math.floor(2 + (a * 16)))))
        screen.rect(x, y0 + h - hh, 1, hh)
        screen.fill()
      end
    end
  end
end

-- ------------------------------------------------------------- the patch graph

local function edges(ctx)
  local m = ctx.m
  local out = {}
  for id = 1, nd.N do
    local n = m.nodes[id]
    local lane = m.lanes[id]
    if n.t == nd.VOICE and m.voices[n.voice].xdepth > 0.02 then
      local src = ctx.model.node_of_voice(m, m.voices[n.voice].xsrc)
      if src and src ~= id then out[#out + 1] = { src, id, m.voices[n.voice].xdepth, lane } end
    end
    if n.t == nd.MULT and lane.a and lane.a ~= id and m.nodes[lane.a].t ~= nd.EMPTY then
      out[#out + 1] = { id, lane.a, 0.8, lane }
    end
    if lane.src == 6 then
      if m.nodes[lane.a] and m.nodes[lane.a].t ~= nd.EMPTY then
        out[#out + 1] = { lane.a, id, 0.4, m.lanes[lane.a] }
      end
      if m.nodes[lane.b] and m.nodes[lane.b].t ~= nd.EMPTY then
        out[#out + 1] = { lane.b, id, 0.4, m.lanes[lane.b] }
      end
    end
  end
  return out
end

local function draw_graph(ctx)
  local m = ctx.m

  for _, e in ipairs(edges(ctx)) do
    local x1, y1 = node_pos(e[1])
    local x2, y2 = node_pos(e[2])
    screen.level(math.max(1, math.floor(e[3] * 4)))
    screen.move(x1 + 2, y1 + 2)
    screen.line(x2 + 2, y2 + 2)
    screen.stroke()
    -- a spark, positioned by where that lane is in its cycle: the polyrhythm
    -- is readable off the screen
    local lane = e[4]
    local t = (lane.pos % math.max(1, lane.len)) / math.max(1, lane.len)
    screen.level(12)
    screen.rect(math.floor(x1 + 2 + ((x2 - x1) * t)), math.floor(y1 + 2 + ((y2 - y1) * t)), 2, 2)
    screen.fill()
  end

  for id = 1, nd.N do
    local n = m.nodes[id]
    local x, y = node_pos(id)
    local lit = viz.led(n.t == nd.EMPTY and 1 or 5, viz.a_node(id))
    if id == m.ui.sel_node then lit = math.max(lit, 12) end
    if n.mute then lit = math.min(lit, 3) end
    glyph.draw(nd.GLYPH[n.t], x, y, lit)
  end
end

-- ------------------------------------------------------------------------ draw

function S.redraw(ctx, G)
  local m = ctx.m
  screen.clear()

  -- header: where you are, what it is tuned to, and how fast
  glyph.draw(glyph.PAGE[m.ui.page], 1, 1, 12)
  glyph.num(20, 7, ctx.tuning:short(), 8)
  if ctx.harmony and ctx.harmony.chord[1] then
    glyph.num(44, 7, ctx.tuning:name(ctx.harmony.chord[1]), 5)
  end

  if ctx.shift then
    glyph.draw('a_hold', 74, 1, 10)
  end
  if not ctx.seq.running then
    glyph.draw('a_stop', 84, 1, 10)
  else
    glyph.draw('a_play', 84, 1, math.floor(4 + (viz.get(viz.a_node(0)) * 8)))
  end
  glyph.num(127, 7, string.format("%.0f", (clock and clock.get_tempo and clock.get_tempo()) or 0), 6, true)

  screen.level(1)
  screen.rect(0, 9, 128, 1)
  screen.fill()

  draw_graph(ctx)

  -- the selected voice, on the right
  local v = m.ui.sel_voice
  local id = ctx.model.node_of_voice(m, v)
  local sel = m.nodes[m.ui.sel_node]
  if sel.voice then v = sel.voice end

  rake(ctx, v, 66, 13, 60, 22)

  -- six macros as arcs, base filled and modulation shown as a ghost mark
  for i = 1, 6 do
    local cx = 71 + ((i - 1) % 3) * 20
    local cy = 45 + math.floor((i - 1) / 3) * 0
    local col = 45 + (math.floor((i - 1) / 3) * 13)
    local base = m.voices[v].macros[i]
    local live = ctx.ec.macro_live(v, i)
    local lvl = (i == m.ui.sel_macro) and 15 or 7
    glyph.arc(cx, col, 5, base, lvl, (math.abs(live - base) > 0.005) and live or nil)
  end

  -- context actions, as glyphs, in the corners
  local page = G and G.cur() or nil
  if page and page.glyphs then
    if page.glyphs.k2 then glyph.draw(page.glyphs.k2, 2, 57, 9) end
    if page.glyphs.k3 then glyph.draw(page.glyphs.k3, 119, 57, 9) end
  end

  -- gesture memory: the one hard ceiling in the instrument, so it gets a bar.
  -- kept left of the macro arcs, which start at x=66.
  local mem = ctx.gesture.mem()
  if mem > 0.01 then
    screen.level(3)
    screen.rect(30, 61, math.max(1, math.floor(mem * 22)), 2)
    screen.fill()
  end

  screen.update()
end

S.rake = rake

return S
