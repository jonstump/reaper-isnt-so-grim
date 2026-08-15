-- SPDX-License-Identifier: MIT
-- Governing: SPEC-0001 REQ "Programmatic Invocation After Render",
--            ADR-0004 (the measurement pipeline this seam wires together)
--
-- The post-render invocation seam (story #13): the entry point the
-- audiobook export action will call with its rendered file's absolute path,
-- once the export action itself exists (`PLAN.md` item 1a.4). Deliberately
-- thin -- this module adds no new way to reach a PCM_source. It calls
-- acx.source.resolve with { path = filepath }, the exact boundary story #11
-- built, so the numbers this shows are the numbers a manual check on the
-- same file would produce (design.md, "One PCM_source boundary for both
-- entry points"). Everything downstream -- measure, evaluate, report -- is
-- the same pipeline the interactive path will use.
--
-- REPORT, NEVER BLOCK. M.check only reads the rendered file at `filepath`
-- and shows a report; nothing in this module deletes, moves, or rewrites
-- it, and no path through M.check returns a signal a caller could use to do
-- so. A failing threshold and a file that cannot be analyzed at all are
-- handled the same way in this respect: the render stays exactly as
-- rendered, and the failure is only ever reported.

local M = {}

local source = require("acx.source")
local measure = require("acx.measure")
local evaluate = require("acx.evaluate")
local report = require("acx.report")
local err = require("acx.error")

local function report_opts(filepath, extra)
  local opts = { title = "ACX Check", subtitle = filepath }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return opts
end

-- The three-row "could not analyze" report used when the file itself could
-- not even be resolved -- Scenario "Analysis failure does not affect the
-- render". This reuses acx.evaluate's existing unavailable-row handling
-- rather than inventing a second reporting path, so an outright analysis
-- failure and a per-measurement failure render through the same window.
local function unresolved_rows(reason, thresholds)
  return (evaluate.evaluate(
    { unavailable = { rms = reason, peak = reason, noise_floor = reason } },
    thresholds))
end

--- Run ACX Check against a rendered file on disk, and show the report.
--
-- Reuses the exact source.resolve -> measure -> evaluate -> report pipeline
-- the interactive path uses; nothing here re-implements resolution or
-- measurement. Never blocks, cancels, or reverses the render: this function
-- only reads `filepath` and calls report.show. The caller's render is
-- untouched no matter what path below executes or what this function
-- returns -- there is no delete, move, or write of the rendered file
-- anywhere in this module.
--
-- @param reaper    table      the Reaper API table
-- @param filepath  string     absolute path to the rendered audio file
-- @param opts      table|nil  { thresholds = table, report = table } --
--                             `report` is passed through to acx.report.show
--                             (title, subtitle, footer, on_close, ...)
-- @return table rows, boolean all_passed, table|nil error  -- error is only
--         set when the file could not be resolved at all; a threshold
--         failure or a per-measurement failure is carried in `rows` instead
function M.check(reaper, filepath, opts)
  opts = opts or {}

  local resolved, resolve_err = source.resolve(reaper, { path = filepath })
  if not resolved then
    local rows = unresolved_rows(err.tostring(resolve_err), opts.thresholds)
    report.show(rows, report_opts(filepath, opts.report))
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
  -- #11's module: an item's source belongs to its take and is left alone; a
  -- file source we created for this check, we destroy. Destroying our
  -- PCM_source handle is not touching the render -- the rendered file on
  -- disk is never opened for writing anywhere in this module, only read.
  source.release(reaper, resolved)

  local rows, all_passed = evaluate.evaluate(measurements, opts.thresholds)
  report.show(rows, report_opts(filepath, opts.report))
  return rows, all_passed, nil
end

return M
