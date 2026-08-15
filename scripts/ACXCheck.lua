-- SPDX-License-Identifier: MIT
-- Governing: SPEC-0001 REQ "Input Resolution",
--            SPEC-0001 REQ "Measurement Source and Version Floor",
--            SPEC-0001 REQ "Report Presentation"
--
-- ACXCheck.lua -- the flagship entry point (PLAN.md's Weekend-1 deliverable):
-- the actual script a user adds to Reaper's Action List, or a toolbar button,
-- and runs. Every other module under scripts/acx/ is a library meant to be
-- require()'d; this file is the thing that turns them into something a user
-- can actually invoke.
--
-- THE SAME PIPELINE AS THE FILE-PATH ENTRY POINT. This is the second
-- consumer of the "one PCM_source boundary for both entry points" decision
-- (design.md): acx.postrender.check (#13) resolves a rendered file on disk
-- and runs source -> measure -> evaluate -> report -> source.release; this
-- module resolves the interactive selection and runs the exact same
-- pipeline, calling the exact same functions in the exact same order. There
-- is deliberately no second implementation here to drift from the first.
--
-- VERSION GATE FIRST. measure.check_version is called before anything else
-- -- before source.resolve, before any selection is even looked at -- so an
-- unsupported Reaper reports "update Reaper" rather than some confusing
-- downstream failure.
--
-- REPORT, NEVER BLOCK, NEVER MUTATE. Same discipline as postrender.lua: this
-- module only reads the selected item's take and shows a report. Nothing
-- here changes project state, and a failure at any stage -- unsupported
-- version, no/multiple selection, unmeasurable source -- is only ever
-- reported, never silently swallowed or escalated into blocking anything.

-- Make require("acx.xxx") resolve to this file's own scripts/ directory,
-- regardless of Reaper's current working directory. Every other acx.* module
-- (and postrender.lua) is only ever require()'d by something upstream that
-- already arranged this -- tests/lua/run.lua for the test suite, or whatever
-- loads a dev harness. This file has no such upstream: it IS the top-level
-- script Reaper loads directly from the Action List, so it has to set its
-- own path up before its own requires below can resolve.
--
-- debug.getinfo(1, "S").source is used rather than reaper.get_action_context()
-- because it works before the `reaper` global is known to exist -- plain Lua
-- provides debug.getinfo unconditionally, so the exact same line resolves
-- the path whether this file is loaded as a real ReaScript or required
-- headlessly by the test suite.
local this_source = debug.getinfo(1, "S").source
local this_dir = this_source:match("^@(.*[/\\])") or "./"
package.path = this_dir .. "?.lua;" .. this_dir .. "?/init.lua;" .. package.path

local source = require("acx.source")
local measure = require("acx.measure")
local evaluate = require("acx.evaluate")
local report = require("acx.report")
local err = require("acx.error")

local M = {}

local function report_opts(subtitle, extra)
  local opts = { title = "ACX Check", subtitle = subtitle }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return opts
end

-- The three-row "could not analyze" report, reused from acx.evaluate's
-- existing unavailable-row handling -- the exact same machinery
-- postrender.lua uses for its own resolve-failure case, and now also for
-- the version-gate failure, so all three "nothing was analyzed" outcomes
-- (bad version, nothing selected, multiple selected) render through the
-- same window instead of a bespoke path for each.
local function unresolved_rows(reason, thresholds)
  return (evaluate.evaluate(
    { unavailable = { rms = reason, peak = reason, noise_floor = reason } },
    thresholds))
end

--- Run ACX Check against the interactively selected media item, and show
--- the report.
--
-- Order of operations, top to bottom:
--   1. measure.check_version -- refuse before touching anything else.
--   2. source.resolve(reaper) -- the interactive path (no opts.path), i.e.
--      resolve_selection: exactly one selected item, or a clear error.
--   3. measure -> evaluate -> report -> source.release, identical to
--      acx.postrender.check.
--
-- @param reaper  table      the Reaper API table
-- @param opts    table|nil  { thresholds = table, report = table } --
--                            `report` is passed through to acx.report.show
--                            (title, subtitle, footer, on_close, ...)
-- @return table rows, boolean all_passed, table|nil error -- error is set
--         when the version gate or the selection could not be resolved; a
--         threshold failure or a per-measurement failure is carried in
--         `rows` instead
function M.run(reaper, opts)
  opts = opts or {}

  local supported, version_err = measure.check_version(reaper)
  if not supported then
    local rows = unresolved_rows(err.tostring(version_err), opts.thresholds)
    report.show(rows, report_opts(nil, opts.report))
    return rows, false, version_err
  end

  local resolved, resolve_err = source.resolve(reaper)
  if not resolved then
    local rows = unresolved_rows(err.tostring(resolve_err), opts.thresholds)
    report.show(rows, report_opts(nil, opts.report))
    return rows, false, resolve_err
  end

  local measurements = { unavailable = {} }

  measurements.rms = measure.measure_rms(reaper, resolved.source, 0, 0, function(e)
    measurements.unavailable.rms = err.tostring(e)
  end)

  local peaks = measure.measure_peaks(reaper, resolved.source, function(e)
    measurements.unavailable.peak = err.tostring(e)
  end)
  measurements.peak = peaks.peak
  measurements.true_peak = peaks.true_peak

  local region, region_err = source.noise_region(reaper, resolved)
  if region then
    measurements.noise_region = { start_sec = region.start, end_sec = region.stop }
    measurements.noise_floor = measure.measure_noise_floor(
      reaper, resolved.source, region.start, region.stop, function(e)
        measurements.unavailable.noise_floor = err.tostring(e)
      end)
  else
    measurements.unavailable.noise_floor = err.tostring(region_err)
  end

  -- Release whatever resolve allocated -- same ownership discipline as
  -- postrender.lua: an item's source belongs to its take and is left alone;
  -- nothing here creates a source it doesn't also destroy.
  source.release(reaper, resolved)

  local rows, all_passed = evaluate.evaluate(measurements, opts.thresholds)
  report.show(rows, report_opts(resolved.label, opts.report))
  return rows, all_passed, nil
end

-- Reaper doesn't call any particular function on a loaded script -- the
-- top-level chunk just executes -- so this is the one line that makes the
-- module above into a runnable ReaScript. Guarded on the `reaper` global so
-- that requiring this file (as tests/lua/test_acxcheck.lua does, to drive
-- M.run directly against a stubbed reaper) never triggers a real run: the
-- headless test runner has no `reaper` global unless a test has installed
-- tests/lua/mock_reaper.lua, and mock.install() only ever runs inside a
-- test's own call to M.run, after this file has already been required once.
if reaper then
  M.run(reaper)
end

return M
