-- grid_ui.lua -- 128 (16x8)
--
-- What the grid shows depends on the selected track's machine:
--
--   drums   all eight rows are steps, 16 per row, up to 128
--   tone    rows 1-4 are 64 steps, rows 5-8 an isomorphic keyboard
--
-- K2+K3 replaces all of it with track select, machine select, mutes and
-- transport. Six machines need six columns, so the rows read
-- 1-6 track, 8-13 machine, 15 mute, 16 transport.
--
-- Holding a step pad and turning an encoder writes a parameter lock onto that
-- step rather than changing the track. A quick press toggles the step. Hold
-- several pads and the lock lands on all of them at once.
--
-- A lock is never pushed at the engine as it is written: the track keeps its
-- own value and the change is heard when the locked step comes round, so
-- what you hear is always what the sequencer is playing.
--
-- Pads address *display* positions. ROTATE is a read-time offset, so the
-- pattern under the pads slides with it and a pad always edits the step it
-- is drawing.

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

local function grid_step(x, y) return ((y - 1) * 16) + x end

-- master page columns
local TRK_HI, MACH_LO, MACH_HI, MUTE_X, TRANS_X = 6, 8, 13, 15, 16

-- isomorphic: one scale degree per column, a third per row
function G.kb_note(sq, x, y)
  local arr = sq:scale_array()
  local per_oct = math.max(1, math.floor(#arr / 10))
  local deg = (x - 1) + ((8 - y) * 3)
  local idx = ((sq.s.octave or 3) * per_oct) + deg + 1
  return arr[util.clamp(idx, 1, #arr)]
end

-- A pad's pitch depends on the scale, root and octave, so it can change while
-- the pad is still down. Remember what each pad sounded when it was pressed
-- and release exactly that, or a scale change mid-press leaves a note hanging.
-- The voice id follows the pad too: two pads can land on the same pitch.

local function kb_key(x, y) return ((y - 1) * 16) + x end

local function kb_release_entry(st8, key, h)
  st8.kb_held[key] = nil
  local c = (st8.playing_notes[h.note] or 1) - 1
  st8.playing_notes[h.note] = (c > 0) and c or nil
  if h.track then h.track:note_off(9000 + key) end
end

local function kb_press(st8, key, note, track)
  st8.kb_held = st8.kb_held or {}
  st8.playing_notes = st8.playing_notes or {}
  -- a press with no matching release (grid glitch, mode change) retires here
  local prev = st8.kb_held[key]
  if prev then kb_release_entry(st8, key, prev) end
  st8.kb_held[key] = { note = note, track = track }
  st8.playing_notes[note] = (st8.playing_notes[note] or 0) + 1
end

local function kb_release(st8, key)
  local h = st8.kb_held and st8.kb_held[key]
  if not h then return end
  kb_release_entry(st8, key, h)
end

-- Leaving the keyboard -- into track select, or onto another machine -- means
-- the pad-up never arrives at the branch that would release the note, so drop
-- everything still sounding on the way out.
function G.kb_panic()
  local st8 = G.state
  if not (st8 and st8.kb_held) then return end
  for key, h in pairs(st8.kb_held) do kb_release_entry(st8, key, h) end
  st8.kb_held = {}
  st8.playing_notes = {}
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

  if st8.mode == "master" then
    for i = 1, 8 do
      local t = st8.tracks[i]
      local sel = (i == st8.sel)
      for x = 1, TRK_HI do G.g:led(x, i, sel and 12 or 3) end
      for m = MACH_LO, MACH_HI do
        G.g:led(m, i, (t.machine == (m - MACH_LO + 1)) and 14 or 2)
      end
      G.g:led(MUTE_X, i, t.mute and 12 or 2)
    end
    G.g:led(TRANS_X, 1, st8.playing and 15 or 5)
    G.g:led(TRANS_X, 2, 4)
    G.g:refresh()
    return
  end

  local t = st8.track()
  local sq = t:seq()

  if sq.kind == "tone" then
    local len = sq:length()
    for y = 1, 4 do
      for x = 1, 16 do
        local i = grid_step(x, y)
        G.g:led(x, y, step_level(sq, sq:disp_step(i), i, sq.pos, len, st8.held[i]))
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
        local i = grid_step(x, y)
        G.g:led(x, y, step_level(sq, sq:disp_step(i), i, sq.pos, len, st8.held[i]))
      end
    end
  end

  G.g:refresh()
end

-- ------------------------------------------------------------------ keys

-- Presses are ordered so that when one of several held pads is let go, the
-- screen falls back to the newest pad still down rather than to nothing.
local press_n = 0

local function focus_newest(st8)
  local best
  for _, h in pairs(st8.held) do
    if not best or h.n > best.n then best = h end
  end
  if best then
    st8.lock_step, st8.lock_pad = best.idx, best.pad
  else
    st8.lock_step, st8.lock_pad = nil, nil
  end
end

-- `pad` is where the finger is, `idx` the step that pad is drawing: under
-- ROTATE the two differ.
local function press_step(sq, pad, idx, key)
  local st8 = G.state
  press_n = press_n + 1
  local existed = sq:get_step(idx) ~= nil
  if not existed then sq:ensure(idx) end
  st8.held[key] = { t = util.time(), n = press_n, pad = pad, idx = idx,
                    existed = existed, locked = false }
  focus_newest(st8)
  st8.dirty = true
end

local function release_step(sq, key)
  local st8 = G.state
  local h = st8.held[key]
  st8.held[key] = nil
  if not h then return end
  -- a quick press on an existing step clears it; a hold was a lock gesture
  if h.existed and not h.locked and (util.time() - h.t) < HOLD_TIME then
    sq:store()[h.idx] = nil
  end
  focus_newest(st8)
  st8.dirty = true
end

function G.key(x, y, z)
  local st8 = G.state

  if st8.mode == "master" then
    G.kb_panic()
    if z == 1 then
      if x <= TRK_HI then
        st8.select_track(y)
      elseif x >= MACH_LO and x <= MACH_HI then
        st8.tracks[y]:set_machine(x - MACH_LO + 1)
        if y == st8.sel then st8.dirty = true end
      elseif x == MUTE_X then
        st8.tracks[y]:set_mute(not st8.tracks[y].mute)
      elseif x == TRANS_X and y == 1 then
        st8.toggle_play()
      elseif x == TRANS_X and y == 2 then
        st8.reset()
      end
      st8.dirty = true
    end
    return
  end

  local t = st8.track()
  local sq = t:seq()

  if sq.kind == "tone" and y >= 5 then
    local key = kb_key(x, y)
    if z == 1 then
      local n = G.kb_note(sq, x, y)
      -- with steps held, the keyboard writes notes onto all of them
      if st8.lock_step then
        for _, h in pairs(st8.held) do
          local step = sq:ensure(h.idx)
          step.notes = step.notes or {}
          local found
          for i, hn in ipairs(step.notes) do if hn == n then found = i end end
          if found then table.remove(step.notes, found)
          else table.insert(step.notes, n) end
          h.locked = true
        end
        kb_press(st8, key, n, nil)
      else
        kb_press(st8, key, n, t)
        t:note_on(9000 + key, n, 0.9)
      end
    else
      kb_release(st8, key)
    end
    st8.dirty = true
    return
  end

  local pad = grid_step(x, y)
  if pad > sq.maxlen then return end
  if z == 1 then
    if pad > sq:length() then return end
    press_step(sq, pad, sq:disp(pad), pad)
  else
    release_step(sq, pad)
  end
end

-- ------------------------------------------------- encoder while holding

-- Sequencer settings that mean something on a single step. Length, speed and
-- direction describe the whole pattern, so they are not among them.
local STEP_SEQ = { prob = true, ratchet = true, gate = true }

-- Every step currently held takes the edit, so a handful of pads can be
-- locked together in one gesture.
local function held_steps(st8, sq)
  local out = {}
  for _, h in pairs(st8.held) do
    local step = sq:get_step(h.idx)
    if step then out[#out + 1] = { h = h, step = step } end
  end
  return out
end

-- returns true if the edit was captured as a parameter lock
function G.try_lock(sp, delta)
  local st8 = G.state
  if not st8.lock_step or not sp then return false end
  local t = st8.track()
  local sq = t:seq()
  local held = held_steps(st8, sq)
  if #held == 0 then return false end

  if sp.k == "seq" then
    if not STEP_SEQ[sp.id] then return false end
    for _, e in ipairs(held) do
      local cur = e.step[sp.id] or sq:get(sp)
      e.step[sp.id] = util.clamp(cur + delta, sp.min, sp.max)
      e.h.locked = true
    end
    return true
  end

  if not sp.ch then return false end
  -- Deliberately not sent at the engine here. The track's own value is
  -- untouched, so the edit is only ever heard on the steps that carry it,
  -- as they come round.
  for _, e in ipairs(held) do
    e.step.lock = e.step.lock or {}
    local cur = e.step.lock[sp.ch] or t:get(sp)
    e.step.lock[sp.ch] = util.clamp(cur + delta, sp.min, sp.max)
    e.h.locked = true
  end
  return true
end

-- E1 sets the held steps' velocity, since track select is not needed then
function G.try_velocity(delta)
  local st8 = G.state
  if not st8.lock_step then return false end
  local sq = st8.track():seq()
  local held = held_steps(st8, sq)
  if #held == 0 then return false end
  for _, e in ipairs(held) do
    e.step.vel = util.clamp((e.step.vel or 100) + (delta * 4), 1, 127)
    e.h.locked = true
  end
  return true
end

return G
