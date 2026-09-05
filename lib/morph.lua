-- morph.lua
-- A/B/C snapshots and a barycentric pad between them. interpolation is
-- type-aware: continuous values lerp, integers lerp then round, and discrete
-- values switch to whichever corner is winning -- with hysteresis, so a hand
-- resting on a boundary does not chatter the lane sources.

local paths = include('lib/paths')
local bus = include('lib/bus')

local morph = {}

morph.snap = { nil, nil, nil }
morph.cur = { 0.34, 0.33, 0.33 }
morph.disc = {}
morph.armed = false

-- corners of the pad: A bottom-left, B bottom-right, C top-centre
local CX = { 0.0, 1.0, 0.5 }
local CY = { 1.0, 1.0, 0.0 }

function morph.init()
  morph.snap = { nil, nil, nil }
  morph.disc = {}
  morph.armed = false
end

function morph.store(m, i)
  morph.snap[i] = paths.capture(m)
  morph.armed = morph.snap[1] ~= nil and morph.snap[2] ~= nil and morph.snap[3] ~= nil
end

function morph.clear(i)
  morph.snap[i] = nil
  morph.armed = false
end

function morph.has(i) return morph.snap[i] ~= nil end

function morph.weights(x, y)
  local det = ((CY[2] - CY[3]) * (CX[1] - CX[3])) + ((CX[3] - CX[2]) * (CY[1] - CY[3]))
  if math.abs(det) < 1e-9 then return { 1, 0, 0 } end
  local w1 = (((CY[2] - CY[3]) * (x - CX[3])) + ((CX[3] - CX[2]) * (y - CY[3]))) / det
  local w2 = (((CY[3] - CY[1]) * (x - CX[3])) + ((CX[1] - CX[3]) * (y - CY[3]))) / det
  local w3 = 1 - w1 - w2
  local w = { math.max(0, w1), math.max(0, w2), math.max(0, w3) }
  local s = w[1] + w[2] + w[3]
  if s <= 0 then return { 0.34, 0.33, 0.33 } end
  return { w[1] / s, w[2] / s, w[3] / s }
end

function morph.apply(m, x, y)
  if not morph.armed then return false end
  local w = morph.weights(x, y)
  morph.cur = w

  -- which corner owns the discrete values right now
  local win, wv = 1, w[1]
  for i = 2, 3 do if w[i] > wv then win, wv = i, w[i] end end
  local prev = morph.disc_win or win
  if win ~= prev and wv < (w[prev] + 0.08) then win = prev end
  morph.disc_win = win

  local a, b, c = morph.snap[1], morph.snap[2], morph.snap[3]
  local list = paths.list
  for i = 1, #list do
    local e = list[i]
    local k = e.key
    local va, vb, vc = a[k], b[k], c[k]
    if va ~= nil and vb ~= nil and vc ~= nil then
      if e.k == 'd' then
        e.set(m, ({ va, vb, vc })[win])
      else
        local v = (va * w[1]) + (vb * w[2]) + (vc * w[3])
        if e.k == 'i' then v = math.floor(v + 0.5) end
        if v < e.lo then v = e.lo elseif v > e.hi then v = e.hi end
        e.set(m, v)
      end
    end
  end

  m.morph.x, m.morph.y = x, y
  bus.emit('morph', { x = x, y = y, w = w })
  return true
end

-- morph position is itself a modulation destination: the P900's interpolating
-- morph inputs, arrived at from the other direction
function morph.update(m, dt)
  local mx = m.morph.x + (m.mod_mx or 0)
  local my = m.morph.y + (m.mod_my or 0)
  if m.morph.rate > 0 then
    m.morph.ph = ((m.morph.ph or 0) + (dt * m.morph.rate * 0.1)) % 1
    local a = m.morph.ph * 2 * math.pi
    mx = mx + (math.cos(a) * 0.35)
    my = my + (math.sin(a * 1.37) * 0.35)
  end
  if (m.mod_mx or 0) ~= 0 or (m.mod_my or 0) ~= 0 or m.morph.rate > 0 then
    morph.apply(m, math.max(0, math.min(1, mx)), math.max(0, math.min(1, my)))
  end
end

-- ------------------------------------------------------------------- scenes

function morph.scene_store(m, i)
  m.scenes[i] = {
    p = paths.capture(m),
    mx = m.morph.x, my = m.morph.y,
  }
end

function morph.scene_recall(m, i)
  local s = m.scenes[i]
  if s == nil then return false end
  paths.restore(m, s.p)
  m.morph.x, m.morph.y = s.mx or 0.5, s.my or 0.5
  m.scene_cur = i
  bus.emit('scene', { scene = i })
  return true
end

return morph
