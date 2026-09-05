-- pages.lua -- the 128x64 display
--
-- Eight cells in two rows of four, the way the hardware this borrows from
-- lays out a page. Each cell is label / glyph / value. The glyph is the
-- point: it should let you read the page without reading the numbers.

local S = include("tahned/lib/core/spec")
local W = include("tahned/lib/ui/widgets")
local C = include("tahned/lib/instruments/common")
local musicutil = require "musicutil"

local P = {}

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
    local d = track.chspec[v]
    return d and d.name or "-"
  end
  if sp.id == "scale" then
    local sc = musicutil.SCALES[util.clamp(v, 1, #musicutil.SCALES)]
    return sc and sc.name:sub(1, 7) or "-"
  end
  if sp.id == "speed" then return C.SPEED_NAMES[v + 1] or "-" end
  return S.text(sp, v)
end

-- ---------------------------------------------------------------- cells

local function draw_cell(track, sp, i, selected, lockv)
  local x, y = cell_xy(i)
  local v = lockv or track:get(sp)
  if v == nil then v = sp.def or 0 end

  -- label, inverted when this is the cell the encoders are on
  if selected then
    screen.level(15)
    screen.rect(x, y, CW - 1, 7)
    screen.fill()
    screen.level(0)
  else
    screen.level(4)
  end
  screen.move(x + 2, y + 6)
  screen.text(sp.name)

  -- glyph
  local extra
  if sp.g == "filt" then extra = track:raw(40) end
  W.draw(sp.g or "bar", x + 2, y + 9, CW - 6, 9, sp, v, selected and 15 or 9, extra)

  -- value; a locked value is flagged so it is never mistaken for the track's
  screen.level(selected and 15 or 6)
  screen.move(x + 2, y + 24)
  screen.text(value_text(track, sp, v))
  if lockv then
    screen.level(15)
    screen.rect(x + CW - 6, y + 20, 3, 3)
    screen.fill()
  end
end

-- ---------------------------------------------------------------- chrome

local function draw_header(track, page, npages, lock_step, state_lock_vel)
  screen.level(15)
  screen.move(0, 6)
  screen.text("T" .. track.idx)
  screen.level(4)
  screen.move(13, 6)
  screen.text(track:inst().short)

  screen.level(track.mute and 3 or 15)
  screen.move(30, 6)
  screen.text(lock_step and ("LOCK " .. lock_step) or track.pages[page].name)
  if lock_step then
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

  if sq.kind == "amb" then
    -- eight lanes, each its own length: draw them as eight short runs
    for l = 1, 8 do
      local ln = sq.lane[l]
      local x0 = (l - 1) * 16
      for i = 1, ln.length do
        local on = ln.steps[i] and ln.steps[i].on
        screen.level(i == ln.last and 15 or (on and 6 or 1))
        screen.rect(x0 + ((i - 1) * (16 / ln.length)), y, 1, i == ln.last and 3 or 2)
      end
    end
    screen.fill()
    return
  end

  local len = sq:length()
  local w = 128 / len
  for i = 1, len do
    local st = sq.steps[i]
    screen.level(i == sq.last and 15 or ((st and st.on) and 6 or 1))
    screen.rect((i - 1) * w, y, math.max(1, w - (len > 32 and 0 or 1)),
      i == sq.last and 3 or 2)
  end
  screen.fill()
end

-- ---------------------------------------------------------------- modes

function P.draw_page(state)
  local track = state.track()
  local page = state.cur_page()
  draw_header(track, state.page(), #track.pages, state.lock_step, state.lock_vel())

  screen.level(1)
  for c = 1, 3 do
    screen.rect(c * CW - 1, TOP, 1, CH * 2 - 3)
  end
  screen.fill()

  for i = 1, 8 do
    local sp = page.params[i]
    if sp then
      draw_cell(track, sp, i, i == state.cursor, state.lock_value(sp))
    end
  end

  draw_footer(track)
end

-- track select and transport, on K2+K3
function P.draw_select(state)
  screen.level(15)
  screen.move(0, 6)
  screen.text(state.playing and "PLAY" or "STOP")
  screen.level(4)
  screen.move(30, 6)
  screen.text(string.format("%.0f BPM", clock.get_tempo()))
  screen.level(4)
  screen.move(127, 6)
  screen.text_right("K3 PLAY")

  for i = 1, 8 do
    local t = state.tracks[i]
    local y = 10 + ((i - 1) * 6.6)
    local sel = (i == state.sel)
    if sel then
      screen.level(15)
      screen.rect(0, y, 128, 6)
      screen.fill()
    end
    screen.level(sel and 0 or (t.mute and 3 or 12))
    screen.move(2, y + 5)
    screen.text("T" .. i)
    screen.move(15, y + 5)
    screen.text(t:inst().name)

    -- pattern at a glance
    local sq = t:seq()
    local len = (sq.kind == "amb") and 16 or sq:length()
    local x0, w = 46, 78
    for s = 1, math.min(len, 64) do
      local on
      if sq.kind == "amb" then
        on = false
        for l = 1, 8 do if sq.lane[l].steps[s] then on = true break end end
      else
        on = sq.steps[s] and sq.steps[s].on
      end
      local head = (sq:playhead() == s)
      screen.level(head and (sel and 0 or 15) or (on and (sel and 4 or 7) or (sel and 12 or 1)))
      screen.rect(x0 + ((s - 1) * (w / math.min(len, 64))), y + 1, 1, 4)
    end
    screen.fill()
    screen.level(sel and 0 or 6)
    screen.move(127, y + 5)
    screen.text_right(t.mute and "M" or "")
  end
end

function P.redraw(state)
  screen.clear()
  screen.font_face(1)
  screen.font_size(8)
  screen.aa(0)
  if state.mode == "select" then P.draw_select(state) else P.draw_page(state) end
  screen.update()
end

return P
