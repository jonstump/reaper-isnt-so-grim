-- SPDX-License-Identifier: MIT
-- Governing: SPEC-0001 REQ "Delta Calculation and Adjustment Hints"
-- Governing: SPEC-0001 REQ "Peak Measurement Convention" (advisory line only)
--
-- Pure evaluation: takes measured values and a threshold table, returns the
-- rows the report renders. No Reaper API, no I/O, no globals — which is what
-- makes this the part of ACX Check that can be tested without Reaper, and the
-- part that survives unchanged if the measurement source ever changes.
--
-- Input shape (all levels in dBFS; any may be nil if unavailable):
--   {
--     rms          = -24.6,
--     peak         = -4.1,          -- sample peak, the pass/fail figure
--     true_peak    = -3.4,          -- optional, advisory only
--     noise_floor  = -58.3,
--     noise_region = { start_sec = 12.4, end_sec = 13.1 },
--     unavailable  = { noise_floor = "source shorter than minimum window" },
--   }

local M = {}

local function round1(x)
  return math.floor(x * 10 + 0.5) / 10
end

local function fmt_db(x)
  return string.format("%.1f dB", round1(x))
end

local function fmt_delta(x)
  return string.format("%+.1f dB", round1(x))
end

local function fmt_time(sec)
  local m = math.floor(sec / 60)
  local s = sec - m * 60
  return string.format("%d:%05.2f", m, s)
end

-- Signed distance from the nearest threshold boundary.
-- Negative means below the allowed region, positive means above it, zero means
-- inside. Callers use the sign to decide direction of advice.
local function range_delta(value, min, max, eps)
  if min and value < min - eps then return value - min end
  if max and value > max + eps then return value - max end
  return 0.0
end

