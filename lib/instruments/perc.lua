-- perc -- 3 operator FM percussion
--
-- Page layout follows the FM DRUM machine this is modelled on, but pooled:
-- the two modulator envelopes share one decay and one end level, and the
-- noise section's band, bandwidth and grain are one macro. What is left is
-- the part that actually shapes an FM drum -- the two ratios, the two
-- modulation amounts, and how fast the whole thing collapses.
--
-- One-shot voices: a trigger starts a synth and its envelope frees it.
--
-- The defaults are an 808 kick: a plain sine body an octave and a bit below
-- the trigger note, no modulation on either operator, a two octave pitch
-- drop over 40ms, a locked start phase so every hit is identical, and a
-- click on top of it. Turning MOD A up is the first thing that takes it
-- somewhere else.

local S = include("tahned/lib/core/spec")

return {
  id = "perc",
  name = "PERC",
  short = "PRC",
  poly = 0,
  seq = "perc",
  pages = {
    { name = "FM", params = {
      S.c(8,  "TUNE",   { min = -24, max = 24, def = -5, g = "bi", unit = "st" }),
      S.b(9,  "SWEEP",  { def = 31, g = "sweep" }),    -- pitch sweep depth
      S.c(10, "S.TIME", { def = 51, g = "rel" }),      -- how long it takes to settle
      S.e(11, "ALGO",   {"1","2","3","4","5","6","7","8"}, { g = "algo3" }),
      S.e(12, "WAVE",   S.WAVES, { g = "wave" }),      -- carrier
      S.e(13, "M.WAVE", S.WAVES, { g = "wave" }),      -- both modulators
      S.c(14, "FDBK",   { def = 0 }),
      S.c(15, "FOLD",   { def = 0, g = "fold" }),
    }},
    { name = "MOD", params = {
      S.e(16, "RAT A", S.RATIOS, { def = 3, g = "ratio" }),
      S.c(17, "MOD A", { def = 0 }),
      S.e(18, "RAT B", S.RATIOS, { def = 7, g = "ratio" }),
      S.c(19, "MOD B", { def = 0 }),
      -- macro: one decay for both modulator envelopes, B kept snappier
      S.c(20, "M.DEC", { def = 30, g = "rel" }),
      -- macro: one end level for both, so the FM either stops dead or hangs on
      S.c(21, "M.END", { def = 0,  g = "bar" }),
      S.c(22, "PHASE", { def = 0,  g = "phase",        -- 127 = free running
        fmt = function(v) return v >= 127 and "FREE"
                or (math.floor(v * 90 / 126) .. "d") end }),
      S.c(23, "LEVEL", { def = 110 }),
    }},
    { name = "BODY", params = {
      S.c(24, "ATK",    { def = 0,  g = "atk" }),
      S.c(25, "HOLD",   { def = 0,  g = "hold" }),
      S.c(26, "DEC",    { def = 89, g = "rel" }),
      S.e(27, "CLICK",  S.TRANS, { g = "trans" }),
      S.c(28, "C.LEV",  { def = 18 }),
      S.c(29, "NOISE",  { def = 0,  g = "noise" }),
      -- macro: noise hold grows with its decay
      S.c(30, "N.DEC",  { def = 30, g = "rel" }),
      -- macro: dark and grainy on the left, bright and fine on the right
      S.b(31, "N.TONE", { def = 0,  g = "ntone" }),
    }},
  },
}
