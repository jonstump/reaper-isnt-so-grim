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
  local message = opts.cause
  if opts.fix then message = message .. ". " .. opts.fix end
  return {
    message = message,
    cause = opts.cause,
    fix = opts.fix,
    detail = opts.detail,
    doc = opts.doc,
  }
end

-- Assert a condition or return an error object; used to fail fast and plainly.
-- @param ok     boolean  condition that must hold
-- @param opts   table    passed to M.new on failure
-- @return nil, error-table|nil (if ok)  -- returns the error only when failing
function M.fail_if(ok, opts)
  if not ok then return nil, M.new(opts) end
  return nil, nil
end

-- Human-readable one-liner for logging or status bars.
function M.tostring(err)
  return err and err.message or ""
end

M._internal = {}

return M