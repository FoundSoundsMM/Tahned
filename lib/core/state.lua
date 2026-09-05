-- state.lua -- tracks, selection, transport
local Track = include("tahned/lib/core/track")

local state = {}

state.tracks  = {}
state.sel     = 1
state.mode    = "page"    -- "page" | "select"
state.cursor  = 1         -- which of the eight cells is being edited
state.shift   = false
state.k2, state.k3 = false, false
state.playing = false
state.held    = {}        -- grid pads currently held, for step editing
state.lock_step = nil     -- step being parameter-locked, if any
state.lock_lane = 1
state.dirty   = true

function state.init()
  for i = 1, 8 do state.tracks[i] = Track.new(i) end
  -- every sequencer needs to see its siblings so a tone track can follow a
  -- leader; kept per instance because include() gives each caller its own
  -- copy of the module table
  for _, t in ipairs(state.tracks) do
    for m = 1, 3 do t.slot[m].seq.tracks = state.tracks end
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

-- value locked to the step currently being held, if any
function state.lock_value(sp)
  if not state.lock_step or not sp then return nil end
  local step = state.seq():get_step(state.lock_step, state.lock_lane)
  if not step then return nil end
  if sp.k == "seq" then return step[sp.id] end
  return sp.ch and step.lock and step.lock[sp.ch]
end

-- velocity of the step being held, for the header readout
function state.lock_vel()
  if not state.lock_step then return nil end
  local step = state.seq():get_step(state.lock_step, state.lock_lane)
  return step and step.vel
end

function state.send_all()
  for _, t in ipairs(state.tracks) do t:send_all() end
end

-- ---------------------------------------------------------------- transport

function state.start()
  if state.playing then return end
  state.playing = true
  Track.transport.playing = true
  for _, t in ipairs(state.tracks) do t:seq():start() end
  state.dirty = true
end

function state.stop()
  if not state.playing then return end
  state.playing = false
  Track.transport.playing = false
  for _, t in ipairs(state.tracks) do t:seq():stop() end
  state.dirty = true
end

function state.toggle_play()
  if state.playing then state.stop() else state.start() end
end

function state.reset()
  for _, t in ipairs(state.tracks) do
    local s = t:seq()
    s.pos, s.last = 0, 0
    if s.lane then for l = 1, 8 do s.lane[l].pos, s.lane[l].last = 0, 0 end end
  end
end

return state
