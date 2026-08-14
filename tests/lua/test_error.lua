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
T.suite("A malformed error is still an error, never a crash")
--------------------------------------------------------------------------------
do
  -- The surface must not be the thing that fails. Raising here would swap the
  -- failure being reported for a traceback that buries it, so a missing cause
  -- degrades to a stand-in message instead. Regression: passing a fix with no
  -- cause used to raise "attempt to concatenate a nil value".
  local ok, fix_only = pcall(error_surface.new, { fix = "update Reaper to 6.44" })
  T.check("a fix without a cause does not raise", ok)
  T.check("the fix still reaches the message", ok and fix_only.message:find("6.44", 1, true) ~= nil)
  T.check("a stand-in cause is supplied", ok and fix_only.cause ~= nil)

  -- No error may render as an empty string: a blank failure is a swallowed one.
  local empty = error_surface.new({})
  T.check("an empty error still has a message", empty.message ~= nil and empty.message ~= "")
  T.check("tostring is never blank", error_surface.tostring(empty) ~= "")

  local nothing = error_surface.new()
  T.check("no arguments at all still yields a message", nothing.message ~= nil and nothing.message ~= "")

  -- A blank string is as absent as nil, and must not become the message.
  local blank = error_surface.new({ cause = "", fix = "retry" })
  T.eq("an empty cause is treated as missing", blank.cause, error_surface._internal.UNSPECIFIED)
  T.check("the fix survives a blank cause", blank.message:find("retry", 1, true) ~= nil)

  -- A blank fix must not leave a dangling separator.
  local no_fix = error_surface.new({ cause = "something broke", fix = "" })
  T.eq("a blank fix is dropped entirely", no_fix.message, "something broke")
end

--------------------------------------------------------------------------------
T.suite("fail_if reports whether the condition held")
--------------------------------------------------------------------------------
do
  local held1, err1 = error_surface.fail_if(true, { cause = "unused" })
  T.check("passing condition yields no error", err1 == nil)
  T.eq("passing condition reports true", held1, true)

  local held2, err2 = error_surface.fail_if(false, { cause = "a real problem" })
  T.check("failing condition yields the error", err2 ~= nil)
  T.eq("failing condition reports false", held2, false)
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