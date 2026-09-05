-- sequencer.lua
--
-- One sequencer per (track, machine) slot. Two behaviours share the step
-- store, direction logic, probability and parameter locks:
--
--   drum  up to 128 steps, ratchets, per-step note offset
--   tone  up to 64 steps holding chords, with leader/follower harmony
--
-- A step is sparse -- nil means empty. Anything the step does not override
-- falls back to the track's sequencer settings.

local C = include("tahned/lib/instruments/common")
local musicutil = require "musicutil"

local Seq = {}
Seq.__index = Seq

local MAXLEN = { drum = 128, tone = 64 }

-- ---------------------------------------------------------------- creation

function Seq.new(track, kind, m)
  local o = setmetatable({}, Seq)
  o.track = track
  o.kind = kind
  o.m = m
  o.s = track.slot[m].s
  o.maxlen = MAXLEN[kind]
  o.steps = {}
  o.pos = 0
  o.last = 0
  o.fwd = true
  o.active_locks = {}
  o.vid = 0
  o.held = {}          -- voice id -> true, for tone
  o.clocks = {}
  o.tracks = nil        -- filled in by state.init
  return o
end

function Seq:get(sp) return self.s[sp.id] end

function Seq:set(sp, v)
  self.s[sp.id] = util.clamp(v, sp.min, sp.max)
end

function Seq:length() return util.clamp(self.s.length or 16, 1, self.maxlen) end
function Seq:step_beats(speed)
  return 0.25 / C.SPEEDS[(speed or self.s.speed) + 1]
end

-- ------------------------------------------------------------------- steps

function Seq:store() return self.steps end

function Seq:get_step(i) return self.steps[i] end

function Seq:toggle(i)
  if self.steps[i] then self.steps[i] = nil else self.steps[i] = self:blank() end
  return self.steps[i]
end

function Seq:blank()
  if self.kind == "tone" then
    return { on = true, notes = {}, vel = 100, lock = {} }
  end
  return { on = true, vel = 100, lock = {} }
end

function Seq:ensure(i)
  if not self.steps[i] then self.steps[i] = self:blank() end
  return self.steps[i]
end

function Seq:clear() self.steps = {} end

-- ------------------------------------------------------------- parameter locks
--
-- A lock holds for exactly the step that carries it. Anything locked on the
-- previous step and not on this one is restored from the track's own value.

function Seq:apply_locks(st)
  local new = (st and st.lock) or {}
  for ch in pairs(self.active_locks) do
    if new[ch] == nil then self.track:send_ch(ch) end
  end
  for ch, v in pairs(new) do
    self.track:send_lock(ch, v)
  end
  self.active_locks = new
end

function Seq:release_locks()
  for ch in pairs(self.active_locks) do self.track:send_ch(ch) end
  self.active_locks = {}
end

-- --------------------------------------------------------------- direction

-- `r` carries the walk state rather than reading it off self, so the walk
-- can be driven for a step that is not the sequencer's current one
function Seq:advance(r, len)
  local dir = self.s.dir or 0
  if r.pos == 0 then
    r.pos = (dir == 1) and len or 1
    return r.pos
  end
  if dir == 0 then
    r.pos = (r.pos % len) + 1
  elseif dir == 1 then
    r.pos = ((r.pos - 2) % len) + 1
  elseif dir == 2 then
    if r.fwd then
      if r.pos >= len then r.fwd = false; r.pos = math.max(1, len - 1)
      else r.pos = r.pos + 1 end
    else
      if r.pos <= 1 then r.fwd = true; r.pos = math.min(len, 2)
      else r.pos = r.pos - 1 end
    end
  elseif dir == 3 then
    r.pos = math.random(len)
  else
    r.pos = ((r.pos - 1 + (math.random(3) - 2)) % len) + 1
  end
  return r.pos
end

-- Rotation is applied when reading, so it stays non-destructive: the stored
-- pattern is never rewritten and turning ROTATE back puts everything where
-- it was. The grid and the screen look through the same mapping, so a
-- rotated pattern is drawn where it actually plays.
function Seq:read_index(pos, len)
  local rot = self.s.rotate or 0
  return ((pos - 1 + rot) % len) + 1
end

-- grid/screen position -> stored step index
function Seq:disp(i)
  return self:read_index(i, self:length())
end

function Seq:disp_step(i)
  return self.steps[self:disp(i)]
end

function Seq:chance(st)
  local p = (st and st.prob) or self.s.prob or 100
  return math.random(100) <= p
end

-- ------------------------------------------------------------------ running

function Seq:start()
  self:stop()
  self.clocks[1] = clock.run(function() self:loop() end)
end

function Seq:stop()
  for k, id in pairs(self.clocks) do
    clock.cancel(id)
    self.clocks[k] = nil
  end
  self:all_off()
  self:release_locks()
  self.pos, self.last = 0, 0
end

function Seq:swing_delay(pos, beats)
  local sw = self.s.swing or 0
  if sw == 0 or pos % 2 == 1 then return 0 end
  return beats * (sw / 100)
end

function Seq:loop()
  while true do
    local beats = self:step_beats()
    clock.sync(beats)
    local len = self:length()
    local pos = self:advance(self, len)
    local d = self:swing_delay(pos, beats)
    if d > 0 then clock.sleep(clock.get_beat_sec() * d) end
    self.last = self:read_index(pos, len)
    self:fire(self.last, beats)
  end
end

-- ------------------------------------------------------------------ harmony

