-- SPDX-License-Identifier: MIT
-- Governing: SPEC-0001 REQ "Threshold Configuration"
--
-- ACX's delivery specifications, in one place, deliberately separate from
-- measurement and reporting logic. Changing a value here MUST NOT require
-- touching anything else.
--
-- These are ACX's published numbers. Reference request item E5 asks whether
-- the narrator delivers to ACX or to a publisher with its own spec sheet; if
-- the answer is the latter, this table is the only thing that changes.

local M = {}

M.acx = {
  rms = {
    label = "RMS level",
    min = -23.0, -- dBFS, inclusive
    max = -18.0, -- dBFS, inclusive
  },
  peak = {
    label = "Peak level",
    max = -3.0, -- dBFS, inclusive
  },
  noise_floor = {
    label = "Noise floor",
    max = -60.0, -- dBFS, inclusive
  },
}

-- How much higher true peak must read than sample peak before the report
-- mentions it. Too low and the advisory line becomes permanent noise; too
-- high and it never appears when it matters. Open question in design.md.
M.acx.true_peak_advisory_margin = 0.3 -- dB

-- Values are compared with a small tolerance so a measurement sitting exactly
-- on a boundary reads as passing, per the spec's "inclusive" wording, rather
-- than failing to floating-point representation.
M.epsilon = 0.001

M.default = M.acx

return M
