-- regen.lua
-- three stereo regeneration loops on softcut's six voices. long buffers, and
-- the buffer treated as a source rather than only an effect: an FX node firing
-- jumps the loop to a random point in its own past.

local nd = include('lib/node')

local regen = {}

regen.BUFLEN = 340.0
regen.REGION = 110.0
regen.on = false

local function region(i)
  local s = (i - 1) * regen.REGION + 0.5
  return s, s + regen.REGION - 1.0
end

local function voices_of(i) return (i * 2) - 1, i * 2 end

function regen.init(m)
  if softcut == nil then return end
  audio.level_eng_cut(1.0)
  audio.level_adc_cut(0.0)
  softcut.buffer_clear()

  for i = 1, nd.N_FX do
    local va, vb = voices_of(i)
    local s = region(i)
    for ch, v in ipairs({ va, vb }) do
      softcut.enable(v, 1)
      softcut.buffer(v, ch)
      softcut.level(v, 0)
      softcut.loop(v, 1)
      softcut.loop_start(v, s)
      softcut.loop_end(v, s + m.regen[i].len)
      softcut.position(v, s)
      softcut.play(v, 1)
      softcut.rate(v, 1)
      softcut.rec(v, 1)
      softcut.rec_level(v, 1)
      softcut.pre_level(v, m.regen[i].fb)
      softcut.fade_time(v, 0.02)
      softcut.level_slew_time(v, 0.1)
      softcut.rate_slew_time(v, 0.05)
      softcut.recpre_slew_time(v, 0.1)
      softcut.post_filter_dry(v, 0)
      softcut.post_filter_lp(v, 1)
      softcut.post_filter_fc(v, 8000)
      softcut.post_filter_rq(v, 2.0)
      softcut.level_input_cut(ch, v, 1.0)
      softcut.pan(v, (ch == 1) and -0.3 or 0.3)
    end
  end
  regen.on = true
  regen.push(m)
end

regen.last = {}

-- called every frame, so it compares first: softcut commands are not free and
-- three loops of twenty parameters at 60Hz would be 3600 messages a second
function regen.push(m, only)
  if softcut == nil or not regen.on then return end
  for i = 1, nd.N_FX do
    if only == nil or only == i then
      local r0 = m.regen[i]
      local sig = string.format('%d%d%.4f%.4f%.4f%.4f%.4f%.4f%.4f',
        r0.on and 1 or 0, r0.mode, r0.len, r0.rate + (r0.mod_rate or 0),
        r0.fb + (r0.mod_fb or 0), r0.filt + (r0.mod_filt or 0),
        r0.res, r0.level, r0.spread)
      if regen.last[i] == sig then goto continue end
      regen.last[i] = sig
    end
    if only == nil or only == i then
      local r = m.regen[i]
      local va, vb = voices_of(i)
      local s = region(i)

      local fb = math.max(0, math.min(1.1, r.fb + (r.mod_fb or 0)))
      local rate = r.rate + (r.mod_rate or 0)
      local filt = math.max(0, math.min(1, r.filt + (r.mod_filt or 0)))
      local fc = 60 * math.exp(filt * 5.3)
      local lvl = r.on and r.level or 0

      local rec = 1
      if r.mode == 3 then rec = 0; fb = 1.0 end            -- freeze
      if r.mode == 4 then rate = rate * 0.5 end            -- stretch

      local len = r.len
      if r.mode == 2 then len = math.min(len, 0.25) end    -- granular windows

      for ch, v in ipairs({ va, vb }) do
        local sp = (ch == 1) and -r.spread or r.spread
        softcut.level(v, lvl)
        softcut.pre_level(v, fb)
        softcut.rec(v, rec)
        softcut.rate(v, rate * (1 + (sp * 0.004)))
        softcut.loop_start(v, s)
        softcut.loop_end(v, s + math.max(0.02, len))
        softcut.post_filter_fc(v, fc)
        softcut.post_filter_rq(v, 2.0 - (r.res * 1.7))
        softcut.pan(v, sp)
      end
    end
    ::continue::
  end
end

-- an FX node firing: the delay becomes a sampler of the piece's own past
function regen.trigger(m, i)
  if softcut == nil or not regen.on or i == nil then return end
  local r = m.regen[i]
  local va, vb = voices_of(i)
  local s, e = region(i)
  if r.mode == 2 or r.mode == 4 then
    local p = s + (math.random() * (e - s - r.len))
    for _, v in ipairs({ va, vb }) do
      softcut.loop_start(v, p)
      softcut.loop_end(v, p + math.max(0.02, r.len))
      softcut.position(v, p)
    end
  else
    for _, v in ipairs({ va, vb }) do
      softcut.position(v, s)
    end
  end
end

function regen.set_on(m, i, on)
  m.regen[i].on = on
  regen.push(m, i)
end

function regen.clear(i)
  if softcut == nil then return end
  local s, e = region(i)
  softcut.buffer_clear_region(s, e - s)
end

return regen
