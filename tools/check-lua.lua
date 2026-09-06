-- Smoke test for the lua side, run on a desktop with plain lua.
--
-- Stubs enough of the norns API to actually execute the script: init, a run
-- of the sequencers, grid presses, encoder turns, page navigation and a
-- redraw of every page of every machine. Parsing does not catch nil fields
-- and wrong call shapes; running does.
--
-- include() deliberately does NOT cache, matching norns, so module-identity
-- mistakes show up here too.
--
--   lua tools/check-lua.lua

local ROOT = (arg[0]:match("(.*)/tools/") or ".")

-- ------------------------------------------------------------------- stubs

function include(path)
  local f = path:gsub("^tahned/", "")
  return dofile(ROOT .. "/" .. f .. ".lua")
end

local now = 0
util = {
  clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end,
  round = function(v) return math.floor(v + 0.5) end,
  linlin = function(a, b, c, d, v)
    if b == a then return c end
    return c + ((d - c) * ((v - a) / (b - a)))
  end,
  time = function() now = now + 0.01 return now end,
  file_exists = function() return true end,
}

local draws = 0
screen = setmetatable({}, { __index = function() return function() draws = draws + 1 end end })

local engine_calls, engine_last = {}, {}

-- the engine keeps one voice per (track, id) and frees it on noteOff, so the
-- stub mirrors that: whatever is left here is a note left sounding
local voices = {}
local function voice_count()
  local n = 0
  for _ in pairs(voices) do n = n + 1 end
  return n
end

engine = setmetatable({ name = "" }, { __index = function(_, k)
  return function(...)
    engine_calls[k] = (engine_calls[k] or 0) + 1
    local a = { ... }
    engine_last[k] = a
    if k == "noteOn" then voices[a[1] .. ":" .. a[2]] = a[3]
    elseif k == "noteOff" then voices[a[1] .. ":" .. a[2]] = nil
    elseif k == "allOff" then
      for id in pairs(voices) do
        if id:match("^" .. a[1] .. ":") then voices[id] = nil end
      end
    end
  end
end })

local gled = 0
local gobj = {
  led = function() gled = gled + 1 end,
  all = function() end,
  refresh = function() end,
}
grid = { connect = function() return gobj end }

local coros = {}
clock = {
  run = function(f, ...)
    local co = coroutine.create(f)
    table.insert(coros, co)
    coroutine.resume(co, ...)
    return #coros
  end,
  sleep = function() coroutine.yield() end,
  sync = function() coroutine.yield() end,
  cancel = function() end,
  get_beat_sec = function() return 0.5 end,
  get_tempo = function() return 120 end,
}

metro = { init = function(f, t) return { start = function() end, stop = function() end, f = f } end }
controlspec = { new = function(a, b, c, d, e, u)
  return { minval = a, maxval = b, default = e or a } end }

-- params holds real values, so the master page has something to read and turn.
-- set and delta fire the param's action the way norns' do, which matters here:
-- the key's action is what moves the notes already written.
local param_actions, param_val, param_spec = {}, { clock_tempo = 120 }, {}
local param_opts = {}
local function param_fire(id)
  local f = param_actions[id]
  if f then f(param_val[id]) end
