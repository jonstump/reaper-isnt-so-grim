-- Tests for scripts/acx/postrender.lua (the post-render invocation seam,
-- story #13).
--
-- These trace to the three WHEN/THEN scenarios of SPEC-0001 REQ
-- "Programmatic Invocation After Render": a passing render, a failing
-- render, and a render that cannot be analyzed at all. In every case the
-- assertion that matters most is not what the report says -- that machinery
-- is already covered by test_evaluate.lua and test_report.lua -- it is that
-- nothing resembling deletion, movement, or rewriting of the rendered file
-- was ever attempted.
--
-- What is provable headless: that M.check resolves through acx.source (not
-- a second path-to-PCM_source implementation), wires measure -> evaluate ->
-- report, releases what it resolved, and never calls anything that looks
-- like a project mutation -- exercised via the same strict-stub technique
-- test_source.lua uses for REQ "Read-Only Operation". What is not provable
-- headless: that a real audiobook export action actually calls this with
-- its rendered file's path, which is the export action's own story.

local mock = require("tests.lua.mock_reaper")
local postrender = require("acx.postrender")

--------------------------------------------------------------------------------
-- A `reaper` stub that fails the test on any call that could mutate project
-- state or otherwise reach for something other than reading the rendered
-- file. Same technique test_source.lua uses: any name that looks like a
-- mutation is a violation unless it was explicitly wired below.
--------------------------------------------------------------------------------
local MUTATING_PREFIX = { "Set", "Undo_", "Main_On", "Insert", "Delete", "Apply", "Move", "Update" }

local function is_mutating(name)
  for _, prefix in ipairs(MUTATING_PREFIX) do
    if name:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local function guarded(api)
  local violations = {}
  local guard = setmetatable(api, {
    __index = function(_, name)
      if is_mutating(name) then
        return function()
          violations[#violations + 1] = name
          return 0
        end
      end
      return nil
    end,
  })
  return guard, violations
end

-- gain = 10^((target - level) / 20), the inverse of measure.recover_level.
-- Same formula test_measure.lua uses to script CalculateNormalization.
local function gain_for(target, level)
  return 10 ^ ((target - level) / 20)
end

-- Build a `reaper` stub that can resolve a file source, measure it via
-- scripted gains, and scan peak data for a noise-floor region -- everything
-- M.check needs for a full pass through the pipeline. `gains` is nil for
-- the analysis-failure scenario, where no measurement is ever reached.
local function file_reaper(opts)
  opts = opts or {}
  local destroyed = {}
  local gains = opts.gains

  local api = {
    PCM_Source_CreateFromFile = function() return opts.file_source end,
    GetMediaSourceLength = function(s) return s and s.length or nil end,
    PCM_Source_Destroy = function(s) destroyed[#destroyed + 1] = s end,
  }

  if gains then
    api.CalculateNormalization = function(_, mode, target, a, b)
      if mode == 1 then
        -- RMS is measured over the full source (bounds 0,0); the noise
        -- floor is measured over the scan's chosen window (non-zero
        -- bounds). Mode 1 is shared between them, same as production.
        if a == 0 and b == 0 then return gains.rms end
        return gains.noise
      elseif mode == 2 then
        return gains.peak
      elseif mode == 3 then
        return gains.true_peak
      end
    end

    -- A flat, otherwise-arbitrary peak buffer: the coarse scan only needs to
    -- find *a* qualifying window, since the reported dB figures come from
    -- the scripted CalculateNormalization above, not from these magnitudes.
    api.PCM_Source_GetPeaks = function(_, _rate, _starttime, numchannels, numsamples, _extra, buf)
      local values = {}
      for i = 1, numsamples * numchannels * 2 do values[i] = 0.1 end
      buf.table = function() return values end
      return numsamples
    end
    api.new_array = function() return {} end
  end

  local guard, violations = guarded(api)
  return guard, violations, destroyed
end

local function fake_source(length)
  return { token = "PCM_source", length = length }
end

-- Run M.check with the mock gfx/reaper globals installed, so report.show's
-- gfx.init/getchar/etc. have somewhere to land -- same pattern
-- test_report.lua uses.
local function run(filepath, reaper, opts)
  mock.install({ keys = { 0 } })
  local rows, all_passed, e = postrender.check(reaper, filepath, opts)
  return rows, all_passed, e, mock
end

--------------------------------------------------------------------------------
T.suite("WHEN the rendered file passes all thresholds")
--------------------------------------------------------------------------------
do
  local file_src = fake_source(2.0)
  local gains = {
    rms = gain_for(-23.0, -20.0),
    peak = gain_for(0.0, -6.0),
    true_peak = gain_for(0.0, -6.5),
    noise = gain_for(-23.0, -68.0),
  }
  local reaper, violations, destroyed = file_reaper({ file_source = file_src, gains = gains })

  local rows, all_passed, e, m = run("/tmp/rendered-pass.wav", reaper, {})

  T.check("no analysis error", e == nil)
  T.eq("all three measurements pass", all_passed, true)
  for _, row in ipairs(rows) do
    T.eq(row.label .. " reports pass", row.status, "pass")
  end

  T.eq("the report window was opened", m.count("init"), 1)
  T.check("PASS is drawn for the render", m.drew_text("PASS") ~= nil)

  T.eq("nothing that looks like a mutation was attempted", #violations, 0)
  T.eq("only the file source we created was destroyed", destroyed[1], file_src)
  T.eq("nothing else was destroyed", #destroyed, 1)
  m.uninstall()
end

--------------------------------------------------------------------------------
T.suite("WHEN the rendered file fails one or more thresholds")
--------------------------------------------------------------------------------
do
  local file_src = fake_source(2.0)
  -- All three measurements genuinely fail: RMS too quiet, peak too hot
  -- (unlike test_report.lua's FAILING fixture, where -4.1 dB peak actually
  -- passes with headroom -- that fixture exists to exercise the RMS/peak
  -- tug-of-war, which is a evaluate.lua concern already covered by
  -- test_evaluate.lua, not this wiring test), noise floor too high.
  local gains = {
    rms = gain_for(-23.0, -24.6),
    peak = gain_for(0.0, -2.5),
    true_peak = gain_for(0.0, -2.0),
    noise = gain_for(-23.0, -58.3),
  }
  local reaper, violations, destroyed = file_reaper({ file_source = file_src, gains = gains })

  local rows, all_passed, e, m = run("/tmp/rendered-fail.wav", reaper, {})

  T.check("no analysis error -- a threshold failure is not an analysis failure", e == nil)
  T.eq("all_passed is false", all_passed, false)

  local by_key = {}
  for _, row in ipairs(rows) do by_key[row.key] = row end
  T.eq("RMS fails", by_key.rms.status, "fail")
  T.eq("peak fails", by_key.peak.status, "fail")
  T.eq("noise floor fails", by_key.noise_floor.status, "fail")
  T.check("a delta is reported for the failing RMS row", by_key.rms.delta_text ~= "")
  T.check("a hint is reported for the failing RMS row", by_key.rms.hint ~= "")

  T.eq("the report window was still opened", m.count("init"), 1)
  T.check("FAIL is drawn", m.drew_text("FAIL") ~= nil)

  T.eq("nothing that looks like a mutation was attempted", #violations, 0)
  T.eq("the render itself (the file source) is never destroyed more than once,"
    .. " and only as our own handle cleanup", #destroyed, 1)
  T.eq("the destroyed handle is the one we created, not some other object",
    destroyed[1], file_src)
  m.uninstall()
end

--------------------------------------------------------------------------------
T.suite("WHEN the rendered file cannot be analyzed")
--------------------------------------------------------------------------------
do
  -- No `gains` at all: PCM_Source_CreateFromFile returns nil, so
  -- source.resolve fails before any measurement is attempted.
  local reaper, violations, destroyed = file_reaper({ file_source = nil })

  local rows, all_passed, e, m = run("/tmp/does-not-exist.wav", reaper, {})

  T.check("an analysis error is returned", e ~= nil)
  T.contains("the error names the path", e.message, "/tmp/does-not-exist.wav")
  T.eq("all_passed is false", all_passed, false)

  for _, row in ipairs(rows) do
    T.eq(row.label .. " is reported unavailable, not fabricated", row.status, "unavailable")
  end

  T.eq("the report window was still opened to show the error", m.count("init"), 1)
  T.check("N/A is drawn for every row", m.drew_text("N/A") ~= nil)
  T.check("the analysis error reaches the report", m.drew_text("could not be read") ~= nil)

  T.eq("still nothing that looks like a mutation was attempted", #violations, 0)
  T.eq("nothing was allocated, so nothing needed destroying", #destroyed, 0)
  m.uninstall()
end

--------------------------------------------------------------------------------
T.suite("The resolved file's own PCM_source is what gets measured -- no second path")
--------------------------------------------------------------------------------
do
  -- If postrender.lua ever grew its own path-to-PCM_source logic instead of
  -- calling acx.source.resolve, this stub would never see
  -- PCM_Source_CreateFromFile called with the exact path passed in, and
  -- CalculateNormalization would never be reached with our fake source.
  local seen_path
  local file_src = fake_source(2.0)
  local api = {
    PCM_Source_CreateFromFile = function(path)
      seen_path = path
      return file_src
    end,
    GetMediaSourceLength = function(s) return s and s.length or nil end,
    PCM_Source_Destroy = function() end,
    CalculateNormalization = function(_, _, target) return gain_for(target, target) end, -- unity
    PCM_Source_GetPeaks = function(_, _r, _s, numchannels, numsamples, _e, buf)
      local values = {}
      for i = 1, numsamples * numchannels * 2 do values[i] = 0.1 end
      buf.table = function() return values end
      return numsamples
    end,
    new_array = function() return {} end,
  }
  local reaper = guarded(api)

  local rows = run("/tmp/exact-path.wav", reaper, {})
  T.eq("source.resolve was called with our exact file path", seen_path, "/tmp/exact-path.wav")
  T.check("a report came back", rows ~= nil and #rows == 3)
  mock.uninstall()
end
