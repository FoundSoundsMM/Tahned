-- amb -- FM drone
--
-- One persistent voice per track rather than one per note. The sequencer
-- does not play notes into it, it fires the eight trigger lanes below to
-- cut rhythm and movement into a texture that is already sounding.
--
-- Because it never stops, its amplitude envelope is not worth a page: the
-- drone fades in when the machine is chosen and out when it is not, on
-- fixed times.

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
      S.c(13, "VOICES", { def = 80, g = "voices" }),
      S.c(14, "SUB",    { def = 30 }),
      S.c(15, "FOLD",   { def = 0,  g = "fold" }),
    }},
    { name = "MOTION", params = {
      S.c(16, "RATE",   { def = 20, g = "lfo" }),
      -- macro: how far the motion moves the partials and the level with them
      S.c(17, "DEPTH",  { def = 40 }),
      S.c(18, "DRIFT",  { def = 30 }),
      S.c(19, "CHAOS",  { def = 10 }),
      S.c(20, "GLIDE",  { def = 60, g = "atk" }),
      S.c(21, "SHIM",   { def = 20 }),
      S.e(22, "SH.INT", {"OCT","+12th","2OCT","+19th"}, { def = 0 }),
      S.c(23, "WIDTH",  { def = 70, g = "pan" }),
    }},
    { name = "LANES", params = {
      S.c(24, "B.DEC",  { def = 40, g = "rel" }),
      S.c(25, "B.PIT",  { def = 40, g = "bi" }),
      -- macro: a louder blip is a brighter blip
      S.c(26, "BLIP",   { def = 90 }),
      S.c(27, "STUT",   { def = 40, g = "rel" }),
      S.c(28, "GATE",   { def = 90 }),
      S.b(29, "SWEEP",  { def = 40, g = "sweep" }),
      S.c(30, "SWELL",  { def = 50, g = "atk" }),
      S.c(31, "SHIFT",  { def = 30, unit = "st" }),
    }},
  },
}
