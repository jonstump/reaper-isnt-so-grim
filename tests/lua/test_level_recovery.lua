-- Spike 9: headless validation of the level-recovery inversion math.
--
-- These pin the pure-math half of the spike: given a known level, the gain
-- factor CalculateNormalization should return, and given that factor, the
-- inversion must recover the original level. The empirical half — confirming
-- Reaper actually returns that factor — requires Reaper and is documented in
-- scripts/dev/level_recovery.lua and docs/spikes/issue-9.md.

local lr = require("dev.level_recovery")

local function round1(x)
  return math.floor(x * 10 + 0.5) / 10
end

--------------------------------------------------------------------------------
T.suite("Reference tones are internally consistent")
--------------------------------------------------------------------------------
do
  -- A pure sine's peak exceeds its RMS by 3.01 dB. The synthesizer must honour
  -- this, and both the RMS and peak metering must agree with the requested level.
  local samples = lr.sine(-20.0, 44100, 44100)
  T.suite("Reference tones are internally consistent")
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
T.suite("Inversion round-trips through a real reference tone")
--------------------------------------------------------------------------------
do
  -- Synthesise a tone, measure it (as a stand-in for CalculateNormalization),
  -- "normalize" to a target by computing the gain, then recover. The recovered
  -- level must equal the measured level within tolerance.
  local samples = lr.sine(-20.0, 44100, 44100)
  local measured_rms = lr.rms(samples)
  local rms_target = -23.0
  local gain = lr.expected_gain(measured_rms, rms_target)
  local recovered = lr.recover_level(gain, rms_target)
  T.near("recovered RMS matches measured RMS", recovered, measured_rms, 0.0001)
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