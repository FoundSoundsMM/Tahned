-- engine_ctl.lua
-- everything that talks to Engine_Tahned. modulation can touch six macros on
-- six voices at gesture rate, so nothing is sent immediately: writes set a
-- dirty flag and flush() bundles each voice into a single OSC message.

local nd = include('lib/node')

local ec = {}

ec.m = nil
ec.live = {}      -- post-modulation values actually sent to the engine
ec.d_mac = {}
ec.d_rat = {}
ec.d_man = {}
ec.d_tr = {}
ec.d_x = {}
ec.d_env = {}
ec.d_misc = {}
ec.sent = 0

local function clamp(x, a, b)
  if x < a then return a elseif x > b then return b else return x end
end

function ec.init(m)
  ec.m = m
  ec.live = {}
  for v = 1, nd.N_VOICES do
    ec.live[v] = { macros = {}, pan = 0, drive = 1, xdepth = 0, gain = 0.9 }
    for i = 1, 6 do ec.live[v].macros[i] = m.voices[v].macros[i] end
  end
  ec.all()
end

-- ------------------------------------------------------------------ live values

-- modulation writes here; the model keeps the unmodulated base value
function ec.set_macro(v, i, val)
  local l = ec.live[v]
  if l == nil then return end
  val = clamp(val, 0, 1)
  if l.macros[i] ~= val then
    l.macros[i] = val
    ec.d_mac[v] = true
  end
end

function ec.set_pan(v, val)
  local l = ec.live[v]
  if l == nil then return end
  val = clamp(val, -1, 1)
  if l.pan ~= val then l.pan = val; ec.d_misc[v] = true end
end

function ec.set_drive(v, val)
  local l = ec.live[v]
  if l == nil then return end
  val = clamp(val, 0.2, 8)
  if l.drive ~= val then l.drive = val; ec.d_misc[v] = true end
end

function ec.set_xdepth(v, val)
  local l = ec.live[v]
  if l == nil then return end
  val = clamp(val, 0, 1)
  if l.xdepth ~= val then l.xdepth = val; ec.d_x[v] = true end
end

function ec.set_gain(v, val)
  local l = ec.live[v]
  if l == nil then return end
  val = clamp(val, 0, 2)
  if l.gain ~= val then l.gain = val; ec.d_misc[v] = true end
end

-- reset a voice's live values back to its unmodulated base. this runs every
-- frame, so it goes through the setters -- they compare, and only a value that
-- actually moved sets a dirty flag and costs an OSC message.
function ec.rebase(v)
  local m = ec.m
  if m == nil or ec.live[v] == nil then return end
  local vo = m.voices[v]
  for i = 1, 6 do ec.set_macro(v, i, vo.macros[i]) end
  ec.set_pan(v, vo.pan)
  ec.set_drive(v, vo.drive)
  ec.set_xdepth(v, vo.xdepth)
  ec.set_gain(v, vo.gain)
end

function ec.macro_live(v, i)
  local l = ec.live[v]
  if l == nil then return 0 end
  return l.macros[i] or 0
end

-- ---------------------------------------------------------------------- marking

function ec.mark_macros(v) ec.d_mac[v] = true end
function ec.mark_ratios(v) ec.d_rat[v] = true end
function ec.mark_man(v)    ec.d_man[v] = true end
function ec.mark_tr(v)     ec.d_tr[v] = true end
function ec.mark_xmod(v)   ec.d_x[v] = true end
function ec.mark_env(v)    ec.d_env[v] = true end
function ec.mark_misc(v)   ec.d_misc[v] = true end

-- ------------------------------------------------------------------- immediate

function ec.gate(v, hz, amp)
  if engine == nil or engine.vgate == nil then return end
  engine.vgate(v - 1, hz, amp)
end

function ec.off(v)
  if engine == nil or engine.voff == nil then return end
  engine.voff(v - 1)
end

function ec.hz(v, hz)
  if engine == nil or engine.vhz == nil then return end
  engine.vhz(v - 1, hz)
end

function ec.panic()
  if engine and engine.panic then engine.panic() end
end

-- ------------------------------------------------------------------------ flush

function ec.flush()
  if engine == nil or ec.m == nil then return end
  local m = ec.m
  local n = 0

  for v, _ in pairs(ec.d_mac) do
    local a = ec.live[v].macros
    if engine.vmacros then
      engine.vmacros(v - 1, a[1], a[2], a[3], a[4], a[5], a[6])
      n = n + 1
    end
  end
  ec.d_mac = {}

  for v, _ in pairs(ec.d_rat) do
    local r = m.voices[v].r
    if engine.vratios then
      engine.vratios(v - 1, r[1], r[2], r[3])
      n = n + 1
    end
  end
  ec.d_rat = {}

  for v, _ in pairs(ec.d_man) do
    local a = m.voices[v].man
    if engine.vmatrix then
      engine.vmatrix(v - 1, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8],
                     a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16])
      n = n + 1
    end
  end
  ec.d_man = {}

  for v, _ in pairs(ec.d_tr) do
    local t = m.voices[v].tr
    if engine.vtr then
      engine.vtr(v - 1, t.amt, t.dec, t.col, t.w[1], t.w[2], t.w[3], t.w[4])
      n = n + 1
    end
  end
  ec.d_tr = {}

  for v, _ in pairs(ec.d_x) do
    local vo = m.voices[v]
    if engine.vxmod then
      engine.vxmod(v - 1, vo.xsrc - 1, ec.live[v].xdepth, vo.xmode)
      n = n + 1
    end
  end
  ec.d_x = {}

  for v, _ in pairs(ec.d_env) do
    local e = m.voices[v].env
    if engine.venv then
      engine.venv(v - 1, e.atk, e.rel, e.crv)
      n = n + 1
    end
  end
  ec.d_env = {}

  for v, _ in pairs(ec.d_misc) do
    local l = ec.live[v]
    if engine.vpan then engine.vpan(v - 1, l.pan) end
    if engine.vdrive then engine.vdrive(v - 1, l.drive) end
    if engine.vgain then engine.vgain(v - 1, l.gain) end
    if engine.vlag then engine.vlag(v - 1, m.voices[v].lag) end
    n = n + 4
  end
  ec.d_misc = {}

  ec.sent = n
end

function ec.all()
  for v = 1, nd.N_VOICES do
    ec.d_mac[v] = true
    ec.d_rat[v] = true
    ec.d_man[v] = true
    ec.d_tr[v] = true
    ec.d_x[v] = true
    ec.d_env[v] = true
    ec.d_misc[v] = true
  end
  if engine and engine.mgain and ec.m then engine.mgain(ec.m.mix.gain) end
  ec.flush()
end

return ec
