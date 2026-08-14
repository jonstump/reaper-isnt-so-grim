-- Text rendering of every fixture case, so hint wording and delta arithmetic
-- can be reviewed without Reaper. Development only.
--
--   lua tests/lua/preview.lua

package.path = "./scripts/?.lua;" .. package.path

local evaluate = require("acx.evaluate")
local thresholds = require("acx.thresholds")
local fixtures = require("dev.fixtures")

local MARK = { pass = "[ok]", fail = "[XX]", unavailable = "[--]" }
local STATE = { pass = "PASS", fail = "FAIL", unavailable = "N/A" }

for i, case in ipairs(fixtures.cases) do
  local rows, all_passed = evaluate.evaluate(case.measurements, thresholds.default)

  print(string.rep("=", 78))
  print(string.format("%d. %s", i, case.name))
  print("   " .. case.note)
  print(string.rep("-", 78))

  for _, row in ipairs(rows) do
    print(string.format("%-5s %-12s %-10s %-22s %-9s %s",
      MARK[row.status], row.label, row.value_text or "",
      row.limit_text ~= "" and ("(" .. row.limit_text .. ")") or "",
      row.delta_text or "", STATE[row.status]))
    print(string.format("      %s", row.hint or ""))
    if row.detail then print(string.format("      %s", row.detail)) end
  end

  print(string.format("\n   overall: %s\n", all_passed and "PASS" or "FAIL"))
end
