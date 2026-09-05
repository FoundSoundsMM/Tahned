-- tone -- 4 operator FM using the OPL3 / YMF262 waveform set
--
-- Operator levels, multipliers and feedback use the chip's own ranges.
-- Four voice polyphony per track. Both envelopes are function-generator
-- style: attack and release each have their own curve control, and either
-- can be set to cycle.

local S = include("tahned/lib/core/spec")

local MOD_DEST = {"INDEX","PITCH","FOLD","CUTOFF","FEEDBK","OP4"}

return {
  id = "tone",
  name = "TONE",
  short = "TON",
  poly = 4,
  seq = "tone",
  pages = {
    { name = "ALGO", params = {
      S.e(8,  "ALGO", {"1","2","3","4","5","6","7","8"}, { g = "algo4" }),
      S.e(9,  "RATIO 1", S.MULTS, { def = 3, g = "ratio" }),
      S.e(10, "RATIO 2", S.MULTS, { def = 3, g = "ratio" }),
      S.e(11, "RATIO 3", S.MULTS, { def = 6, g = "ratio" }),
      S.e(12, "RATIO 4", S.MULTS, { def = 6, g = "ratio" }),
      S.c(13, "FEEDBK", { min = 0, max = 7, def = 0 }),   -- 3 bit on the chip
      S.b(14, "DETUNE", { def = 0 }),
      S.b(15, "FINE",   { def = 0 }),
    }},
    { name = "OPS", params = {
      S.c(16, "LVL 1", { min = 0, max = 63, def = 63 }),   -- 6 bit
      S.c(17, "LVL 2", { min = 0, max = 63, def = 45 }),   -- 6 bit
      S.c(18, "LVL 3", { min = 0, max = 63, def = 0 }),   -- 6 bit
      S.c(19, "LVL 4", { min = 0, max = 63, def = 0 }),   -- 6 bit
      S.e(20, "WAVE C", S.WAVES, { g = "wave" }),
      S.e(21, "WAVE M", S.WAVES, { g = "wave" }),
      S.c(22, "INDEX", { def = 40 }),
      S.c(23, "FOLD",  { def = 0, g = "fold" }),
    }},
    { name = "AMP EG", params = {
      S.c(24, "ATTACK",  { def = 8,  g = "time" }),
      S.c(25, "A.CURVE", { def = 64, g = "curve" }),
      S.c(26, "SUSTAIN", { def = 90, g = "bar" }),
      S.c(27, "RELEASE", { def = 40, g = "time" }),
      S.c(28, "R.CURVE", { def = 96, g = "curve" }),
      S.e(29, "LOOP", {"OFF","CYCLE"}),
      S.c(30, "VEL",     { def = 80 }),
      S.b(31, "SPREAD",  { def = 0, g = "pan" }),
    }},
    { name = "MOD EG", params = {
      S.c(32, "ATTACK",  { def = 4,  g = "time" }),
      S.c(33, "A.CURVE", { def = 64, g = "curve" }),
      S.c(34, "SUSTAIN", { def = 0,  g = "bar" }),
      S.c(35, "RELEASE", { def = 50, g = "time" }),
      S.c(36, "R.CURVE", { def = 96, g = "curve" }),
      S.e(37, "DEST", MOD_DEST),
      S.b(38, "DEPTH",   { def = 0 }),
      S.e(39, "LOOP", {"OFF","CYCLE"}),
    }},
  },
}
