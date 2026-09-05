local stub = dofile("test/norns_stub.lua")
_G.norns.state.path = "./"
math.randomseed(42)

local fails = 0
local function try(label, fn, ...)
  local o, e = pcall(fn, ...)
  if not o then
    print("FAIL [" .. label .. "] " .. tostring(e))
    fails = fails + 1
    return false
  end
  return true
end

if not try("load", dofile, "tahned.lua") then os.exit(1) end
if not try("init", init) then os.exit(1) end
print("init ok  engine=" .. tostring(engine.name))

local g = _G.__g

local function tick(seconds)
  local steps = math.floor(seconds * 60)
  for i = 1, steps do
    stub.vtime = stub.vtime + (1/60)
    for _, mt in ipairs(stub.metros) do
      if mt.running then
        if mt.time > 0.02 then
          if i % 2 == 0 then try("metro-ui", mt.event) end
        else
          try("metro-phys", mt.event)
        end
      end
    end
    for _, l in ipairs(stub.lattices) do
      for p = 1, 4 do try("lattice", function() l:pulse() end) end
    end
  end
end

local function gkey(x, y, z) try(("gkey %d,%d,%d"):format(x,y,z), g.key, x, y, z) end
local function press(x, y) gkey(x,y,1) gkey(x,y,0) end

print("-- free run")
tick(2.0)

print("-- every page, every key, both shift states")
for page = 1, 8 do
  press(1, page)
  for _, sh in ipairs({false, true}) do
    try("k1", key, 1, sh and 1 or 0)
    for x = 2, 16 do
      for y = 1, 8 do press(x, y) end
    end
    tick(0.15)
  end
  try("k1 off", key, 1, 0)
  for n = 1, 3 do
    for d = -3, 3 do try("enc", enc, n, d) end
  end
  try("k2", key, 2, 1) try("k2u", key, 2, 0)
  try("k3", key, 3, 1) try("k3u", key, 3, 0)
  tick(0.3)
  try("redraw", redraw)
end

print("-- drags on the field page, and a busy arena")
press(1, 3)
for i = 1, 6 do
  gkey(3 + i, 2, 1)
  gkey(6 + i, 6, 0)
end
tick(2.0)

print("-- shift-held grid gestures (two fingers in a row on timbre)")
press(1, 5)
gkey(4, 2, 1) gkey(11, 2, 1) gkey(4, 2, 0) gkey(11, 2, 0)
tick(0.3)

print("-- gesture record cycle")
press(1, 6)
gkey(2, 1, 1)
stub.vtime = stub.vtime + 0.8
gkey(2, 1, 0)
for i = 1, 60 do try("enc-rec", enc, 2, (i % 7) - 3) tick(0.02) end
gkey(2, 1, 1) gkey(2, 1, 0)
tick(1.0)

print("-- morph: store three corners then sweep the pad")
press(1, 7)
try("k2 morph", key, 2, 1) try("k2u", key, 2, 0)
for x = 2, 14 do for y = 1, 8, 2 do press(x, y) end end
tick(1.0)

print("-- perturb + undo via K2+K3")
for i = 1, 8 do
  try("perturb", function()
    key(2,1) key(3,1) key(3,0) key(2,0)
  end)
  tick(0.2)
end
for i = 1, 4 do
  try("undo", function()
    key(1,1) key(2,1) key(3,1) key(3,0) key(2,0) key(1,0)
  end)
  tick(0.2)
end

print("-- transport, tuning sweep, save/load")
try("stop", function() key(1,1) key(2,1) key(2,0) key(1,0) end)
tick(0.3)
try("start", function() key(1,1) key(3,1) key(3,0) key(1,0) end)
tick(0.5)
local Tuning = include("lib/tuning")
for t = 1, Tuning.n_presets() do
  try("tuning " .. t, params.set, params, 'tuning_preset', t)
  tick(0.25)
end
try("pset write", params.write, params, 1)
try("pset read", params.read, params, 1)
tick(0.5)

print("-- set slot save/load via shift + page column")
try("k1", key, 1, 1)
gkey(1, 4, 1) stub.vtime = stub.vtime + 1.0 gkey(1, 4, 0)
gkey(1, 4, 1) gkey(1, 4, 0)
try("k1 off", key, 1, 0)
tick(1.0)

print("-- rebuild a patch using only the grid, then soak")
-- the brute-force sweep above shift-cleared every node, which is what that
-- gesture is for. rebuild through the hardware, the way a player would.
press(1, 1)                                   -- MAP page
local made = 0
for i = 1, 6 do
  -- select node i, then hit VOICE in the type picker (row 7, col 2 of the strip)
  local col = ((i - 1) % 4) + 1
  local row = math.floor((i - 1) / 4) + 1
  press(1 + ((col - 1) * 2) + 1, ((row - 1) * 2) + 1)
  press(1 + 8 + 2, 7)
  made = made + 1
end
press(1 + 8 + 2, 7)

local bus = include('lib/bus')
local notes, collisions = 0, 0
bus.on('note', function() notes = notes + 1 end)
bus.on('collision', function() collisions = collisions + 1 end)

params:set('f_on', 1)
params:set('h_on', 1)
params:set('drift', 0.5)
params:set('humanise', 0.3)
params:set('swing', 0.2)

-- put a few nodes in the arena and set them to be triggered by balls
press(1, 3)
for i = 1, 3 do
  gkey(2 + i, 2, 1)
  gkey(9 + i, 7, 0)
end
tick(20.0)

print(string.format("   soak: notes=%d collisions=%d", notes, collisions))
if notes < 100 then print("FAIL [soak] too few notes: " .. notes) fails = fails + 1 end

print("-- tuning sweep with the patch alive (checks op ratios stay sane)")
local TN = include("lib/tuning")
print("   presets available: " .. TN.n_presets() .. " (incl. " .. (TN.n_presets() - TN.BASE_PRESETS) .. " scala)")
for t = 1, TN.n_presets() do
  params:set('tuning_preset', t)
  tick(0.6)
end

try("cleanup", cleanup)

if #stub.ranges > 0 then
  print("RANGE VIOLATIONS:")
  local seen = {}
  for _, r in ipairs(stub.ranges) do
    if not seen[r] then seen[r] = true print("   " .. r) end
  end
  fails = fails + 1
end
local sccalls = 0
for k, v in pairs(stub.calls) do if k:sub(1,8) == 'softcut.' then sccalls = sccalls + v end end
print("softcut calls: " .. sccalls)

print("")
print("frames drawn: " .. tostring(stub.calls.frames))
print("grid refreshes: " .. tostring(stub.calls.grefresh))
local ecalls = {}
for k, v in pairs(stub.calls) do if k:sub(1,2) == 'e.' then ecalls[#ecalls+1] = k .. "=" .. v end end
table.sort(ecalls)
print("engine: " .. table.concat(ecalls, " "))
print("")
if fails == 0 then print("ALL OK") else print(fails .. " FAILURES") end
