-- tuning.lua
-- one integer lattice, spent three ways: as pitch, as FM operator ratio, and
-- (via seq) as clock division. three backends behind one interface.
--
--   EDO(n, period)  any equal division of any period, not just the octave
--   JI(limit)       prime-limit just intonation, with the exponent vectors kept
--                   because they are what harmony walks on
--   SCL(file)       scala files out of the data directory

local Tuning = {}
Tuning.__index = Tuning

local PRIMES = { 3, 5, 7, 11, 13 }
local LOG2 = math.log(2)

local function log2(x) return math.log(x) / LOG2 end

-- continued-fraction rational approximation, used to give EDO and scala
-- scales an approximate harmonic distance
local function approx_frac(x, maxd)
  maxd = maxd or 64
  local n0, d0, n1, d1 = 0, 1, 1, 0
  local v = x
  for _ = 1, 24 do
    local a = math.floor(v)
    local n2, d2 = a * n1 + n0, a * d1 + d0
    if d2 > maxd then break end
    n0, d0, n1, d1 = n1, d1, n2, d2
    local f = v - a
    if f < 1e-9 then break end
    v = 1 / f
  end
  if d1 == 0 then return 1, 1 end
  return n1, d1
end

local function gcd(a, b) while b ~= 0 do a, b = b, a % b end return a end

-- ----------------------------------------------------------------- construction

local function build_edo(t, n, period)
  t.steps = n
  t.period = period
  t.ratios = {}
  for i = 1, n do
    t.ratios[i] = period ^ ((i - 1) / n)
  end
end

