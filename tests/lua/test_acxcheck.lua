-- Tests for scripts/ACXCheck.lua (the entry point and version-floor gate,
-- story #28).
--
-- These trace to three SPEC-0001 REQs: "Measurement Source and Version
-- Floor" (the gate runs first and refuses to proceed, naming both
-- versions), "Input Resolution" (the interactive selected-item path -- this
-- is source.resolve_selection's existing behaviour, surfaced rather than
-- reimplemented), and "Report Presentation" (a report window opens either
-- way). As with test_postrender.lua, the assertion that matters most is not
-- what the report says -- that machinery is already covered by
-- test_evaluate.lua and test_report.lua -- it is that (a) the version gate
-- genuinely short-circuits everything downstream, and (b) nothing resembling
-- a project mutation is ever attempted.
--
-- What is provable headless: that M.run checks the version before touching
-- selection, that a supported version resolves through acx.source's
-- interactive path (not a second implementation), wires
-- measure -> evaluate -> report, releases nothing it doesn't own (an item's
-- source belongs to its take), and never calls anything that looks like a
-- project mutation. What is not provable headless: that this file actually
-- runs standalone when loaded by Reaper's Action List -- that needs Reaper.

local mock = require("tests.lua.mock_reaper")

-- Require ACXCheck.lua with the real `reaper` global absent (saving/
-- restoring whatever happens to be installed at this point in the suite),
-- so the bottom-of-file `if reaper then M.run(reaper) end` guard sees a nil
-- global and does not auto-invoke a real run during `require`. Every test
-- below instead calls acxcheck.run(...) directly with its own stub, the
-- same way test_postrender.lua calls postrender.check(...) directly.
local saved_reaper = _G.reaper
_G.reaper = nil
local acxcheck = require("ACXCheck")
_G.reaper = saved_reaper

--------------------------------------------------------------------------------
-- A `reaper` stub that fails the test on any call that could mutate project
-- state. Same technique test_source.lua and test_postrender.lua use: any
-- name that looks like a mutation is a violation unless it was explicitly
-- wired below.
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

