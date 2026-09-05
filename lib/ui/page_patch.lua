-- ui/page_patch.lua
-- thirty-two gesture lanes down, seventy-five destinations across, banked.
-- repeated presses walk the depth round 0 -> +1 -> +2 -> -1 -> -2 -> 0;
-- brightness carries magnitude and the blink phase carries the sign.

local viz = include('lib/viz')

local P = {}

local STEPS = { 0, 0.3, 0.75, -0.3, -0.75 }

P.glyphs = { k2 = 'a_clear', k3 = 'a_link' }
P.last_src = 1
P.last_dst = 1

local function next_depth(d)
  for i = 1, #STEPS do
    if math.abs(STEPS[i] - d) < 0.001 then
      return STEPS[(i % #STEPS) + 1]
    end
  end
  return STEPS[2]
end

function P.key(ctx, cx, cy, z)
  if z == 0 then return end
  local m = ctx.m
  local src = (m.ui.bank_src * 8) + cy
  local dst = (m.ui.bank_dst * 15) + cx
  if src > 32 or dst > ctx.patch.N_DEST then return end

  P.last_src, P.last_dst = src, dst
  m.ui.sel_gest = src

  local cell = ctx.model.mod_get(m, src, dst)
  if ctx.shift then
    -- shift changes how a routing behaves rather than how deep it is
    if cell then
      cell.m = (cell.m % 3) + 1
    end
  else
    local d = cell and cell.d or 0
    ctx.model.mod_set(m, src, dst, next_depth(d), cell and cell.m or 1)
  end
end

function P.enc(ctx, e, d)
  local m = ctx.m
  if e == 1 then
    m.ui.sel_gest = util.clamp(m.ui.sel_gest + d, 1, 32)
    m.ui.bank_src = math.floor((m.ui.sel_gest - 1) / 8)
  elseif e == 2 then
    m.ui.bank_src = util.clamp(m.ui.bank_src + d, 0, 3)
  elseif e == 3 then
    m.ui.bank_dst = util.clamp(m.ui.bank_dst + d, 0, ctx.patch.dest_bank_count() - 1)
  end
end

function P.k2(ctx, z)
  if z == 0 then return end
  local m = ctx.m
  if ctx.shift then
    m.matrix = {}
  else
    m.matrix[P.last_src] = nil
  end
end

function P.k3(ctx, z)
  if z == 0 then return end
  -- route the selected lane to the destination under the cursor at full depth
  ctx.model.mod_set(ctx.m, P.last_src, P.last_dst, 0.75, 1)
end

function P.draw(ctx, g, G)
  local m = ctx.m
  local blink = (math.floor((util.time and util.time() or os.clock()) * 4) % 2) == 0

  for cy = 1, 8 do
    local src = (m.ui.bank_src * 8) + cy
    for cx = 1, 15 do
      local dst = (m.ui.bank_dst * 15) + cx
      local rest = G.STRUCT
      if dst > ctx.patch.N_DEST then
        rest = G.OFF
      else
        local cell = ctx.model.mod_get(m, src, dst)
        if cell then
          local a = math.abs(cell.d)
          rest = (a > 0.5) and G.FIRE or G.SET
          if cell.d < 0 and not blink then rest = G.AVAIL end
          if cell.m == 2 then rest = math.max(G.AVAIL, rest - 3) end
        elseif src == m.ui.sel_gest then
          rest = G.AVAIL
        end
      end
      G.cled(g, cx, cy, rest, viz.a_gest(src))
    end
  end
end

return P
