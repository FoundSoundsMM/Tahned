-- Draws the script's real screen output to SVG, so the display can be judged
-- without hardware. Every glyph you see is the same code norns would run.
--
--   lua tools/render-screen.lua [outdir]

local ROOT = (arg[0]:match("(.*)/tools/") or ".")
local OUT = arg[1] or "/tmp/tahned-screens"
local SCALE = 6

-- ------------------------------------------------------------------ canvas

local svg, path, cur = {}, {}, { x = 0, y = 0, lv = 15 }

local function grey(l)
  local v = math.floor((l / 15) * 255)
  return string.format("rgb(%d,%d,%d)", v, v, v)
end

local function flush(mode)
  for _, it in ipairs(path) do
    if it.t == "rect" then
      if mode == "fill" then
        svg[#svg + 1] = string.format(
          '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>',
          it.x, it.y, math.max(it.w, 0.4), math.max(it.h, 0.4), grey(it.lv))
      else
        svg[#svg + 1] = string.format(
          '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="%s" stroke-width="0.7"/>',
          it.x + 0.15, it.y + 0.15, math.max(it.w - 0.3, 0.4), math.max(it.h - 0.3, 0.4), grey(it.lv))
      end
    elseif it.t == "poly" and #it.pts >= 2 then
      local pts = {}
      for _, p in ipairs(it.pts) do pts[#pts + 1] = string.format("%.2f,%.2f", p[1], p[2]) end
      svg[#svg + 1] = string.format(
        '<polyline points="%s" fill="none" stroke="%s" stroke-width="0.8" stroke-linecap="square"/>',
        table.concat(pts, " "), grey(it.lv))
    end
  end
  path = {}
end

local function last_poly()
  local it = path[#path]
  if it and it.t == "poly" then return it end
  it = { t = "poly", pts = {}, lv = cur.lv }
  path[#path + 1] = it
  return it
end

local S = {}
function S.clear() svg = {}; path = {} end
function S.level(l) cur.lv = l end
function S.aa() end
function S.line_width() end
function S.font_face() end
function S.font_size() end
function S.move(x, y)
  cur.x, cur.y = x, y
  path[#path + 1] = { t = "poly", pts = { { x, y } }, lv = cur.lv }
end
function S.line(x, y)
  local p = last_poly()
  p.pts[#p.pts + 1] = { x, y }
  p.lv = cur.lv
  cur.x, cur.y = x, y
end
function S.rect(x, y, w, h) path[#path + 1] = { t = "rect", x = x, y = y, w = w, h = h, lv = cur.lv } end
function S.pixel(x, y) path[#path + 1] = { t = "rect", x = x, y = y, w = 1, h = 1, lv = cur.lv } end
function S.circle(x, y, r)
  svg[#svg + 1] = string.format('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="none" stroke="%s" stroke-width="0.7"/>',
    x, y, r, grey(cur.lv))
end
function S.fill() flush("fill") end
function S.stroke() flush("stroke") end
function S.close() end

-- norns' font is ~4px per character at size 8; monospace at 6.5 is close
local function emit_text(s, anchor)
  svg[#svg + 1] = string.format(
    '<text x="%.2f" y="%.2f" font-family="Menlo,DejaVu Sans Mono,monospace" font-size="6.5" '
    .. 'letter-spacing="-0.15" text-anchor="%s" fill="%s">%s</text>',
    cur.x, cur.y, anchor, grey(cur.lv),
    tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
function S.text(s) emit_text(s, "start") end
function S.text_right(s) emit_text(s, "end") end
function S.text_center(s) emit_text(s, "middle") end
function S.update() end

-- --------------------------------------------------------------------- run

local stats = dofile(ROOT .. "/tools/stub_norns.lua")(ROOT, S)
dofile(ROOT .. "/tahned.lua")
init()

local state = tahned.state

local function save(name, title)
  local body = table.concat(svg, "\n")
  local f = assert(io.open(OUT .. "/" .. name .. ".svg", "w"))
  f:write(string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 128 64" '
    .. 'shape-rendering="crispEdges"><title>%s</title>'
    .. '<rect width="128" height="64" fill="black"/>%s</svg>',
    128 * SCALE, 64 * SCALE, title, body))
  f:close()
  print("  " .. name .. ".svg   " .. title)
end

os.execute("mkdir -p " .. OUT)

-- something worth looking at on the page
local function dial(track, page, cell, v)
  state.set_page(page)
  local sp = state.track().pages[page].params[cell]
  if sp then track:set(sp, v) end
end

local shots = {}
local function shot(name, title, machine, page, cursor, prep)
  state.select_track(1)
  state.tracks[1]:set_machine(machine)
  if prep then prep(state.tracks[1]) end
  state.set_page(page)
  state.cursor = cursor or 1
  S.clear()
  redraw()
  save(name, title)
  shots[#shots + 1] = { name = name, title = title }
end

-- give track 1 a pattern so the footer and locks have something to show
do
  local t = state.tracks[1]
  t:set_machine(1)
  local sq = t:seq()
  for _, i in ipairs({ 1, 5, 7, 11, 13, 16 }) do
    local st = sq:ensure(i)
    st.vel = 60 + (i * 4)
  end
  sq.last = 5
end

print("rendering " .. OUT)
shot("01-perc-fm",    "PERC / FM",     1, 3, 3, function(t)
  dial(t, 3, 2, 30); dial(t, 3, 3, 40); dial(t, 3, 8, 70)
  dial(t, 3, 5, 2);  dial(t, 3, 6, 5)
end)
shot("02-perc-mod",   "PERC / MOD",    1, 4, 1)
shot("03-perc-body",  "PERC / BODY",   1, 5, 3, function(t) dial(t, 5, 3, 40) end)
shot("04-perc-noise", "PERC / NOISE",  1, 6, 7, function(t)
  dial(t, 6, 7, 80); dial(t, 6, 8, 90); dial(t, 6, 4, 60)
end)
shot("05-perc-seq",   "PERC / SEQ",    1, 2, 2)
shot("06-filter",     "FILTER",        1, 7, 2, function(t) dial(t, 7, 2, 70); dial(t, 7, 3, 60) end)
shot("07-colour",     "COLOUR",        1, 8, 5, function(t)
  dial(t, 8, 1, 70); dial(t, 8, 3, 50); dial(t, 8, 5, 60); dial(t, 8, 8, 80)
end)
shot("08-lfo",        "LFO 1",         1, 9, 5)
shot("09-tone-algo",  "TONE / ALGO",   2, 4, 1)
shot("10-tone-ampeg", "TONE / AMP EG", 2, 6, 2)
shot("11-tone-harm",  "TONE / HARMONY", 2, 3, 4, function(t)
  local sq = t:seq()
  sq.s.chord = 11; sq.s.scale = 3; sq.s.invert = 1
end)
shot("12-amb-spec",   "AMB / SPECTRUM", 3, 3, 2)
shot("09b-tone-ops",  "TONE / OPS",    2, 5, 2)
shot("13-amb-lanes",  "AMB / LANES",    3, 5, 1)

-- every algorithm, to check the routing glyph against the engine's tables
for a = 0, 7 do
  shot(string.format("20-algo4-%d", a + 1), "TONE / ALGO " .. (a + 1), 2, 4, 1,
    function(t) state.set_page(4); t:set(state.track().pages[4].params[1], a) end)
end

-- a parameter lock in progress
do
  state.select_track(1)
  state.tracks[1]:set_machine(1)
  state.set_page(3)
  state.cursor = 1
  tahned.grid.g.key(5, 1, 1)
  enc(3, -18)
  S.clear(); redraw()
  save("14-lock", "PERC / FM  with step 5 held and TUNE locked")
  tahned.grid.g.key(5, 1, 0)
end

-- track select
state.mode = "select"
state.tracks[2]:set_machine(2)
state.tracks[3]:set_machine(3)
state.tracks[4]:set_mute(true)
S.clear(); redraw()
save("15-select", "K2+K3  track select and transport")

print("done")
