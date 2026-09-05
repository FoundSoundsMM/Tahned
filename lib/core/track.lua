-- track.lua
--
-- Owns one track's parameter values and pushes them at the engine. Values are
-- kept in display units; the engine only ever sees what S.encode produces.
--
-- Switching machine is non-destructive. Channels 8..39 mean different things
-- per machine, so each track keeps a slot per machine holding those values,
-- its sequencer settings and its pattern. Master, filter, colour and the LFOs
-- are shared across machines and live directly on the track.

local S = include("tahned/lib/core/spec")
local I = include("tahned/lib/instruments/init")
local Seq = include("tahned/lib/seq/sequencer")
local musicutil = require "musicutil"

local SYN_LO, SYN_HI = 8, 39

local Track = {}
Track.__index = Track
Track.transport = { playing = false }

local function is_syn(ch) return ch and ch >= SYN_LO and ch <= SYN_HI end

function Track.new(idx)
  local t = setmetatable({}, Track)
  t.idx = idx
  t.machine = 1
  t.mute = false
  t.v = {}            -- shared channels, [ch] = display value
  t.slot = {}         -- per machine: syn channels, seq settings, pattern
  t.page = { 1, 1, 1 }

  for m = 1, 3 do
    t.slot[m] = { v = {}, s = {}, seq = nil }
  end

  -- shared defaults come from any machine's page list
  for _, page in ipairs(I.pages_for(1)) do
    for _, sp in ipairs(page.params) do
      if sp.ch and not is_syn(sp.ch) then t.v[sp.ch] = sp.def end
    end
  end

  for m = 1, 3 do
    for _, page in ipairs(I.pages_for(m)) do
      for _, sp in ipairs(page.params) do
        if is_syn(sp.ch) then t.slot[m].v[sp.ch] = sp.def
        elseif sp.k == "seq" then t.slot[m].s[sp.id] = sp.def end
      end
    end
    t.slot[m].seq = Seq.new(t, I[m].seq, m)
  end

  t:build_lookup()
  return t
end

-- channel -> spec, for the current machine. LFO depths need this to know what
-- range their destination has.
function Track:build_lookup()
  self.chspec = {}
  self.pages = I.pages_for(self.machine)
  self.dests = I.destinations_for(self.machine)
  self.dest_by_ch = {}
  for i, d in ipairs(self.dests) do self.dest_by_ch[d.ch] = i end
  for _, page in ipairs(self.pages) do
    for _, sp in ipairs(page.params) do
      if sp.ch then self.chspec[sp.ch] = sp end
    end
  end
end

function Track:inst() return I[self.machine] end
function Track:seq()  return self.slot[self.machine].seq end
function Track:npages() return #self.pages end

-- ------------------------------------------------------------------ values

function Track:get(sp)
  if sp.k == "mach" then return self.machine - 1 end
  if sp.k == "seq"  then return self:seq():get(sp) end
  if is_syn(sp.ch)  then return self.slot[self.machine].v[sp.ch] end
  return self.v[sp.ch]
end

function Track:raw(ch)
  if is_syn(ch) then return self.slot[self.machine].v[ch] end
  return self.v[ch]
end

function Track:set(sp, v)
  if sp.k == "mach" then self:set_machine(v + 1) return end
  if sp.k == "seq" then self:seq():set(sp, v) return end
  v = util.clamp(v, sp.min, sp.max)
  if is_syn(sp.ch) then self.slot[self.machine].v[sp.ch] = v
  else self.v[sp.ch] = v end
  self:send(sp)
  -- a destination change rescales the depth sitting next to it
  if sp.k == "dest" then
    local dep = self.chspec[sp.ch + 1]
    if dep then self:send(dep) end
  end
end

function Track:delta(sp, d)
  self:set(sp, util.clamp(self:get(sp) + d, sp.min, sp.max))
end

-- ------------------------------------------------------------------ engine

function Track:send(sp)
  if sp.k == "seq" or sp.k == "mach" then return end
  local v = self:get(sp)
  if sp.k == "ftype" then
    engine.ftype(self.idx - 1, v)
    return
  end
  local destspec
  if sp.k == "depth" then
    local dch = self:raw(sp.ch - 1)
    destspec = dch and self.chspec[dch]
  end
  engine.pset(self.idx - 1, sp.ch, S.encode(sp, v, destspec))
end

-- send one channel's stored value, used to release a parameter lock
function Track:send_ch(ch)
  local sp = self.chspec[ch]
  if sp then self:send(sp) end
end

-- send an overriding value for one channel without storing it
function Track:send_lock(ch, v)
  local sp = self.chspec[ch]
  if not sp then return end
  local destspec
  if sp.k == "depth" then
    local dch = self:raw(ch - 1)
    destspec = dch and self.chspec[dch]
  end
  engine.pset(self.idx - 1, ch, S.encode(sp, util.clamp(v, sp.min, sp.max), destspec))
end

function Track:send_all()
  engine.machine(self.idx - 1, self.machine - 1)
  for _, page in ipairs(self.pages) do
    for _, sp in ipairs(page.params) do
      if sp.ch then self:send(sp) end
    end
  end
  self:send_level()
end

function Track:send_level()
  local sp = self.chspec[0]
  if not sp then return end
  local v = self.mute and 0 or self:get(sp)
  engine.pset(self.idx - 1, 0, S.encode(sp, v))
end

function Track:set_mute(m)
  self.mute = m
  self:send_level()
end

function Track:set_machine(m)
  m = util.clamp(m, 1, 3)
  if m == self.machine then return end
  self:seq():stop()
  self.machine = m
  self:build_lookup()
  self:send_all()
  if Track.transport.playing then self:seq():start() end
end

-- ------------------------------------------------------------------- notes

function Track:trig(vel, note)
  if self.mute then return end
  engine.trig(self.idx - 1, vel or 1, note or 36)
end

function Track:note_on(id, note, vel)
  if self.mute then return end
  engine.noteOn(self.idx - 1, id, musicutil.note_num_to_freq(note), vel or 1)
end

function Track:note_off(id)
  engine.noteOff(self.idx - 1, id)
end

function Track:amb_trig(lane, v)
  if self.mute then return end
  engine.ambTrig(self.idx - 1, lane - 1, v)
end

return Track
