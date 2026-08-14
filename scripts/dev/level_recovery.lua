-- Governing: ADR-0004 (measurement by inverting CalculateNormalization's gain factor)
-- Governing: SPEC-0001 REQ "Measurement Validation"
-- Governing: SPEC-0001 REQ "Measurement Source and Version Floor"
--
-- Spike 9: level recovery by inversion. Development only; not shipped.
--
-- Reaper's CalculateNormalization returns the linear gain factor that would
-- normalize a source to a requested target, not a level. The measured level
-- is recovered by inverting that factor against the target:
--
--     measured_level_dBFS  =  target_dBFS - 20 * log10(gain_factor)
--
-- Because the gain factor is what-remains-to-be-applied, a factor > 1 (needs
-- boosting) means the source is quieter than the target, so the measured level
-- sits below the target; a factor < 1 (needs cutting) means the opposite.
-- This mirrors Reaper's own WDL_VAL2DB = 20*log10(x).
--
-- This module is testable without Reaper: the pure math below is what gets
-- pinned by tests/lua/test_level_recovery.lua. What it cannot prove is that
-- Reaper's CalculateNormalization actually returns the factor the docs say;
-- that empirical confirmation MUST be run in Reaper against synthesized
-- reference tones (see the "Run in Reaper" section at the bottom).

local M = {}

-- WDL's VAL2DB/DB2VAL pair (db2val.h), which every figure in this module routes
-- through. Named rather than inlined at each use so the one piece of arithmetic
-- the whole spike turns on is written down exactly once.
local function val2db(ratio)
  return 20 * math.log(ratio) / math.log(10)
end

local function db2val(db)
  return 10 ^ (db / 20)
end

-- Recover a level in dBFS from a CalculateNormalization gain factor.
-- @param gain       number  linear gain factor returned by Reaper (double)
-- @param targetDb   number  the normalizeTarget the factor was computed for,
--                           in dBFS (modes 1 RMS, 2 peak, 3 true peak)
-- @return number measured level in dBFS
function M.recover_level(gain, targetDb)
  return targetDb - val2db(gain)
end

-- Reference signals of known level.
-- Produces a linear-PCM buffer for a sine wave of the given RMS level (dBFS)
-- and sample peak level (dBFS). For a pure sine, peak = rms + 3.01 dB, so only
-- rmsDb needs to be given; the requested peak is implied and checked.
-- @param rmsDb  number  target RMS level in dBFS (e.g. -20)
-- @param n      number  number of samples
-- @param sr     number  sample rate
-- @return table of samples in [-1, 1], each shifted/scaled so RMS equals rmsDb
function M.sine(rmsDb, n, sr)
  local amplitude = db2val(rmsDb) * math.sqrt(2) -- sine rms = amp/sqrt(2)
  local samples = {}
  for i = 0, n - 1 do
    samples[i + 1] = amplitude * math.sin(2 * math.pi * 440 * i / sr)
  end
  return samples
end

-- Peak level of a sample buffer in dBFS (sample peak, matching Audacity).
function M.sample_peak(samples)
  local m = 0
  for _, s in ipairs(samples) do
    local a = math.abs(s)
    if a > m then m = a end
  end
  return val2db(m)
end

-- RMS level of a sample buffer in dBFS.
function M.rms(samples)
  local sum = 0
  for _, s in ipairs(samples) do sum = sum + s * s end
  return val2db(math.sqrt(sum / #samples))
end

-- Inverse of Reaper's normalization: given a known level and a target, the
-- gain factor CalculateNormalization should return. Used to build reference
-- expectations so the in-Reaper spike can check Reaper against us.
-- @param levelDb   number  actual measured level in dBFS
-- @param targetDb  number  the target normalization was computed for
-- @return number expected linear gain factor
function M.expected_gain(levelDb, targetDb)
  return db2val(targetDb - levelDb)
end

-- Exposed for tests.
M._internal = {
  val2db = val2db,
  db2val = db2val,
}

return M


-- ============================================================================
-- Run in Reaper (the empirical half the pure suite cannot cover)
-- ============================================================================
--   1. Render each synthesized tone (M.sine at a known RMS, e.g. -20 dBFS) to
--      a WAV on disk, or put it into a take via the item API.
--   2. Obtain a PCM_source for it.
--   3. Call CalculateNormalization(source, mode, target, 0, 0) for mode 1
--      (RMS) and mode 2 (sample peak), with target = -23 for RMS.
--   4. For each, recover the level: level = target - 20*log10(returned_gain).
--   5. Assert recovered level is within 0.5 dB of the known level.
--        o For the -20 dBFS RMS sine: RMS should recover to ~ -20.0,
--          and sample peak to about -16.99 dBFS.
--   6. Also compare M.expected_gain(knownLevel, target) to Reaper's return and
--      confirm they agree within 0.5 dB, which cross-checks the formula.
--
-- Record the results next to the findings doc (docs/spikes/issue-9.md). If the
-- recovery is off by more than 0.5 dB, ADR-0004 must be reopened — do not
-- work around it.
-- ============================================================================