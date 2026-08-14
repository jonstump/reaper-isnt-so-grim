-- Tests for scripts/acx/evaluate.lua
--
-- Every scenario below traces to a WHEN/THEN pair in SPEC-0001 REQ "Delta
-- Calculation and Adjustment Hints", plus the boundary and unavailability
-- cases the requirement implies.

local ev = require("acx.evaluate")
local th = require("acx.thresholds")

local function rows_by_key(measurements)
  local rows = ev.evaluate(measurements, th.default)
  local out = {}
  for _, r in ipairs(rows) do out[r.key] = r end
  return out
end

--------------------------------------------------------------------------------
T.suite("PLAN.md's own worked example")
--------------------------------------------------------------------------------
-- PLAN.md item 1a.1 illustrates the report with these exact numbers and the
-- hint "raise gain ~2 dB". Those values are 1.6 dB short on RMS with only
-- 1.1 dB of peak headroom, so that gain would push peak to about -2.5 dB and
-- breach the -3 limit. The spec's tug-of-war rule exists for precisely this,
-- and the plan's hand-written example is the case it catches.
do
  local r = rows_by_key({ rms = -24.6, peak = -4.1, noise_floor = -58.3 })

  T.eq("RMS fails", r.rms.status, "fail")
  T.near("RMS delta is -1.6", r.rms.delta, -1.6)
  T.eq("gain is blocked by peak headroom", r.rms.blocked_by_peak, true)
  T.contains("hint recommends dynamics", r.rms.hint, "compress or limit")
  T.contains("hint names the available headroom", r.rms.hint, "1.1 dB")
  T.not_contains("hint states no raise-gain instruction", r.rms.hint, "raise gain")

  T.eq("peak passes", r.peak.status, "pass")
  T.contains("peak reports headroom", r.peak.hint, "1.1 dB")

  T.eq("noise floor fails", r.noise_floor.status, "fail")
  T.near("noise floor delta is +1.7", r.noise_floor.delta, 1.7)
  T.contains("noise hint points at noise reduction", r.noise_floor.hint, "noise reduction")
end

--------------------------------------------------------------------------------
T.suite("WHEN RMS is low and headroom is sufficient")
--------------------------------------------------------------------------------
do
  -- 3 dB short, 9 dB of headroom — gain is genuinely the right advice.
  local r = rows_by_key({ rms = -26.0, peak = -12.0, noise_floor = -70.0 })

  T.eq("RMS fails", r.rms.status, "fail")
  T.contains("hint states a gain figure", r.rms.hint, "raise gain")
  T.contains("gain figure is 3.0 dB", r.rms.hint, "3.0 dB")
  T.eq("not blocked by peak", r.rms.blocked_by_peak, nil)
end

--------------------------------------------------------------------------------
T.suite("WHEN gain would land exactly on the peak limit")
--------------------------------------------------------------------------------
do
  -- 2 dB short with exactly 2 dB of headroom. Landing on the inclusive limit
  -- is legal, so gain remains the correct recommendation.
  local r = rows_by_key({ rms = -25.0, peak = -5.0, noise_floor = -70.0 })

  T.contains("gain is still recommended at the boundary", r.rms.hint, "raise gain")
  T.eq("not blocked", r.rms.blocked_by_peak, nil)
end

--------------------------------------------------------------------------------
T.suite("WHEN RMS exceeds the allowed range")
--------------------------------------------------------------------------------
do
  local r = rows_by_key({ rms = -16.5, peak = -4.0, noise_floor = -70.0 })

  T.eq("RMS fails", r.rms.status, "fail")
  T.near("delta is +1.5", r.rms.delta, 1.5)
  T.contains("hint recommends reduction", r.rms.hint, "reduce gain")
end

--------------------------------------------------------------------------------
T.suite("WHEN all three measurements pass")
--------------------------------------------------------------------------------
do
  local rows, all_passed = ev.evaluate(
    { rms = -20.0, peak = -6.0, noise_floor = -68.0 }, th.default)

  T.eq("all_passed is true", all_passed, true)
  for _, row in ipairs(rows) do
    T.eq(row.label .. " passes", row.status, "pass")
    T.check(row.label .. " states a margin, not a blank",
      row.hint ~= nil and row.hint ~= "", row.hint)
  end
end