end
params = {
  add_separator = function() end,
  add_group = function() end,
  add_control = function(_, id, _, spec)
    param_spec[id] = spec
    param_val[id] = spec and spec.default or 0
  end,
  add_option = function(_, id, _, list, def)
    param_opts[id] = list
    param_val[id] = def or 1
  end,
  add_trigger = function() end,
  set_action = function(_, id, f) param_actions[id] = f end,
  get = function(_, id) return param_val[id] end,
  set = function(_, id, v) param_val[id] = v; param_fire(id) end,
  string = function(_, id)
    local o = param_opts[id]
    if o then return o[param_val[id] or 1] or "-" end
    return string.format("%.2f", param_val[id] or 0)
  end,
  delta = function(_, id, d)
    local o = param_opts[id]
    if o then
      param_val[id] = math.min(math.max((param_val[id] or 1) + d, 1), #o)
    else
      local sp = param_spec[id]
      local lo, hi = sp and sp.minval or 20, sp and sp.maxval or 300
      param_val[id] = math.min(math.max((param_val[id] or lo) + (d * (hi - lo) / 100), lo), hi)
    end
    param_fire(id)
  end,
  bang = function() for id in pairs(param_actions) do param_fire(id) end end,
}
setmetatable(params, { __index = function() return function() end end })

norns = { state = { data = "/tmp/", path = ROOT, shortname = "tahned" } }
tab = { save = function() end, load = function() return nil end }

local SCALES = {}
for _, n in ipairs({ "Major", "Natural Minor", "Dorian", "Phrygian", "Lydian",
                     "Mixolydian", "Locrian", "Whole Tone", "Major Pentatonic" }) do
  table.insert(SCALES, { name = n })
end
package.preload["musicutil"] = function()
  return {
    SCALES = SCALES,
    generate_scale = function(root, name, oct)
      local t = {}
      local iv = { 0, 2, 4, 5, 7, 9, 11 }
      for o = 0, (oct or 1) - 1 do
        for _, i in ipairs(iv) do table.insert(t, root + (o * 12) + i) end
      end
      return t
    end,
    note_num_to_freq = function(n) return 440 * (2 ^ ((n - 69) / 12)) end,
    snap_note_to_array = function(n, a)
      local best, bd = a[1], math.huge
      for _, v in ipairs(a) do
        local d = math.abs(v - n)
        if d < bd then best, bd = v, d end
      end
      return best
    end,
  }
end

-- --------------------------------------------------------------------- run

local fails = 0
local function check(what, fn)
  local ok, err = pcall(fn)
  if ok then
    print(string.format("  ok    %s", what))
  else
    fails = fails + 1
    print(string.format("  FAIL  %s\n        %s", what, err))
  end
end

dofile(ROOT .. "/tahned.lua")

print("tahned lua smoke test")
check("init", function() init() end)

-- include() would hand back a fresh, uninitialised copy of each module, so
-- everything below goes through the live ones the script exposes
local state = tahned.state
local G = tahned.grid
local NM = tahned.instruments.n          -- machines: five drums and TONE
local TONE = NM                          -- TONE is the last of them
local MPAGES = #tahned.master.pages

check("every page of every machine redraws", function()
  local st = state
  for t = 1, 8 do
    for m = 1, NM do
      st.tracks[t]:set_machine(m)
      st.select_track(t)
      for p = 1, #st.tracks[t].pages do
        st.set_page(p)
        for c = 1, 8 do
          st.cursor = c
          redraw()
        end
      end
    end
  end
end)

check("page navigation clamps at both ends", function()
  local st = state
  st.select_track(1)
  for _ = 1, 40 do key(2, 1); key(2, 0) end
  assert(st.page() == 1, "page ran off the front: " .. st.page())
  for _ = 1, 40 do key(3, 1); key(3, 0) end
  assert(st.page() == #st.tracks[1].pages, "page ran off the back")
end)

check("K2+K3 toggles the master mode", function()
  local st = state
  key(2, 1); key(3, 1); key(3, 0); key(2, 0)
  assert(st.mode == "master", "did not enter master")
  key(2, 1); key(3, 1); key(3, 0); key(2, 0)
  assert(st.mode == "page", "did not leave master")
end)

check("K1+K3 runs and stops without moving the page", function()
  local st = state
  st.mode = "page"
  st.select_track(1)
  st.set_page(2)
  local p0 = st.page()
  st.shift = true
  key(3, 1); key(3, 0)
  assert(st.playing, "K1+K3 did not start the transport")
  key(3, 1); key(3, 0)
  assert(not st.playing, "K1+K3 did not stop it again")
  key(2, 1); key(2, 0)                       -- K1+K2 is reset, not page back
  st.shift = false
  assert(st.page() == p0, "a shifted key moved the page")
  -- and unshifted the same keys still page
  key(3, 1); key(3, 0)
  assert(st.page() == p0 + 1, "K3 did not page forward")
  key(2, 1); key(2, 0)
end)

check("encoders move cursor and edit values on every page", function()
  local st = state
  for m = 1, NM do
    st.tracks[1]:set_machine(m)
    for p = 1, #st.tracks[1].pages do
      st.set_page(p)
      for c = 1, 8 do
        st.cursor = c
        enc(3, 1); enc(3, -1); enc(3, 5)
      end
      enc(2, 1); enc(2, -1)
    end
  end
  enc(1, 1); enc(1, -1)
end)

check("grid draws and takes presses for each machine", function()
  local st = state
  for m = 1, NM do
    st.tracks[st.sel]:set_machine(m)
    G.redraw()
    for y = 1, 8 do
      for x = 1, 16 do
        G.g.key(x, y, 1)
        G.g.key(x, y, 0)
      end
    end
    G.redraw()
  end
end)

-- A cell is 32px wide with a 1px divider, so a label has 29px, and norns'
-- font advances about 4px a character. Anything over seven runs into the
-- next section; six is where it stays comfortable.
check("no label is wide enough to run into the next cell", function()
  local st = state
  local seen, over = {}, {}
  for m = 1, NM do
    st.tracks[1]:set_machine(m)
    for _, page in ipairs(st.tracks[1].pages) do
      for _, sp in ipairs(page.params) do
        if not seen[sp.name] then
          seen[sp.name] = true
          if #sp.name > 6 then table.insert(over, sp.name .. " (" .. #sp.name .. ")") end
        end
      end
    end
  end
  -- the master pages draw in the same cells, so they are held to the same width
  for _, page in ipairs(tahned.master.pages) do
    for _, e in ipairs(page.p or {}) do
      if not seen[e.name] then
        seen[e.name] = true
        if #e.name > 6 then table.insert(over, e.name .. " (" .. #e.name .. ")") end
      end
    end
  end
  assert(#over == 0, "labels too wide: " .. table.concat(over, ", "))
end)

check("holding several steps locks all of them, silently", function()
  local st = state
  st.mode = "page"
  st.select_track(1)
  st.tracks[1]:set_machine(1)
  local sq = st.seq()
  sq:clear()
  st.set_page(4)                            -- KICK / SYNTH
  st.cursor = 1                             -- TUNE
  local sp = st.cur_spec()
  local before = engine_calls.pset or 0
  local track_before = st.tracks[1]:get(sp)

  G.g.key(1, 1, 1); G.g.key(3, 1, 1); G.g.key(5, 1, 1)
  assert(st.lock_count() == 3, "three pads held, saw " .. st.lock_count())
  enc(3, 5)
  for _, i in ipairs({ 1, 3, 5 }) do
    local step = sq:get_step(i)
    assert(step and step.lock and step.lock[sp.ch], "step " .. i .. " took no lock")
  end
  -- nothing is pushed at the engine and the track keeps its own value, so
  -- the edit is only ever heard on the steps that carry it
  assert((engine_calls.pset or 0) == before, "a lock was sent at the engine live")
  assert(st.tracks[1]:get(sp) == track_before, "a lock moved the track's own value")

  -- E1 is the held steps' velocity, and it reaches all of them too
  enc(1, 3)
  for _, i in ipairs({ 1, 3, 5 }) do
    assert(sq:get_step(i).vel ~= 100, "step " .. i .. " kept its velocity")
  end

  -- letting one go leaves the others holding
  G.g.key(5, 1, 0)
  assert(st.lock_count() == 2 and st.lock_step ~= nil, "focus lost with pads still down")
  G.g.key(3, 1, 0); G.g.key(1, 1, 0)
  assert(st.lock_step == nil, "lock target not released")
  sq:clear()
end)

check("rotating slides the pattern the grid and screen draw", function()
  local st = state
  st.select_track(1)
  st.tracks[1]:set_machine(1)
  local sq = st.seq()
  sq:clear()
  sq.s.length, sq.s.rotate = 16, 0
  sq:ensure(1)
  assert(sq:disp_step(1) ~= nil, "step 1 not drawn where it was written")
  sq.s.rotate = 3
  assert(sq:disp_step(1) == nil, "rotate did not move the pattern")
  local found
  for i = 1, 16 do if sq:disp_step(i) then found = i end end
  assert(found == 14, "step 1 drew at " .. tostring(found) .. ", expected 14")
  -- and a pad now edits the step it is drawing
  G.g.key(14, 1, 1); G.g.key(14, 1, 0)
  assert(sq.steps[1] == nil, "the pad under the rotated step did not edit it")
  sq.s.rotate = 0
  sq:clear()
end)

check("the master pages walk, and each kind turns what it holds", function()
  local st = state
  st.mode = "master"
  st.mpage, st.mcursor = 1, 1

  -- K2 and K3 walk the master's own pages, and do not wrap
  for _ = 1, MPAGES + 5 do key(3, 1); key(3, 0) end
  assert(st.mpage == MPAGES, "master pages ran off the back: " .. st.mpage)
  for _ = 1, MPAGES + 5 do key(2, 1); key(2, 0) end
  assert(st.mpage == 1, "master pages ran off the front: " .. st.mpage)

  -- the master lane's own settings sit at page 2, drawn and turned by the
  -- same cell code a track's SEQ page uses
  st.set_master_page(2)
  assert(st.master_page().kind == "seq", "page 2 is not the master sequencer")
  st.mcursor = 1
  local mlen = st.mseq:length()
  enc(3, 4)
  assert(st.mseq:length() ~= mlen, "E3 did not turn the master lane's LENGTH")
  redraw()

  -- MIX: E2 walks the eight tracks and E3 turns the one under the cursor
  st.set_master_page(4)
  assert(st.master_page().kind == "mix", "page 4 is not MIX")
  enc(2, 2)
  assert(st.mcursor == 3, "E2 did not walk the faders")
  local t3 = st.tracks[3]
  local lvl = t3.chspec[0]
  local v0 = t3:get(lvl)
  enc(3, -6)
  assert(t3:get(lvl) ~= v0, "E3 did not move track 3's fader")
  redraw()

  -- COLOUR and PERFORM are norns params, turned the same way the sends are
  for _, page in ipairs({ 3, 5 }) do
    st.set_master_page(page)
    st.mcursor = 1
    for c = 1, #st.master_page().p do
      st.mcursor = c
      local e = st.master_param()
      local p0 = params:get(e.param)
      enc(3, 5)
      assert(params:get(e.param) ~= p0, "E3 did not turn " .. e.param)
    end
    redraw()
  end

  -- SEND FX points at the same params the full pages hold
  st.set_master_page(6)
  assert(st.master_page().name == "SEND FX", "page 6 is not SEND FX")
  st.mcursor = 1
  assert(st.master_param().param == "rev_size", "SEND FX does not start on the reverb")
  local sz = params:get("rev_size")
  enc(3, 5)
  assert(params:get("rev_size") ~= sz, "E3 did not turn the reverb from SEND FX")
  redraw()

  -- the clock still lands under the cursor the moment you reach its page
  st.set_master_page(7)
  st.mcursor = 1
  assert(st.master_param().param == "clock_tempo", "page 7 is not the clock")
  local t0 = params:get("clock_tempo")
  enc(3, 4)
  assert(params:get("clock_tempo") ~= t0, "E3 did not move the tempo")

  -- K1+E2 jumps whole pages
  st.shift = true
  enc(2, 3)
  st.shift = false
  assert(st.mpage == 10 and st.master_page().name == "REVERB",
    "K1+E2 landed on " .. st.master_page().name)
  enc(2, 2)
  local e = st.master_param()
  assert(e and e.param:match("^rev_"), "E2 left the page")
  local rv = params:get(e.param)
  enc(3, 6)
  assert(params:get(e.param) ~= rv, "E3 did not turn " .. e.param)
  redraw()

  st.set_master_page(1)
  redraw()
  st.mode = "page"
end)

check("holding a step and turning E3 writes a parameter lock", function()
  local st = state
  st.tracks[st.sel]:set_machine(1)
  st.set_page(4)                         -- KICK / SYNTH
  st.cursor = 1
  G.g.key(1, 1, 1)                       -- create + hold step 1
  local sp = st.cur_spec()
  enc(3, 4)
  local step = st.seq():get_step(1)
  assert(step and step.lock and step.lock[sp.ch], "no lock written")
  -- sequencer settings lock per step too, and E1 is velocity while held
  st.set_page(2)
  for c = 1, 8 do
    st.cursor = c
    enc(3, 2)
  end
  local seqlocked = step.ratchet or step.prob
  assert(seqlocked, "no sequencer setting locked to the step")
  local v0 = step.vel
  enc(1, 3)
  assert(step.vel ~= v0, "E1 did not set step velocity")
  local sel0 = st.sel
  G.g.key(1, 1, 0)
  assert(st.lock_step == nil, "lock target not released")
  enc(1, 1)
  assert(st.sel ~= sel0, "E1 did not return to track select")
end)

check("keyboard notes survive a scale change while held", function()
  local st = state
  st.mode = "page"
  st.select_track(1)
  st.tracks[1]:set_machine(TONE)
  local sq = st.seq()
  st.lock_step = nil
  local before = voice_count()

  -- hold a keyboard pad, change the scale under it, then let go
  G.g.key(3, 6, 1)
  assert(voice_count() == before + 1, "keyboard pad did not sound")
  -- the key is global now, so the change comes from the master's SONG page
  -- rather than from this track's own settings
  params:set("key_scale", (params:get("key_scale") or 1) + 3)
  params:set("key_root", ((params:get("key_root") or 1) + 5 - 1) % 12 + 1)
  G.g.key(3, 6, 0)
  assert(voice_count() == before, "note left hanging after a scale change")

  -- two pads can land on the same pitch; releasing one must not cut the other
  G.g.key(1, 6, 1)
  G.g.key(4, 7, 1)
  assert(voice_count() == before + 2, "overlapping pads share a voice")
  G.g.key(1, 6, 0)
  assert(voice_count() == before + 1, "releasing one pad cut both")
  G.g.key(4, 7, 0)
  assert(voice_count() == before, "second pad left hanging")

  -- and dropping into select mode with a pad down releases it
  G.g.key(5, 8, 1)
  assert(voice_count() == before + 1, "keyboard pad did not sound")
  st.mode = "master"
  G.g.key(1, 1, 1); G.g.key(1, 1, 0)
  assert(voice_count() == before, "note left hanging entering master mode")
  st.mode = "page"
  st.select_track(1)
end)

check("master grid selects tracks, all six machines, mutes, transport", function()
  local st = state
  st.mode = "master"
  st.set_master_page(1)              -- the overview is the one page that is
  G.redraw()                         -- not the master lane's steps
  G.g.key(1, 5, 1); G.g.key(1, 5, 0)
  assert(st.sel == 5, "track select failed")
  -- columns 8..13 are the six machines, in order
  for m = 1, NM do
    G.g.key(7 + m, 5, 1); G.g.key(7 + m, 5, 0)
    assert(st.tracks[5].machine == m,
      "machine column " .. (7 + m) .. " chose " .. st.tracks[5].machine)
  end
  G.g.key(15, 5, 1); G.g.key(15, 5, 0)
  assert(st.tracks[5].mute == true, "mute failed")
  G.g.key(15, 5, 1); G.g.key(15, 5, 0)
  G.g.key(16, 1, 1); G.g.key(16, 1, 0)
  assert(st.playing, "grid transport did not start")
  G.g.key(16, 1, 1); G.g.key(16, 1, 0)
  st.mode = "page"
  st.select_track(1)
end)

check("transport runs every sequencer", function()
  local st = state
  for i = 1, 8 do st.tracks[i]:set_machine(((i - 1) % NM) + 1) end
  st.start()
  -- pump the clock coroutines the way norns would
  for _ = 1, 200 do
    for _, co in ipairs(coros) do
      if coroutine.status(co) == "suspended" then coroutine.resume(co) end
    end
  end
  st.stop()
end)

-- HOLD is the one sequencer feature that changes the shape of the run loop,
-- so it is checked by running it: the playhead has to sit still for exactly
-- as many pulses as the step asks for, and REPEAT has to sound on each.
check("a held step stalls the playhead and repeats on every pulse", function()
  local st = state
  st.stop()
  st.select_track(1)
  local t = st.tracks[1]
  t:set_machine(1)
  local sq = t:seq()
  sq:clear()
  sq.s.length, sq.s.speed, sq.s.swing, sq.s.dir, sq.s.rotate = 4, 5, 0, 0, 0
  for i = 1, 4 do sq:ensure(i) end
  sq.steps[2].hold = 3
  sq.steps[2].htype = 1                       -- REPEAT

  local before = engine_calls.trig or 0
  sq:start()
  local co = coros[sq.clocks[1]]
  local seen = {}
  for k = 1, 5 do
    coroutine.resume(co)
    seen[k] = sq.last
  end
  sq:stop()

  assert(seen[1] == 1, "first pulse played step " .. tostring(seen[1]))
  for k = 2, 4 do
    assert(seen[k] == 2, "pulse " .. k .. " left step 2 for " .. tostring(seen[k]))
  end
  assert(seen[5] == 3, "the hold did not release onto step 3, got "
    .. tostring(seen[5]))
  assert((engine_calls.trig or 0) - before == 5,
    "REPEAT sounded " .. ((engine_calls.trig or 0) - before) .. " times, want 5")
end)

check("a time signature scales the step and groups the bar", function()
  local sq = state.tracks[1]:seq()
  sq.s.speed, sq.s.tsig = 5, 0                 -- x1, 4/4
  assert(math.abs(sq:step_beats() - 0.25) < 1e-9, "4/4 x1 is not a 16th")
  assert(sq:bar_steps() == 16, "4/4 x1 bar is " .. sq:bar_steps() .. ", want 16")
  assert(sq:mark_steps() == 4, "the pattern marker is not every fourth step")
  sq.s.tsig = 9                                -- 7/8
  assert(math.abs(sq:step_beats() - 0.125) < 1e-9,
    "7/8 did not halve the step: " .. sq:step_beats())
  assert(sq:bar_steps() == 28, "7/8 x1 bar is " .. sq:bar_steps() .. ", want 28")
  sq.s.tsig = 0
end)

check("an LFO pointed at BPM moves the tempo, and gives it back", function()
  local LFO = tahned.lfo
  local S2 = include("tahned/lib/core/spec")
  -- earlier checks turn every cell of every page, BPM destinations included,
  -- so start from a clean routing rather than from whatever they left
  for _, tr in ipairs(state.tracks) do
    for n = 0, 3 do
      tr.v[56 + (n * 8) + 4] = S2.NULL_DEST
      tr.v[56 + (n * 8) + 6] = S2.NULL_DEST
    end
  end
  local t = state.tracks[1]
  LFO.step(state.tracks, 1 / 30)               -- hand back anything still held
  local base = params:get("clock_tempo")
  LFO.step(state.tracks, 1 / 30)               -- settle the centre
  t.v[60] = S2.BPM_DEST                        -- LFO 1 DEST A
  t.v[61] = 63                                 -- DEP A, full swing
  local moved = false
  for _ = 1, 40 do
    LFO.step(state.tracks, 1 / 30)
    if math.abs(params:get("clock_tempo") - base) > 0.5 then moved = true end
  end
  assert(moved, "BPM never moved")
  t.v[60] = S2.NULL_DEST
  LFO.step(state.tracks, 1 / 30)
  assert(math.abs(params:get("clock_tempo") - base) < 0.01,
    "the tempo was not handed back: " .. params:get("clock_tempo"))
end)

-- The three gestures the grid grew: a key change that takes the written notes
-- with it, the master's own lane, and reaching from one step to another.

check("moving the key moves the notes already written", function()
  local st = state
  st.mode = "page"
  st.select_track(1)
  st.tracks[1]:set_machine(TONE)
  local sq = st.seq()
  sq:clear()

  params:set("key_scale", 1)
  params:set("key_root", 1)                    -- C, and the key is now known
  local step = sq:ensure(1)
  step.notes = { 60, 64, 67 }
  -- a pattern parked on a machine nobody is looking at moves too
  local other = st.tracks[2].slot[TONE].seq
  other:clear()
  other:ensure(1).notes = { 48 }

  params:set("key_root", 3)                    -- D: everything up a tone
  assert(step.notes[1] == 62 and step.notes[2] == 66 and step.notes[3] == 69,
    "the written notes did not follow the root: "
    .. table.concat(step.notes, ","))
  assert(other:get_step(1).notes[1] == 50, "an unselected slot kept the old key")

  -- and the long way round is never taken: B is a semitone down, not eleven up
  params:set("key_root", 2)                    -- C# from D
  assert(step.notes[1] == 61, "the root moved the long way: " .. step.notes[1])

  -- a scale change re-snaps rather than transposes, and leaves every note in
  -- the new scale
  params:set("key_scale", 2)
  local arr = sq:scale_array()
  for _, n in ipairs(step.notes) do
    local found
    for _, v in ipairs(arr) do if v == n then found = true end end
    assert(found, "note " .. n .. " is not in the new scale")
  end

  -- a drum's NOTE is an offset from its own tuning and has nothing to do with
  -- the key, so it does not move
  local dr = st.tracks[1].slot[1].seq
  dr:clear()
  dr:ensure(1).note = 5
  params:set("key_root", 8)
  assert(dr:get_step(1).note == 5, "a drum step followed the key")

  sq:clear(); other:clear(); dr:clear()
  params:set("key_scale", 1)
  params:set("key_root", 1)
end)

check("the master lane locks a master parameter to a step", function()
  local st = state
  st.mode = "master"
  st.set_master_page(5)                        -- COLOUR
  st.mcursor = 1                               -- CRUSH
  local sq = st.mseq
  sq:clear()
  sq.s.length, sq.s.rotate = 16, 0
  local e = st.master_param()
  local own = params:get(e.param)
  local sent = engine_calls.colSet or 0

  G.redraw()
  G.g.key(1, 1, 1)
  assert(st.lock_step == 1, "the master lane did not take the pad")
  enc(3, 6)
  local step = sq:get_step(1)
  assert(step and step.lock and step.lock[e.param], "no master lock written")
  -- the same rule the track locks follow: nothing is pushed as it is written
  assert(params:get(e.param) == own, "a lock moved the master's own value")
  assert((engine_calls.colSet or 0) == sent, "a master lock was sent live")
  redraw()
  G.g.key(1, 1, 0)

  -- it reaches the engine when the step comes round, and is handed back when
  -- the step passes
  local locked = step.lock[e.param]
  sq:apply_locks(step)
  assert(engine_last.colSet[2] == locked,
    "the lock never reached the engine: " .. tostring(engine_last.colSet[2]))
  sq:apply_locks(nil)
  assert(engine_last.colSet[2] == own, "the master's own value was not put back")

  -- the key and the clock are not lockable: E3 turns them as it always did
  st.set_master_page(7)                        -- SONG
  st.mcursor = 2                               -- ROOT
  local r0 = params:get("key_root")
  G.g.key(2, 1, 1)
  enc(3, 1)
  assert(params:get("key_root") ~= r0, "ROOT stopped turning when it cannot lock")
  local s2 = sq:get_step(2)
  assert(not (s2 and s2.lock and next(s2.lock)), "the key took a lock")
  G.g.key(2, 1, 0)
  params:set("key_root", r0)

  -- the lane's own HOLD is lock-only: it moves onto a held step and nowhere
  -- else, and E1 stays track select because a master step never sounds
  st.set_master_page(2)
  st.mcursor = 8
  local h0 = st.mseq:get(st.master_spec())
  enc(3, 3)
  assert(st.mseq:get(st.master_spec()) == h0, "the lane's HOLD turned unheld")
  G.g.key(4, 1, 1)
  enc(3, 3)
  assert(st.mseq:get_step(4).hold ~= nil, "HOLD did not lock onto the held step")
  local sel0 = st.sel
  enc(1, 1)
  assert(st.sel ~= sel0, "E1 left track select for a velocity nothing reads")
  G.g.key(4, 1, 0)

  sq:clear()
  st.set_master_page(1)
  st.mode = "page"
end)

check("every master page draws with one of its steps held", function()
  local st = state
  st.mode = "master"
  for pg = 1, MPAGES do
    st.set_master_page(pg)
    if st.master_steps() then
      G.g.key(1, 1, 1)
      G.redraw()
      for c = 1, tahned.master.page_cells(pg) do
        st.mcursor = c
        redraw()
      end
      G.g.key(1, 1, 0)
    else
      G.redraw()
      redraw()
    end
  end
  st.mseq:clear()
  st.set_master_page(1)
  st.mode = "page"
end)

check("reaching from one step to another sustains the first", function()
  local st = state
  st.mode = "page"
  st.select_track(1)
  st.tracks[1]:set_machine(1)
  local sq = st.seq()
  sq:clear()
  sq.s.length, sq.s.rotate = 16, 0

  G.g.key(1, 1, 1)                             -- hold step 1
  G.g.key(5, 1, 1)                             -- tap step 5
  G.g.key(5, 1, 0)
  G.g.key(1, 1, 0)
  local step = sq:get_step(1)
  assert(step, "the step reached from was cleared by its own release")
  assert(step.hold == 5, "step 1 carries " .. tostring(step.hold) .. ", want 5")
  assert(sq:get_step(5) == nil, "the pad that was tapped left a step behind")

  -- reaching backwards is the long way round rather than nothing
  sq:clear()
  G.g.key(4, 1, 1)
  G.g.key(2, 1, 1); G.g.key(2, 1, 0)
  G.g.key(4, 1, 0)
  assert(sq:get_step(4).hold == 15,
    "reaching backwards gave " .. tostring(sq:get_step(4).hold) .. ", want 15")

  -- and holding several pads is still a lock gesture, not a reach
  sq:clear()
  st.set_page(4)
  st.cursor = 1
  G.g.key(1, 1, 1); G.g.key(3, 1, 1)
  enc(3, 4)
  G.g.key(3, 1, 0); G.g.key(1, 1, 0)
  local sp = st.cur_spec()
  for _, i in ipairs({ 1, 3 }) do
    local e = sq:get_step(i)
    assert(e and e.lock and e.lock[sp.ch], "step " .. i .. " took no lock")
    assert(e.hold == nil, "a lock gesture wrote a reach onto step " .. i)
  end
  sq:clear()
end)

check("notes held on the keyboard write onto a step that is pressed", function()
  local st = state
  st.mode = "page"
  st.select_track(1)
  st.tracks[1]:set_machine(TONE)
  local sq = st.seq()
  sq:clear()
  sq.s.length, sq.s.rotate = 16, 0
  st.lock_step = nil

  local n1 = G.kb_note(sq, 2, 6)
  local n2 = G.kb_note(sq, 5, 6)
  G.g.key(2, 6, 1)
  G.g.key(5, 6, 1)
  G.g.key(3, 1, 1); G.g.key(3, 1, 0)           -- press a step, both ways round
  G.g.key(5, 6, 0); G.g.key(2, 6, 0)

  local step = sq:get_step(3)
  assert(step and step.notes and #step.notes == 2,
    "the step did not take the held notes")
  assert(step.notes[1] == math.min(n1, n2) and step.notes[2] == math.max(n1, n2),
    "the step took the wrong notes")
  assert(voice_count() == 0, "a keyboard note was left sounding")
  sq:clear()
end)

check("serialize round trip", function()
  local st = state
  local d = st.serialize()
  st.deserialize(d)
end)

print(string.format("\n%s  (%d screen ops, %d grid leds, %d engine call sites)",
  fails == 0 and "PASS" or ("FAIL: " .. fails), draws, gled,
  (function() local n = 0 for _ in pairs(engine_calls) do n = n + 1 end return n end)()))
os.exit(fails == 0 and 0 or 1)
