-- Tests for scripts/acx/error.lua (shared error surface).
--
-- SPEC-0001 REQ "Error Handling Standards": plain-language cause + corrective
-- action, nothing silently swallowed, raw API codes only as supplementary
-- detail. This module is the foundation surface stories #11/#12/#13 reuse.

local error_surface = require("acx.error")

--------------------------------------------------------------------------------
T.suite("Construction assembles a plain-language message")
--------------------------------------------------------------------------------
do
  local err = error_surface.new({
    cause = "the measurement call could not produce a level",
    fix = "rerun ACX Check",
  })
  T.contains("message names the cause", err.message, "could not produce a level")
  T.contains("message names the fix", err.message, "rerun ACX Check")
  T.contains("cause is preserved", err.cause, "measurement call")
  T.eq("fix is preserved", err.fix, "rerun ACX Check")
end

--------------------------------------------------------------------------------
T.suite("Detail is supplementary, never the primary message")
--------------------------------------------------------------------------------
do
  local err = error_surface.new({
    cause = "the source could not be decoded",
    detail = "API return 0x00000001",
  })
  T.not_contains("raw code is not the lead", err.message, "0x00000001")
  T.not_contains("raw code is not in message", err.message, "0x")
end

--------------------------------------------------------------------------------
T.suite("fail_if returns an error only when the condition fails")
--------------------------------------------------------------------------------
do
  local ok1, err1 = error_surface.fail_if(true, { cause = "unused" })
  T.check("passing condition yields no error", err1 == nil)

  local ok2, err2 = error_surface.fail_if(false, { cause = "a real problem" })
  T.check("failing condition yields the error", err2 ~= nil)
  T.contains("error cause surfaces", err2.message, "a real problem")
end

--------------------------------------------------------------------------------
T.suite("tostring renders a one-liner")
--------------------------------------------------------------------------------
do
  local err = error_surface.new({ cause = "something happened", fix = "try again" })
  T.eq("tostring is the message", error_surface.tostring(err), err.message)
  T.eq("nil renders empty", error_surface.tostring(nil), "")
end

--------------------------------------------------------------------------------
T.suite("Reasons for intentional suppression are documented, not lost")
--------------------------------------------------------------------------------
do
  -- The "documented reason for suppression" clause: when a failure is handled
  -- without being surfaced, the reason travels on the error object.
  local suppressed = error_surface.new({
    cause = "noise floor shorter than minimum window",
    doc = "suppressed because RMS and peak still report (per-row degradation)",
  })
  T.contains("suppression reason is documented", suppressed.doc, "per-row degradation")
end