local function build_ji(t, limit, maxnotes, period)
  local np = 0
  for i = 1, #PRIMES do if PRIMES[i] <= limit then np = i end end
  -- exponent ranges shrink as the prime grows; this is what keeps the set musical
  local range = { 4, 2, 1, 1, 1 }
  local cand = {}

  local function rec(i, num, den, vec, cost)
    if i > np then
      if num == 1 and den == 1 then
        cand[#cand + 1] = { r = 1, v = { 0, 0, 0, 0, 0 }, c = 0, n = 1, d = 1 }
        return
      end
      local r = num / den
      -- fold into one period
      local nn, dd = num, den
      while r >= period do r = r / period; dd = dd * period end
      while r < 1 do r = r * period; nn = nn * period end
      local g = gcd(nn, dd)
      nn, dd = nn // g, dd // g
      cand[#cand + 1] = { r = r, v = { table.unpack(vec) }, c = cost, n = nn, d = dd }
      return
    end
    local p = PRIMES[i]
    for e = -range[i], range[i] do
      vec[i] = e
      local nnum, nden = num, den
      -- integer powers only; float exponentiation would leak into the
      -- displayed fractions and these are the numerals the player reads
      for _ = 1, math.abs(e) do
        if e > 0 then nnum = nnum * p else nden = nden * p end
      end
      rec(i + 1, nnum, nden, vec, cost + (math.abs(e) * log2(p)))
    end
    vec[i] = 0
  end

  rec(1, 1, 1, { 0, 0, 0, 0, 0 }, 0)

  -- dedupe by pitch, keeping the cheapest spelling of each
  table.sort(cand, function(a, b)
    if math.abs(a.r - b.r) < 1e-9 then return a.c < b.c end
    return a.r < b.r
  end)
  local uniq = {}
  for i = 1, #cand do
    local c = cand[i]
    local last = uniq[#uniq]
    if last == nil or math.abs(log2(c.r) - log2(last.r)) > 0.0004 then
      uniq[#uniq + 1] = c
    end
  end

  -- keep the lowest-complexity notes, then put them back in pitch order
  table.sort(uniq, function(a, b) return a.c < b.c end)
  local keep = {}
  for i = 1, math.min(maxnotes, #uniq) do keep[i] = uniq[i] end
  table.sort(keep, function(a, b) return a.r < b.r end)

  t.steps = #keep
  t.period = period
  t.ratios = {}
  t.vectors = {}
  t.fracs = {}
  for i = 1, #keep do
    t.ratios[i] = keep[i].r
    t.vectors[i] = keep[i].v
    t.fracs[i] = { keep[i].n, keep[i].d }
  end
end

local function build_scl(t, path)
  local f = io.open(path, "r")
  if f == nil then return false end
  local lines = {}
  for raw in f:lines() do
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "!" then lines[#lines + 1] = line end
  end
  f:close()
  if #lines < 2 then return false end

  t.desc = lines[1]
  local count = tonumber(lines[2]:match("^(%d+)"))
  if count == nil then return false end

  local ratios = { 1 }
  for i = 1, count do
    local s = lines[2 + i]
    if s == nil then break end
    s = s:match("^(%S+)")
    local r
    local n, d = s:match("^(%d+)%s*/%s*(%d+)$")
    if n then
      r = tonumber(n) / tonumber(d)
    elseif s:match("^%d+$") then
      r = tonumber(s)                 -- bare integer is a ratio n/1 in scala
    else
      r = 2 ^ (tonumber(s) / 1200)    -- anything with a dot is cents
    end
    if r then ratios[#ratios + 1] = r end
  end

  -- the last entry is the period, and is not itself a degree
  t.period = ratios[#ratios] or 2
  table.remove(ratios, #ratios)
  t.ratios = ratios
  t.steps = #ratios
  return true
end

-- ------------------------------------------------------------------------ public

-- opts: {backend = 'edo'|'ji'|'scl', n, period, limit, maxnotes, path}
function Tuning.new(opts)
  opts = opts or {}
  local t = setmetatable({}, Tuning)
  t.backend = opts.backend or 'edo'
  t.label = opts.label

  if t.backend == 'ji' then
    build_ji(t, opts.limit or 5, opts.maxnotes or 12, opts.period or 2)
  elseif t.backend == 'scl' then
    if not build_scl(t, opts.path) then
      t.backend = 'edo'
      build_edo(t, 12, 2)
    end
  else
    build_edo(t, opts.n or 12, opts.period or 2)
  end

  t.root = opts.root or 55.0
  return t
end

-- degree is an integer over any number of periods; 0 is the root
function Tuning:ratio(degree)
  local n = self.steps
  local p = math.floor(degree / n)
  local i = degree - (p * n)
  return self.ratios[i + 1] * (self.period ^ p)
end

function Tuning:hz(degree, root)
  return (root or self.root) * self:ratio(degree)
end

-- a register offset plus a wandering chord can walk a voice down to 10Hz,
-- which is a click train rather than a note. fold by whole periods so the
-- pitch class is preserved -- clamping here would put the voice out of tune.
function Tuning:fold_hz(hz, lo, hi)
  lo = lo or 24.0
  hi = hi or 7000.0
  if hz <= 0 then return lo end
  local p = self.period
  if p <= 1.0001 then return math.max(lo, math.min(hi, hz)) end
  local n = 0
  while hz < lo and n < 24 do hz = hz * p; n = n + 1 end
  while hz > hi and n < 48 do hz = hz / p; n = n + 1 end
  return hz
end

function Tuning:cents(degree)
  return 1200 * log2(self:ratio(degree))
end

-- the degree whose ratio sits closest to a target, searched across periods
function Tuning:nearest(target)
  local best, bd = 0, math.huge
  local lt = log2(target)
  local span = self.steps * 4
  for d = -span, span do
    local diff = math.abs(log2(self:ratio(d)) - lt)
    if diff < bd then bd = diff; best = d end
  end
  return best, bd
end

-- harmonic distance. for JI this is exact (tenney height of the interval);
-- for EDO and scala it comes from the best rational approximation.
function Tuning:distance(d1, d2)
  if self.vectors then
    local n = self.steps
    local i1 = d1 - (math.floor(d1 / n) * n)
    local i2 = d2 - (math.floor(d2 / n) * n)
    local v1, v2 = self.vectors[i1 + 1], self.vectors[i2 + 1]
    local dist = math.abs(math.floor(d1 / n) - math.floor(d2 / n)) * 1.0
    for i = 1, #PRIMES do
      dist = dist + (math.abs((v1[i] or 0) - (v2[i] or 0)) * log2(PRIMES[i]))
    end
    return dist
  end
  local r = self:ratio(d2) / self:ratio(d1)
  while r < 1 do r = r * self.period end
  while r >= self.period do r = r / self.period end
  local n, d = approx_frac(r, 48)
  return log2(n * d)
end

function Tuning:name(degree)
  local n = self.steps
  local i = degree - (math.floor(degree / n) * n)
  if self.fracs then
    local f = self.fracs[i + 1]
    if f then return f[1] .. "/" .. f[2] end
  end
  if self.backend == 'edo' then
    return i .. "\\" .. n
  end
  return string.format("%d", math.floor(self:cents(i) + 0.5))
end

function Tuning:short()
  if self.label then return self.label end
  if self.backend == 'edo' then
    if math.abs(self.period - 2) < 1e-9 then return tostring(self.steps) end
    return self.steps .. "|" .. string.format("%.0f", self.period)
  elseif self.backend == 'ji' then
    return "ji" .. (self.limit or "")
  end
  return (self.desc or "scl"):sub(1, 6)
end

-- ------------------------------------------------- the spine: ratios as timbre
--
-- op2 sits at unison and gives the full harmonic series (the EVEN macro).
-- op3 sits at the period, so odd-harmonic FM in an octave tuning gives odd
--   harmonics and in Bohlen-Pierce gives the BP odd-partial series, which is
--   the correct answer for BP rather than an accident.
-- op4 takes its ratio from the interval to another sounding chord tone, so the
--   sidebands land on pitches the harmony is already using.
function Tuning:op_ratios(degree, partner)
  local r2 = 1
  local r3 = self.period
  local r4 = 3
  if partner ~= nil then
    r4 = self:ratio(partner) / self:ratio(degree)
    while r4 < 1.5 do r4 = r4 * self.period end
    while r4 > 8.0 do r4 = r4 / self.period end
  end
  return r2, r3, r4
end

-- the same lattice spent as time: a degree becomes a clock ratio
function Tuning:division(degree, base)
  local r = self:ratio(degree)
  while r >= 2 do r = r / 2 end
  local n, d = approx_frac(r, 16)
  return (base or 1) * d / n, n, d
end

-- ---------------------------------------------------------------------- presets

Tuning.PRESETS = {
  { label = "12",  backend = 'edo', n = 12,  period = 2 },
  { label = "13",  backend = 'edo', n = 13,  period = 2 },
  { label = "17",  backend = 'edo', n = 17,  period = 2 },
  { label = "19",  backend = 'edo', n = 19,  period = 2 },
  { label = "22",  backend = 'edo', n = 22,  period = 2 },
  { label = "24",  backend = 'edo', n = 24,  period = 2 },
  { label = "31",  backend = 'edo', n = 31,  period = 2 },
  { label = "53",  backend = 'edo', n = 53,  period = 2 },
  { label = "bp",  backend = 'edo', n = 13,  period = 3 },
  { label = "a",   backend = 'edo', n = 9,   period = 1.5 },   -- carlos alpha
  { label = "b",   backend = 'edo', n = 11,  period = 1.5 },   -- carlos beta
  { label = "g",   backend = 'edo', n = 20,  period = 1.5 },   -- carlos gamma
  { label = "ji5", backend = 'ji',  limit = 5,  maxnotes = 12, period = 2 },
  { label = "ji7", backend = 'ji',  limit = 7,  maxnotes = 14, period = 2 },
  { label = "ji11",backend = 'ji',  limit = 11, maxnotes = 17, period = 2 },
  { label = "ji13",backend = 'ji',  limit = 13, maxnotes = 19, period = 2 },
}

Tuning.BASE_PRESETS = #Tuning.PRESETS

-- scala files dropped in either the script's data folder or the user's own
-- data directory become presets alongside the built-in EDOs and JI sets, so
-- a tuning you add is reachable from the grid without touching any code
function Tuning.scan(dirs)
  for i = #Tuning.PRESETS, Tuning.BASE_PRESETS + 1, -1 do
    table.remove(Tuning.PRESETS, i)
  end
  local seen = {}
  for _, d in ipairs(dirs) do
    local files = (util and util.scandir) and util.scandir(d) or nil
    if files then
      for _, f in ipairs(files) do
        if f:match('%.scl$') and not seen[f] then
          seen[f] = true
          Tuning.PRESETS[#Tuning.PRESETS + 1] = {
            label = f:gsub('%.scl$', ''):sub(1, 6),
            backend = 'scl',
            path = d .. f,
          }
        end
      end
    end
  end
  return #Tuning.PRESETS - Tuning.BASE_PRESETS
end

function Tuning.preset(i)
  local p = Tuning.PRESETS[((i - 1) % #Tuning.PRESETS) + 1]
  local t = Tuning.new(p)
  t.limit = p.limit
  return t
end

function Tuning.n_presets() return #Tuning.PRESETS end

return Tuning
