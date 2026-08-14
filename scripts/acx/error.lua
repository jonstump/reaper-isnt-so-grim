-- Governing: SPEC-0001 REQ "Error Handling Standards", ADR-0004 (stock Reaper DSP)
--
-- Shared error surface for the ACX Check capability. Foundation concern, not a
-- per-story one — stories #11 (source resolution), #12 (report), and #13
-- (post-render invocation) all surface failures through this module so the
-- plain-language rules below hold everywhere.
--
-- Rules (SPEC-0001 REQ "Error Handling Standards"):
--   * Every failure is surfaced with a cause and, where one exists, a
--     corrective action.
--   * Nothing is silently swallowed: either report it, or pass a documented
--     reason for suppression.
--   * Raw API return codes are never the primary message; they may appear as
--     supplementary detail.
--   * A measurement that fails must not be fabricated or partially reported.

local M = {}

-- Stand-in cause for a caller that omits one. A missing cause is itself a defect
-- worth seeing, but it is reported rather than raised: raising here would replace
-- the failure being reported with a traceback that hides it, which is the exact
-- opposite of what this module exists to do. The message is always non-empty, so
-- no failure can render as a blank string and vanish.
local UNSPECIFIED = "an unspecified failure occurred"

local function text(value)
  return (type(value) == "string" and value ~= "") and value or nil
end

-- Build a plain-language error object from structured parts.
-- @param opts {
--   cause    = "the installed Reaper (6.44.0) does not provide CalculateNormalization",
--   fix      = "update Reaper to 6.44 or newer and run ACX Check again",  (optional)
--   detail   = "API return code 0x1",                                     (optional)
--   doc      = "reason suppression is intentional",                       (optional)
-- }
-- @return { message = "text", cause = ..., fix = ..., detail = ..., doc = ... }
function M.new(opts)
  opts = opts or {}
  local cause = text(opts.cause) or UNSPECIFIED
  local fix = text(opts.fix)
  return {
    message = fix and (cause .. ". " .. fix) or cause,
    cause = cause,
    fix = fix,
    detail = opts.detail,
    doc = opts.doc,
  }
end

-- Assert a condition or return an error object; used to fail fast and plainly.
-- @param ok     boolean  condition that must hold
-- @param opts   table    passed to M.new on failure
-- @return boolean held, error-table|nil  -- the error is present only on failure
function M.fail_if(ok, opts)
  if not ok then return false, M.new(opts) end
  return true, nil
end

-- Human-readable one-liner for logging or status bars.
function M.tostring(err)
  return err and err.message or ""
end

-- Exposed for tests.
M._internal = { UNSPECIFIED = UNSPECIFIED, text = text }

return M