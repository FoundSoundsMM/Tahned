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

-- Time signature, per sequencer rather than per song, which is the whole
-- point: an 8-step track in 7/8 against a 16-step track in 4/4 is a real
-- polyrhythm rather than two patterns of different lengths.
--
-- The denominator is the beat unit and it scales the step: SPEED counts
-- steps per beat unit, so /8 signatures run at half the step length of /4
-- ones and the two tracks pull against each other. The numerator groups
-- those steps into bars, which is what the grid draws its bar lights from.
--
-- 4/4 is index 0 and scales by 1, so nothing that never touches this moves.
C.TSIG = {
  { name = "4/4",  num = 4,  den = 4 },
  { name = "3/4",  num = 3,  den = 4 },
  { name = "2/4",  num = 2,  den = 4 },
  { name = "5/4",  num = 5,  den = 4 },
  { name = "6/4",  num = 6,  den = 4 },
  { name = "7/4",  num = 7,  den = 4 },
  { name = "3/8",  num = 3,  den = 8 },
  { name = "5/8",  num = 5,  den = 8 },
  { name = "6/8",  num = 6,  den = 8 },
  { name = "7/8",  num = 7,  den = 8 },
  { name = "9/8",  num = 9,  den = 8 },
  { name = "11/8", num = 11, den = 8 },
  { name = "12/8", num = 12, den = 8 },
  { name = "5/16", num = 5,  den = 16 },
  { name = "7/16", num = 7,  den = 16 },
}
C.TSIG_NAMES = {}
for i, t in ipairs(C.TSIG) do C.TSIG_NAMES[i] = t.name end

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

-- WIDTH is gone. A mid/side trim on a track that is mostly one panned voice
-- was a control that measured something rather than moved it, and PAN is the
-- one everybody actually reaches for -- so the strip places the track and
-- leaves the image alone.
C.mix = { name = "MIX", params = {
  { k = "mach", name = "MACH", g = "mach", opts = S.MACHINE,
    min = 0, max = #S.MACHINE - 1, def = 0 },
  S.c(0, "LEVEL",  { def = 100 }),
  S.b(1, "PAN",    { def = 0, g = "pan" }),
  S.c(2, "DRIVE",  { def = 0 }),
  S.c(3, "CHORUS", { def = 0, g = "send" }),
  S.c(4, "DELAY",  { def = 0, g = "send" }),
  S.c(5, "REVERB", { def = 0, g = "send" }),
}}

C.filter = { name = "FILTER", env = { at = 5, segs = { "atk", "dec" } }, params = {
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
    S.i(b,     "SPD", 0, 127, 32, { g = "lfoscope" }),
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
    S.seq("tsig",   "TSIG",   { opts = C.TSIG_NAMES, def = 0, g = "tsig" }),
    S.seq("swing",  "SWING",  { min = -50, max = 50, def = 0, g = "bi" }),
    S.seq("dir",    "DIR",    { opts = S.DIRS, g = "dir" }),
    S.seq("rotate", "ROTATE", { min = -64, max = 64, def = 0, g = "bi" }),
    S.seq("prob",   "PROB",   { min = 0, max = 100, def = 100, g = "bar" }),
  }
end

-- The STEP page is what one step does with the time it gets. HOLD and HTYPE
-- are lock-only and struck out until a grid pad is held, because a HOLD
-- written across the whole track would just be a slower track -- the point is
-- one step that stalls.
--
-- HOLD is the Metropolis stage: the sequencer stays on this step for that
-- many pulses instead of one. HTYPE says what it does with them -- sit there,
-- retrigger each pulse, or retrigger while walking the level up or down.
local function hold_pair()
  return {
    S.seq("hold",  "HOLD",  { min = 1, max = 16, def = 1, g = "hold_n", lock = true }),
    S.seq("htype", "HTYPE", { opts = S.HTYPE, def = 0, g = "htype", lock = true }),
  }
end

C.seqpage = {}

C.seqpage.drum = {
  { name = "SEQ", params = (function()
    local p = shared_seq(128, 16)
    p[8] = S.seq("ratchet", "RATCH", { min = 1, max = 8, def = 1, g = "ratchet" })
    return p
  end)() },
  { name = "STEP", params = (function()
    local p = hold_pair()
    -- a drum step has always carried a note offset; until now nothing could
    -- write one, and it is per step by nature, so it belongs here
    p[3] = S.seq("note", "NOTE", { min = -24, max = 24, def = 0, g = "bi",
                                   lock = true })
    return p
  end)() },
}

C.seqpage.tone = {
  { name = "SEQ", params = (function()
    local p = shared_seq(64, 16)
    p[8] = S.seq("strum", "STRUM", { min = 0, max = 100, def = 0, g = "bar" })
    return p
  end)() },
  { name = "STEP", params = (function()
    local p = hold_pair()
    -- how long the note lasts is about the step rather than the pattern, and
    -- it locks per step, so it belongs here beside the stage controls
    p[3] = S.seq("gate", "GATE", { min = 1, max = 200, def = 50, g = "bar" })
    return p
  end)() },
  -- LEADER sat on the SEQ page and FOLLOW on this one, which are two halves
  -- of one decision; they are next to each other now.
  { name = "HARMONY", params = {
    S.seq("root",   "ROOT",   { opts = C.NOTE_NAMES, def = 0 }),
    S.seq("octave", "OCT",    { min = 1, max = 7, def = 3 }),
    S.seq("scale",  "SCALE",  { min = 1, max = 40, def = 1, g = "scale" }),
    S.seq("chord",  "CHORD",  { opts = C.CHORDS, def = 0, g = "chord" }),
    S.seq("invert", "INVERT", { min = -3, max = 3, def = 0, g = "bi" }),
    S.seq("spread", "SPREAD", { min = 0, max = 3, def = 0 }),
    S.seq("follow", "FOLLOW", { opts = {"OFF","DEGREE","VOICE","BASS"}, def = 1 }),
    S.seq("leader", "LEADER", { opts = {"-","T1","T2","T3","T4","T5","T6","T7","T8"},
                                g = "leader" }),
  }},
}

return C
