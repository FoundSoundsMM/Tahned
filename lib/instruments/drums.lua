-- drums -- five FM percussion machines
--
-- One page each. A drum is not a synth with a page of envelopes bolted to a
-- page of operators: it is one sound, and the eight controls here are the
-- eight that move it around inside its own family. Nothing is shared between
-- them beyond the channel range, so KICK's FM means something different from
-- HAT's and each one is free to spend its eight where that family needs them.
--
-- Every voice is one-shot: a trigger starts a synth and its envelope frees
-- it, and everything is latched at the trigger, so a parameter lock is exact.
--
-- Channels 8..15. The rest of the track -- filter, LFOs, the mix strip -- is
-- the same for all five, and COLOUR is now on the master rather than here.

local S = include("tahned/lib/core/spec")

-- KICK. A sine body dropped onto a fundamental, with one modulator for the
-- FM buzz and a transient on top. PUNCH is a macro: it drives the body and
-- tightens its front at the same time, which is the only way either moved.
local kick = {
  id = "kick", name = "KICK", short = "KCK", seq = "drum",
  pages = { { name = "SYNTH", params = {
    S.c(8,  "TUNE",   { min = -24, max = 24, def = -5, g = "tune", unit = "st" }),
    S.b(9,  "SWEEP",  { def = 31, g = "sweep" }),
    S.c(10, "S.TIME", { def = 72, g = "ptime" }), -- ~150ms: an 808 glide
    S.c(11, "DECAY",  { def = 85, g = "rel" }),
    S.c(12, "FM",     { def = 0, g = "fm" }),
    S.e(13, "RATIO",  S.RATIOS, { def = 3, g = "ratio" }),
    S.c(14, "CLICK",  { def = 20, g = "click" }),
    S.c(15, "PUNCH",  { def = 30, g = "sat" }),
  }} },
}

-- SNARE. Two detuned FM tones for the shell and a filtered noise bed for the
-- wires, balanced by SNAP. N.TONE is one bipolar control over the noise's
-- colour and its bandwidth: dark and narrow to the left, bright and open to
-- the right.
local snare = {
  id = "snare", name = "SNARE", short = "SNR", seq = "drum",
  pages = { { name = "SYNTH", params = {
    S.c(8,  "TUNE",   { min = -24, max = 24, def = 2, g = "tune", unit = "st" }),
    S.c(9,  "SNAP",   { def = 64, g = "snap" }),
    S.c(10, "FM",     { def = 30, g = "fm" }),
    S.e(11, "RATIO",  S.RATIOS, { def = 8, g = "ratio" }),
    S.c(12, "B.DEC",  { def = 45, g = "rel" }),
    S.c(13, "N.DEC",  { def = 70, g = "rel" }),
    S.b(14, "N.TONE", { def = 0,  g = "ntone" }),
    S.c(15, "CRACK",  { def = 40, g = "click" }),
  }} },
}

-- HAT. Six inharmonic partials cross-modulating each other and pushed through
-- a resonant high band -- the 808's square-oscillator cluster done in FM.
-- OPEN is the one control that turns a tick into a wash: it stretches the
-- decay and opens a tail behind it.
local hat = {
  id = "hat", name = "HAT", short = "HAT", seq = "drum",
  pages = { { name = "SYNTH", params = {
    S.c(8,  "TUNE",   { min = -24, max = 24, def = 0, g = "tune", unit = "st" }),
    S.c(9,  "SPREAD", { def = 60, g = "spectrum" }),
    S.c(10, "FM",     { def = 45, g = "fm" }),
    S.c(11, "DECAY",  { def = 45, g = "rel" }),
    S.c(12, "TONE",   { def = 80, g = "band" }),
    S.c(13, "RES",    { def = 30, g = "res" }),
    S.c(14, "NOISE",  { def = 20, g = "noise" }),
    S.c(15, "OPEN",   { def = 0,  g = "hold" }),
  }} },
}

-- TOM. A kick that keeps its pitch: a shallower, slower bend, a skin
-- transient, and WOOD ringing a shell around it.
local tom = {
  id = "tom", name = "TOM", short = "TOM", seq = "drum",
  pages = { { name = "SYNTH", params = {
    S.c(8,  "TUNE",   { min = -24, max = 24, def = 7, g = "tune", unit = "st" }),
    S.b(9,  "BEND",   { def = 25, g = "sweep" }),
    S.c(10, "B.TIME", { def = 45, g = "ptime" }),
    S.c(11, "DECAY",  { def = 75, g = "rel" }),
    S.c(12, "FM",     { def = 18, g = "fm" }),
    S.e(13, "RATIO",  S.RATIOS, { def = 5, g = "ratio" }),
    S.c(14, "SKIN",   { def = 25, g = "noise" }),
    S.c(15, "WOOD",   { def = 30, g = "spectrum" }),
  }} },
}

-- CYMB. The hat's cluster taken long and dense, with SWELL running the attack
-- backwards for a reverse crash and DIRT folding the whole thing over.
local cymb = {
  id = "cymb", name = "CYMB", short = "CYM", seq = "drum",
  pages = { { name = "SYNTH", params = {
    S.c(8,  "TUNE",   { min = -24, max = 24, def = 0, g = "tune", unit = "st" }),
    S.c(9,  "SPREAD", { def = 80, g = "spectrum" }),
    S.c(10, "FM",     { def = 70, g = "fm" }),
    S.c(11, "DECAY",  { def = 85, g = "rel" }),
    S.c(12, "TONE",   { def = 70, g = "band" }),
    S.c(13, "SIZZLE", { def = 50, g = "noise" }),
    S.c(14, "SWELL",  { def = 0,  g = "atk" }),
    S.c(15, "DIRT",   { def = 20, g = "fold" }),
  }} },
}

return { kick, snare, hat, tom, cymb }
