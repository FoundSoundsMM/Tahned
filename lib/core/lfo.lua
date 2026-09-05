-- lfo.lua -- the LFO shapes, and the one LFO that has to run in lua
--
-- The four LFOs a track owns live in the engine: they scatter into the mod
-- bus and any control channel can be a destination for free. Two things need
-- the shapes on this side of the fence as well.
--
--   the screen   the SPD cell draws the selected wave running at the rate
--                SPD and MULT actually give it, so the cell is a scope
--
--   BPM          the norns clock is not on the control bus and never can be,
--                so a BPM destination is served by running that one LFO here
--                and writing the tempo param. Only while the clock source is
--                internal: with MIDI, Link or crow driving it, the tempo is
--                not ours to move.
--
-- Rate matches tahned_lfo exactly -- hz = spd/64 * mult * bpm/60 / 8 -- so a
-- wave drawn on the screen is the wave the engine is running.

local S = include("tahned/lib/core/spec")

local L = {}

L.MULT = { 1, 2, 4, 8, 16, 32, 64, 128 }

-- Full swing at either end of the depth range. 60 BPM is enough to be a
-- gesture rather than a wobble and still leaves the clock somewhere usable.
L.BPM_RANGE = 60
L.BPM_MIN, L.BPM_MAX = 20, 300

-- 0..1 phase -> -1..1, in the order S.LFOWAVE lists them. RND and S&H are
-- deterministic here rather than random: a scope of a random wave that
-- reshuffles every frame reads as static, and the tempo has to be repeatable.
function L.sample(wave, ph)
  ph = ph % 1
  if wave == 0 then return 1 - (4 * math.abs(ph - 0.5))          -- tri
  elseif wave == 1 then return math.sin(ph * 2 * math.pi)        -- sine
  elseif wave == 2 then return (ph < 0.5) and 1 or -1            -- square
  elseif wave == 3 then return 1 - (ph * 2)                      -- saw down
  elseif wave == 4 then return (ph * 2) - 1                      -- ramp up
  elseif wave == 5 then return (((1 - ph) ^ 3) * 2) - 1          -- exp
  elseif wave == 6 then
    -- smooth random: cosine interpolation between eight fixed nodes
    local function node(i)
      local x = math.sin((i % 8) * 12.9898) * 43758.5453
      return ((x - math.floor(x)) * 2) - 1
    end
    local t = ph * 8
    local i = math.floor(t)
    local f = (1 - math.cos((t - i) * math.pi)) / 2
    return node(i) + ((node(i + 1) - node(i)) * f)
  else
    -- sample and hold: eight steps a cycle, held
    local x = math.sin(math.floor(ph * 8) * 12.9898) * 43758.5453
    return ((x - math.floor(x)) * 2) - 1
  end
end

-- the engine's rate, given SPD (0..127 raw), the MULT index and the tempo
function L.hz(spd, mult_idx, bpm)
  local m = L.MULT[(mult_idx or 0) + 1] or 1
  return util.clamp(((spd or 0) / 64) * m * ((bpm or 120) / 60) / 8, 0.001, 200)
end

-- ------------------------------------------------------------------- BPM

-- Phases are keyed by track and LFO so the tempo keeps moving smoothly when
-- the page changes under it. Kept on the module: tahned.lua includes it once
-- and is the only caller that drives it.
L.phase = {}
L.base = nil        -- the tempo the modulation swings around
L.wrote = nil       -- the last tempo we set, so a user edit is distinguishable

local function internal_clock()
  local ok, src = pcall(function() return params:get("clock_source") end)
  return not ok or src == nil or src == 1
end

-- The first LFO with a BPM destination and a depth wins, walking tracks then
-- LFOs. Two of them fighting over one clock is not a thing worth arranging.
local function find(tracks)
  for ti, t in ipairs(tracks) do
    for n = 1, 4 do
      local b = 56 + ((n - 1) * 8)
      for _, o in ipairs({ 4, 6 }) do
        local dep = t:raw(b + o + 1) or 0
        if t:raw(b + o) == S.BPM_DEST and dep ~= 0 then
          return { key = ti .. ":" .. n .. ":" .. o, spd = t:raw(b) or 0,
                   mult = t:raw(b + 1) or 0, wave = t:raw(b + 2) or 0, dep = dep }
        end
      end
    end
  end
  return nil
end

-- Called on a timer with the seconds since the last call. Returns true while
-- it owns the tempo, so the caller knows the screen is moving.
function L.step(tracks, dt)
  local cur = params:get("clock_tempo")
  -- anything that moved the tempo other than us becomes the new centre
  if L.wrote == nil or math.abs(cur - L.wrote) > 0.05 then L.base = cur end

  local m = internal_clock() and find(tracks) or nil
  if not m then
    if L.wrote ~= nil then
      -- hand the clock back where it was found, once
      if L.base then params:set("clock_tempo", L.base) end
      L.wrote, L.phase = nil, {}
    end
    return false
  end

  local base = L.base or cur
  local hz = L.hz(m.spd, m.mult, base)
  local ph = ((L.phase[m.key] or 0) + (hz * dt)) % 1
  L.phase[m.key] = ph

  local v = L.sample(m.wave, ph) * (m.dep / 63) * L.BPM_RANGE
  local want = util.clamp(base + v, L.BPM_MIN, L.BPM_MAX)
  -- the tempo param reaches the engine and every running clock, so only move
  -- it when the move is worth hearing
  if L.wrote == nil or math.abs(want - L.wrote) >= 0.1 then
    L.wrote = want
    params:set("clock_tempo", want)
  end
  return true
end

function L.release()
  if L.wrote ~= nil and L.base then params:set("clock_tempo", L.base) end
  L.wrote, L.phase = nil, {}
end

return L
