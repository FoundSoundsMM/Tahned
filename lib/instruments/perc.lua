-- perc -- 3 operator FM percussion
--
-- Page layout follows the FM DRUM machine this is modelled on. The part that
-- matters is page 2: each modulator has its own decay envelope with an end
-- level and its own modulation amount, which is what makes an FM drum snap
-- rather than just hum.
--
-- One-shot voices: a trigger starts a synth and its envelope frees it.

local S = include("tahned/lib/core/spec")

return {
  id = "perc",
  name = "PERC",
  short = "PRC",
  poly = 0,
  seq = "perc",
  pages = {
    { name = "FM", params = {
      S.c(8,  "TUNE",  { min = -24, max = 24, def = 0, g = "bi", unit = "st" }),
      S.c(9,  "STIM",  { def = 40, g = "time" }),      -- sweep time
      S.b(10, "SDEP",  { def = 0,  g = "sweep" }),     -- sweep depth
      S.e(11, "ALGO",  {"1","2","3","4","5","6","7","8"}, { g = "algo3" }),
      S.e(12, "OP.C",  S.WAVES, { g = "wave" }),
      S.e(13, "OP.AB", S.WAVES, { g = "wave" }),
      S.c(14, "FDBK",  { def = 0 }),
      S.c(15, "FOLD",  { def = 0, g = "fold" }),
    }},
    { name = "MOD", params = {
      S.e(16, "RATIO A", S.RATIOS, { def = 3, g = "ratio" }),
      S.c(17, "DEC A",   { def = 30, g = "env" }),
      S.c(18, "END A",   { def = 0,  g = "bar" }),
      S.c(19, "MOD A",   { def = 60 }),
      S.e(20, "RATIO B", S.RATIOS, { def = 7, g = "ratio" }),
      S.c(21, "DEC B",   { def = 20, g = "env" }),
      S.c(22, "END B",   { def = 0,  g = "bar" }),
      S.c(23, "MOD B",   { def = 30 }),
    }},
    { name = "BODY", params = {
      S.c(24, "HOLD",   { def = 0,  g = "env" }),
      S.c(25, "DECAY",  { def = 40, g = "env" }),
      S.c(26, "PH.C",   { def = 0,  g = "phase",       -- 127 = free running
        fmt = function(v) return v >= 127 and "FREE"
                or (math.floor(v * 90 / 126) .. "d") end }),
      S.c(27, "LEVEL",  { def = 110 }),
      S.e(28, "N.RST",  {"OFF","ON"}),                 -- repeatable noise
      S.e(29, "N.RM",   {"OFF","ON"}),                 -- ring mod noise by OP C
      S.c(30, "ATTACK", { def = 0,  g = "time" }),
      S.c(31, "CURVE",  { def = 100, g = "curve" }),
    }},
    { name = "NOISE", params = {
      S.c(32, "N.HOLD", { def = 0,  g = "env" }),
      S.c(33, "N.DEC",  { def = 30, g = "env" }),
      S.e(34, "TRANS",  S.TRANS, { g = "trans" }),
      S.c(35, "T.LEV",  { def = 0 }),
      S.c(36, "BASE",   { def = 70, g = "filt" }),
      S.c(37, "WIDTH",  { def = 40 }),
      S.c(38, "GRAIN",  { def = 0,  g = "grain" }),
      S.c(39, "N.LEV",  { def = 0,  g = "noise" }),
    }},
  },
}
