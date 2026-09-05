-- pages.lua -- the 128x64 display
--
-- Eight cells in two rows of four, the way the hardware this borrows from
-- lays out a page. Each cell is label / glyph / value. The glyph is the
-- point: it should let you read the page without reading the numbers.

local S = include("tahned/lib/core/spec")
local W = include("tahned/lib/ui/widgets")
local C = include("tahned/lib/instruments/common")
local M = include("tahned/lib/core/master")
local musicutil = require "musicutil"

local P = {}

-- Set while a page has a cell that moves on its own -- the LFO scope. The
-- screen metro reads it, so an animated page keeps redrawing and a still one
-- costs nothing.
P.anim = false

local CW, CH = 32, 26
local TOP = 8

local function cell_xy(i)
  local col = (i - 1) % 4
  local row = math.floor((i - 1) / 4)
  return col * CW, TOP + (row * CH)
end

-- ---------------------------------------------------------------- text

local function value_text(track, sp, v)
  if sp.k == "mach" then return S.MACHINE[v + 1] end
  if sp.k == "dest" then
    if v == S.NULL_DEST then return "OFF" end
    -- read the machine's own destination list: BPM is in it and is not a
    -- channel any page holds, so chspec would not find it
    local i = track.dest_by_ch[v]
    local d = i and track.dests[i]
    return d and d.name or "-"
  end
  if sp.id == "scale" then
    local sc = musicutil.SCALES[util.clamp(v, 1, #musicutil.SCALES)]
    return sc and sc.name:sub(1, 6) or "-"
  end
  if sp.id == "speed" then return C.SPEED_NAMES[v + 1] or "-" end
  return S.text(sp, v)
end

-- ---------------------------------------------------------------- cells

local function glyph_extra(track, sp)
  if sp.g == "filt" then return track:raw(40) end
  if sp.g == "lfoscope" then
    -- the scope needs the rest of its own LFO: the wave to draw and the
    -- multiplier that, with SPD and the tempo, sets how fast it runs
    P.anim = true
    return { wave = track:raw(sp.ch + 2), mult = track:raw(sp.ch + 1),
             bpm = clock.get_tempo(), now = util.time() }
  end
  return nil
end

local function draw_cell(track, sp, i, selected, lockv, noglyph, holding)
  local x, y = cell_xy(i)
  local v = lockv or track:get(sp)
  if v == nil then v = sp.def or 0 end
  -- A lock-only control is inert unless a step is being held: it is still
  -- drawn, so the page is the same page either way, but it is plainly not
  -- turnable. Holding a pad is what wakes it, lock written or not.
  local inert = sp.lockonly and not holding

  -- label, inverted when this is the cell the encoders are on
  if selected then
    screen.level(15)
    screen.rect(x, y, CW - 1, 7)
    screen.fill()
    screen.level(0)
  else
    screen.level(inert and 3 or 4)
  end
  screen.move(x + 2, y + 6)
  screen.text(sp.name)

  -- glyph. An envelope run draws once across all of its cells instead.
  if not noglyph then
    if inert then
      W.strike(x + 2, y + 9, CW - 6, 9)
    else
      W.draw(sp.g or "bar", x + 2, y + 9, CW - 6, 9, sp, v,
        selected and 15 or 9, glyph_extra(track, sp))
    end
  end

  -- value; a locked value is flagged so it is never mistaken for the track's
  screen.level(inert and 3 or (selected and 15 or 6))
  screen.move(x + 2, y + 24)
  screen.text(value_text(track, sp, v))
  if lockv then
    screen.level(15)
    screen.rect(x + CW - 6, y + 20, 3, 3)
    screen.fill()
  end
end

-- One envelope across the run of cells its segments occupy, rather than four
-- separate pictures of four numbers. Returns the cell range it covered so the
-- cells themselves know to leave their glyph out.
local function draw_env(state, track, page)
  local e = page.env
  if not e then return 0, -1 end
  local segs = {}
  for k, kind in ipairs(e.segs) do
    local sp = page.params[e.at + k - 1]
    if not sp then return 0, -1 end
    local v = state.lock_value(sp) or track:get(sp)
    if v == nil then v = sp.def or 0 end
    segs[k] = { kind = kind, p = S.unit_pos(sp, v) }
  end
  local x, y = cell_xy(e.at)
  local sel = state.cursor - e.at + 1
  if sel < 1 or sel > #segs then sel = nil end
  W.envelope(x + 2, y + 9, (#segs * CW) - 6, 9, segs, sel)
  return e.at, e.at + #segs - 1
end

-- ---------------------------------------------------------------- chrome

local function draw_header(track, page, npages, lock_pad, state_lock_vel, nheld)
  screen.level(15)
  screen.move(0, 6)
  screen.text("T" .. track.idx)
  screen.level(4)
  screen.move(13, 6)
  screen.text(track:inst().short)

  -- a lock gesture over several pads says so, since the edit lands on all
  local label = track.pages[page].name
  if lock_pad then
    label = "LOCK " .. lock_pad
    if (nheld or 1) > 1 then label = label .. "+" .. (nheld - 1) end
  end
  screen.level(track.mute and 3 or 15)
  screen.move(30, 6)
  screen.text(label)
  if lock_pad then
    screen.level(6)
    screen.move(75, 6)
    screen.text("v" .. (state_lock_vel or 100))
  end

  -- page position, one tick per page, no wrap so the ends are meaningful
  local x0 = 128 - (npages * 3)
  for i = 1, npages do
    screen.level(i == page and 15 or 2)
    screen.rect(x0 + ((i - 1) * 3), 2, 2, i == page and 4 or 2)
    screen.fill()
  end
end

-- position bar for the selected track, along the bottom edge
local function draw_footer(track)
  local sq = track:seq()
  local y = 61
  screen.level(1)
  screen.rect(0, y, 128, 1)
  screen.fill()

  local len = sq:length()
  local w = 128 / len
  local head = sq:playhead()
  local bar = sq:bar_steps()
  for i = 1, len do
    local st = sq:disp_step(i)
    local on = st and st.on
    local lv = 1
    if ((i - 1) % bar) == 0 then lv = 3 end
    if on then lv = 6 end
    if i == head then lv = 15 end
    screen.level(lv)
    screen.rect((i - 1) * w, y, math.max(1, w - (len > 32 and 0 or 1)),
      i == head and 3 or 2)
  end
  screen.fill()
end

-- ---------------------------------------------------------------- modes

function P.draw_page(state)
  local track = state.track()
  local page = state.cur_page()
  draw_header(track, state.page(), #track.pages, state.lock_pad, state.lock_vel(),
    state.lock_count())

  screen.level(1)
  for c = 1, 3 do
    screen.rect(c * CW - 1, TOP, 1, CH * 2 - 3)
  end
  screen.fill()

  local e0, e1 = draw_env(state, track, page)
  local holding = state.lock_step ~= nil
  for i = 1, 8 do
    local sp = page.params[i]
    if sp then
      draw_cell(track, sp, i, i == state.cursor, state.lock_value(sp),
        i >= e0 and i <= e1, holding)
    end
  end

  draw_footer(track)
end

-- ---------------------------------------------------------------- master
--
-- K2+K3 opens a page set of its own; K2 and K3 walk it, E2 moves the cursor
-- inside a page and E3 turns what is under it. E1 still picks a track.

local function draw_master_header(state, pg)
  screen.level(15)
  screen.move(0, 6)
  screen.text(state.playing and "PLAY" or "STOP")
  screen.level(4)
  screen.move(28, 6)
  screen.text(pg.name)

  local n = #M.pages
  local x0 = 128 - (n * 3)
  for i = 1, n do
    screen.level(i == state.mpage and 15 or 2)
    screen.rect(x0 + ((i - 1) * 3), 2, 2, i == state.mpage and 4 or 2)
    screen.fill()
  end
end

-- the eight tracks: machine, mute, and the pattern each one is playing
local function draw_over(state)
  for i = 1, 8 do
    local t = state.tracks[i]
    local y = 9 + ((i - 1) * 6.7)
    local sel = (i == state.sel)
    if sel then
      screen.level(15)
      screen.rect(0, y, 128, 6.2)
      screen.fill()
    end
    screen.level(sel and 0 or (t.mute and 3 or 12))
    screen.move(2, y + 5)
    screen.text("T" .. i)
    screen.move(15, y + 5)
    screen.text(t:inst().name)

    -- the sequencing lane, through the same rotation the grid draws
    local sq = t:seq()
    local shown = math.min(sq:length(), 64)
    local x1, w = 52, 70
    for st = 1, shown do
      local step = sq:disp_step(st)
      local on = step and step.on
      local head = (sq:playhead() == st)
      screen.level(head and (sel and 0 or 15) or (on and (sel and 4 or 7) or (sel and 12 or 1)))
      screen.rect(x1 + ((st - 1) * (w / shown)), y + 1, 1, 4)
    end
    screen.fill()
    screen.level(sel and 0 or 6)
    screen.move(127, y + 5)
    screen.text_right(t.mute and "M" or "")
  end
end

-- eight faders, one a track, reading the level channel its MIX page turns
local function draw_mix(state)
  local top, bot = 14, 54
  for i = 1, 8 do
    local t = state.tracks[i]
    local sp = t.chspec[0]
    local v = sp and t:get(sp) or 0
    local p = sp and S.unit_pos(sp, v) or 0
    local x = 4 + ((i - 1) * 15.5)
    local cur = (i == state.mcursor)

    screen.level(1)
    screen.rect(x + 4, top, 1, bot - top)
    screen.fill()
    screen.level(t.mute and 2 or (cur and 15 or 6))
    screen.rect(x + 4, bot - ((bot - top) * p), 1, (bot - top) * p)
    screen.fill()
    -- the cap, so a fader at zero is still visibly a fader
    screen.level(cur and 15 or 8)
    screen.rect(x, bot - ((bot - top) * p) - 1, 9, 2)
    screen.fill()

    screen.level(cur and 15 or (t.mute and 3 or 5))
    screen.move(x, 62)
    screen.text(t.mute and "M" or tostring(i))
  end
  local sp = state.tracks[state.mcursor] and state.tracks[state.mcursor].chspec[0]
  if sp then
    screen.level(15)
    screen.move(126, 13)
    screen.text_right("T" .. state.mcursor .. " "
      .. S.text(sp, state.tracks[state.mcursor]:get(sp)))
  end
end

-- a params page draws in the same eight cells a track page does, so the
-- master does not become a second, differently shaped instrument
local function draw_master_params(state, pg)
  -- only as many dividers as there are columns in use, or the clock's single
  -- cell sits inside an empty grid
  screen.level(1)
  for c = 1, math.min(4, #pg.p) - 1 do
    screen.rect(c * CW - 1, TOP, 1, CH * 2 - 3)
  end
  screen.fill()

  local pseudo = { min = 0, max = 1 }
  for i = 1, math.min(8, #pg.p) do
    local e = pg.p[i]
    local x, y = cell_xy(i)
    local sel = (i == state.mcursor)
    if sel then
      screen.level(15)
      screen.rect(x, y, CW - 1, 7)
      screen.fill()
      screen.level(0)
    else
      screen.level(4)
    end
    screen.move(x + 2, y + 6)
    screen.text(e.name)

    W.draw(e.g or "bar", x + 2, y + 9, CW - 6, 9, pseudo, M.norm(e), sel and 15 or 9)

    screen.level(sel and 15 or 6)
    screen.move(x + 2, y + 24)
    screen.text(M.text(e))
  end
end

function P.draw_master(state)
  local pg = state.master_page()
  draw_master_header(state, pg)
  if pg.kind == "over" then draw_over(state)
  elseif pg.kind == "mix" then draw_mix(state)
  else draw_master_params(state, pg) end
end

function P.redraw(state)
  P.anim = false
  screen.clear()
  screen.font_face(1)
  screen.font_size(8)
  screen.aa(0)
  if state.mode == "master" then P.draw_master(state) else P.draw_page(state) end
  screen.update()
end

return P
