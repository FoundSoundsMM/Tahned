-- amb -- FM drone
--
-- One persistent voice per track rather than one per note. The sequencer
-- does not play notes into it, it fires the eight trigger lanes below to
-- cut rhythm and movement into a texture that is already sounding.

local S = include("tahned/lib/core/spec")

-- lane order matches t_l0..t_l7 in tahned_amb
local LANES = {"BLIP","GATE","SWELL","SHIFT","FILT","SHIM","STUT","FOLD"}

return {
  id = "amb",
  name = "AMB",
  short = "AMB",
  poly = -1,           -- persistent drone
  seq = "amb",
  lanes = LANES,
  pages = {
    { name = "SPECTRUM", params = {
      S.c(8,  "ROOT",   { min = -24, max = 24, def = 0, g = "bi", unit = "st" }),
      S.c(9,  "HARM",   { def = 20, g = "spectrum" }),
      S.b(10, "TILT",   { def = 0,  g = "tilt" }),
      S.c(11, "INDEX",  { def = 30 }),
      S.c(12, "SPREAD", { def = 20 }),
      S.c(13, "DRIFT",  { def = 30 }),
      S.c(14, "VOICES", { def = 80, g = "voices" }),
      S.c(15, "FOLD",   { def = 0,  g = "fold" }),
    }},
    { name = "MOTION", params = {
      S.c(16, "RATE",   { def = 20, g = "lfo" }),
      S.c(17, "DEPTH",  { def = 40 }),
      S.c(18, "CHAOS",  { def = 10 }),
      S.c(19, "SHIMMER",{ def = 20 }),
      S.e(20, "INTERVAL", {"OCT","+12th","2OCT","+19th"}, { def = 0 }),
      S.c(21, "GLIDE",  { def = 60, g = "time" }),
      S.c(22, "WIDTH",  { def = 70, g = "pan" }),
      S.c(23, "SUB",    { def = 30 }),
    }},
    { name = "LANES", params = {
      S.c(24, "BLP DEC", { def = 40, g = "env" }),
      S.c(25, "BLP PIT", { def = 40, g = "bi" }),
      S.c(26, "BLP IDX", { def = 50 }),
      S.c(27, "BLP LVL", { def = 90 }),
      S.c(28, "STUTTER", { def = 40, g = "time" }),
      S.c(29, "GATE",    { def = 90 }),
      S.b(30, "SWEEP",   { def = 40, g = "sweep" }),
      S.c(31, "SWELL",   { def = 50, g = "time" }),
    }},
    { name = "ENV", params = {
      S.c(32, "ATTACK",  { def = 40, g = "time" }),
      S.c(33, "A.CURVE", { def = 64, g = "curve" }),
      S.c(34, "SUSTAIN", { def = 110, g = "bar" }),
      S.c(35, "RELEASE", { def = 50, g = "time" }),
      S.c(36, "R.CURVE", { def = 64, g = "curve" }),
      S.c(37, "SHIFT",   { def = 30, unit = "st" }),
      S.c(38, "AM",      { def = 0 }),
      S.c(39, "-",       { def = 0 }),
    }},
  },
}
