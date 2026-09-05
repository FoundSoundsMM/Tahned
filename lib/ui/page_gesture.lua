-- ui/page_gesture.lua
-- all thirty-two lanes visible at once in the top-left block, because banking
-- modulation is miserable. hold a lane to record, tap to arm.

local viz = include('lib/viz')

local P = {}

P.glyphs = { k2 = 'a_rec', k3 = 'a_clear' }
P.recording = nil

local SPEEDS = { -2, -1.5, -1, -0.75, -0.5, -0.25, -0.125, 0, 0.125, 0.25, 0.5, 0.75, 1, 1.5, 2 }
P.SRC = { 'enc', 'ball', 'mx', 'my', 'lvl', 'lane' }

local function lane_at(cx, cy)
  if cx > 8 or cy > 4 then return nil end
  return ((cy - 1) * 8) + cx
end

function P.key(ctx, cx, cy, z)
  local m = ctx.m
  local G = ctx.G

  local id = lane_at(cx, cy)
  if id then
    if z == 1 then
      m.ui.sel_gest = id
      P.pending = { id = id, t = (util.time and util.time() or os.clock()) }
    else
      local held = (util.time and util.time() or os.clock()) - (P.pending and P.pending.t or 0)
      if P.recording == id then
        ctx.gesture.rec_stop(m, id)
        P.recording = nil
      elseif held > 0.4 then
        ctx.gesture.rec_start(m, id)
        P.recording = id
      else
        ctx.gesture.toggle(m, id)
      end
      P.pending = nil
    end
    return
  end

  if z == 0 then return end
  local sel = m.ui.sel_gest
  local gg = m.gest[sel]

  if cy <= 4 and cx >= 10 then
    local col = cx - 9              -- 1..6
    if cy == 1 then
      gg.gen = math.min(6, col)
    elseif cy == 2 then
      gg.mode = math.min(4, col)
    elseif cy == 3 then
      gg.src = math.min(6, col) - 1
    else
      if col == 1 then ctx.gesture.retrig(m, sel)
      elseif col == 6 then ctx.gesture.clear(m, sel) end
    end
    return
  end

  if cy == 5 then
    gg.speed = SPEEDS[cx]
  elseif cy == 6 then
    gg.offset = ((cx - 8) / 7)
  elseif cy == 7 then
    gg.atten = (cx - 1) / 14
  elseif cy == 8 then
    gg.rate = 0.02 * (1.42 ^ (cx - 1))
  end
end

function P.enc(ctx, e, d)
  local m = ctx.m
  local gg = m.gest[m.ui.sel_gest]
  if e == 1 then
    m.ui.sel_gest = util.clamp(m.ui.sel_gest + d, 1, 32)
  elseif e == 2 then
    gg.atten = util.clamp(gg.atten + (d * 0.01), 0, 1)
    -- an encoder move is also the thing a lane records, when it is armed
    if P.recording then ctx.gesture.rec_write(m, P.recording, (gg.atten * 2) - 1) end
  elseif e == 3 then
    gg.speed = util.clamp(gg.speed + (d * 0.01), -2, 2)
  end
end

-- the lane records whatever the player is moving, wherever they are
function P.feed(ctx, v)
  if P.recording then ctx.gesture.rec_write(ctx.m, P.recording, v) end
end

function P.k2(ctx, z)
  if z == 0 then return end
  local m = ctx.m
  local sel = m.ui.sel_gest
  if P.recording == sel then
    ctx.gesture.rec_stop(m, sel)
    P.recording = nil
  else
    ctx.gesture.rec_start(m, sel)
    P.recording = sel
  end
end

function P.k3(ctx, z)
  if z == 0 then return end
  ctx.gesture.clear(ctx.m, ctx.m.ui.sel_gest)
end

function P.draw(ctx, g, G)
  local m = ctx.m
  local sel = m.ui.sel_gest

  for cy = 1, 4 do
    for cx = 1, 8 do
      local id = lane_at(cx, cy)
      local gg = m.gest[id]
      local rest = G.STRUCT
      if ctx.gesture.has(id) or gg.gen > 1 then rest = G.AVAIL end
      if gg.playing then rest = G.SET end
      if gg.rec then rest = G.FIRE end
      if id == sel then rest = G.SEL end
      G.cled(g, cx, cy, rest, viz.a_gest(id))
    end
  end

  local gg = m.gest[sel]
  for cx = 10, 15 do
    local col = cx - 9
    G.cled(g, cx, 1, (gg.gen == col) and G.SEL or G.AVAIL)
    G.cled(g, cx, 2, (col <= 4) and ((gg.mode == col) and G.SEL or G.AVAIL) or G.OFF)
    G.cled(g, cx, 3, (gg.src == col - 1) and G.SEL or G.AVAIL)
    if col == 1 then G.cled(g, cx, 4, G.AVAIL)
    elseif col == 6 then G.cled(g, cx, 4, G.STRUCT)
    else G.cled(g, cx, 4, G.OFF) end
  end

  local si = 8
  for i = 1, 15 do
    if math.abs(SPEEDS[i] - gg.speed) < 0.06 then si = i end
  end
  for cx = 1, 15 do
    G.cled(g, cx, 5, (cx == si) and G.SEL or ((cx == 8) and G.AVAIL or G.STRUCT))
  end

  local oi = math.floor((gg.offset * 7) + 8.5)
  for cx = 1, 15 do
    G.cled(g, cx, 6, (cx == oi) and G.SEL or ((cx == 8) and G.AVAIL or G.STRUCT))
  end

  G.bar(g, 7, gg.atten, G.SET)

  local ri = util.clamp(math.floor((math.log(math.max(gg.rate, 0.02) / 0.02) / math.log(1.42)) + 1.5), 1, 15)
  for cx = 1, 15 do
    G.cled(g, cx, 8, (cx == ri) and G.SEL or G.STRUCT)
  end
end

return P
