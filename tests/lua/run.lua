-- Minimal Lua test runner. No dependencies — plain Lua, per ADR-0003's rule
-- that development tooling is unconstrained but must never be imported by
-- shipped code. Nothing under scripts/ requires anything from here.
--
-- Run from the repository root:
--   lua tests/lua/run.lua

package.path = "./scripts/?.lua;./scripts/?/init.lua;" .. package.path

local passed, failed = 0, 0
local failures = {}
local current_suite = "?"

local T = {}

function T.suite(name)
  current_suite = name
  io.write("\n", name, "\n")
end

function T.check(desc, ok, detail)
  if ok then
    passed = passed + 1
    io.write("  ok   ", desc, "\n")
  else
    failed = failed + 1
    failures[#failures + 1] = string.format("%s → %s%s", current_suite, desc,
      detail and ("\n       " .. detail) or "")
    io.write("  FAIL ", desc, "\n")
    if detail then io.write("       ", detail, "\n") end
  end
end

function T.eq(desc, actual, expected)
  T.check(desc, actual == expected,
    string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

function T.near(desc, actual, expected, tol)
  tol = tol or 0.05
  local ok = type(actual) == "number" and math.abs(actual - expected) <= tol
  T.check(desc, ok,
    string.format("expected %s (±%s), got %s", tostring(expected), tostring(tol), tostring(actual)))
end

function T.contains(desc, haystack, needle)
  local ok = type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
  T.check(desc, ok, string.format("expected to contain %q, got %q", needle, tostring(haystack)))
end

function T.not_contains(desc, haystack, needle)
  local ok = type(haystack) == "string" and haystack:find(needle, 1, true) == nil
  T.check(desc, ok, string.format("expected NOT to contain %q, got %q", needle, tostring(haystack)))
end

_G.T = T

local suites = {
  "tests.lua.test_evaluate",
  "tests.lua.test_report",
  "tests.lua.test_level_recovery",
  "tests.lua.test_measure",
  "tests.lua.test_error",
  "tests.lua.test_source",
  "tests.lua.test_postrender",
}
for _, s in ipairs(suites) do
  require(s)
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
  io.write("\nFailures:\n")
  for _, f in ipairs(failures) do io.write("  - ", f, "\n") end
  os.exit(1)
end
os.exit(0)
