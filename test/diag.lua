local stub = dofile("test/norns_stub.lua")
math.randomseed(5)
dofile("tahned.lua")
init()
local bus = include('lib/bus')
local nd = include('lib/node')
local notes, trigs, chords = 0, 0, 0
bus.on('note', function() notes = notes + 1 end)
bus.on('trig', function() trigs = trigs + 1 end)
bus.on('chord', function() chords = chords + 1 end)

local seq = include('lib/seq')
local function tick(sec)
  for i = 1, math.floor(sec*60) do
    stub.vtime = stub.vtime + 1/60
    for _, mt in ipairs(stub.metros) do
      if mt.running then
        if mt.time > 0.02 then if i%2==0 then mt.event() end else mt.event() end
      end
    end
    for _, l in ipairs(stub.lattices) do for p=1,4 do l:pulse() end end
  end
end

print("lattices: "..#stub.lattices.." running="..tostring(seq.running))
for _, l in ipairs(stub.lattices) do print("  enabled="..tostring(l.enabled).." sprockets="..#l.sprockets) end
local before = stub.calls['e.vmacros'] or 0
tick(10)
print(string.format("10s: notes=%d trigs=%d chords=%d gates=%d vmacros=%d",
  notes, trigs, chords, stub.calls['e.vgate'] or 0, (stub.calls['e.vmacros'] or 0) - before))
for i=1,6 do
  local lane = _G.__m and nil
end
-- per-lane report
local model = include('lib/model')
print("lane positions / cycles:")