local CHORD_IV = C.CHORD_IV

-- norns' include() re-executes a file on every call rather than caching, so
-- two modules that include this one hold different Seq tables. The track
-- registry therefore lives on the instance, set by state.init.

function Seq:root_note()
  return (self.s.root or 0) + ((self.s.octave or 3) * 12)
end

function Seq:scale_array()
  local list = musicutil.SCALES
  local sc = list[util.clamp(self.s.scale or 1, 1, #list)]
  return musicutil.generate_scale(self.s.root or 0, sc.name, 10)
end

function Seq:leader()
  local li = self.s.leader or 0
  if li == 0 or not self.tracks then return nil end
  local t = self.tracks[li]
  if not t or t == self.track then return nil end
  local sq = t:seq()
  return (sq and sq.kind == "tone") and sq or nil
end

-- turn a step's stored notes into the notes actually played
function Seq:resolve(st)
  local notes = {}
  if st.notes and #st.notes > 0 then
    for _, n in ipairs(st.notes) do table.insert(notes, n) end
  else
    table.insert(notes, self:root_note())
  end

  -- chord mode stacks intervals on each stored note
  local ci = self.s.chord or 0
  if ci > 0 and CHORD_IV[ci] then
    local out = {}
    for _, n in ipairs(notes) do
      for _, iv in ipairs(CHORD_IV[ci]) do table.insert(out, n + iv) end
    end
    notes = out
  end

  -- inversion rotates voices by an octave at a time
  local inv = self.s.invert or 0
  if inv ~= 0 and #notes > 1 then
    table.sort(notes)
    for k = 1, math.abs(inv) do
      if inv > 0 then
        local n = table.remove(notes, 1); table.insert(notes, n + 12)
      else
        local n = table.remove(notes); table.insert(notes, 1, n - 12)
      end
    end
  end

  -- spread opens the voicing out by octaves
  local sp = self.s.spread or 0
  if sp > 0 and #notes > 1 then
    table.sort(notes)
    for k = 2, #notes do
      notes[k] = notes[k] + (12 * math.min(sp, k - 1))
    end
  end

  notes = self:follow_leader(notes)

  -- kept fractional: the detuned voicings live between the semitones
  for k, n in ipairs(notes) do notes[k] = util.clamp(n, 0, 127) end
  return notes
end

function Seq:follow_leader(notes)
  local mode = self.s.follow or 0
  local lead = self:leader()
  if mode == 0 or not lead or not lead.cur_notes or #lead.cur_notes == 0 then
    return notes
  end
  local lroot = lead.cur_notes[1]

  if mode == 1 then
    -- DEGREE: take on however far the leader has moved from its own root
    local shift = lroot - lead:root_note()
    for k, n in ipairs(notes) do notes[k] = n + shift end
  elseif mode == 2 then
    -- VOICE: snap every note into the leader's sounding chord
    local pcs, arr = {}, {}
    for _, n in ipairs(lead.cur_notes) do pcs[n % 12] = true end
    for pc in pairs(pcs) do
      for o = 0, 9 do table.insert(arr, pc + (o * 12)) end
    end
    table.sort(arr)
    for k, n in ipairs(notes) do
      notes[k] = musicutil.snap_note_to_array(n, arr)
    end
  elseif mode == 3 then
    -- BASS: play the leader's root, in our own register
    local oct = math.floor((notes[1] or 60) / 12)
    notes = { (lroot % 12) + (oct * 12) }
  end
  return notes
end

-- ------------------------------------------------------------------ firing

function Seq:vid_next()
  self.vid = (self.vid % 4096) + 1
  return self.vid
end

function Seq:fire(i, beats)
  local st = self.steps[i]
  self:apply_locks(st)
  if not (st and st.on) then return end
  if not self:chance(st) then return end

  if self.kind == "drum" then
    local vel = (st.vel or 100) / 127
    local note = 36 + (st.note or 0)
    local r = st.ratchet or self.s.ratchet or 1
    if r <= 1 then
      self.track:trig(vel, note)
    else
      local gap = clock.get_beat_sec() * beats / r
      clock.run(function()
        for k = 1, r do
          self.track:trig(vel * (1 - ((k - 1) * 0.05)), note)
          clock.sleep(gap)
        end
      end)
    end

  elseif self.kind == "tone" then
    local notes = self:resolve(st)
    self.cur_notes = notes
    local gate = (st.gate or self.s.gate or 50) / 100
    local dur = clock.get_beat_sec() * beats * gate
    local strum = ((self.s.strum or 0) / 100) * clock.get_beat_sec() * beats * 0.5
    local vel = (st.vel or 100) / 127
    for k, n in ipairs(notes) do
      clock.run(function()
        if strum > 0 and k > 1 then clock.sleep(strum * (k - 1) / #notes) end
        local id = self:vid_next()
        self.held[id] = true
        self.track:note_on(id, n, vel)
        clock.sleep(dur)
        self.track:note_off(id)
        self.held[id] = nil
      end)
    end
  end
end

function Seq:all_off()
  if self.kind == "tone" then
    for id in pairs(self.held) do self.track:note_off(id) end
    self.held = {}
    self.cur_notes = nil
  end
end

-- What the grid should light. `last` is the stored step that sounded; the
-- playhead belongs at the *display* position it sounded from, so that under
-- rotation the pattern slides and the playhead keeps walking left to right.
function Seq:playhead() return self.pos end

return Seq
