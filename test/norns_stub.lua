-- headless norns stand-in: enough of the API to boot a script and drive it
local stub = {}
stub.errors = {}
stub.calls = {}

local function noop_table(name)
  return setmetatable({}, {
    __index = function(t, k)
      return function(...) stub.calls[name .. '.' .. k] = (stub.calls[name .. '.' .. k] or 0) + 1 end
    end
  })
end

-- include with caching, relative to cwd
local _inc = {}
function _G.include(p)
  if _inc[p] then return _inc[p] end
  local chunk, err = loadfile(p .. '.lua')
  if chunk == nil then error('include failed: ' .. p .. ' :: ' .. tostring(err)) end
  _inc[p] = chunk()
  return _inc[p]
end

-- util
_G.util = {}
function util.clamp(x, a, b) if x < a then return a elseif x > b then return b else return x end end
function util.linlin(a,b,c,d,x) if x<=a then return c end if x>=b then return d end return (x-a)/(b-a)*(d-c)+c end
function util.linexp(a,b,c,d,x) return c * math.exp(math.log(d/c) * util.linlin(a,b,0,1,x)) end
function util.round(x, q) q = q or 1 return math.floor(x/q + 0.5)*q end
local t0 = os.clock()
stub.vtime = 0
function util.time() return stub.vtime end
function util.scandir(d)
  local out = {}
  local f = io.popen('ls -1 "' .. d .. '" 2>/dev/null')
  if f == nil then return out end
  for line in f:lines() do out[#out+1] = line end
  f:close()
  return out
end
function util.file_exists(p) local f = io.open(p, 'r') if f then f:close() return true end return false end

-- tab
_G.tab = {}
function tab.save(t, p) stub.saved = t; stub.saved_path = p; return true end
function tab.load(p) if stub.saved_path == p then return stub.saved end return nil end
function tab.print(t) end
function tab.count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end

-- screen: records draw ops, validates arguments
_G.screen = {}
local sc = { level=0 }
local function num(fn, ...)
  for i, v in ipairs({...}) do
    if type(v) ~= 'number' then error('screen.'..fn..' arg '..i..' is '..type(v)) end
    if v ~= v then error('screen.'..fn..' arg '..i..' is NaN') end
  end
end
function screen.clear() end
function screen.update() stub.calls.frames = (stub.calls.frames or 0) + 1 end
function screen.level(v) num('level', v) sc.level = v end
function screen.rect(x,y,w,h) num('rect',x,y,w,h) end
function screen.fill() end
function screen.stroke() end
function screen.move(x,y) num('move',x,y) end
function screen.line(x,y) num('line',x,y) end
function screen.circle(x,y,r) num('circle',x,y,r) end
function screen.arc(x,y,r,a1,a2) num('arc',x,y,r,a1,a2) end
function screen.pixel(x,y) num('pixel',x,y) end
function screen.text(s) if type(s) ~= 'string' then error('screen.text non-string: '..type(s)) end end
function screen.text_right(s) if type(s) ~= 'string' then error('screen.text_right non-string: '..type(s)) end end
function screen.font_face(n) num('font_face', n) end
function screen.font_size(n) num('font_size', n) end
function screen.aa(n) end

-- grid
stub.leds = {}
_G.grid = {}
function grid.connect()
  local g = {}
  _G.__g = g
  function g:led(x,y,z)
    if type(x)~='number' or type(y)~='number' or type(z)~='number' then
      error('g:led bad args '..tostring(x)..','..tostring(y)..','..tostring(z))
    end
    if x<1 or x>16 or y<1 or y>8 then error('g:led out of range '..x..','..y) end
    if z<0 or z>15 then error('g:led level out of range: '..z) end
    if z ~= math.floor(z) then error('g:led non-integer level: '..z) end
    stub.leds[#stub.leds+1] = {x,y,z}
  end
  function g:all(z) stub.leds = {} end
  function g:refresh() stub.calls.grefresh = (stub.calls.grefresh or 0) + 1 end
  g.key = nil
  return g
end

-- engine
_G.engine = { name = nil }
local ENGINE_CMDS = {'vgate','voff','vhz','vmacro','vmacros','vratios','vmatrix',
                     'vlevels','venv','vtr','vxmod','vpan','vgain','vdrive','vlag','mgain','panic'}
stub.ranges = {}
local RANGE = {
  vgate = { [2] = {20, 9000}, [3] = {0, 4} },
  vhz   = { [2] = {20, 9000} },
  vmacros = { [2]={0,1},[3]={0,1},[4]={0,1},[5]={0,1},[6]={0,1},[7]={0,1} },
  vratios = { [2] = {0.05, 64}, [3] = {0.05, 64}, [4] = {0.05, 64} },
}
for _, c in ipairs(ENGINE_CMDS) do
  engine[c] = function(...)
    local args = {...}
    local rg = RANGE[c]
    if rg then
      for idx, lim in pairs(rg) do
        local v = args[idx]
        if v ~= nil and (v < lim[1] or v > lim[2]) then
          stub.ranges[#stub.ranges+1] = string.format("%s arg%d = %s (want %s..%s)", c, idx, tostring(v), tostring(lim[1]), tostring(lim[2]))
        end
      end
    end
    for i, v in ipairs({...}) do
      if type(v) ~= 'number' then error('engine.'..c..' arg '..i..' is '..type(v)) end
      if v ~= v then error('engine.'..c..' arg '..i..' is NaN') end
      if v == math.huge or v == -math.huge then error('engine.'..c..' arg '..i..' is inf') end
    end
    stub.calls['e.'..c] = (stub.calls['e.'..c] or 0) + 1
  end
end

-- controlspec
_G.controlspec = {}
function controlspec.new(lo, hi, warp, step, default, units)
  return { minval=lo, maxval=hi, warp=warp, step=step, default=default, units=units }
end

-- params
_G.params = { p = {}, actions = {}, order = {} }
local function reg(id, default)
  params.p[id] = default
  params.order[#params.order+1] = id
end
function params:add_separator(...) end
function params:add_group(...) end
function params:add_control(id, name, spec) reg(id, spec and spec.default or 0) end
function params:add_number(id, name, lo, hi, d) reg(id, d or lo) end
function params:add_option(id, name, opts, d) reg(id, d or 1) end
function params:add_binary(id, name, behav, d) reg(id, d or 0) end
function params:add_taper(id, name, lo, hi, d) reg(id, d or lo) end
function params:set_action(id, fn) params.actions[id] = fn end
function params:set(id, v) params.p[id] = v if params.actions[id] then params.actions[id](v) end end
function params:get(id) return params.p[id] end
function params:bang()
  for _, id in ipairs(params.order) do
    if params.actions[id] then params.actions[id](params.p[id]) end
  end
end
function params:write(n) if params.action_write then params.action_write('f','n', n or 1) end end
function params:read(n) if params.action_read then params.action_read('f', false, n or 1) end end

-- clock
_G.clock = {}
stub.coros = {}
function clock.run(fn, ...)
  local co = coroutine.create(fn)
  stub.coros[#stub.coros+1] = co
  local ok, err = coroutine.resume(co, ...)
  if not ok then error('clock.run body: '..tostring(err)) end
  return #stub.coros
end
function clock.sleep(t) coroutine.yield() end
function clock.sync(t) coroutine.yield() end
function clock.get_tempo() return 120 end
function clock.get_beat_sec() return 0.5 end
clock.transport = {}

-- metro
_G.metro = {}
stub.metros = {}
function metro.init(fn, time, count)
  local mt = { event = fn, time = time, count = count, running = false }
  function mt:start() self.running = true end
  function mt:stop() self.running = false end
  stub.metros[#stub.metros+1] = mt
  return mt
end

-- softcut / audio / poll
_G.softcut = noop_table('softcut')
softcut.buffer_clear = function() end
_G.audio = noop_table('audio')
_G.poll = { set = function(name, fn) return { time = 0.1, start = function() end, stop = function() end } end }

-- norns
_G.norns = { state = { data = '/tmp/tahned_test/', path = './', name = 'tahned' } }
os.execute('mkdir -p /tmp/tahned_test')

-- lattice stub: sprockets fire on a virtual pulse counter
local lattice = {}
lattice.__index = lattice
stub.lattices = {}
function lattice:new(args)
  local l = setmetatable({}, lattice)
  l.ppqn = (args and args.ppqn) or 96
  l.sprockets = {}
  l.transport = 0
  l.enabled = false
  stub.lattices[#stub.lattices+1] = l
  return l
end
function lattice:new_sprocket(args)
  local s = {
    action = args.action,
    division = args.division or 1/4,
    enabled = args.enabled ~= false,
    phase = 0,
  }
  function s:set_division(d) self.division = d end
  function s:start() self.enabled = true end
  function s:stop() self.enabled = false end
  self.sprockets[#self.sprockets+1] = s
  return s
end
function lattice:start() self.enabled = true end
function lattice:stop() self.enabled = false end
function lattice:destroy() self.enabled = false self.sprockets = {} end
function lattice:hard_restart() self.transport = 0 end
-- advance by one ppqn pulse
function lattice:pulse()
  if not self.enabled then return end
  self.transport = self.transport + 1
  for _, s in ipairs(self.sprockets) do
    if s.enabled then
      local period = math.max(1, math.floor(self.ppqn * 4 * s.division))
      if (self.transport % period) == 0 then s.action(self.transport) end
    end
  end
end
package.preload['lattice'] = function() return lattice end

return stub
