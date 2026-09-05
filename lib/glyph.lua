-- glyph.lua
-- the wordless vocabulary. every icon in TAHNED comes from this table and
-- nowhere else, so the language stays consistent across pages.
--
-- glyphs are authored as ascii and compiled once into horizontal runs, because
-- 49 screen.pixel() calls per icon at 30fps would not survive contact with the
-- norns screen socket. a typical glyph is 8-12 rect calls instead.

local glyph = {}

local defs = {}

-- ---------------------------------------------------------------- 7x7 concepts

defs.voice = {
  "..###..",
  ".#...#.",
  "#.###.#",
  "#.###.#",
  "#.###.#",
  ".#...#.",
  "..###..",
}

-- complementary combs: odd harmonics present / even harmonics present
defs.odd = {
  "#.#.#.#",
  "#.#.#.#",
  "#.#.#.#",
  "#.#.#.#",
  "#.#.#.#",
  "#.#.#.#",
  "#######",
}

defs.even = {
  ".#.#.#.",
  ".#.#.#.",
  ".#.#.#.",
  ".#.#.#.",
  ".#.#.#.",
  ".#.#.#.",
  "#######",
}

-- a rake: partial count is the modulation index
defs.partials = {
  "......#",
  "....#.#",
  "....#.#",
  "..#.#.#",
  "..#.#.#",
  "#.#.#.#",
  "#######",
}

defs.tilt = {
  "......#",
  ".....##",
  "....###",
  "...####",
  "..#####",
  ".######",
  "#######",
}

defs.feedback = {
  ".#####.",
  "#.....#",
  "#......",
  "#......",
  "#.....#",
  "#....##",
  ".####.#",
}

-- two combs pulled out of alignment: the sound of the lattice coming apart
defs.skew = {
  "#.#.#.#",
  "#.#.#.#",
  "#.#.#.#",
  ".......",
  ".#.#.#.",
  ".#.#.#.",
  ".#.#.#.",
}

defs.transient = {
  "..#....",
  "..#....",
  "..##...",
  "..#.#..",
  "..#..#.",
  "..#...#",
  "#######",
}

defs.gesture = {
  "#######",
  "#.....#",
  "#...#.#",
  "#..#..#",
  "#.#...#",
  "#.....#",
  "#######",
}

defs.speed = {
  ".......",
  "#..#..#",
  ".#..#..",
  "..#..#.",
  ".#..#..",
  "#..#..#",
  ".......",
}

defs.atten = {
  "#......",
  "##.....",
  "####...",
  "######.",
  "####...",
  "##.....",
  "#......",
}

defs.ball = {
  ".......",
  ".....#.",
  "....###",
  "#.#.###",
  "....###",
  ".....#.",
  ".......",
}

defs.morph = {
  "...#...",
  "..#.#..",
  "..#.#..",
  ".#...#.",
  ".#.#.#.",
  "#.....#",
  "#######",
}

defs.snapshot = {
  "##...##",
  "##...##",
  ".......",
  ".......",
  "..###..",
  "..###..",
  ".......",
}

-- decaying echoes: the regeneration buffer
defs.regen = {
  "#......",
  "#.#....",
  "#.#.#..",
  "#.#.#.#",
  "#.#.#..",
  "#.#....",
  "#......",
}

defs.prob = {
  "#######",
  "#.....#",
  "#.#...#",
  "#..#..#",
  "#...#.#",
  "#.....#",
  "#######",
}

defs.mute = {
  ".....#.",
  "....#..",
  "...#...",
  "..#....",
  ".#.....",
  "#......",
  ".......",
}

defs.lattice = {
  "..#.#..",
  ".#.#.#.",
  "#.#.#.#",
  ".#.#.#.",
  "#.#.#.#",
  ".#.#.#.",
  "..#.#..",
}

defs.clock = {
  "..###..",
  ".#...#.",
  "#..#..#",
  "#..##.#",
  "#.....#",
  ".#...#.",
  "..###..",
}

defs.matrix = {
  "#######",
  "#.#.#.#",
  "#######",
  "#.###.#",
  "#######",
  "#.#.#.#",
  "#######",
}

defs.map = {
  "##.##..",
  "##.##..",
  ".......",
  "##.##..",
  "##.##..",
  ".......",
  ".......",
}

defs.groove = {
  ".......",
  "##.##.#",
  "##.##.#",
  "##.##.#",
  "##.##.#",
  "##.##.#",
  ".......",
}

-- --------------------------------------------------------------- 5x5 node types

defs.n_voice = { ".###.", "#####", "#####", "#####", ".###." }
defs.n_seq   = { "#....", ".#...", "..#..", "...#.", "....#" }
defs.n_mod   = { "..###", ".#...", "..#..", "...#.", "###.." }
defs.n_logic = { "###..", "#..#.", "#...#", "#..#.", "###.." }
defs.n_fx    = { "#..#.", ".#..#", "#..#.", ".#..#", "#..#." }
defs.n_mult  = { "#...#", ".#.#.", "..#..", ".#.#.", "#...#" }
defs.n_empty = { ".....", "..#..", ".#.#.", "..#..", "....." }

