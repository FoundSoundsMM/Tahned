-- tahned
--
-- FM groovebox for norns + grid 128
--
-- E1 track   E2 cursor   E3 value
-- K1 shift   K2 page back   K3 page forward   (pages do not wrap)
-- K2+K3 master: track select, transport and the three sends
--
-- K1+E2 jump pages   K1+E3 coarse
-- hold grid steps and turn E3 to lock a parameter to all of them

engine.name = "Tahned"

local S     = include("tahned/lib/core/spec")
local M     = include("tahned/lib/core/master")
local state = include("tahned/lib/core/state")
local P     = include("tahned/lib/ui/pages")
local G     = include("tahned/lib/ui/grid_ui")
local Track = include("tahned/lib/core/track")

local combo = false
local screen_metro, grid_metro

-- ------------------------------------------------------------------- params

local function build_params()
  params:add_separator("tahned", "TAHNED")

  for _, key in ipairs(M.order) do
    local fx = M.fx[key]
    params:add_group("fx_" .. key, fx.name, #fx.p)
    for _, e in ipairs(fx.p) do
      local id = key .. "_" .. e[1]
      params:add_control(id, e[2], e[3])
      params:set_action(id, function(v) engine.fxSet(key, e[1], v) end)
    end
  end

  params:add_separator("tahned_data", "PATTERN")
  params:add_trigger("clear_track", "CLEAR TRACK")
  params:set_action("clear_track", function()
    state.seq():clear()
    state.dirty = true
  end)
  params:add_trigger("panic", "PANIC")
  params:set_action("panic", function()
    state.stop()
    engine.panic()
  end)

  params.action_write = function(filename, name, number)
    local f = norns.state.data .. "tahned-" .. number .. ".data"
    tab.save(state.serialize(), f)
  end
  params.action_read = function(filename, silent, number)
    local f = norns.state.data .. "tahned-" .. number .. ".data"
    local d = tab.load(f)
    if d then state.deserialize(d) end
  end
end

-- ---------------------------------------------------------------- persistence

-- Bumped when the channel map moves under a machine, since a slot's values
-- and a step's locks are both keyed by channel and would land on the wrong
-- parameter otherwise.
local DATA_VERSION = 2

function state.serialize()
  local out = { v = DATA_VERSION, sel = state.sel, tracks = {} }
  for i, t in ipairs(state.tracks) do
    local e = { machine = t.machine, mute = t.mute, v = t.v, page = t.page, slot = {} }
    for m = 1, 3 do
      local sq = t.slot[m].seq
      local s = { v = t.slot[m].v, s = t.slot[m].s }
      if sq.kind == "amb" then
        s.lane = {}
        for l = 1, 8 do
          s.lane[l] = { steps = sq.lane[l].steps, length = sq.lane[l].length,
                        speed = sq.lane[l].speed }
        end
      else
        s.steps = sq.steps
      end
      e.slot[m] = s
    end
    out.tracks[i] = e
  end
  return out
end

function state.deserialize(d)
  if not d or not d.tracks then return end
  if (d.v or 1) ~= DATA_VERSION then
    print("tahned: pattern data is version " .. tostring(d.v)
      .. ", this build reads " .. DATA_VERSION .. " -- not loaded")
    return
  end
  state.stop()
  for i, e in ipairs(d.tracks) do
    local t = state.tracks[i]
    if t and e then
      t.mute = e.mute or false
      t.v = e.v or t.v
      t.page = e.page or t.page
      for m = 1, 3 do
        local s = e.slot and e.slot[m]
        local sq = t.slot[m].seq
        if s then
          t.slot[m].v = s.v or t.slot[m].v
          t.slot[m].s = s.s or t.slot[m].s
          sq.s = t.slot[m].s
          if sq.kind == "amb" and s.lane then
            for l = 1, 8 do
              if s.lane[l] then
                sq.lane[l].steps  = s.lane[l].steps or {}
                sq.lane[l].length = s.lane[l].length or 16
                sq.lane[l].speed  = s.lane[l].speed or 5
              end
            end
          else
            sq.steps = s.steps or {}
          end
        end
      end
      t.machine = e.machine or 1
      t:build_lookup()
      t:send_all()
    end
  end
  state.sel = d.sel or 1
  state.dirty = true
end

-- ---------------------------------------------------------------------- init

-- Exposed on purpose: include() hands every caller its own copy of a module,
-- so this is the only handle on the live ones -- for the maiden repl and for
-- tools/check-lua.lua.
tahned = { state = state, grid = G, pages = P }

function init()
  state.init()
  G.init(state)
  build_params()

  clock.tempo_change_handler = function(bpm) engine.tempo(bpm) end

  -- give the engine a moment to finish alloc before pushing 8 tracks at it
  clock.run(function()
    clock.sleep(0.4)
    state.send_all()
    engine.tempo(clock.get_tempo())
    params:bang()
  end)

  screen_metro = metro.init(function()
    if state.dirty or state.playing then
      redraw()
      state.dirty = false
    end
  end, 1 / 30)
  screen_metro:start()

  grid_metro = metro.init(function() G.redraw() end, 1 / 30)
  grid_metro:start()
end

function cleanup()
  state.stop()
  if screen_metro then screen_metro:stop() end
  if grid_metro then grid_metro:stop() end
end

-- ---------------------------------------------------------------------- keys

function key(n, z)
  if n == 1 then
    state.shift = (z == 1)
    state.dirty = true
    return
  end

  if n == 2 then state.k2 = (z == 1) end
  if n == 3 then state.k3 = (z == 1) end

  if z == 1 then
    if state.k2 and state.k3 then
      combo = true
      state.mode = (state.mode == "select") and "page" or "select"
      G.kb_panic()
      state.dirty = true
    end
    return
  end

  -- released
  if combo then
    if not state.k2 and not state.k3 then combo = false end
    return
  end

  if state.mode == "select" then
    if n == 2 then state.mode = "page"
    else state.toggle_play() end
  else
    if n == 2 then state.page_back() else state.page_fwd() end
  end
  state.dirty = true
end

-- ------------------------------------------------------------------ encoders

function enc(n, d)
  if n == 1 then
    -- while a step is held, E1 is that step's velocity rather than track select
    if not G.try_velocity(d) then state.select_track(state.sel + d) end
    state.dirty = true
    return
  end

  -- select mode is the master page: E2 walks the sends, K1+E2 jumps group,
  -- E3 turns whatever is under the cursor
  if state.mode == "select" then
    if n == 2 then
      if state.shift then state.master_group_move(d) else state.master_move(d) end
    else
      state.master_edit(state.shift and (d * 10) or d)
    end
    state.dirty = true
    return
  end

  if n == 2 then
    if state.shift then
      state.set_page(state.page() + d)
    else
      local page = state.cur_page()
      state.cursor = util.clamp(state.cursor + d, 1, #page.params)
    end
    state.dirty = true
    return
  end

  local sp = state.cur_spec()
  if not sp then return end
  local t = state.track()

  -- destinations walk the machine's list rather than raw channel numbers
  if sp.k == "dest" then
    local cur = t.dest_by_ch[t:get(sp)] or 1
    t:set(sp, t.dests[util.clamp(cur + d, 1, #t.dests)].ch)
    state.dirty = true
    return
  end

  local mult = 1
  if state.shift then
    mult = (sp.k == "cont" or sp.k == "int") and 10 or 1
  end

  if not G.try_lock(sp, d * mult) then
    t:delta(sp, d * mult)
  end
  state.dirty = true
end

function redraw()
  P.redraw(state)
end