--------------------------------------------------------------------------------
T.suite("Boundary values are inclusive")
--------------------------------------------------------------------------------
do
  local r = rows_by_key({ rms = -23.0, peak = -3.0, noise_floor = -60.0 })
  T.eq("RMS at -23 passes", r.rms.status, "pass")
  T.eq("peak at -3 passes", r.peak.status, "pass")
  T.eq("noise floor at -60 passes", r.noise_floor.status, "pass")

  local r2 = rows_by_key({ rms = -18.0, peak = -3.0, noise_floor = -60.0 })
  T.eq("RMS at -18 passes", r2.rms.status, "pass")
end

--------------------------------------------------------------------------------
T.suite("Just outside the boundary fails")
--------------------------------------------------------------------------------
do
  local r = rows_by_key({ rms = -23.2, peak = -2.9, noise_floor = -59.8 })
  T.eq("RMS just below -23 fails", r.rms.status, "fail")
  T.eq("peak just above -3 fails", r.peak.status, "fail")
  T.eq("noise floor just above -60 fails", r.noise_floor.status, "fail")
end

--------------------------------------------------------------------------------
T.suite("True peak is advisory only")
--------------------------------------------------------------------------------
do
  -- Sample peak legal, true peak over the limit. Verdict must stay passing.
  local r = rows_by_key({ rms = -20.0, peak = -3.5, true_peak = -2.4, noise_floor = -70.0 })
  T.eq("peak row still passes", r.peak.status, "pass")
  T.contains("true peak appears as a detail line", r.peak.detail or "", "true peak")
  T.contains("detail is labelled informational", r.peak.detail or "", "informational")

  -- Within the advisory margin — no extra line.
  local r2 = rows_by_key({ rms = -20.0, peak = -3.5, true_peak = -3.4, noise_floor = -70.0 })
  T.eq("no advisory when true peak is close", r2.peak.detail, nil)
end

--------------------------------------------------------------------------------
T.suite("Noise floor discloses the region it measured")
--------------------------------------------------------------------------------
do
  local r = rows_by_key({
    rms = -20.0, peak = -6.0, noise_floor = -68.0,
    noise_region = { start_sec = 12.4, end_sec = 13.1 },
  })
  T.contains("region is shown", r.noise_floor.detail or "", "measured over")
  T.contains("start time formatted", r.noise_floor.detail or "", "0:12.40")
end

--------------------------------------------------------------------------------
T.suite("Unavailable measurements degrade per-row, not wholesale")
--------------------------------------------------------------------------------
do
  -- SPEC-0001 REQ "Noise Floor Region Determination": a source shorter than
  -- the minimum window still reports RMS and peak.
  local r = rows_by_key({
    rms = -20.0, peak = -6.0, noise_floor = nil,
    unavailable = { noise_floor = "source shorter than minimum room-tone window" },
  })

  T.eq("noise floor is unavailable", r.noise_floor.status, "unavailable")
  T.contains("reason is carried through", r.noise_floor.hint, "shorter than minimum")
  T.eq("RMS still reported", r.rms.status, "pass")
  T.eq("peak still reported", r.peak.status, "pass")
  T.eq("no fabricated value", r.noise_floor.value, nil)
end

--------------------------------------------------------------------------------
T.suite("Gain advice is never implied safe when peak is unknown")
--------------------------------------------------------------------------------
do
  local r = rows_by_key({
    rms = -26.0, peak = nil, noise_floor = -70.0,
    unavailable = { peak = "measurement call failed" },
  })

  T.eq("peak row is unavailable", r.peak.status, "unavailable")
  T.contains("RMS hint flags that peak is unverified", r.rms.hint, "could not be measured")
end

--------------------------------------------------------------------------------
T.suite("Thresholds are honoured from the table, not hardcoded")
--------------------------------------------------------------------------------
do
  -- A hypothetical publisher spec with a tighter noise floor. Reference request
  -- item E5 asks whether ACX's numbers are actually the target.
  local custom = {
    rms = { label = "RMS level", min = -21.0, max = -18.0 },
    peak = { label = "Peak level", max = -3.0 },
    noise_floor = { label = "Noise floor", max = -65.0 },
    true_peak_advisory_margin = 0.3,
    epsilon = 0.001,
  }
  local rows = ev.evaluate({ rms = -22.0, peak = -6.0, noise_floor = -62.0 }, custom)
  local r = {}
  for _, row in ipairs(rows) do r[row.key] = row end

  T.eq("RMS fails against the tighter minimum", r.rms.status, "fail")
  T.contains("limit text reflects the custom range", r.rms.limit_text, "-21")
  T.eq("noise floor fails against -65", r.noise_floor.status, "fail")
end