-- Distance to the nearest boundary while inside the allowed region. Reported
-- as "margin" so a passing row says something useful instead of nothing.
local function range_margin(value, min, max)
  local candidates = {}
  if min then candidates[#candidates + 1] = value - min end
  if max then candidates[#candidates + 1] = max - value end
  local best = candidates[1]
  for i = 2, #candidates do
    if candidates[i] < best then best = candidates[i] end
  end
  return best or 0.0
end

local function unavailable_row(key, label, reason)
  return {
    key = key,
    label = label,
    status = "unavailable",
    value_text = "—",
    limit_text = "",
    delta_text = "",
    hint = reason or "not measured",
  }
end

--- RMS row, including the tug-of-war check.
--
-- The important behaviour: when RMS is too low, the gain that would fix it is
-- only advice if applying it keeps sample peak legal. If it would not, we say
-- so and recommend dynamics processing instead — and deliberately state no
-- gain figure at all, because a number that cannot be applied is worse than
-- no number for someone who has chosen to trust this readout.
local function rms_row(m, t, eps)
  local spec = t.rms
  local limit_text = string.format("need %.0f to %.0f dB", spec.min, spec.max)

  if m.rms == nil then
    local row = unavailable_row("rms", spec.label, m.unavailable and m.unavailable.rms)
    row.limit_text = limit_text
    return row
  end

  local delta = range_delta(m.rms, spec.min, spec.max, eps)
  local row = {
    key = "rms",
    label = spec.label,
    value = m.rms,
    value_text = fmt_db(m.rms),
    limit_text = limit_text,
    delta = delta,
  }

  if delta == 0.0 then
    row.status = "pass"
    row.delta_text = ""
    row.hint = string.format("%s of margin", fmt_db(range_margin(m.rms, spec.min, spec.max)))
    return row
  end

  row.status = "fail"
  row.delta_text = fmt_delta(delta)

  if delta > 0 then
    row.hint = string.format("%s too loud → reduce gain ~%s", fmt_db(delta), fmt_db(delta))
    return row
  end

  -- Too quiet. Work out the gain that would reach the allowed range, then
  -- check what that gain would do to peak before recommending it.
  local needed_gain = -delta
  local too_quiet_by = fmt_db(needed_gain)

  if m.peak == nil then
    -- Cannot verify the peak consequence. State the figure, but never silently
    -- imply it is safe.
    row.hint = string.format(
      "%s too quiet → gain ~%s would reach range, but peak could not be measured to confirm it is safe",
      too_quiet_by, too_quiet_by)
    return row
  end

  local headroom = t.peak.max - m.peak
  if needed_gain > headroom + eps then
    row.hint = string.format(
      "%s too quiet, but only %s of peak headroom → compress or limit; gain alone cannot fix this",
      too_quiet_by, fmt_db(headroom))
    row.blocked_by_peak = true
  else
    row.hint = string.format("%s too quiet → raise gain ~%s", too_quiet_by, too_quiet_by)
  end

  return row
end

local function peak_row(m, t, eps)
  local spec = t.peak
  local limit_text = string.format("need <= %.0f dB", spec.max)

  if m.peak == nil then
    local row = unavailable_row("peak", spec.label, m.unavailable and m.unavailable.peak)
    row.limit_text = limit_text
    return row
  end

  local delta = range_delta(m.peak, nil, spec.max, eps)
  local row = {
    key = "peak",
    label = spec.label,
    value = m.peak,
    value_text = fmt_db(m.peak),
    limit_text = limit_text,
    delta = delta,
  }

  if delta == 0.0 then
    row.status = "pass"
    row.delta_text = ""
    row.hint = string.format("%s of headroom", fmt_db(spec.max - m.peak))
  else
    row.status = "fail"
    row.delta_text = fmt_delta(delta)
    row.hint = string.format("%s too hot → reduce gain or limit", fmt_db(delta))
  end

  -- True peak never changes the verdict; it only ever adds a line.
  if m.true_peak ~= nil then
    local margin = t.true_peak_advisory_margin or 0.3
    if m.true_peak - m.peak >= margin - eps then
      row.detail = string.format("true peak %s (informational — not used for pass/fail)",
        fmt_db(m.true_peak))
    end
  end

  return row
end

local function noise_row(m, t, eps)
  local spec = t.noise_floor
  local limit_text = string.format("need <= %.0f dB", spec.max)

  if m.noise_floor == nil then
    local row = unavailable_row("noise_floor", spec.label,
      m.unavailable and m.unavailable.noise_floor)
    row.limit_text = limit_text
    return row
  end

  local delta = range_delta(m.noise_floor, nil, spec.max, eps)
  local row = {
    key = "noise_floor",
    label = spec.label,
    value = m.noise_floor,
    value_text = fmt_db(m.noise_floor),
    limit_text = limit_text,
    delta = delta,
  }

  if delta == 0.0 then
    row.status = "pass"
    row.delta_text = ""
    row.hint = string.format("%s of margin", fmt_db(spec.max - m.noise_floor))
  else
    row.status = "fail"
    row.delta_text = fmt_delta(delta)
    row.hint = string.format("%s too noisy → revisit noise reduction", fmt_db(delta))
  end

  -- Which region produced this number. A wrong auto-pick is only correctable
  -- if it is visible, so this line is not optional.
  if m.noise_region then
    row.detail = string.format("measured over %s – %s",
      fmt_time(m.noise_region.start_sec), fmt_time(m.noise_region.end_sec))
  end

  return row
end

--- Evaluate measurements against thresholds.
-- @param measurements table  see input shape above
-- @param thresholds   table  defaults to the ACX table
-- @return table rows, boolean all_passed
function M.evaluate(measurements, thresholds)
  local t = thresholds or require("acx.thresholds").default
  local eps = (thresholds and thresholds.epsilon) or require("acx.thresholds").epsilon

  local rows = {
    rms_row(measurements, t, eps),
    peak_row(measurements, t, eps),
    noise_row(measurements, t, eps),
  }

  local all_passed = true
  for _, row in ipairs(rows) do
    if row.status ~= "pass" then all_passed = false end
  end

  return rows, all_passed
end

-- Exposed for tests.
M._internal = {
  range_delta = range_delta,
  range_margin = range_margin,
  fmt_db = fmt_db,
  fmt_time = fmt_time,
}

return M
