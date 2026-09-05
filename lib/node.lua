-- node.lua
-- sixteen slots, seven types. six of the slots may be VOICE at a time, which is
-- the engine's polyphony; the rest are the non-sounding half of the patch.

local node = {}

node.EMPTY = 1
node.VOICE = 2
node.SEQ   = 3
node.MOD   = 4
node.LOGIC = 5
node.FX    = 6
node.MULT  = 7

node.N = 16
node.N_VOICES = 6
node.N_FX = 3

-- 2x2 quad-glyphs. sixteen lit-corner patterns are available at grid
-- resolution; these seven are the ones that read cleanly at a glance.
-- order is {top-left, top-right, bottom-left, bottom-right}
node.QUAD = {
  [node.EMPTY] = { 1, 0, 0, 0 },
  [node.VOICE] = { 1, 1, 1, 1 },
  [node.SEQ]   = { 1, 0, 0, 1 },
  [node.MOD]   = { 0, 1, 1, 0 },
  [node.LOGIC] = { 1, 1, 0, 0 },
  [node.FX]    = { 0, 0, 1, 1 },
  [node.MULT]  = { 1, 0, 1, 0 },
}

node.GLYPH = {
  [node.EMPTY] = 'n_empty',
  [node.VOICE] = 'n_voice',
  [node.SEQ]   = 'n_seq',
  [node.MOD]   = 'n_mod',
  [node.LOGIC] = 'n_logic',
  [node.FX]    = 'n_fx',
  [node.MULT]  = 'n_mult',
}

node.SOUNDS = {
  [node.VOICE] = true,
}

function node.new(i)
  return {
    id = i,
    t = node.EMPTY,
    voice = nil,       -- engine voice index when t == VOICE
    fx = nil,          -- regen loop index when t == FX
    gest = nil,        -- gesture lane when t == MOD
    reg = 0,           -- register offset in periods
    tuning = 0,        -- 0 = follow the global tuning, else a preset index
    x = ((i - 1) % 4) * 3 + 3,   -- position in the field
    y = math.floor((i - 1) / 4) * 2 + 2,
    mute = false,
    degree = 0,
    amp = 0.8,
  }
end

return node
