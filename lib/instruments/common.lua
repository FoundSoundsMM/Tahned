-- common -- the pages every track has regardless of machine, plus the
-- sequencer page for each sequencer type.
--
-- COLOUR is not here any more. It is one chain across the whole mix rather
-- than eight of them, so it lives on the master (K2+K3) with PERFORM and the
-- sends; see lib/core/master.lua.

local S = include("tahned/lib/core/spec")

local C = {}

-- step rate relative to the sequencer clock
C.SPEEDS = { 1/16, 1/8, 1/4, 1/3, 1/2, 1, 2, 3, 4, 6, 8, 16 }
C.SPEED_NAMES = { "/16","/8","/4","/3","/2","x1","x2","x3","x4","x6","x8","x16" }

-- The chord set from the hardware this borrows from, in its order. The three
-- detuned voicings are unisons pulled apart by fractions of a semitone, which
-- works because note numbers stay fractional all the way to the engine.
C.CHORDS = { "OFF","5th","OCT","2OCT","3OCT","MAJ","MIN","SUS","AUG","DIM",
             "DOM7","MAJ7","MIN7","MAJ9","DET3","DET4","DET5" }

C.CHORD_IV = {
  {0,7}, {0,12}, {0,12,24}, {0,12,24,36},
  {0,4,7}, {0,3,7}, {0,5,7}, {0,4,8}, {0,3,6},
  {0,4,7,10}, {0,4,7,11}, {0,3,7,10}, {0,4,7,10,14},
  {0,0.08,-0.08}, {0,0.07,-0.07,0.14}, {0,0.06,-0.06,0.12,-0.12},
}
C.NOTE_NAMES = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }

-- Operator routing, mirroring the tables in Engine_Tahned.sc. Kept here so the
-- ALGO cell can draw the structure the engine will actually patch rather than
-- a decorative stand-in. Edges are {from, to}; outs are the audible operators.
-- If the engine's tables change, these must change with them.
C.ALGO4 = {
  { ops = 4, edges = {{4,3},{2,1}},                   outs = {1} },
  { ops = 4, edges = {{4,3},{4,2},{3,2},{2,1}},       outs = {1} },
  { ops = 4, edges = {{4,2},{3,2},{2,1}},             outs = {1} },
  { ops = 4, edges = {{4,3},{3,2},{4,1}},             outs = {1,2} },
  { ops = 4, edges = {{4,3},{3,1},{2,1}},             outs = {1} },
  { ops = 4, edges = {{4,3},{4,2},{4,1}},             outs = {1,2,3} },
  { ops = 4, edges = {{4,1},{3,1},{2,1}},             outs = {1} },
  { ops = 4, edges = {},                              outs = {1,2,3,4} },
}

C.mix = { name = "MIX", params = {
  { k = "mach", name = "MACH", g = "mach", opts = S.MACHINE,
    min = 0, max = #S.MACHINE - 1, def = 0 },
  S.c(0, "LEVEL",  { def = 100 }),
  S.b(1, "PAN",    { def = 0, g = "pan" }),
  S.c(2, "DRIVE",  { def = 0 }),
  S.c(3, "CHORUS", { def = 0, g = "send" }),
  S.c(4, "DELAY",  { def = 0, g = "send" }),
  S.c(5, "REVERB", { def = 0, g = "send" }),
  S.c(6, "WIDTH",  { def = 64, g = "pan" }),
}}

C.filter = { name = "FILTER", params = {
  { k = "ftype", ch = 40, name = "TYPE", g = "ftype",
    opts = S.FILTERS, min = 0, max = 3, def = 0 },
  S.c(41, "CUTOFF", { def = 127, g = "filt" }),
  S.c(42, "RES",    { def = 0 }),
  S.b(43, "ENV",    { def = 0, g = "sweep" }),
  S.c(44, "ATK",    { def = 0,  g = "atk" }),
  S.c(45, "DEC",    { def = 60, g = "rel" }),
  S.c(46, "KTRK",   { def = 0 }),
  S.c(47, "DRIVE",  { def = 0 }),
}}

-- four LFOs, two destinations each
C.lfo = {}
for n = 1, 4 do
  local b = 56 + ((n - 1) * 8)
  C.lfo[n] = { name = "LFO " .. n, params = {
    S.i(b,     "SPD", 0, 127, 32, { g = "rate" }),
    S.e(b + 1, "MULT", S.LFOMULT, { def = 2 }),
    S.e(b + 2, "WAVE", S.LFOWAVE, { g = "lfowave" }),
    S.e(b + 3, "MODE", S.LFOMODE, { def = 1 }),
    S.dest(b + 4,  "DEST A"),
    S.depth(b + 5, "DEP A"),
    S.dest(b + 6,  "DEST B"),
    S.depth(b + 7, "DEP B"),
  }}
end

-- ------------------------------------------------------------- seq pages

local function speed_spec()
  return S.seq("speed", "SPEED", { opts = C.SPEED_NAMES, def = 5 })
end

local function shared_seq(maxlen, deflen)
  return {
    S.seq("length", "LENGTH", { min = 1, max = maxlen, def = deflen, g = "len" }),
    speed_spec(),
    S.seq("swing",  "SWING",  { min = -50, max = 50, def = 0, g = "bi" }),
    S.seq("dir",    "DIR",    { opts = S.DIRS, g = "dir" }),
    S.seq("rotate", "ROTATE", { min = -64, max = 64, def = 0, g = "bi" }),
    S.seq("prob",   "PROB",   { min = 0, max = 100, def = 100, g = "bar" }),
  }
end

C.seqpage = {}

C.seqpage.drum = { { name = "SEQ", params = (function()
  local p = shared_seq(128, 16)
  p[7] = S.seq("ratchet", "RATCH", { min = 1, max = 8, def = 1, g = "ratchet" })
  p[8] = S.seq("gate",    "GATE",    { min = 1, max = 100, def = 50, g = "bar" })
  return p
end)() } }

C.seqpage.tone = {
  { name = "SEQ", params = (function()
    local p = shared_seq(64, 16)
    p[7] = S.seq("gate",   "GATE",   { min = 1, max = 200, def = 50, g = "bar" })
    p[8] = S.seq("leader", "LEADER", { opts = {"-","T1","T2","T3","T4","T5","T6","T7","T8"},
                                       g = "leader" })
    return p
  end)() },
  { name = "HARMONY", params = {
    S.seq("root",   "ROOT",   { opts = C.NOTE_NAMES, def = 0 }),
    S.seq("octave", "OCT", { min = 1, max = 7, def = 3 }),
    S.seq("scale",  "SCALE",  { min = 1, max = 40, def = 1, g = "scale" }),
    S.seq("chord",  "CHORD",  { opts = C.CHORDS, def = 0, g = "chord" }),
    S.seq("invert", "INVERT", { min = -3, max = 3, def = 0, g = "bi" }),
    S.seq("spread", "SPREAD", { min = 0, max = 3, def = 0 }),
    S.seq("strum",  "STRUM",  { min = 0, max = 100, def = 0, g = "bar" }),
    S.seq("follow", "FOLLOW", { opts = {"OFF","DEGREE","VOICE","BASS"}, def = 1 }),
  }},
}

return C