-- A `reaper` stub that only answers GetAppVersion -- everything else falls
-- through a metatable that records the call and returns a harmless 0,
-- rather than erroring. This is what proves the version gate short-circuits
-- concretely: if M.run ever reached for selection or measurement before (or
-- despite) an unsupported version, `touched` would be non-empty.
local function version_gate_reaper(version_str)
  local touched = {}
  local api = { GetAppVersion = function() return version_str end }
  local guard = setmetatable(api, {
    __index = function(_, name)
      touched[#touched + 1] = name
      return function() return 0 end
    end,
  })
  return guard, touched
end

-- gain = 10^((target - level) / 20), the inverse of measure.recover_level.
-- Same formula test_measure.lua and test_postrender.lua use to script
-- CalculateNormalization.
local function gain_for(target, level)
  return 10 ^ ((target - level) / 20)
end

local function fake_source(length)
  return { token = "PCM_source", length = length }
end

-- Build a `reaper` stub that resolves a selected item (CountSelectedMediaItems,
-- GetSelectedMediaItem, GetActiveTake, GetMediaItemTake_Source, and the
-- item/take metadata source.resolve_selection reads), and, when `gains` is
-- supplied, can also measure it via scripted gains and scan for a
-- noise-floor region -- everything M.run needs for a full pass through the
-- pipeline. `gains` is nil for the selection-failure scenarios, where no
-- measurement is ever reached.
local function item_reaper(opts)
  opts = opts or {}
  local destroyed = {}
  local gains = opts.gains
  local count = opts.count == nil and 1 or opts.count
  local item = { token = "item" }
  local take = { token = "take" }
  local file_src = opts.source

  local api = {
    GetAppVersion = function() return opts.version or "6.44" end,
    CountSelectedMediaItems = function() return count end,
    GetSelectedMediaItem = function() return item end,
    GetActiveTake = function() return take end,
    GetMediaItemTake_Source = function() return file_src end,
    GetMediaSourceLength = function(s) return s and s.length or nil end,
    GetMediaItemInfo_Value = function(_, name)
      if name == "D_POSITION" then return 0 end
      if name == "D_LENGTH" then return file_src and file_src.length or 0 end
      return 0
    end,
    GetMediaItemTakeInfo_Value = function(_, name)
      if name == "D_STARTOFFS" then return 0 end
      if name == "D_PLAYRATE" then return 1.0 end
      return nil
    end,
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

-- Run M.run with the mock gfx/reaper globals installed, so report.show's
-- gfx.init/getchar/reaper.defer have somewhere to land -- same pattern
-- test_postrender.lua uses. Note this installs a *second*, separate
-- `reaper` as _G.reaper (for report.show's internals); the `reaper` stub
-- built above is what's passed explicitly to acxcheck.run for source and
-- measurement calls.
local function run(reaper, opts)
  mock.install({ keys = { 0 } })
  local rows, all_passed, e = acxcheck.run(reaper, opts)
  return rows, all_passed, e, mock
end

--------------------------------------------------------------------------------
T.suite("WHEN the running Reaper is unsupported")
--------------------------------------------------------------------------------
do
  local reaper, touched = version_gate_reaper("6.43")

  local rows, all_passed, e, m = run(reaper, {})

  T.check("an error is returned", e ~= nil)
  T.contains("the required version is named", e.message, "6.44")
  T.contains("the running version is named", e.message, "6.43")
  T.eq("all_passed is false", all_passed, false)

  for _, row in ipairs(rows) do
    T.eq(row.label .. " is reported unavailable, not fabricated", row.status, "unavailable")
  end

  T.eq("the report window was still opened to show the error", m.count("init"), 1)
  T.check("N/A is drawn for every row", m.drew_text("N/A") ~= nil)

  T.eq("nothing beyond GetAppVersion was ever touched -- the gate short-circuited"
    .. " before selection or measurement", #touched, 0)
  m.uninstall()
end

--------------------------------------------------------------------------------
T.suite("WHEN the version is supported but nothing is selected")
--------------------------------------------------------------------------------
do
  local reaper, violations = item_reaper({ count = 0 })

  local rows, all_passed, e, m = run(reaper, {})

  T.check("an error is returned", e ~= nil)
  T.contains("the constraint is named", e.message, "no media item is selected")
  T.eq("all_passed is false", all_passed, false)

  for _, row in ipairs(rows) do
    T.eq(row.label .. " is reported unavailable, not fabricated", row.status, "unavailable")
  end

  T.eq("the report window was still opened to show the error", m.count("init"), 1)
  T.eq("nothing that looks like a mutation was attempted", #violations, 0)
  m.uninstall()
end

--------------------------------------------------------------------------------
T.suite("WHEN the version is supported but multiple items are selected")
--------------------------------------------------------------------------------
do
  local reaper, violations = item_reaper({ count = 2 })

  local rows, all_passed, e, m = run(reaper, {})

  T.check("an error is returned", e ~= nil)
  T.contains("the constraint is named", e.message, "2 media items are selected")
  T.eq("all_passed is false", all_passed, false)

  T.eq("the report window was still opened to show the error", m.count("init"), 1)
  T.eq("nothing that looks like a mutation was attempted", #violations, 0)
  m.uninstall()
end

--------------------------------------------------------------------------------
T.suite("WHEN the version is supported and exactly one item passes all thresholds")
--------------------------------------------------------------------------------
do
  local item_src = fake_source(2.0)
  local gains = {
    rms = gain_for(-23.0, -20.0),
    peak = gain_for(0.0, -6.0),
    true_peak = gain_for(0.0, -6.5),
    noise = gain_for(-23.0, -68.0),
  }
  local reaper, violations, destroyed = item_reaper({ source = item_src, gains = gains })

  local rows, all_passed, e, m = run(reaper, {})

  T.check("no analysis error", e == nil)
  T.eq("all three measurements pass", all_passed, true)
  for _, row in ipairs(rows) do
    T.eq(row.label .. " reports pass", row.status, "pass")
  end

  T.eq("the report window was opened", m.count("init"), 1)
  T.check("PASS is drawn for the selected item", m.drew_text("PASS") ~= nil)
  T.check("the report names the selected item, via source.resolve's own label"
    .. " -- not a second implementation", m.drew_text("the selected item") ~= nil)

  T.eq("nothing that looks like a mutation was attempted", #violations, 0)
  T.eq("an item's source belongs to its take -- nothing was destroyed", #destroyed, 0)
  m.uninstall()
end

--------------------------------------------------------------------------------
T.suite("The resolved item's own PCM_source is what gets measured -- no second path")
--------------------------------------------------------------------------------
do
  -- If ACXCheck.lua ever grew its own selection-to-PCM_source logic instead
  -- of calling acx.source.resolve, this stub would never see
  -- CalculateNormalization reached with our fake source.
  local seen_source
  local item_src = fake_source(2.0)
  local api = {
    GetAppVersion = function() return "6.44" end,
    CountSelectedMediaItems = function() return 1 end,
    GetSelectedMediaItem = function() return { token = "item" } end,
    GetActiveTake = function() return { token = "take" } end,
    GetMediaItemTake_Source = function() return item_src end,
    GetMediaSourceLength = function(s) return s and s.length or nil end,
    GetMediaItemInfo_Value = function(_, name)
      if name == "D_LENGTH" then return item_src.length end
      return 0
    end,
    GetMediaItemTakeInfo_Value = function(_, name)
      if name == "D_PLAYRATE" then return 1.0 end
      return 0
    end,
    PCM_Source_Destroy = function() end,
    CalculateNormalization = function(source, _, target)
      seen_source = source
      return gain_for(target, target) -- unity
    end,
    PCM_Source_GetPeaks = function(_, _r, _s, numchannels, numsamples, _e, buf)
      local values = {}
      for i = 1, numsamples * numchannels * 2 do values[i] = 0.1 end
      buf.table = function() return values end
      return numsamples
    end,
    new_array = function() return {} end,
  }
  local reaper = guarded(api)

  local rows = run(reaper, {})
  T.eq("source.resolve's own item source was what got measured", seen_source, item_src)
  T.check("a report came back", rows ~= nil and #rows == 3)
  mock.uninstall()
end
