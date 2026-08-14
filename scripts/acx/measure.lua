-- Governing: SPEC-0001 REQ "Measurement Source and Version Floor",
--            SPEC-0001 REQ "Peak Measurement Convention",
--            SPEC-0001 REQ "Error Handling Standards",
--            ADR-0004 (stock Reaper DSP, inversion bounded to one place)
--
-- Measurement core. Derives RMS, sample peak, true peak, and noise floor from
-- Reaper's native CalculateNormalization and recovers each level by inverting
-- the returned gain factor. The inversion lives in EXACTLY ONE place here
-- (M.recover_level) and must never be reimplemented at a call site — that is a
-- SPEC-0001 requirement.
--
-- Stock Reaper plus ReaPack only, per ADR-0003: no SWS, ReaImGui, or
-- js_ReaScriptAPI. The minimum Reaper version is detected here and the
-- capability refuses to proceed below it (6.44, per spike 9).
--
-- Reaper notes:
--   * CalculateNormalization returns a LINEAR gain factor, not a level, and not
--     a status integer. Recovery = target - 20*log10(gain).
--   * normalizeTo mode bits: 0=LUFS-I, 1=RMS-I, 2=peak, 3=true peak,
--     4=LUFS-M max, 5=LUFS-S max. normalizeTarget is dBFS for modes 1/2/3.
--   * normalizeStart/normalizeEnd bound the analysis in seconds; both 0 = full.
--   * A returned gain of 0/NaN means the measurement could not be produced.

local M = {}

local err = require("acx.error")

-- Minimum Reaper version providing CalculateNormalization. Confirmed against
-- Reaper's changelog in spike 9: the function first appears in v6.44.
M.min_version = { major = 6, minor = 44 }

-- The single inversion. Given the linear gain factor CalculateNormalization
-- returned for a given target, recover the measured level in dBFS.
-- Governing: SPEC-0001 REQ "Measurement Source and Version Floor"
--            ("inversion MUST be implemented in one place")
-- @param gain      number  linear gain factor (as returned by Reaper)
-- @param targetDb  number  the normalizeTarget the factor was computed for
-- @param failIfZero  boolean  treat gain<=0 as a failed measurement (default true)
-- @return number|nil measured level in dBFS, nil if the measurement failed
function M.recover_level(gain, targetDb, failIfZero)
  if failIfZero ~= false and not (gain and gain > 0) then return nil end
  return targetDb - 20 * math.log(gain) / math.log(10)
end

-- Compare a version pair against the minimum. Pure and testable without Reaper.
-- @param running  table { major = int, minor = int }
-- @return boolean true if running is >= M.min_version
function M.version_supported(running)
  if not running or not running.major or running.major == nil then return false end
  if running.major ~= M.min_version.major then
    return running.major > M.min_version.major
  end
  return (running.minor or 0) >= M.min_version.minor
end

-- Parse Reaper's Version() string ("v6.44+dev1234", "6.78rc1", ...) into a
-- comparable {major, minor, patch}. Pure and testable.
function M.parse_version(str)
  if type(str) ~= "string" then return nil end
  local major, minor = str:match("(%d+)%.(%d+)")
  if not major then return nil end
  local patch = str:match("%.%d+%.(%d+)")
  return { major = tonumber(major), minor = tonumber(minor), patch = patch and tonumber(patch) or 0 }
end

-- The per-measure metering config used by the measure wrappers.
local MODES = {
  rms        = { mode = 1, target = -23.0 }, -- RMS-I; any target works, inversion is target-independent
  peak       = { mode = 2, target = 0.0  },  -- sample peak
  true_peak  = { mode = 3, target = 0.0  },  -- true peak (advisory)
  noise      = { mode = 1, target = -23.0 }, -- RMS-I, bounded to a quiet window
}

-- Run CalculateNormalization over a PCM_source and recover the level.
-- A nil/zero gain is surfaced as an unavailability via `on_fail` rather than a
-- fabricated value, per REQ "Error Handling Standards".
-- @param source  PCM_source  to analyze
-- @param measure table  { mode = int, target = number }
-- @param a,b     number  time bounds in seconds; both 0 = full source
-- @param on_fail function|nil  called with an error object when measurement fails
-- @return number|nil recovered level in dBFS
local function normalized_level(reaper, source, measure, a, b, on_fail)
  local gain = reaper.CalculateNormalization(source, measure.mode, measure.target, a, b)
  local level = M.recover_level(gain, measure.target)
  if level == nil and on_fail then
    on_fail(err.new({
      cause = "the measurement call could not produce a level",
      detail = string.format("mode %d returned gain %s for target %s dBFS",
        measure.mode, tostring(gain), tostring(measure.target)),
      fix = "check the source is decodable and rerun ACX Check",
    }))
  end
  return level
end

-- Measure RMS level in dBFS over the given bounds (or the full source when both
-- are 0). Returns nil on failure instead of fabricating a value.
function M.measure_rms(reaper, source, startSec, endSec, on_fail)
  return normalized_level(reaper, source, MODES.rms, startSec or 0, endSec or 0, on_fail)
end

-- Measure sample peak and true peak in dBFS. Returns { peak, true_peak }, each
-- nil-able so a failed pair degrades per-row rather than wholesale.
function M.measure_peaks(reaper, source, on_fail)
  local peak = normalized_level(reaper, source, MODES.peak, 0, 0, on_fail)
  local true_peak = normalized_level(reaper, source, MODES.true_peak, 0, 0, on_fail)
  return { peak = peak, true_peak = true_peak }
end

-- Measure noise floor in dBFS over an explicit quiet window. The window is
-- chosen by the noise-floor locator (story #11); measuring reuses this same
-- trusted RMS path so the reported figure shares provenance with the others.
function M.measure_noise_floor(reaper, source, startSec, endSec, on_fail)
  return normalized_level(reaper, source, MODES.noise, startSec, endSec, on_fail)
end

-- Surface the active minimum-version requirements in a reportable form.
-- @return string e.g. "Reaper 6.44"
function M.min_version_text()
  return string.format("Reaper %d.%d", M.min_version.major, M.min_version.minor)
end

M._internal = { MODES = MODES, normalized_level = normalized_level }

return M