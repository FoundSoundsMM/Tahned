-- grid_ui.lua -- 128 (16x8)
--
-- What the grid shows depends on the selected track's machine:
--
--   drums   all eight rows are steps, 16 per row, up to 128
--   tone    rows 1-4 are 64 steps, rows 5-8 an isomorphic keyboard
--
-- K2+K3 opens the master. Its first page, the overview, replaces all of the
-- grid with track select, machine select, mutes and transport -- six machines
-- need six columns, so the rows read 1-6 track, 8-13 machine, 15 mute,
-- 16 transport. Every other master page hands the grid to the master's own
-- sequencer: eight rows of its steps, locking master parameters the way a
-- track's steps lock channels.
--
-- Holding a step pad and turning an encoder writes a parameter lock onto that
-- step rather than changing the track. A quick press toggles the step. Hold
-- several pads and the lock lands on all of them at once.
--
-- Holding one pad and *tapping* another is a third thing: a reach. The held
-- step is given a Metropolis stage long enough to arrive at the pad that was
-- tapped, so a note sustains across the distance rather than stopping at the
-- end of its own step. Held is a lock gesture, tapped is a reach, which is
-- the same distinction a lone pad already makes between a hold and a press.
--
-- A lock is never pushed at the engine as it is written: the track keeps its
-- own value and the change is heard when the locked step comes round, so
-- what you hear is always what the sequencer is playing.
--
-- Pads address *display* positions. ROTATE is a read-time offset, so the
-- pattern under the pads slides with it and a pad always edits the step it
-- is drawing.

local S = include("tahned/lib/core/spec")
local M = include("tahned/lib/core/master")

local G = {}
local HOLD_TIME = 0.28

G.g = nil
G.state = nil

function G.init(state)
  G.state = state
  G.g = grid.connect()
  G.g.key = function(x, y, z) G.key(x, y, z) end
end

-- The sequencer the pads are addressing: the master's own lane on every
-- master page but the overview, otherwise the selected track's.
function G.cur_seq()
  local st8 = G.state
  if st8.mode == "master" then
    return st8.master_steps() and st8.mseq or nil
  end
  return st8.track():seq()
end

-- Pads belong to whatever sequencer was under them when they went down. If
-- that changes with pads still held -- a page turn, a track change, K2+K3 --
-- the pad-up will never reach the branch that would let them go, so they are
-- dropped here rather than left holding a lock target that has moved.
local function check_owner(st8, sq)
  if st8.held_seq == sq then return end
  st8.held_seq = sq
  st8.held = {}
  st8.lock_step, st8.lock_pad = nil, nil
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

