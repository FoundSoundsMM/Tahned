-- bus.lua
-- typed event bus. every musically meaningful thing publishes here; nothing
-- calls anything else directly. the viz layer is just another subscriber,
-- which is what keeps draw code out of the sequencer callbacks.

local bus = {}

bus.subs = {}

-- event types, for reference and for typo-catching in debug builds
bus.TYPES = {
  note = true,        -- {node, voice, hz, amp, degree}
  trig = true,        -- {node, lane, step, vel}
  collision = true,   -- {ball, node, vel, angle}
  mod = true,         -- {src, dst, value}
  gesture = true,     -- {lane, value, state}
  morph = true,       -- {a, b, c, x, y}
  chord = true,       -- {degrees, tension}
  patch = true,       -- {kind, ...} structural change
  page = true,        -- {page}
  scene = true,       -- {scene}
  perturb = true,     -- {scope, amount}
}

function bus.on(t, fn)
  if bus.subs[t] == nil then bus.subs[t] = {} end
  table.insert(bus.subs[t], fn)
  return fn
end

function bus.off(t, fn)
  local s = bus.subs[t]
  if s == nil then return end
  for i = #s, 1, -1 do
    if s[i] == fn then table.remove(s, i) end
  end
end

function bus.emit(t, ev)
  local s = bus.subs[t]
  if s == nil then return end
  ev = ev or {}
  ev.type = t
  for i = 1, #s do s[i](ev) end
end

function bus.clear()
  bus.subs = {}
end

return bus
