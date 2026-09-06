-- state.lua -- tracks, selection, transport
local Track = include("tahned/lib/core/track")
local MT    = include("tahned/lib/core/mtrack")
local I     = include("tahned/lib/instruments/init")
local M     = include("tahned/lib/core/master")

local state = {}

state.tracks  = {}
state.sel     = 1
state.mode    = "page"    -- "page" | "master"
state.cursor  = 1         -- which of the eight cells is being edited
state.shift   = false
state.k2, state.k3 = false, false
state.playing = false
state.held    = {}        -- grid pads currently held, for step editing
state.held_seq = nil      -- which sequencer those pads belong to
state.lock_step = nil     -- step being parameter-locked, if any
state.lock_pad  = nil     -- where that step is drawn, which ROTATE can move
state.mpage   = 1         -- master page, and the cell E2 is on inside it
state.mcursor = 1
state.dirty   = true

function state.init()
  for i = 1, 8 do state.tracks[i] = Track.new(i) end
  -- the master's own lane, which every master page but the overview shares
  state.mtrack = MT.new()
  state.mseq = state.mtrack:seq()
  -- every sequencer needs to see its siblings so a tone track can follow a
  -- leader; kept per instance because include() gives each caller its own
  -- copy of the module table
  for _, t in ipairs(state.tracks) do
    for m = 1, I.n do t.slot[m].seq.tracks = state.tracks end
  end
end

function state.track()  return state.tracks[state.sel] end
function state.seq()    return state.track():seq() end
function state.pages()  return state.track().pages end

function state.page()
  local t = state.track()
  return util.clamp(t.page[t.machine], 1, #t.pages)
end

function state.set_page(p)
  local t = state.track()
  t.page[t.machine] = util.clamp(p, 1, #t.pages)
  state.cursor = util.clamp(state.cursor, 1, 8)
  state.dirty = true
end

-- pages do not wrap: at either end the key simply does nothing
function state.page_fwd()  state.set_page(state.page() + 1) end
function state.page_back() state.set_page(state.page() - 1) end

function state.cur_page() return state.track().pages[state.page()] end

function state.cur_spec()
  local p = state.cur_page()
  return p and p.params[state.cursor]
end

function state.select_track(i)
  state.sel = util.clamp(i, 1, 8)
  state.cursor = util.clamp(state.cursor, 1, 8)
  state.dirty = true
end

-- how many pads are down; a lock gesture writes to all of them
function state.lock_count()
  local n = 0
  for _ in pairs(state.held) do n = n + 1 end
  return n
end

-- ---------------------------------------------------------------- master
--
-- Its own page set, walked by K2 and K3 the same way a track's pages are.

function state.master_page() return M.page(state.mpage) end

function state.master_param() return M.param(state.mpage, state.mcursor) end

-- the master sequencer's own setting under the cursor, on its SEQ page
function state.master_spec()
  local pg = state.master_page()
  if pg.kind ~= "seq" then return nil end
  return pg.params[util.clamp(state.mcursor, 1, #pg.params)]
end

-- whether the grid is the master lane's steps rather than the overview
function state.master_steps() return M.has_steps(state.mpage) end

function state.set_master_page(p)
  state.mpage = util.clamp(p, 1, #M.pages)
  state.mcursor = util.clamp(state.mcursor, 1, M.page_cells(state.mpage))
  state.dirty = true
end

function state.master_page_fwd()  state.set_master_page(state.mpage + 1) end
function state.master_page_back() state.set_master_page(state.mpage - 1) end

function state.master_move(d)
  state.mcursor = util.clamp(state.mcursor + d, 1, M.page_cells(state.mpage))
  state.dirty = true
end

-- E3 turns whatever the cursor is on: a norns param on a params page, and
-- the track's own level on MIX, which is the same channel its MIX page has
function state.master_edit(d)
  local pg = state.master_page()
  if pg.kind == "mix" then
    local t = state.tracks[util.clamp(state.mcursor, 1, 8)]
    local sp = t.chspec[0]
    if sp then t:delta(sp, d) end
  elseif pg.kind == "seq" then
    -- HOLD is lock-only here for the same reason it is on a track: a stage on
    -- every step of the lane is just a slower lane, so it only moves when one
    -- of the lane's steps is held and the lock path has already taken the edit
    local sp = state.master_spec()
    if sp and not sp.lockonly then state.mtrack:delta(sp, d) end
  else
    local e = state.master_param()
    if e then params:delta(e.param, d) end
  end
  state.dirty = true
end

-- ---------------------------------------------------- master lock readout
--
-- The same two questions the track pages ask of a held step, asked of the
-- master lane: what has this step locked for the cell under the cursor, and
-- what velocity is on it. A master step never sounds, so its velocity is only
-- ever the header's readout -- it is kept because the gesture is the same one.

local function mstep()
  if not state.lock_step then return nil end
  return state.mseq and state.mseq:get_step(state.lock_step)
end

function state.mlock_param(e)
  local st = e and mstep()
  return st and st.lock and st.lock[e.param]
end

function state.mlock_seq(sp)
  local st = sp and mstep()
  return st and st[sp.id]
end

-- value locked to the step currently being held, if any
function state.lock_value(sp)
  if not state.lock_step or not sp then return nil end
  local step = state.seq():get_step(state.lock_step)
  if not step then return nil end
  if sp.k == "seq" then return step[sp.id] end
  return sp.ch and step.lock and step.lock[sp.ch]
end

-- velocity of the step being held, for the header readout
function state.lock_vel()
  if not state.lock_step then return nil end
  local step = state.seq():get_step(state.lock_step)
  return step and step.vel
end

function state.send_all()
  for _, t in ipairs(state.tracks) do t:send_all() end
end

-- The song's key moved, so everything already written moves with it. Every
-- slot of every track, not just the machines that happen to be selected: a
-- pattern parked on a machine nobody is looking at is still part of the song,
-- and finding it in the old key later is the bug this exists to prevent.
-- Drum slots return immediately -- a drum's NOTE is an offset in semitones
-- from its own tuning and has nothing to do with the scale.
function state.rekey(prev, now)
  for _, t in ipairs(state.tracks) do
    for m = 1, I.n do
      local sq = t.slot[m] and t.slot[m].seq
      if sq then sq:rekey(prev, now) end
    end
  end
  state.dirty = true
end

-- ---------------------------------------------------------------- transport

function state.start()
  if state.playing then return end
  state.playing = true
  Track.transport.playing = true
  for _, t in ipairs(state.tracks) do t:seq():start() end
  state.mseq:start()
  state.dirty = true
end

function state.stop()
  if not state.playing then return end
  state.playing = false
  Track.transport.playing = false
  for _, t in ipairs(state.tracks) do t:seq():stop() end
  -- stopping releases the lane's locks, so the master is left holding its own
  -- values rather than wherever the last step that went by put them
  state.mseq:stop()
  state.dirty = true
end

function state.toggle_play()
  if state.playing then state.stop() else state.start() end
end

function state.reset()
  for _, t in ipairs(state.tracks) do
    local s = t:seq()
    s.pos, s.last = 0, 0
  end
  state.mseq.pos, state.mseq.last = 0, 0
end

return state
