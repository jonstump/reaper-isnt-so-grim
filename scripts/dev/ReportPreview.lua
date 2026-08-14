-- Development harness. Not shipped.
--
-- Renders the ACX Check report against stubbed measurements so the presentation
-- layer can be built and reviewed before the measurement layer exists
-- (blocked on the level-recovery spike, issue #9).
--
-- Run from Reaper: Actions → Load ReaScript → this file.
--
--   Space / n  next case
--   b          previous case
--   m          toggle monochrome — this is how SPEC-0001's colour-independence
--              criterion gets verified: in monochrome, pass and fail must still
--              be distinguishable by marker shape and status text alone
--   Esc        close

local sep = package.config:sub(1, 1)
local here = ({ reaper.get_action_context() })[2]:match("(.*" .. sep .. ")")
package.path = here .. ".." .. sep .. "?.lua;" .. here .. "?.lua;" .. package.path

local evaluate  = require("acx.evaluate")
local thresholds = require("acx.thresholds")
local report    = require("acx.report")
local fixtures  = require("dev.fixtures")

local index = 1
local monochrome = false

local function show()
  local case = fixtures.cases[index]
  local rows = evaluate.evaluate(case.measurements, thresholds.default)

  report.show(rows, {
    title = string.format("ACX Check — preview %d/%d", index, #fixtures.cases),
    subtitle = case.name .. "   ·   " .. case.note,
    footer = "space/n next   ·   b back   ·   m mono ("
      .. (monochrome and "on" or "off") .. ")   ·   Esc close",
    monochrome = monochrome,
    -- Mutate state and signal a restart. Do NOT call show() from here: that
    -- would open a new window which the outgoing loop then closes, so the
    -- fixture appears to switch and the window vanishes. report.show tears
    -- down first and re-enters via on_restart on its own frame.
    on_key = function(ch)
      if ch == 32 or ch == 110 then      -- space, n
        index = index % #fixtures.cases + 1
      elseif ch == 98 then                -- b
        index = (index - 2) % #fixtures.cases + 1
      elseif ch == 109 then               -- m
        monochrome = not monochrome
      else
        return nil
      end
      return "restart"
    end,
    on_restart = show,
  })
end

show()
