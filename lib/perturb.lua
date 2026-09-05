-- perturb.lua
-- the dice, done properly. a bounded random walk from wherever the parameter
-- already is, with a heavy tail so most moves are small and a few are not --
-- never a re-roll, and always undoable.

local paths = include('lib/paths')
local bus = include('lib/bus')

local perturb = {}

perturb.ring = {}
perturb.ring_n = 0
perturb.RING = 16

-- cauchy-ish: mostly small, occasionally a jump. this is the difference
-- between a machine that evolves and a machine that resets.
local function jitter(amount)
  local u = math.random()
  local t = math.tan(math.pi * (u - 0.5))
  return amount * t * 0.16
end

function perturb.push(m)
  perturb.ring_n = perturb.ring_n + 1
  perturb.ring[((perturb.ring_n - 1) % perturb.RING) + 1] = paths.capture(m)
end

function perturb.undo(m)
  if perturb.ring_n == 0 then return false end
  local snap = perturb.ring[((perturb.ring_n - 1) % perturb.RING) + 1]
  perturb.ring_n = perturb.ring_n - 1
  if snap == nil then return false end
  paths.restore(m, snap)
  return true
end

-- filter: nil for everything, or a predicate on the path entry
-- mask: nil for every class, or a set of class names
function perturb.apply(m, amount, filter, mask)
  perturb.push(m)
  local list = paths.list
  local n = 0
  for i = 1, #list do
    local e = list[i]
    if (filter == nil or filter(e)) and (mask == nil or mask[e.cls]) then
      local v = e.get(m)
      local range = e.hi - e.lo
      if e.k == 'd' then
        if math.random() < (amount * 0.35) then
          local step = (math.random() < 0.5) and -1 or 1
          if range > 8 then step = math.floor(jitter(amount) * range) end
          v = v + step
          if v < e.lo then v = e.hi elseif v > e.hi then v = e.lo end
          e.set(m, v)
          n = n + 1
        end
      else
        local d = jitter(amount) * range
        if math.abs(d) > 1e-6 then
          v = v + d
          if v < e.lo then v = e.lo elseif v > e.hi then v = e.hi end
          if e.k == 'i' then v = math.floor(v + 0.5) end
          e.set(m, v)
          n = n + 1
        end
      end
    end
  end
  bus.emit('perturb', { amount = amount, n = n })
  return n
end

-- scope helpers, matching the page the player is looking at
function perturb.scope_all() return nil end

function perturb.scope_voice(v)
  local pre = 'v' .. v .. '.'
  return function(e) return e.key:sub(1, #pre) == pre end
end

function perturb.scope_node(id, voice)
  local pl, pn = 'l' .. id .. '.', 'n' .. id .. '.'
  local pv = voice and ('v' .. voice .. '.') or nil
  return function(e)
    local k = e.key
    if k:sub(1, #pl) == pl or k:sub(1, #pn) == pn then return true end
    if pv and k:sub(1, #pv) == pv then return true end
    return false
  end
end

function perturb.scope_class(cls)
  return function(e) return e.cls == cls end
end

-- what each page hands to perturb, so the gesture means "mess with what I am
-- looking at" on every page
perturb.PAGE_MASK = {
  [1] = { macro = true, voice = true, env = true, trans = true },
  [2] = { matrix = true },
  [3] = { field = true, lane = true },
  [4] = { harm = true, reg = true },
  [5] = { macro = true, trans = true, env = true },
  [6] = { time = true },
  [7] = { macro = true, voice = true, lane = true, harm = true },
  [8] = { lane = true, cond = true, time = true },
}

return perturb
