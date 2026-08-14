-- Tests for scripts/dev/level_recovery.lua — the spike-9 inversion math.
--
-- These pin the headless half of SPEC-0001 REQ "Measurement Validation": given a
-- reference tone of known level, the gain factor CalculateNormalization should
-- return, and given that factor, the inversion must recover the original level.
-- The empirical half — confirming Reaper actually returns that factor — requires
-- Reaper and is documented in scripts/dev/level_recovery.lua and
-- docs/spikes/issue-9.md.
--
-- A note on what proves what. Most cases below invert a gain produced by
-- expected_gain, which is recover_level's algebraic inverse, so they can only
-- catch a sign or scale slip introduced on one side. The load-bearing case is
-- "Inversion recovers a reference tone's known level", which derives the gain
-- numerically without touching that closed form.

local lr = require("dev.level_recovery")

-- Derive the normalization gain the way Reaper must: search for the scalar that,
-- applied to the buffer, lands its measured RMS on the target. Deliberately
-- numeric — it never uses expected_gain — so the recovery it feeds is a test of
-- the inversion rather than a restatement of its own algebra. Geometric
-- bisection because gain is a ratio; 80 halvings of [1e-6, 1e6] converge well
-- past double precision.
local function gain_by_search(samples, targetDb)
  local lo, hi = 1e-6, 1e6
  local scaled = {}
  for _ = 1, 80 do
    local mid = math.sqrt(lo * hi)
    for i = 1, #samples do scaled[i] = samples[i] * mid end
    if lr.rms(scaled) < targetDb then lo = mid else hi = mid end
  end
  return math.sqrt(lo * hi)
end

--------------------------------------------------------------------------------
T.suite("Reference tones are internally consistent")
--------------------------------------------------------------------------------
do
  -- A pure sine's peak exceeds its RMS by 3.01 dB. The synthesizer must honour
  -- this, and both the RMS and peak metering must agree with the requested level.
  local samples = lr.sine(-20.0, 44100, 44100) -- 440 whole cycles of 440 Hz
  T.near("sine RMS matches the requested -20 dBFS", lr.rms(samples), -20.0, 0.01)
  T.near("sine sample peak is RMS + 3.01 dB", lr.sample_peak(samples), -16.99, 0.02)
end

--------------------------------------------------------------------------------
T.suite("Inversion recovers level from a gain factor")
--------------------------------------------------------------------------------
do
  -- A source 3 dB below the target needs a gain factor > 1 (10^(3/20) ≈ 1.413).
  -- Inverting it must bring the level back to the known -26 dBFS (RMS target
  -- -23). This is SPEC-0001's whole risk: gain round-trips to level.
  local known_rms = -26.0
  local rms_target = -23.0
  local gain = lr.expected_gain(known_rms, rms_target)
  T.near("gain for a 3 dB-quiet source is ~1.413", gain, 1.4125, 0.0005)
  T.near("inversion recovers the RMS level", lr.recover_level(gain, rms_target), known_rms, 0.01)
end

--------------------------------------------------------------------------------
T.suite("Inversion recovers a reference tone's known level")
--------------------------------------------------------------------------------
do
  -- The end-to-end shape of the spike, and the one case here that could actually
  -- fail if the inversion were wrong: synthesise a tone at a KNOWN level, derive
  -- the normalization gain numerically, invert it, and land back on that level.
  -- Nothing in this block uses expected_gain to produce the gain it inverts.
  local known_rms = -20.0
  local samples = lr.sine(known_rms, 4410, 44100) -- 44 whole cycles of 440 Hz
  local target = -23.0
  local gain = gain_by_search(samples, target)

  -- Known -20 sits 3 dB ABOVE a -23 target, so normalizing must cut: 10^(-3/20).
  T.near("searched gain cuts a source 3 dB above target", gain, 0.70795, 0.0005)
  T.near("inversion recovers the tone's known -20 dBFS",
    lr.recover_level(gain, target), known_rms, 0.01)
  -- Only now is the closed form validated, against a gain derived without it.
  T.near("expected_gain agrees with the searched gain",
    lr.expected_gain(known_rms, target), gain, 0.0001)
end

--------------------------------------------------------------------------------
T.suite("Quieter and louder sources round-trip at the extremes")
--------------------------------------------------------------------------------
do
  local cases = {
    { rms = -12.0, target = -23.0 }, -- much louder than target -> gain < 1
    { rms = -30.0, target = -23.0 }, -- much quieter -> gain > 1
    { rms = -23.0, target = -23.0 }, -- exactly at target -> gain == 1
  }
  for _, c in ipairs(cases) do
    local gain = lr.expected_gain(c.rms, c.target)
    T.near("level " .. c.rms .. " recovers exactly",
      lr.recover_level(gain, c.target), c.rms, 0.000001)
  end
end

--------------------------------------------------------------------------------
T.suite("Gain sign convention is correct")
--------------------------------------------------------------------------------
do
  -- factor < 1 means the source must be cut, i.e. it is louder than the target;
  -- the recovered level is therefore ABOVE (less negative than) the target.
  local source_louder = lr.recover_level(0.5, -23.0) -- gain 0.5 = -6.0206 dB to cut
  T.near("a cut factor recovers a level above target", source_louder, -16.9794, 0.00001)

  -- factor > 1 means the source must be boosted, i.e. quieter than target.
  local source_quieter = lr.recover_level(2.0, -23.0)
  T.near("a boost factor recovers a level below target", source_quieter, -29.0206, 0.00001)
end

--------------------------------------------------------------------------------
T.suite("Sample peak recovery uses the same inversion")
--------------------------------------------------------------------------------
do
  local samples = lr.sine(-20.0, 44100, 44100)
  local peak = lr.sample_peak(samples)
  local target = -3.0 -- ACX sample peak limit
  local gain = lr.expected_gain(peak, target)
  T.near("peak gain is computed from the peak level", gain, 10 ^ ((-3 - peak) / 20), 0.000001)
  T.near("peak inversion recovers the peak level", lr.recover_level(gain, target), peak, 0.0000001)
end

--------------------------------------------------------------------------------
T.suite("The dB conversions match WDL's VAL2DB/DB2VAL")
--------------------------------------------------------------------------------
do
  -- Every figure in the module routes through this pair, so pin it directly
  -- rather than only through its callers.
  local val2db, db2val = lr._internal.val2db, lr._internal.db2val
  T.near("unity gain is 0 dB", val2db(1.0), 0.0, 1e-12)
  T.near("half amplitude is -6.02 dB", val2db(0.5), -6.0206, 0.0001)
  T.near("double amplitude is +6.02 dB", val2db(2.0), 6.0206, 0.0001)
  T.near("0 dB is unity gain", db2val(0.0), 1.0, 1e-12)
  T.near("-20 dB is a tenth of the amplitude", db2val(-20.0), 0.1, 1e-12)
  T.near("the pair round-trips", db2val(val2db(0.3333)), 0.3333, 1e-9)
end