-- The notes under the fingers right now, in order and without duplicates.
-- What a step takes when one is pressed while the keyboard is held.
local function kb_roots(st8)
  local out, seen = {}, {}
  for _, h in pairs(st8.kb_held or {}) do
    if h.note and not seen[h.note] then
      seen[h.note] = true
      out[#out + 1] = h.note
    end
  end
  table.sort(out)
  return out
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

-- A ladder of levels, so the pattern reads at a glance without counting pads:
--
--   0   past the end of the sequence -- dark, so the length is visible
--   2   inside the sequence, empty -- the faint floor the pattern sits on
--   4   every fourth step, the ruler the pattern is counted against
--   7   the playhead
--   9-14 an active step, by its velocity; 15 with the playhead on it
--
-- The floor is the point: a 12 step sequence is now twelve lit pads and four
-- dark ones rather than a guess.
local function step_level(sq, st, idx, head, len, held, mark)
  if idx > len then return 0 end
  if held then return 15 end
  if st and st.on then
    if idx == head then return 15 end
    return util.round(util.linlin(0, 127, 9, 14, st.vel or 100))
  end
  if idx == head then return 7 end
  if mark and ((idx - 1) % mark) == 0 then return 4 end
  return 2
end

function G.redraw()
  local st8 = G.state
  if not G.g then return end
  G.g:all(0)

  if st8.mode == "master" then
    -- every master page but the overview is the master lane's steps, drawn by
    -- the same ladder a track's pattern is
    if st8.master_steps() then
      local sq = st8.mseq
      check_owner(st8, sq)
      local len, mark = sq:length(), sq:mark_steps()
      for y = 1, 8 do
        for x = 1, 16 do
          local i = grid_step(x, y)
          G.g:led(x, y, step_level(sq, sq:disp_step(i), i, sq.pos, len,
            st8.held[i], mark))
        end
      end
      G.g:refresh()
      return
    end

    check_owner(st8, nil)
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
  check_owner(st8, sq)

  if sq.kind == "tone" then
    local len, mark = sq:length(), sq:mark_steps()
    for y = 1, 4 do
      for x = 1, 16 do
        local i = grid_step(x, y)
        G.g:led(x, y, step_level(sq, sq:disp_step(i), i, sq.pos, len,
          st8.held[i], mark))
      end
    end
    -- keyboard: scale roots brighter, notes on the held step brighter still
    local hs = st8.lock_step and sq.steps[st8.lock_step]
    local root = M.root()
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
    local len, mark = sq:length(), sq:mark_steps()
    for y = 1, 8 do
      for x = 1, 16 do
        local i = grid_step(x, y)
        G.g:led(x, y, step_level(sq, sq:disp_step(i), i, sq.pos, len,
          st8.held[i], mark))
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

-- Reaching from one step to another. The held step is given a Metropolis
-- stage long enough to arrive at the pad that was tapped: HOLD is the control
-- the STEP page already carries -- the sequencer sits on the step for that
-- many pulses instead of one -- so a tone note sustains across the whole
-- reach, a drum's ratchets spread over it, and the master lane holds its
-- locked values for the distance. Sustaining a step is saying how far it goes.
--
-- The distance is counted in the positions you can see, and it wraps, so
-- reaching backwards is the long way round rather than nothing. Sixteen
-- pulses is as far as a stage goes, which is what HOLD holds.
function G.extend(sq, anchor, pad)
  local len = sq:length()
  local step = sq:ensure(anchor.idx)
  step.on = true
  step.hold = util.clamp(((pad - anchor.pad) % len) + 1, 1, 16)
  G.state.dirty = true
end

-- `pad` is where the finger is, `idx` the step that pad is drawing: under
-- ROTATE the two differ.
local function press_step(sq, pad, idx, key)
  local st8 = G.state
  press_n = press_n + 1
  local existed = sq:get_step(idx) ~= nil

  -- Whatever is already down is what this press might be reaching from. The
  -- release decides whether it was a reach or another pad in a lock gesture,
  -- but the anchor is marked now: a step someone has reached from is not a
  -- step to toggle off, whichever of the two pads comes up first.
  local anchor
  for _, h in pairs(st8.held) do
    if not anchor or h.n > anchor.n then anchor = h end
  end
  if anchor then anchor.reached = true end

  -- Notes held on the keyboard and a step pressed: the step takes them. It is
  -- the hold-a-step-and-play gesture from the other end, and it is the faster
  -- one when the chord is already under your fingers.
  local written = false
  if sq.kind == "tone" then
    local roots = kb_roots(st8)
    if #roots > 0 then
      local step = sq:ensure(idx)
      step.notes = roots
      step.on = true
      written = true
    end
  end

  if not (existed or written) then sq:ensure(idx) end
  st8.held[key] = { t = util.time(), n = press_n, pad = pad, idx = idx,
                    existed = existed, locked = written, anchor = anchor }
  focus_newest(st8)
  st8.dirty = true
end

local function release_step(sq, key)
  local st8 = G.state
  local h = st8.held[key]
  st8.held[key] = nil
  if not h then return end
  local quick = (util.time() - h.t) < HOLD_TIME
  if quick and not h.locked and h.anchor then
    -- a tap landing while another pad was down is a reach, not a step: it
    -- says where the held step should carry to, and nothing is toggled
    G.extend(sq, h.anchor, h.pad)
    if not h.existed then sq:store()[h.idx] = nil end
  elseif quick and not h.locked and not h.reached and h.existed then
    -- a quick press on an existing step clears it; a hold was a lock gesture
    sq:store()[h.idx] = nil
  end
  focus_newest(st8)
  st8.dirty = true
end

function G.key(x, y, z)
  local st8 = G.state

  if st8.mode == "master" then
    G.kb_panic()

    -- every master page but the overview is the master lane
    if st8.master_steps() then
      local sq = st8.mseq
      check_owner(st8, sq)
      local pad = grid_step(x, y)
      if pad > sq.maxlen then return end
      if z == 1 then
        if pad > sq:length() then return end
        press_step(sq, pad, sq:disp(pad), pad)
      else
        release_step(sq, pad)
      end
      return
    end

    check_owner(st8, nil)
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
  check_owner(st8, sq)

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

-- Sequencer settings that mean something on a single step. Length, speed,
-- metre and direction describe the whole pattern, so they are not among them.
-- HOLD, HTYPE and NOTE are lock-only and live nowhere else at all.
local STEP_SEQ = { prob = true, ratchet = true, gate = true,
                   hold = true, htype = true, note = true }

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
  if st8.mode == "master" then return false end
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

-- E1 sets the held steps' velocity, since track select is not needed then.
-- The master lane declines it: its steps never sound, so a velocity on one
-- would be a number written where nothing reads it and nothing shows it, and
-- E1 is better left picking a track.
function G.try_velocity(delta)
  local st8 = G.state
  if not st8.lock_step then return false end
  local sq = G.cur_seq()
  if not sq or sq.kind == "master" then return false end
  local held = held_steps(st8, sq)
  if #held == 0 then return false end
  for _, e in ipairs(held) do
    e.step.vel = util.clamp((e.step.vel or 100) + (delta * 4), 1, 127)
    e.h.locked = true
  end
  return true
end

-- ------------------------------------------------ the master's own locks
--
-- The same gesture on the master's lane: hold one of its steps and turn E3,
-- and whatever the cursor is on is locked to that step. The master keeps its
-- own value and nothing is written into the norns param -- the locked value
-- goes at the engine when the step comes round and is taken back when it
-- passes, which is what makes the lane play rather than leave the knob moved.
--
-- A lock is keyed by param name here rather than by control-bus channel. Seq
-- never looks at the key, so both kinds of lock go through the same code.
function G.try_master_lock(delta)
  local st8 = G.state
  if st8.mode ~= "master" or not st8.lock_step then return false end
  local sq = st8.mseq
  local held = held_steps(st8, sq)
  if #held == 0 then return false end
  local pg = st8.master_page()

  -- the lane's own settings, on its SEQ page: the ones that mean something on
  -- a single step. Length, speed, metre and direction describe the whole lane.
  if pg.kind == "seq" then
    local sp = st8.master_spec()
    if not (sp and STEP_SEQ[sp.id]) then return false end
    for _, e in ipairs(held) do
      local cur = e.step[sp.id] or sq:get(sp)
      e.step[sp.id] = util.clamp(cur + delta, sp.min, sp.max)
      e.h.locked = true
    end
    return true
  end

  local ent = st8.master_param()
  if not M.lockable(ent) then return false end
  for _, e in ipairs(held) do
    e.step.lock = e.step.lock or {}
    local cur = e.step.lock[ent.param] or M.value(ent)
    e.step.lock[ent.param] = M.lock_delta(ent, cur, delta)
    e.h.locked = true
  end
  return true
end

return G
