-- Tests for scripts/acx/measure.lua (measurement core).
--
-- The measurement core is exercised headless against a stubbed `reaper`
-- table. What can be proven without Reaper: the single-site inversion
-- (SPEC-0001 "inversion MUST be implemented in one place"), the version-floor
-- detection (SPEC-0001 REQ "Measurement Source and Version Floor"), the
-- per-measurement wrappers, and that failures degrade per-row and never
-- fabricate a value (SPEC-0001 REQ "Error Handling Standards"). What requires
-- Reaper — that CalculateNormalization returns the documented factor — is the
-- empirical spike 9 half.

local measure = require("acx.measure")

-- A stub `reaper` that hands back a scripted gain per mode, so the wrappers can
-- be driven deterministically.
local function fake_reaper(gains)
  local calls = {}
  return {
    calls = calls,
    CalculateNormalization = function(source, mode, target, a, b)
      calls[#calls + 1] = { mode = mode, target = target, a = a, b = b }
      local ans = gains[mode]
      if type(ans) == "function" then ans = ans(source, target, a, b) end
      return ans
    end,
  }
end

--------------------------------------------------------------------------------
T.suite("Version floor detection")
--------------------------------------------------------------------------------
do
  T.check("6.44 is supported", measure.version_supported({ major = 6, minor = 44 }))
  T.check("6.78 is supported", measure.version_supported({ major = 6, minor = 78 }))
  T.check("7.0 is supported", measure.version_supported({ major = 7, minor = 0 }))
  T.check("6.43 is rejected", not measure.version_supported({ major = 6, minor = 43 }))
  T.check("6.0 is rejected", not measure.version_supported({ major = 6, minor = 0 }))
  T.check("5 is rejected", not measure.version_supported({ major = 5, minor = 99 }))
  T.check("nil is rejected", not measure.version_supported(nil))
end

--------------------------------------------------------------------------------
T.suite("Version string parsing")
--------------------------------------------------------------------------------
do
  local v = measure.parse_version("v6.44+dev20220107")
  T.eq("major parsed", v.major, 6)
  T.eq("minor parsed", v.minor, 44)

  local v7 = measure.parse_version("7.05rc1")
  T.eq("v7 major", v7.major, 7)
  T.eq("v7 minor", v7.minor, 5)

  T.check("garbage is nil", measure.parse_version("not a version") == nil)
  T.check("nil input is nil", measure.parse_version(nil) == nil)
end

--------------------------------------------------------------------------------
T.suite("The single inversion recovers level from a gain factor")
--------------------------------------------------------------------------------
do
  -- 3 dB quieter than the target => gain = 10^(3/20) ~= 1.413; level recovers
  -- to the known value. Same fixture as the spike so the two stay aligned.
  local known = -26.0
  local target = -23.0
  local gain = 10 ^ ((target - known) / 20)
  T.near("recovered RMS", measure.recover_level(gain, target), known, 0.000001)

  -- gain == 1 (already at target) recovers the target itself.
  T.near("unity gain recovers target", measure.recover_level(1.0, -23.0), -23.0, 0.000001)

  -- gain < 1 (louder than target) recovers a level above the target.
  T.near("cut recovers level above target", measure.recover_level(0.5, -23.0), -16.9794, 0.00001)

  -- A non-positive gain signals failure, not a level: never fabricated.
  T.check("zero gain is nil", measure.recover_level(0.0, -23.0) == nil)
  T.check("negative gain is nil", measure.recover_level(-1.0, -23.0) == nil)
  T.check("nil gain is nil", measure.recover_level(nil, -23.0) == nil)
  T.check("NaN gain is nil", measure.recover_level(0 / 0, -23.0) == nil)
  T.check("non-numeric gain is nil", measure.recover_level("1.0", -23.0) == nil)

  -- Regression: an opt-out of the guard used to exist, and returned inf for a
  -- zero gain and NaN for a negative one. There must be no argument that turns
  -- a failed measurement into a number. The value is named in each description
  -- so a failure says which input produced it.
  for _, extra in ipairs({ false, true, 0, "false" }) do
    local named = string.format("%s (%s)", tostring(extra), type(extra))
    T.check("a zero gain stays nil with a third argument of " .. named,
      measure.recover_level(0.0, -23.0, extra) == nil)
    T.check("a negative gain stays nil with a third argument of " .. named,
      measure.recover_level(-1.0, -23.0, extra) == nil)
  end
end

--------------------------------------------------------------------------------
T.suite("A bad target is a caller bug, not a failed measurement")
--------------------------------------------------------------------------------
do
  -- The two must not report alike. Returning nil for a garbage target made the
  -- surface claim "the measurement call could not produce a level" for a source
  -- Reaper had measured perfectly well — a false cause from the module whose REQ
  -- is about naming true ones. A contract violation raises instead.
  -- Labelled rather than derived from the value: tostring(a table) embeds an
  -- address, which would make the test output differ run to run.
  local bad_targets = {
    { label = "a numeric string", value = "-23" },
    { label = "a table",          value = {} },
    { label = "a boolean",        value = true },
    { label = "nil",              value = nil },
  }
  for _, case in ipairs({ 1, 2, 3, 4 }) do
    local bad = bad_targets[case]
    local ok, raised = pcall(measure.recover_level, 1.413, bad.value)
    T.check("a target of " .. bad.label .. " raises", not ok)
    T.contains("the raise from " .. bad.label .. " names the argument",
      tostring(raised), "target must be a number")
  end

  local _, raised_nil = pcall(measure.recover_level, 1.413, nil)
  T.contains("the raise names the type it got", tostring(raised_nil), "got nil")

  -- The distinction is the point: a gain Reaper could not produce is still nil.
  T.check("a bad gain with a good target is still a quiet nil",
    measure.recover_level(0.0, -23.0) == nil)
end

--------------------------------------------------------------------------------
T.suite("measure_rms uses mode 1 and recovers the level")
--------------------------------------------------------------------------------
do
  -- A source whose RMS is 3 dB below the -23 target: gain = 10^(3/20).
  local known = -26.0
  local target = -23.0
  local reaper = fake_reaper({ [1] = 10 ^ ((target - known) / 20) })
  local level = measure.measure_rms(reaper, {}, 0, 0)
  T.near("RMS level recovered", level, known, 0.000001)
  T.eq("mode is RMS-I (1)", reaper.calls[1].mode, 1)
  T.near("bounds default to full source", reaper.calls[1].a, 0)
  T.near("bounds default to full source end", reaper.calls[1].b, 0)
end

--------------------------------------------------------------------------------
T.suite("measure_rms honours explicit time bounds")
--------------------------------------------------------------------------------
do
  local reaper = fake_reaper({ [1] = 1.0 })
  measure.measure_rms(reaper, {}, 12.4, 13.1)
  T.near("start bound passed through", reaper.calls[1].a, 12.4)
  T.near("end bound passed through", reaper.calls[1].b, 13.1)
end

--------------------------------------------------------------------------------
T.suite("measure_peaks uses sample peak and true peak modes")
--------------------------------------------------------------------------------
do
  -- gain 0.9 at target 0 dBFS: level = 0 - 20*log10(0.9) = +0.915 dBFS. The
  -- source is LOUDER than the target, so the recovered level is above it.
  local reaper = fake_reaper({ [2] = 0.9, [3] = 0.85 })
  local p = measure.measure_peaks(reaper, {})
  T.near("sample peak recovered", p.peak, 0.915, 0.001)
  T.near("true peak recovered", p.true_peak, 1.411, 0.001)

  -- 0 * log10 = 0, so a gain of exactly 1 at target 0 gives 0 dBFS.
  local r2 = fake_reaper({ [2] = 1.0, [3] = 1.0 })
  local p2 = measure.measure_peaks(r2, {})
  T.near("peak at unity is 0 dBFS", p2.peak, 0.0, 0.000001)
end

--------------------------------------------------------------------------------
T.suite("measure_noise_floor uses RMS bounded to the quiet window")
--------------------------------------------------------------------------------
do
  -- A noise floor 47 dB BELOW the -23 target needs a boost of 10^(47/20), so
  -- the recovered level is -70 dBFS.
  local reaper = fake_reaper({ [1] = 10 ^ ((-23 - -70) / 20) })
  local floor = measure.measure_noise_floor(reaper, {}, 0.5, 1.4)
  T.near("noise floor recovered", floor, -70.0, 0.000001)
  T.eq("mode is RMS-I", reaper.calls[1].mode, 1)
  T.near("window start passed", reaper.calls[1].a, 0.5)
  T.near("window end passed", reaper.calls[1].b, 1.4)
end

--------------------------------------------------------------------------------
T.suite("No fabricated value on failure")
--------------------------------------------------------------------------------
do
  -- CalculateNormalization returns 0/negative on failure; the wrapper must
  -- surface the failure via on_fail and return nil, never report a level.
  local failed = 0
  local function on_fail(err)
    failed = failed + 1
    T.contains("failure names the cause", err.message, "could not produce a level")
    T.contains("failure carries a corrective action", err.message, "rerun ACX Check")
  end
  local dead = fake_reaper({ [1] = 0.0, [2] = -1, [3] = 0 })
  T.check("RMS failure is nil", measure.measure_rms(dead, {}, 0, 0, on_fail) == nil)
  local p = measure.measure_peaks(dead, {}, on_fail)
  T.check("peak failure is nil", p.peak == nil)
  T.check("true peak failure is nil", p.true_peak == nil)
  T.eq("on_fail fired for the failures", failed, 3)
end

--------------------------------------------------------------------------------
T.suite("min_version_text is reportable")
--------------------------------------------------------------------------------
do
  T.eq("min version text", measure.min_version_text(), "Reaper 6.44")
end

--------------------------------------------------------------------------------
T.suite("The refusal names both the installed and the required version")
--------------------------------------------------------------------------------
do
  -- REQ "Measurement Source and Version Floor" asks for both halves: what is
  -- installed and what is needed. Reporting only the requirement leaves the user
  -- guessing whether they are the ones affected.
  local function at(version)
    return { GetAppVersion = function() return version end }
  end

  local ok, none = measure.check_version(at("6.44/x64"))
  T.check("6.44 is allowed to proceed", ok)
  T.check("no error accompanies a supported version", none == nil)

  T.check("7.05 is allowed to proceed", (measure.check_version(at("7.05rc1"))))

  local blocked, why = measure.check_version(at("6.43/x64"))
  T.check("6.43 is refused", not blocked)
  T.contains("the refusal names the installed version", why.message, "6.43")
  T.contains("the refusal names the required version", why.message, "Reaper 6.44")
  T.contains("the refusal says what to do", why.message, "update to")
  T.not_contains("the raw string is not the lead", why.message, "/x64")
  T.contains("the raw string survives as detail", why.detail, "6.43/x64")

  -- An install too old or too odd to parse is still an install worth naming.
  local unparsed, odd = measure.check_version(at("wildly unexpected"))
  T.check("an unparseable version is refused", not unparsed)
  T.contains("the raw string is reported when it cannot be parsed", odd.message, "wildly unexpected")

  local absent, missing = measure.check_version({})
  T.check("a Reaper without GetAppVersion is refused", not absent)
  T.contains("an unknown version is named as unknown", missing.message, "unknown")
  T.check("no detail is invented when there is no raw string", missing.detail == nil)

  local nothing, nil_err = measure.check_version(nil)
  T.check("no reaper table at all is refused", not nothing)
  T.check("a refusal always carries an error", nil_err ~= nil)
end