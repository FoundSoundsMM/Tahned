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

local bodies = {}

local function save(name, title)
  local body = table.concat(svg, "\n")
  bodies[name] = body
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
  sq.pos, sq.last = 5, 5
end

print("rendering " .. OUT)

-- Drums  1 MIX  2 SEQ  3 SYNTH  4 FILTER  5..8 LFO
shot("01-kick",       "KICK / SYNTH",   1, 3, 2)
shot("02-snare",      "SNARE / SYNTH",  2, 3, 2, function(t)
  dial(t, 3, 3, 70); dial(t, 3, 7, 40)
end)
shot("03-hat",        "HAT / SYNTH",    3, 3, 5)
shot("04-tom",        "TOM / SYNTH",    4, 3, 2)
shot("05-cymb",       "CYMB / SYNTH",   5, 3, 4)
shot("06-drum-seq",   "KICK / SEQ",     1, 2, 2)
shot("07-filter",     "FILTER",         1, 4, 2, function(t)
  dial(t, 4, 2, 70); dial(t, 4, 3, 60); dial(t, 4, 5, 30)
end)
shot("08-lfo",        "LFO 1",          1, 5, 5)

-- TONE  1 MIX 2 SEQ 3 HARMONY 4 ALGO 5 OPS 6 AMP EG 7 MOD EG 8 FILTER ...
shot("09-tone-algo",  "TONE / ALGO",    6, 4, 1)
shot("09b-tone-ops",  "TONE / OPS",     6, 5, 2)
shot("10-tone-ampeg", "TONE / AMP EG",  6, 6, 2)
shot("10b-tone-modeg","TONE / MOD EG",  6, 7, 5, function(t)
  dial(t, 7, 6, 40); dial(t, 7, 7, 4); dial(t, 7, 8, -30)
end)
shot("11-tone-harm",  "TONE / HARMONY", 6, 3, 4, function(t)
  local sq = t:seq()
  sq.s.chord = 11; sq.s.scale = 3; sq.s.invert = 1
end)

-- every algorithm, to check the routing glyph against the engine's tables
for a = 0, 7 do
  shot(string.format("20-algo4-%d", a + 1), "TONE / ALGO " .. (a + 1), 6, 4, 1,
    function(t) state.set_page(4); t:set(state.track().pages[4].params[1], a) end)
end

-- a parameter lock in progress, over two held steps at once
do
  state.select_track(1)
  state.tracks[1]:set_machine(1)
  state.set_page(3)
  state.cursor = 1
  tahned.grid.g.key(5, 1, 1)
  tahned.grid.g.key(7, 1, 1)
  enc(3, -18)
  S.clear(); redraw()
  save("14-lock", "KICK / SYNTH  steps 5 and 7 held, TUNE locked on both")
  shots[#shots + 1] = { name = "14-lock",
    title = "KICK / SYNTH  steps 5 and 7 held, TUNE locked on both" }
  tahned.grid.g.key(7, 1, 0)
  tahned.grid.g.key(5, 1, 0)
end

-- the master: its own page set, K2+K3 to reach it
do
  local names = { "OVER", "PERFORM", "MIX", "COLOUR", "SEND FX",
                  "CLOCK", "CHORUS", "DELAY", "REVERB" }
  state.mode = "master"
  state.tracks[2]:set_machine(2)
  state.tracks[3]:set_machine(3)
  state.tracks[4]:set_machine(6)
  state.tracks[5]:set_machine(5)
  state.tracks[4]:set_mute(true)
  -- give the mix page something other than eight identical faders
  for i, v in ipairs({ 110, 96, 74, 100, 58, 120, 40, 88 }) do
    local t = state.tracks[i]
    t:set(t.chspec[0], v)
  end
  for pg = 1, #tahned.master.pages do
    state.set_master_page(pg)
    state.mcursor = math.min(3, tahned.master.page_cells(pg))
    S.clear(); redraw()
    local nm = string.format("30-master-%d", pg)
    local title = "K2+K3  master " .. pg .. " / " .. names[pg]
    save(nm, title)
    shots[#shots + 1] = { name = nm, title = title }
  end
  state.mode = "page"
end

-- contact sheet, rebuilt from the same draws so it can never go stale
do
  local css = "body{background:#141414;color:#999;font:12px/1.5 system-ui,sans-serif;"
    .. "margin:0;padding:24px}h1{color:#ddd;font-size:15px;margin:0 0 4px}"
    .. "p.sub{margin:0 0 24px;color:#777}.wrap{display:grid;"
    .. "grid-template-columns:repeat(auto-fill,minmax(360px,1fr));gap:20px}"
    .. "figure{margin:0}.scr{background:#000;border:1px solid #2c2c2c;"
    .. "border-radius:3px;line-height:0}.scr svg{width:100%;height:auto;display:block}"
    .. "figcaption{margin-top:6px;color:#8a8a8a}"
  local out = { "<style>", css, "</style>",
    "<h1>tahned &mdash; 128&times;64 display</h1>",
    "<p class=sub>Drawn by the script's own code via tools/render-screen.lua. ",
    "Text metrics approximated with a monospace face; everything else is exact.</p>",
    "<div class=wrap>" }
  for _, sh in ipairs(shots) do
    out[#out + 1] = string.format(
      '<figure><div class=scr><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 64"'
      .. ' shape-rendering="crispEdges"><title>%s</title>'
      .. '<rect width="128" height="64" fill="black"/>%s</svg></div>'
      .. '<figcaption>%s</figcaption></figure>',
      sh.title, bodies[sh.name] or "", sh.title)
  end
  out[#out + 1] = "</div>"
  local f = assert(io.open(OUT .. "/index.html", "w"))
  f:write(table.concat(out, ""))
  f:close()
  print("  index.html   " .. #shots .. " screens")
end

print("done")
