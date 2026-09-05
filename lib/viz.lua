-- viz.lua
-- the reactive layer. every event writes a decaying spike at an address;
-- grid and screen renderers read those spikes and are otherwise pure
-- functions of the model. nothing here draws anything.

local bus = include('lib/bus')

local viz = {}

viz.env = {}       -- addr -> {v = level, d = decay per second, s = style}
viz.count = 0
viz.level = 0      -- master audio level from the engine poll
viz.beat = 0       -- 0..1 phase of the current beat, for structure pulsing

-- address helpers. numeric keys, because these tables are walked every frame.
function viz.a_grid(x, y)  return 10000 + (y * 16) + x end
function viz.a_node(id)    return 20000 + id end
function viz.a_lane(id)    return 30000 + id end
function viz.a_gest(id)    return 40000 + id end
function viz.a_edge(a, b)  return 50000 + (a * 32) + b end
function viz.a_ball(id)    return 60000 + id end
function viz.a_deg(d)      return 70000 + (d % 128) end

-- decay rates by event character: a trig snaps, a morph glides
viz.SNAP  = 7.0
viz.HIT   = 4.5
viz.GLIDE = 1.4
viz.SLOW  = 0.6

function viz.spike(addr, level, decay, style)
  local e = viz.env[addr]
  if e == nil then
    viz.env[addr] = { v = level, d = decay or viz.HIT, s = style or 0 }
    viz.count = viz.count + 1
  else
    if level > e.v then e.v = level end
    e.d = decay or e.d
    if style then e.s = style end
  end
end

function viz.get(addr)
  local e = viz.env[addr]
  if e == nil then return 0 end
  return e.v
end

function viz.style(addr)
  local e = viz.env[addr]
  if e == nil then return 0 end
  return e.s
end

-- returns the spike scaled into a 0..n LED/level range
function viz.lit(addr, n)
  local e = viz.env[addr]
  if e == nil then return 0 end
  return e.v * (n or 15)
end

-- brightness grammar: a resting level, lifted toward 15 by activity.
-- this is the single function that makes the whole surface feel alive, so
-- every page draws through it rather than doing its own arithmetic.
function viz.led(rest, addr)
  local e = viz.env[addr]
  if e == nil then return rest end
  local v = e.v
  if v <= 0 then return rest end
  return math.floor(rest + ((15 - rest) * v) + 0.5)
end

function viz.update(dt)
  local env = viz.env
  local dead = nil
  for k, e in pairs(env) do
    e.v = e.v - (e.d * dt * e.v + 0.0008)
    if e.v <= 0.004 then
      if dead == nil then dead = {} end
      dead[#dead + 1] = k
    end
  end
  if dead then
    for i = 1, #dead do env[dead[i]] = nil end
    viz.count = viz.count - #dead
  end
end

function viz.clear()
  viz.env = {}
  viz.count = 0
end

-- wire the standard events. subsystems don't know the viz layer exists.
function viz.init()
  bus.on('note', function(e)
    viz.spike(viz.a_node(e.node), 1.0, viz.HIT)
    if e.voice then viz.spike(viz.a_lane(e.voice), 1.0, viz.SNAP) end
    if e.degree then viz.spike(viz.a_deg(e.degree), 1.0, viz.GLIDE) end
  end)

  bus.on('trig', function(e)
    viz.spike(viz.a_node(e.node), e.vel or 1.0, viz.SNAP)
  end)

  bus.on('collision', function(e)
    viz.spike(viz.a_ball(e.ball), 1.0, viz.SNAP)
    if e.node then viz.spike(viz.a_node(e.node), e.vel or 1.0, viz.HIT) end
  end)

  bus.on('gesture', function(e)
    viz.spike(viz.a_gest(e.lane), math.abs(e.value or 0), viz.GLIDE)
  end)

  bus.on('mod', function(e)
    if e.dst then viz.spike(viz.a_edge(e.src or 0, e.dst), 0.7, viz.GLIDE) end
  end)

  bus.on('morph', function(e)
    viz.spike(viz.a_node(0), 1.0, viz.SLOW)
  end)

  bus.on('chord', function(e)
    if e.degrees then
      for i = 1, #e.degrees do
        viz.spike(viz.a_deg(e.degrees[i]), 1.0, viz.GLIDE)
      end
    end
  end)
end

return viz
