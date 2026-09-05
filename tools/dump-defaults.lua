-- Prints what the script actually sends for one track, as "channel value"
-- lines, so an offline render can be driven by the defaults that ship
-- rather than by numbers copied into a test.
--
--   lua tools/dump-defaults.lua [perc|tone|amb] [ch=value ...]

local ROOT = (arg[0]:match("(.*)/tools/") or ".")
local WANT = arg[1] or "perc"

local sent = {}
local S = setmetatable({}, { __index = function() return function() end end })
dofile(ROOT .. "/tools/stub_norns.lua")(ROOT, S)

-- capture pset instead of the generic no-op the stub installs
engine = setmetatable({ name = "" }, { __index = function(_, k)
  return function(t, ch, v)
    if k == "pset" and t == 0 then sent[ch] = v end
  end
end })

dofile(ROOT .. "/tahned.lua")
init()

local MACH = { perc = 1, tone = 2, amb = 3 }
local st = tahned.state
st.select_track(1)
st.tracks[1]:set_machine(MACH[WANT] or 1)
st.tracks[1]:send_all()

-- overrides, so a check can render one parameter moved off its default
for i = 2, #arg do
  local ch, v = arg[i]:match("^(%d+)=([%d.%-]+)$")
  if ch then sent[tonumber(ch)] = tonumber(v) end
end

for ch = 0, 95 do
  io.write(string.format("%d %.6f\n", ch, sent[ch] or 0))
end
