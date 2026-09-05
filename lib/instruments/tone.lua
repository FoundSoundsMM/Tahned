-- tone -- 4 operator FM using the OPL3 / YMF262 waveform set
--
-- Operator levels, multipliers and feedback use the chip's own ranges.
-- Sixteen voices a track. Both envelopes are ADSR with fixed curves --
-- a convex attack and an exponential decay and release -- which is what
-- the curve controls were being turned to anyway.
--
-- Everything here is read live off the control bus, so a parameter moved
-- while a note is held is heard on that note.

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
      S.e(9,  "RAT 1", S.MULTS, { def = 3, g = "ratio" }),
      S.e(10, "RAT 2", S.MULTS, { def = 3, g = "ratio" }),
      S.e(11, "RAT 3", S.MULTS, { def = 6, g = "ratio" }),
      S.e(12, "RAT 4", S.MULTS, { def = 6, g = "ratio" }),
      S.c(13, "FDBK",   { min = 0, max = 7, def = 0 }),   -- 3 bit on the chip
      S.b(14, "DETUNE", { def = 0 }),
      S.b(15, "FINE",   { def = 0 }),
    }},
    { name = "OPS", params = {
      S.c(16, "LVL 1", { min = 0, max = 63, def = 63 }),   -- 6 bit
      S.c(17, "LVL 2", { min = 0, max = 63, def = 45 }),   -- 6 bit
      S.c(18, "LVL 3", { min = 0, max = 63, def = 0 }),    -- 6 bit
      S.c(19, "LVL 4", { min = 0, max = 63, def = 0 }),    -- 6 bit
      S.e(20, "WAVE C", S.WAVES, { g = "wave" }),
      S.e(21, "WAVE M", S.WAVES, { g = "wave" }),
      S.c(22, "INDEX", { def = 40 }),
      S.c(23, "FOLD",  { def = 0, g = "fold" }),
    }},
    { name = "AMP EG", params = {
      S.c(24, "ATK",    { def = 8,  g = "atk" }),
      S.c(25, "DEC",    { def = 40, g = "rel" }),
      S.c(26, "SUS",    { def = 90, g = "bar" }),
      S.c(27, "REL",    { def = 40, g = "rel" }),
      S.e(28, "LOOP",   {"OFF","CYCLE"}),
      S.c(29, "VEL",    { def = 80 }),
      -- pans a chord across the field by pitch, low to high; not a pan offset
      S.b(30, "SPREAD", { def = 0, g = "pan" }),
    }},
    { name = "MOD EG", params = {
      S.c(31, "ATK",   { def = 4,  g = "atk" }),
      S.c(32, "DEC",   { def = 50, g = "rel" }),
      S.c(33, "SUS",   { def = 0,  g = "bar" }),
      S.c(34, "REL",   { def = 50, g = "rel" }),
      S.e(35, "LOOP",  {"OFF","CYCLE"}),
      S.e(36, "DEST",  MOD_DEST),
      S.b(37, "DEPTH", { def = 0 }),
    }},
  },
}
