-- instrument registry
local drums = include("tahned/lib/instruments/drums")
local tone  = include("tahned/lib/instruments/tone")
local C     = include("tahned/lib/instruments/common")

local I = {}
for _, d in ipairs(drums) do table.insert(I, d) end
table.insert(I, tone)

I.by_id = {}
for _, inst in ipairs(I) do I.by_id[inst.id] = inst end
I.common = C
I.n = #I

-- Full ordered page list for a machine:
--   MIX, SEQ..., the machine's own pages, FILTER, LFO 1..4
function I.pages_for(m)
  local inst = I[m]
  local pages = { C.mix }
  for _, p in ipairs(C.seqpage[inst.seq]) do table.insert(pages, p) end
  for _, p in ipairs(inst.pages) do table.insert(pages, p) end
  table.insert(pages, C.filter)
  for n = 1, 4 do table.insert(pages, C.lfo[n]) end
  return pages
end

-- every channel-backed parameter a machine has, for LFO destination lists
function I.destinations_for(m)
  local d = { { ch = 88, name = "OFF" } }
  for _, page in ipairs(I.pages_for(m)) do
    for _, sp in ipairs(page.params) do
      if sp.ch and (sp.k == "cont" or sp.k == "enum" or sp.k == "int") and sp.ch < 56 then
        table.insert(d, { ch = sp.ch, name = sp.name, spec = sp })
      end
    end
  end
  return d
end

return I
