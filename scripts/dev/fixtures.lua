-- Stubbed measurements for previewing the report without a measurement layer.
--
-- These exist so SPEC-0001's presentation requirements can be built and eyeballed
-- before the level-recovery spike (issue #9) settles how measurements are
-- actually produced. Nothing here ships — the ReaPack package lists scripts/acx/
-- and the entry point, not scripts/dev/.

local M = {}

M.cases = {
  {
    name = "PLAN.md worked example — gain blocked by peak headroom",
    note = "1.6 dB short on RMS with only 1.1 dB of headroom. Must NOT say 'raise gain'.",
    measurements = {
      rms = -24.6,
      peak = -4.1,
      noise_floor = -58.3,
      noise_region = { start_sec = 12.4, end_sec = 13.1 },
    },
  },
  {
    name = "All passing",
    note = "Every row should state its margin rather than sitting blank.",
    measurements = {
      rms = -20.1,
      peak = -6.4,
      noise_floor = -67.8,
      noise_region = { start_sec = 3.0, end_sec = 3.8 },
    },
  },
  {
    name = "RMS low with ample headroom — gain is safe",
    note = "3 dB short, 9 dB of headroom. A gain figure is the right advice here.",
    measurements = {
      rms = -26.0,
      peak = -12.0,
      noise_floor = -70.2,
      noise_region = { start_sec = 0.5, end_sec = 1.4 },
    },
  },
  {
    name = "Too hot — RMS and peak both over",
    note = "Peak failing outright, plus a true-peak advisory line.",
    measurements = {
      rms = -16.4,
      peak = -1.8,
      true_peak = -0.9,
      noise_floor = -64.0,
      noise_region = { start_sec = 41.2, end_sec = 42.0 },
    },
  },
  {
    name = "Noise floor unavailable — source too short",
    note = "Per-row degradation: RMS and peak still report.",
    measurements = {
      rms = -20.8,
      peak = -5.2,
      noise_floor = nil,
      unavailable = { noise_floor = "source shorter than minimum room-tone window" },
    },
  },
  {
    name = "Peak unavailable — gain advice must not imply safety",
    note = "Hint states the gain but flags that peak could not be confirmed.",
    measurements = {
      rms = -26.0,
      peak = nil,
      noise_floor = -70.0,
      noise_region = { start_sec = 8.0, end_sec = 8.9 },
      unavailable = { peak = "measurement call failed" },
    },
  },
}

return M
