-- Enough of the norns API to run the script on a desktop. Shared by
-- tools/check-lua.lua and tools/render-screen.lua.
--
-- include() deliberately does NOT cache, matching norns, so mistakes that
-- assume a module is a singleton show up rather than hiding.

return function(ROOT, screen_impl)
  function include(path)
    return dofile(ROOT .. "/" .. path:gsub("^tahned/", "") .. ".lua")
  end

  local now = 0
  util = {
    clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end,
    round = function(v) return math.floor(v + 0.5) end,
    linlin = function(a, b, c, d, v)
      if b == a then return c end
      return c + ((d - c) * ((v - a) / (b - a)))
    end,
    time = function() now = now + 0.01 return now end,
    file_exists = function() return true end,
  }

  local stats = { draws = 0, leds = 0, engine = {} }

  screen = screen_impl or setmetatable({}, { __index = function()
    return function() stats.draws = stats.draws + 1 end
  end })

  engine = setmetatable({ name = "" }, { __index = function(_, k)
    return function() stats.engine[k] = (stats.engine[k] or 0) + 1 end
  end })

  local gobj = {
    led = function() stats.leds = stats.leds + 1 end,
    all = function() end,
    refresh = function() end,
  }
  grid = { connect = function() return gobj end }

  local coros = {}
  clock = {
    run = function(f, ...)
      local co = coroutine.create(f)
      table.insert(coros, co)
      coroutine.resume(co, ...)
      return #coros
    end,
    sleep = function() coroutine.yield() end,
    sync = function() coroutine.yield() end,
    cancel = function() end,
    get_beat_sec = function() return 0.5 end,
    get_tempo = function() return 120 end,
  }
  stats.coros = coros

  metro = { init = function(f) return { start = function() end, stop = function() end, f = f } end }
  controlspec = { new = function(a, b, c, d, e) return { minval = a, maxval = b, default = e or a } end }

  local actions, val, spec = {}, { clock_tempo = 120 }, {}
  params = setmetatable({
    add_control = function(_, id, _, sp)
      spec[id] = sp
      val[id] = sp and sp.default or 0
    end,
    set_action = function(_, id, f) actions[id] = f end,
    get = function(_, id) return val[id] end,
    set = function(_, id, v) val[id] = v end,
    string = function(_, id) return string.format("%.2f", val[id] or 0) end,
    delta = function(_, id, d)
      local sp = spec[id]
      local lo, hi = sp and sp.minval or 20, sp and sp.maxval or 300
      val[id] = math.min(math.max((val[id] or lo) + (d * (hi - lo) / 100), lo), hi)
    end,
    bang = function() for _, f in pairs(actions) do f(0.5) end end,
  }, { __index = function() return function() end end })

  norns = { state = { data = "/tmp/", path = ROOT, shortname = "tahned" } }
  tab = { save = function() end, load = function() return nil end }

  local SCALES = {}
  for _, n in ipairs({ "Major", "Natural Minor", "Dorian", "Phrygian", "Lydian",
                       "Mixolydian", "Locrian", "Whole Tone", "Major Pentatonic" }) do
    table.insert(SCALES, { name = n })
  end
  package.preload["musicutil"] = function()
    return {
      SCALES = SCALES,
      generate_scale = function(root, _, oct)
        local t, iv = {}, { 0, 2, 4, 5, 7, 9, 11 }
        for o = 0, (oct or 1) - 1 do
          for _, i in ipairs(iv) do table.insert(t, root + (o * 12) + i) end
        end
        return t
      end,
      note_num_to_freq = function(n) return 440 * (2 ^ ((n - 69) / 12)) end,
      snap_note_to_array = function(n, a)
        local best, bd = a[1], math.huge
        for _, v in ipairs(a) do
          local d = math.abs(v - n)
          if d < bd then best, bd = v, d end
        end
        return best
      end,
    }
  end

  return stats
end
