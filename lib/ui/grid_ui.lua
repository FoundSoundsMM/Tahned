-- ui/grid_ui.lua
-- page dispatch and the brightness grammar. every page draws through
-- grid_ui.led so that the seven levels mean exactly one thing each, everywhere.
-- column 1 is the page selector; pages see content columns 1..15.

local viz = include('lib/viz')
local bus = include('lib/bus')
local glyph = include('lib/glyph')

local G = {}

-- the grammar. nothing on the grid is ever lit at a level outside this table.
G.OFF    = 0
G.STRUCT = 2
G.AVAIL  = 4
G.SET    = 8
G.SEL    = 11
G.HELD   = 13
G.FIRE   = 15

G.W = 16
G.H = 8
G.CW = 15          -- content width

G.pages = {}
G.names = { 'map', 'patch', 'field', 'lattice', 'timbre', 'gesture', 'morph', 'groove' }
G.held = {}
G.n_held = 0
G.ctx = nil
G.dirty = true

local function now()
  if util and util.time then return util.time() end
  return os.clock()
end

function G.init(ctx)
  G.ctx = ctx
  G.held = {}
  for y = 1, G.H do G.held[y] = {} end
  G.pages = {
    include('lib/ui/page_map'),
    include('lib/ui/page_patch'),
    include('lib/ui/page_field'),
    include('lib/ui/page_lattice'),
    include('lib/ui/page_timbre'),
    include('lib/ui/page_gesture'),
    include('lib/ui/page_morph'),
    include('lib/ui/page_groove'),
  }
  for i = 1, #G.pages do
    if G.pages[i].init then G.pages[i].init(ctx) end
  end
end

function G.page() return G.ctx.m.ui.page end

function G.set_page(p)
  local m = G.ctx.m
  if p == m.ui.page then return end
  m.ui.page = p
  bus.emit('page', { page = p })
  G.dirty = true
end

function G.cur()
  return G.pages[G.ctx.m.ui.page]
end

-- ------------------------------------------------------------------- held keys

function G.is_held(x, y)
  return G.held[y] and G.held[y][x] ~= nil
end

function G.held_time(x, y)
  local t = G.held[y] and G.held[y][x]
  if t == nil then return 0 end
  return now() - t
end

-- the other key held down in the same row, for two-finger range gestures
function G.partner_in_row(y, x)
  local row = G.held[y]
  if row == nil then return nil end
  for k, _ in pairs(row) do
    if k ~= x then return k end
  end
  return nil
end

function G.held_count() return G.n_held end

-- ------------------------------------------------------------------------- key

function G.key(x, y, z)
  local ctx = G.ctx
  if ctx == nil then return end
  G.dirty = true

  if z == 1 then
    G.held[y][x] = now()
    G.n_held = G.n_held + 1
  else
    if G.held[y][x] ~= nil then G.n_held = math.max(0, G.n_held - 1) end
  end

  -- page column, plus the set slots under shift. a slot is recalled on a tap
  -- and stored on a hold, so saving needs no second gesture and no naming.
  if x == 1 then
    if z == 1 then
      if not ctx.shift then G.set_page(y) end
      viz.spike(viz.a_grid(1, y), 1.0, viz.SNAP)
    else
      if ctx.shift then ctx.set_slot(y, G.held_time(x, y)) end
      G.held[y][x] = nil
    end
    return
  end

  local page = G.cur()
  if page and page.key then page.key(ctx, x - 1, y, z) end

  if z == 0 then G.held[y][x] = nil end
end

function G.enc(n, d)
  local page = G.cur()
  if page and page.enc then return page.enc(G.ctx, n, d) end
end

function G.k2(z)
  local page = G.cur()
  if page and page.k2 then page.k2(G.ctx, z) end
end

function G.k3(z)
  local page = G.cur()
  if page and page.k3 then page.k3(G.ctx, z) end
end

-- ---------------------------------------------------------------------- drawing

-- the one place a resting level is lifted by activity
function G.led(g, x, y, rest, addr)
  local v = rest
  if addr then v = viz.led(rest, addr) end
  if G.held[y] and G.held[y][x] and v < G.HELD then v = G.HELD end
  if v > 0 then g:led(x, y, math.min(15, math.floor(v))) end
end

-- content coordinates: pages think in 1..15, the grid is 2..16
function G.cled(g, cx, cy, rest, addr)
  G.led(g, cx + 1, cy, rest, addr)
end

-- a 2x2 node quad-glyph at content position (cx, cy)
function G.quad(g, cx, cy, pattern, rest, addr)
  local lit = viz.led(rest, addr)
  local q = pattern
  if q[1] == 1 then G.cled(g, cx,     cy,     lit) end
  if q[2] == 1 then G.cled(g, cx + 1, cy,     lit) end
  if q[3] == 1 then G.cled(g, cx,     cy + 1, lit) end
  if q[4] == 1 then G.cled(g, cx + 1, cy + 1, lit) end
end

-- a 15-wide value bar. `ghost` marks where modulation has pushed the value.
function G.bar(g, cy, val, level, ghost, x0, w)
  x0 = x0 or 1
  w = w or G.CW
  local n = math.floor((val * w) + 0.5)
  for i = 1, w do
    local rest = G.STRUCT
    if i <= n then rest = level or G.SET end
    if i == n then rest = G.SEL end
    if ghost then
      local gn = math.floor((ghost * w) + 0.5)
      if i == gn and i ~= n then rest = math.max(rest, 6) end
    end
    G.cled(g, x0 + i - 1, cy, rest)
  end
end

function G.redraw(g)
  g:all(0)

  -- page column: structure, with the current page selected and a pulse when
  -- a page's subsystem fires while you are looking elsewhere
  for y = 1, G.H do
    local rest = G.STRUCT
    if y == G.page() then rest = G.SEL end
    if G.ctx.shift then
      rest = G.ctx.set_slot_level and G.ctx.set_slot_level(y) or G.AVAIL
      if y == G.page() then rest = math.max(rest, G.SEL) end
    end
    G.led(g, 1, y, rest, viz.a_grid(1, y))
  end

  local page = G.cur()
  if page and page.draw then page.draw(G.ctx, g, G) end

  g:refresh()
end

G.viz = viz
G.glyph = glyph

return G
