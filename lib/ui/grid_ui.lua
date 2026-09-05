-- grid_ui.lua -- 128 (16x8)
--
-- What the grid shows depends on the selected track's machine:
--
--   perc    all eight rows are steps, 16 per row, up to 128
--   tone    rows 1-4 are 64 steps, rows 5-8 an isomorphic keyboard
--   amb     eight rows are the drone's eight trigger lanes, 16 steps each
--
-- Holding K2+K3 replaces all of it with track select, machine select, mutes
-- and transport.
--
-- Holding a step pad and turning an encoder writes a parameter lock onto that
-- step rather than changing the track. A quick press toggles the step.

local S = include("tahned/lib/core/spec")

local G = {}
local HOLD_TIME = 0.28

G.g = nil
G.state = nil

function G.init(state)
  G.state = state
  G.g = grid.connect()
  G.g.key = function(x, y, z) G.key(x, y, z) end
end

-- ------------------------------------------------------------- addressing

local function perc_step(x, y) return ((y - 1) * 16) + x end
local function tone_step(x, y) return ((y - 1) * 16) + x end

-- isomorphic: one scale degree per column, a third per row
function G.kb_note(sq, x, y)
  local arr = sq:scale_array()
  local per_oct = math.max(1, math.floor(#arr / 10))
  local deg = (x - 1) + ((8 - y) * 3)
  local idx = ((sq.s.octave or 3) * per_oct) + deg + 1
  return arr[util.clamp(idx, 1, #arr)]
end

-- ------------------------------------------------------------------ leds

local function step_level(sq, st, idx, head, len, held)
  if idx > len then return 0 end
  if held then return 15 end
  if idx == head then return 15 end
  if st and st.on then
    return util.round(util.linlin(0, 127, 5, 12, st.vel or 100))
  end
  return ((idx - 1) % 4 == 0) and 3 or 1
end

function G.redraw()
  local st8 = G.state
  if not G.g then return end
  G.g:all(0)

  if st8.mode == "select" then
    for i = 1, 8 do
      local t = st8.tracks[i]
      local sel = (i == st8.sel)
      for x = 1, 8 do G.g:led(x, i, sel and 12 or 3) end
      for m = 1, 3 do
        G.g:led(9 + m, i, (t.machine == m) and 14 or 2)
      end
      G.g:led(14, i, t.mute and 12 or 2)
    end
    G.g:led(16, 1, st8.playing and 15 or 5)
    G.g:led(16, 2, 4)
    G.g:refresh()
    return
  end

  local t = st8.track()
  local sq = t:seq()

  if sq.kind == "amb" then
    for l = 1, 8 do
      local ln = sq.lane[l]
      local sel = (l == (sq.s.lane or 1))
      for x = 1, 16 do
        local s = ln.steps[x]
        local lv
        if x > ln.length then lv = 0
        elseif x == ln.last then lv = 15
        elseif s and s.on then lv = util.round(util.linlin(0, 127, 5, 12, s.vel or 100))
        else lv = ((x - 1) % 4 == 0) and (sel and 4 or 2) or (sel and 2 or 1) end
        if st8.held[l * 100 + x] then lv = 15 end
        G.g:led(x, l, lv)
      end
    end

  elseif sq.kind == "tone" then
    local len = sq:length()
    for y = 1, 4 do
      for x = 1, 16 do
        local i = tone_step(x, y)
        G.g:led(x, y, step_level(sq, sq.steps[i], i, sq.last, len, st8.held[i]))
      end
    end
    -- keyboard: scale roots brighter, notes on the held step brighter still
    local hs = st8.lock_step and sq.steps[st8.lock_step]
    local root = (sq.s.root or 0) % 12
    for y = 5, 8 do
      for x = 1, 16 do
        local n = G.kb_note(sq, x, y)
        local lv = ((n % 12) == root) and 4 or 2
        if hs and hs.notes then
          for _, hn in ipairs(hs.notes) do if hn == n then lv = 13 end end
        end
        if st8.playing_notes and st8.playing_notes[n] then lv = 15 end
        G.g:led(x, y, lv)
      end
    end

  else
    local len = sq:length()
    for y = 1, 8 do
      for x = 1, 16 do
        local i = perc_step(x, y)
        G.g:led(x, y, step_level(sq, sq.steps[i], i, sq.last, len, st8.held[i]))
      end
    end
  end

  G.g:refresh()
end

-- ------------------------------------------------------------------ keys

local function press_step(sq, idx, key, lane)
  local st8 = G.state
  local existing = sq:get_step(idx, lane)
  if existing then
    -- keep it, and let the hold become a parameter lock
    st8.held[key] = { t = util.time(), idx = idx, lane = lane, existed = true, locked = false }
  else
    sq:ensure(idx, lane)
    st8.held[key] = { t = util.time(), idx = idx, lane = lane, existed = false, locked = false }
  end
  st8.lock_step, st8.lock_lane = idx, lane or 1
  st8.dirty = true
end

local function release_step(sq, key)
  local st8 = G.state
  local h = st8.held[key]
  st8.held[key] = nil
  if not h then return end
  -- a quick press on an existing step clears it; a hold was a lock gesture
  if h.existed and not h.locked and (util.time() - h.t) < HOLD_TIME then
    local store = sq:store(h.lane or 1)
    store[h.idx] = nil
  end
  if st8.lock_step == h.idx then st8.lock_step = nil end
  st8.dirty = true
end

function G.key(x, y, z)
  local st8 = G.state

  if st8.mode == "select" then
    if z == 1 then
      if x <= 8 then
        st8.select_track(y)
      elseif x >= 10 and x <= 12 then
        st8.tracks[y]:set_machine(x - 9)
        if y == st8.sel then st8.dirty = true end
      elseif x == 14 then
        st8.tracks[y]:set_mute(not st8.tracks[y].mute)
      elseif x == 16 and y == 1 then
        st8.toggle_play()
      elseif x == 16 and y == 2 then
        st8.reset()
      end
      st8.dirty = true
    end
    return
  end

  local t = st8.track()
  local sq = t:seq()

  if sq.kind == "amb" then
    local key = (y * 100) + x
    if z == 1 then
      sq.s.lane = y
      press_step(sq, x, key, y)
    else
      release_step(sq, key)
    end
    return
  end

  if sq.kind == "tone" and y >= 5 then
    local n = G.kb_note(sq, x, y)
    st8.playing_notes = st8.playing_notes or {}
    if z == 1 then
      st8.playing_notes[n] = true
      -- with a step held, the keyboard writes notes onto that step
      if st8.lock_step then
        local step = sq:ensure(st8.lock_step)
        step.notes = step.notes or {}
        local found
        for i, hn in ipairs(step.notes) do if hn == n then found = i end end
        if found then table.remove(step.notes, found)
        else table.insert(step.notes, n) end
        local h = st8.held[st8.lock_step]
        if h then h.locked = true end
      else
        t:note_on(9000 + n, n, 0.9)
      end
    else
      st8.playing_notes[n] = nil
      if not st8.lock_step then t:note_off(9000 + n) end
    end
    st8.dirty = true
    return
  end

  local idx = perc_step(x, y)
  if idx > sq.maxlen then return end
  if z == 1 then press_step(sq, idx, idx) else release_step(sq, idx) end
end

-- ------------------------------------------------- encoder while holding

-- Sequencer settings that mean something on a single step. Length, speed and
-- direction describe the whole pattern, so they are not among them.
local STEP_SEQ = { prob = true, ratchet = true, gate = true, density = true }

local function mark_held(st8, sq)
  local key = (sq.kind == "amb")
    and ((st8.lock_lane * 100) + st8.lock_step) or st8.lock_step
  local h = st8.held[key]
  if h then h.locked = true end
end

-- returns true if the edit was captured as a parameter lock
function G.try_lock(sp, delta)
  local st8 = G.state
  if not st8.lock_step or not sp then return false end
  local t = st8.track()
  local sq = t:seq()
  local step = sq:get_step(st8.lock_step, st8.lock_lane)
  if not step then return false end

  if sp.k == "seq" then
    if not STEP_SEQ[sp.id] then return false end
    local cur = step[sp.id] or sq:get(sp)
    step[sp.id] = util.clamp(cur + delta, sp.min, sp.max)
    mark_held(st8, sq)
    return true
  end

  if not sp.ch then return false end
  step.lock = step.lock or {}
  local cur = step.lock[sp.ch] or t:get(sp)
  step.lock[sp.ch] = util.clamp(cur + delta, sp.min, sp.max)
  mark_held(st8, sq)
  t:send_lock(sp.ch, step.lock[sp.ch])
  return true
end

-- E1 sets the held step's velocity, since track select is not needed then
function G.try_velocity(delta)
  local st8 = G.state
  if not st8.lock_step then return false end
  local sq = st8.track():seq()
  local step = sq:get_step(st8.lock_step, st8.lock_lane)
  if not step then return false end
  step.vel = util.clamp((step.vel or 100) + (delta * 4), 1, 127)
  mark_held(st8, sq)
  return true
end

return G
