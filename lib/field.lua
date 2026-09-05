-- field.lua
-- the physics sequencer, and the reason this is a grid instrument rather than
-- a menu. balls run free at 60Hz; their collisions are latched and consumed by
-- the sequencer on the next division, so the output is unrepeating but in time.
--
-- unquantised this is mush. quantised it is a groove that never comes round.

local bus = include('lib/bus')
local nd = include('lib/node')

local field = {}

field.W = 15
field.H = 8
field.MAXV = 14.0

field.EMPTY   = 0
field.WALL    = 1
field.MIRRORA = 2   -- /
field.MIRRORB = 3   -- \
field.ATTRACT = 4
field.REPEL   = 5

field.t = 0
field.balls = {}
field.pending = {}      -- pending[node_id] = velocity of the strike
field.nodemap = {}      -- nodemap[y][x] = node id

local function clamp(v, a, b)
  if v < a then return a elseif v > b then return b else return v end
end

function field.init(m)
  field.t = 0
  field.balls = {}
  field.pending = {}
  field.rebuild(m)
end

-- node positions change when the player moves them, so the lookup is rebuilt
-- rather than searched every frame
function field.rebuild(m)
  field.nodemap = {}
  for y = 1, field.H do field.nodemap[y] = {} end
  for i = 1, nd.N do
    local n = m.nodes[i]
    if n.t ~= nd.EMPTY then
      local x = clamp(math.floor(n.x), 1, field.W)
      local y = clamp(math.floor(n.y), 1, field.H)
      field.nodemap[y][x] = i
    end
  end
end

function field.launch(x, y, vx, vy)
  if #field.balls >= 8 then table.remove(field.balls, 1) end
  local b = {
    x = x, y = y, vx = vx, vy = vy,
    m = 1.0,
    cool = {},
    trail = {},
    id = (field.next_id or 0) + 1,
  }
  field.next_id = b.id
  field.balls[#field.balls + 1] = b
  return b
end

function field.clear_balls() field.balls = {} end

function field.cell(m, x, y)
  if x < 1 or x > field.W or y < 1 or y > field.H then return field.WALL end
  return m.field.walls[y][x] or field.EMPTY
end

local function solid(c) return c == field.WALL end
local function mirror(c) return c == field.MIRRORA or c == field.MIRRORB end

-- ------------------------------------------------------------------------ step

local function accelerate(m, b, dt)
  local f = m.field
  local grav = f.grav + (m.mod_grav or 0)
  local mag  = f.mag + (m.mod_mag or 0)
  local wave = f.wave + (m.mod_wave or 0)

  local ax, ay = 0, grav * 6

  if mag ~= 0 then
    for y = 1, field.H do
      local row = f.walls[y]
      for x = 1, field.W do
        local c = row[x]
        if c == field.ATTRACT or c == field.REPEL then
          local dx, dy = x - b.x, y - b.y
          local d2 = (dx * dx) + (dy * dy)
          if d2 > 0.09 then
            local s = (mag * 12) / d2
            if c == field.REPEL then s = -s end
            local d = math.sqrt(d2)
            ax = ax + (s * dx / d)
            ay = ay + (s * dy / d)
          end
        end
      end
    end
  end

  if wave ~= 0 then
    ax = ax + (math.sin((b.y * 0.7) + (field.t * 0.9)) * wave * 5)
    ay = ay + (math.cos((b.x * 0.5) + (field.t * 0.6)) * wave * 5)
  end

  b.vx = b.vx + (ax * dt)
  b.vy = b.vy + (ay * dt)

  local damp = m.field.damp
  if damp < 1.0 then
    local k = damp ^ (dt * 60)
    b.vx = b.vx * k
    b.vy = b.vy * k
  end

  local sp = math.sqrt((b.vx * b.vx) + (b.vy * b.vy))
  if sp > field.MAXV then
    b.vx = b.vx * field.MAXV / sp
    b.vy = b.vy * field.MAXV / sp
  end
end

local function strike(m, b, id, sp, angle)
  local cd = b.cool[id] or 0
  if field.t - cd < 0.06 then return end
  b.cool[id] = field.t
  local v = clamp(sp / 8.0, 0.05, 1.0)
  -- angle of incidence becomes a modulation value, as it does on the P900
  field.pending[id] = { vel = v, ang = (angle / math.pi + 1) * 0.5 }
  bus.emit('collision', { ball = b.id, node = id, vel = v, angle = angle })
end

local function hit(m, b, cx, cy, sp)
  local id = field.nodemap[cy] and field.nodemap[cy][cx]
  if id then
    strike(m, b, id, sp, math.atan(b.vy, b.vx))
    return true
  end
  return false
end

local function deflect(m, b, cx, cy)
  local c = field.cell(m, cx, cy)
  if c == field.MIRRORA then
    b.vx, b.vy = -b.vy, -b.vx
  elseif c == field.MIRRORB then
    b.vx, b.vy = b.vy, b.vx
  end
end

function field.step(m, dt)
  if not m.field.on then return end
  local speed = m.field.speed + (m.mod_fspeed or 0)
  dt = dt * clamp(speed, 0.05, 4)
  field.t = field.t + dt

  for bi = #field.balls, 1, -1 do
    local b = field.balls[bi]
    accelerate(m, b, dt)

    local sp = math.sqrt((b.vx * b.vx) + (b.vy * b.vy))
    -- substep so a fast ball cannot tunnel through a wall
    local n = math.max(1, math.ceil(sp * dt / 0.3))
    local h = dt / n

    for _ = 1, n do
      -- x axis
      local nx = b.x + (b.vx * h)
      local cx, cy = math.floor(nx + 0.5), math.floor(b.y + 0.5)
      local c = field.cell(m, cx, cy)
      local blocked = solid(c) or (field.nodemap[cy] and field.nodemap[cy][cx] ~= nil)
      if blocked then
        if not hit(m, b, cx, cy, sp) then deflect(m, b, cx, cy) end
        b.vx = -b.vx
      elseif mirror(c) then
        deflect(m, b, cx, cy)
      else
        b.x = nx
      end

      -- y axis
      local ny = b.y + (b.vy * h)
      cx, cy = math.floor(b.x + 0.5), math.floor(ny + 0.5)
      c = field.cell(m, cx, cy)
      blocked = solid(c) or (field.nodemap[cy] and field.nodemap[cy][cx] ~= nil)
      if blocked then
        if not hit(m, b, cx, cy, sp) then deflect(m, b, cx, cy) end
        b.vy = -b.vy
      elseif mirror(c) then
        deflect(m, b, cx, cy)
      else
        b.y = ny
      end

      b.x = clamp(b.x, 1, field.W)
      b.y = clamp(b.y, 1, field.H)
    end

    local tr = b.trail
    tr[#tr + 1] = { b.x, b.y }
    while #tr > 6 do table.remove(tr, 1) end

    -- a ball that has lost all its energy is removed rather than left to sulk
    if math.abs(b.vx) + math.abs(b.vy) < 0.05 and m.field.grav == 0 then
      table.remove(field.balls, bi)
    end
  end
end

-- the sequencer consumes strikes on its own division; this is the quantiser
function field.consume(id)
  local p = field.pending[id]
  if p then field.pending[id] = nil end
  return p
end

function field.n_balls() return #field.balls end

return field
