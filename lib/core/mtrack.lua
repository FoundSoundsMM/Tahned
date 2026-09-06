-- mtrack.lua -- the master, shaped like a track so it can carry a sequencer
--
-- The master sequencer is the same Seq the eight tracks run: the same length,
-- speed, metre, swing, direction, rotation, probability and Metropolis stage,
-- and the same parameter locks. All Seq asks of whatever owns it is a place
-- to keep its settings and two calls -- push a locked value, put the stored
-- one back -- so the master gets an object that answers those and nothing
-- else. There is no eleventh track: this one never sounds.
--
-- A track's lock is keyed by control-bus channel. The master's is keyed by
-- norns param name instead, which is the only difference between the two, and
-- Seq never looks at the key.

local M = include("tahned/lib/core/master")
local Seq = include("tahned/lib/seq/sequencer")

local MT = {}
MT.__index = MT

function MT.new()
  local o = setmetatable({}, MT)
  o.idx = 0
  o.mute = false
  o.slot = { { v = {}, s = {}, seq = nil } }
  for _, sp in ipairs(M.seqpage.params) do o.slot[1].s[sp.id] = sp.def end
  o.slot[1].seq = Seq.new(o, "master", 1)
  return o
end

function MT:seq() return self.slot[1].seq end

-- Seq and the cell drawing code both read values through get/set, so the
-- master's SEQ page draws and turns with exactly the track page's code.
function MT:get(sp)
  if sp.k == "seq" then return self:seq():get(sp) end
  return nil
end

function MT:set(sp, v)
  if sp.k == "seq" then self:seq():set(sp, v) end
end

function MT:delta(sp, d)
  if sp.k ~= "seq" then return end
  self:set(sp, util.clamp((self:get(sp) or sp.def or 0) + d, sp.min, sp.max))
end

-- what a lock does when its step comes round, and when it passes
function MT:send_lock(param, v) M.send_lock(param, v) end
function MT:send_ch(param)      M.send_now(param) end

-- Seq calls these on a step that sounds. This lane does not sound: it is a
-- lane of parameter locks, and the locks are applied before either would be
-- reached, so they are here to be nothing rather than to do nothing subtle.
function MT:trig() end
function MT:note_on() end
function MT:note_off() end

-- the header and the footer read these off whatever they are drawing
function MT:inst() return { name = "MASTER", short = "MST" } end
function MT:raw() return nil end

return MT
