-- instrument registry
local perc = include("tahned/lib/instruments/perc")
local tone = include("tahned/lib/instruments/tone")
local amb  = include("tahned/lib/instruments/amb")
local C    = include("tahned/lib/instruments/common")

local I = { perc, tone, amb }
I.by_id = { perc = perc, tone = tone, amb = amb }
I.common = C

-- Full ordered page list for a machine:
--   MASTER, SEQ..., instrument pages, FILTER, COLOUR, LFO 1..4
function I.pages_for(m)
  local inst = I[m]
  local pages = { C.master }
  for _, p in ipairs(C.seqpage[inst.seq]) do table.insert(pages, p) end
  for _, p in ipairs(inst.pages) do table.insert(pages, p) end
  table.insert(pages, C.filter)
  table.insert(pages, C.colour)
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