-- ------------------------------------------------------------------ 5x5 actions

defs.a_play  = { "#....", "##...", "###..", "##...", "#...." }
defs.a_stop  = { ".....", ".###.", ".###.", ".###.", "....." }
defs.a_rec   = { ".....", ".###.", "#####", ".###.", "....." }
defs.a_clear = { "#...#", ".#.#.", "..#..", ".#.#.", "#...#" }
defs.a_copy  = { "###..", "#.#..", "#.###", "..#.#", "..###" }
defs.a_up    = { "..#..", ".###.", "#.#.#", "..#..", "..#.." }
defs.a_down  = { "..#..", "..#..", "#.#.#", ".###.", "..#.." }
defs.a_hold  = { "#...#", "#...#", "#...#", "#...#", "#...#" }
defs.a_link  = { "..###", "..#..", ".#.#.", "..#..", "###.." }

-- ------------------------------------------------------------------- compilation

local compiled = {}

local function compile(rows)
  local runs = {}
  local h = #rows
  local w = #rows[1]
  for y = 1, h do
    local row = rows[y]
    local x = 1
    while x <= w do
      if row:sub(x, x) == "#" then
        local run = 1
        while x + run <= w and row:sub(x + run, x + run) == "#" do run = run + 1 end
        runs[#runs + 1] = { x - 1, y - 1, run }
        x = x + run
      else
        x = x + 1
      end
    end
  end
  return { runs = runs, w = w, h = h }
end

for name, rows in pairs(defs) do compiled[name] = compile(rows) end

-- ------------------------------------------------------------------------ drawing

function glyph.draw(name, x, y, level)
  local g = compiled[name]
  if g == nil then return end
  screen.level(level or 15)
  local runs = g.runs
  for i = 1, #runs do
    local r = runs[i]
    screen.rect(x + r[1], y + r[2], r[3], 1)
  end
  screen.fill()
end

function glyph.w(name) local g = compiled[name] return g and g.w or 0 end
function glyph.h(name) local g = compiled[name] return g and g.h or 0 end
function glyph.exists(name) return compiled[name] ~= nil end

-- the six spectral macros, in engine order
glyph.MACRO = { "odd", "even", "partials", "tilt", "feedback", "skew" }
glyph.NODE  = { "n_empty", "n_voice", "n_seq", "n_mod", "n_logic", "n_fx", "n_mult" }
glyph.PAGE  = { "map", "matrix", "ball", "lattice", "partials", "gesture", "morph", "groove" }

-- ------------------------------------------------------- values as shape, not text

-- a 270 degree value arc. `ghost` draws a second, dimmer position showing
-- where modulation is currently pushing the value.
function glyph.arc(x, y, r, val, level, ghost, bipolar)
  local a0 = math.pi * 0.75
  local span = math.pi * 1.5
  screen.level(math.floor((level or 15) * 0.25) + 1)
  screen.arc(x, y, r, a0, a0 + span)
  screen.stroke()
  screen.level(level or 15)
  if bipolar then
    local mid = a0 + (span * 0.5)
    local to = a0 + (span * (val * 0.5 + 0.5))
    if to < mid then screen.arc(x, y, r, to, mid) else screen.arc(x, y, r, mid, to) end
  else
    screen.arc(x, y, r, a0, a0 + (span * val))
  end
  screen.stroke()
  if ghost ~= nil then
    local a = a0 + (span * util.clamp(ghost, 0, 1))
    screen.level(6)
    screen.move(x + (r - 2) * math.cos(a), y + (r - 2) * math.sin(a))
    screen.line(x + (r + 2) * math.cos(a), y + (r + 2) * math.sin(a))
    screen.stroke()
  end
end

function glyph.bar(x, y, w, h, val, level, ghost)
  screen.level(2)
  screen.rect(x, y, w, h)
  screen.fill()
  screen.level(level or 15)
  local fw = math.floor(w * util.clamp(val, 0, 1) + 0.5)
  if fw > 0 then
    screen.rect(x, y, fw, h)
    screen.fill()
  end
  if ghost ~= nil then
    local gx = x + math.floor(w * util.clamp(ghost, 0, 1) + 0.5)
    screen.level(6)
    screen.rect(gx, y - 1, 1, h + 2)
    screen.fill()
  end
end

-- a cellular automaton rule drawn as what it literally is: eight cells.
function glyph.rule(x, y, rule, level)
  screen.level(level or 15)
  for i = 0, 7 do
    if (rule >> i) & 1 == 1 then
      screen.rect(x + ((7 - i) * 2), y, 2, 3)
    end
  end
  screen.fill()
end

-- numerals are the one exception to the wordless rule, and only where
-- precision is the point: ratios, edo counts, clock divisions.
function glyph.num(x, y, str, level, right)
  screen.level(level or 15)
  screen.font_face(1)
  screen.font_size(8)
  screen.move(x, y)
  if right then screen.text_right(str) else screen.text(str) end
end

function glyph.ratio(x, y, n, d, level)
  glyph.num(x, y, n .. "/" .. d, level)
end

return glyph
