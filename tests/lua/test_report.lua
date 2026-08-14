-- Tests for scripts/acx/report.lua against the mocked reaper/gfx globals.
--
-- These verify what was drawn, not how it looks. Layout arithmetic, primitive
-- selection per status, monochrome behaviour, and defer-loop exit conditions
-- are all checkable here. Visual correctness — font metrics, spacing, whether
-- the markers read clearly at a glance — still requires Reaper.

local mock = require("tests.lua.mock_reaper")
local evaluate = require("acx.evaluate")
local thresholds = require("acx.thresholds")

-- report.lua binds gfx/reaper at call time, not load time, but it must be
-- loaded fresh after the mock is installed to be safe about future changes.
local function load_report()
  package.loaded["acx.report"] = nil
  return require("acx.report")
end

local function rows_for(measurements)
  return (evaluate.evaluate(measurements, thresholds.default))
end

local PASSING  = { rms = -20.0, peak = -6.0, noise_floor = -68.0 }
local FAILING  = { rms = -24.6, peak = -4.1, noise_floor = -58.3 }
local WITH_NA  = { rms = -20.8, peak = -5.2, noise_floor = nil,
                   unavailable = { noise_floor = "source shorter than minimum window" } }

--- Render one frame and return the mock so tests can query it.
local function render(measurements, opts)
  mock.install({ keys = { 0 } }) -- one frame, then loop defers
  local report = load_report()
  report.show(rows_for(measurements), opts or {})
  return mock
end

--------------------------------------------------------------------------------
T.suite("Window is initialised with computed geometry")
--------------------------------------------------------------------------------
do
  local m = render(PASSING)
  local inits = m.ops("init")
  T.eq("gfx.init called exactly once", #inits, 1)
  T.eq("width is the fixed report width", inits[1].w, 760)
  T.check("height is positive and plausible",
    inits[1].h > 100 and inits[1].h < 800, tostring(inits[1].h))
  local h_no_detail = inits[1].h
  m.uninstall()

  -- A noise-floor region adds a detail line, which must grow the window.
  local m2 = render({ rms = -20.0, peak = -6.0, noise_floor = -68.0,
                      noise_region = { start_sec = 3.0, end_sec = 3.8 } })
  local h_with_detail = m2.ops("init")[1].h
  T.check("detail line increases window height",
    h_with_detail > h_no_detail,
    string.format("%d vs %d", h_with_detail, h_no_detail))
  m2.uninstall()
end

--------------------------------------------------------------------------------
T.suite("Every row's content reaches the screen")
--------------------------------------------------------------------------------
do
  local m = render(FAILING)

  for _, row in ipairs(rows_for(FAILING)) do
    T.check("label drawn: " .. row.label, m.drew_text(row.label) ~= nil)
    T.check("value drawn: " .. row.value_text, m.drew_text(row.value_text) ~= nil)
    T.check("hint drawn for " .. row.label, m.drew_text(row.hint) ~= nil)
  end

  T.check("allowed range is shown", m.drew_text("need -23 to -18") ~= nil)
  T.check("delta is shown", m.drew_text("-1.6 dB") ~= nil)
  m.uninstall()
end

--------------------------------------------------------------------------------
T.suite("Status text is present for every state")
--------------------------------------------------------------------------------
do
  local m = render(FAILING)
  T.check("FAIL text drawn", m.drew_text("FAIL") ~= nil)
  T.check("PASS text drawn", m.drew_text("PASS") ~= nil)
  m.uninstall()

  local m2 = render(WITH_NA)
  T.check("N/A text drawn for unavailable row", m2.drew_text("N/A") ~= nil)
  T.check("unavailable reason drawn", m2.drew_text("shorter than minimum") ~= nil)
  m2.uninstall()
end

--------------------------------------------------------------------------------
T.suite("Status markers are geometrically distinct")
--------------------------------------------------------------------------------
-- The marker is the channel that survives both greyscale and a font lacking
-- check/cross glyphs, so pass, fail, and unavailable must not draw the same
-- shape.
do
  -- All three fixtures put the state under test in row 1, so the same
  -- bounding box isolates the marker in every case.
  local NA_FIRST = { rms = nil, peak = -6.0, noise_floor = -68.0,
                     unavailable = { rms = "measurement call failed" } }

  local function first_marker_lines(measurements)
    local m = render(measurements)
    local ls = m.lines_in(18, 50, 20, 24)
    m.uninstall()
    return ls
  end

  local function signature(ls)
    local parts = {}
    for _, l in ipairs(ls) do
      parts[#parts + 1] = string.format("%.1f,%.1f>%.1f,%.1f", l.x1, l.y1, l.x2, l.y2)
    end
    return table.concat(parts, "|")
  end

  local pass_lines = first_marker_lines(PASSING)
  local fail_lines = first_marker_lines(FAILING)
  local na_lines   = first_marker_lines(NA_FIRST)

  T.check("pass marker draws primitives", #pass_lines > 0, tostring(#pass_lines))
  T.check("fail marker draws primitives", #fail_lines > 0, tostring(#fail_lines))
  T.check("unavailable marker draws primitives", #na_lines > 0, tostring(#na_lines))

  -- The requirement is that shape carries status, so all three must differ.
  -- Two identical shapes would mean colour and text were doing the work alone.
  local sp, sf, sn = signature(pass_lines), signature(fail_lines), signature(na_lines)
  T.check("pass and fail markers differ in shape", sp ~= sf)
  T.check("pass and unavailable markers differ in shape", sp ~= sn)
  T.check("fail and unavailable markers differ in shape", sf ~= sn)

  -- The unavailable marker is a flat dash — every stroke horizontal. This is
  -- the one shape claim strong enough to assert directly.
  local all_flat = true
  for _, l in ipairs(na_lines) do
    if math.abs(l.y2 - l.y1) > 0.001 then all_flat = false end
  end
  T.check("unavailable marker is horizontal strokes only", all_flat)

  -- Pass and fail both use diagonals, so neither is flat.
  local function any_diagonal(ls)
    for _, l in ipairs(ls) do
      if math.abs(l.y2 - l.y1) > 0.001 and math.abs(l.x2 - l.x1) > 0.001 then
        return true
      end
    end
    return false
  end
  T.check("pass marker uses diagonal strokes", any_diagonal(pass_lines))
  T.check("fail marker uses diagonal strokes", any_diagonal(fail_lines))
end

--------------------------------------------------------------------------------
T.suite("Monochrome mode removes hue entirely")
--------------------------------------------------------------------------------
do
  local m = render(FAILING, { monochrome = true })
  local ok, offender = m.all_colours_grey()
  T.check("every colour set in monochrome mode is a pure grey", ok,
    offender and string.format("r=%s g=%s b=%s", offender.r, offender.g, offender.b))
  -- Status must still be readable without hue.
  T.check("PASS still drawn in monochrome", m.drew_text("PASS") ~= nil)
  T.check("FAIL still drawn in monochrome", m.drew_text("FAIL") ~= nil)
  T.check("markers still drawn in monochrome", #m.lines() > 0)
  m.uninstall()

  local m2 = render(FAILING, { monochrome = false })
  T.check("colour mode does use hue", m2.has_chromatic_colour())
  m2.uninstall()
end

--------------------------------------------------------------------------------
T.suite("Header, subtitle, and footer render")
--------------------------------------------------------------------------------
do
  local m = render(PASSING, {
    title = "ACX Check — preview 1/6",
    subtitle = "All passing",
    footer = "Esc close",
  })
  T.check("title drawn", m.drew_text("ACX Check") ~= nil)
  T.check("subtitle drawn", m.drew_text("All passing") ~= nil)
  T.check("footer drawn", m.drew_text("Esc close") ~= nil)
  m.uninstall()
end

--------------------------------------------------------------------------------
T.suite("The report persists until dismissed")
--------------------------------------------------------------------------------
do
  mock.install({ keys = { 0, 0, 0 } })
  local report = load_report()
  report.show(rows_for(PASSING), {})
  local frames = mock.pump(5)
  T.check("loop keeps deferring while no key is pressed", frames >= 3, tostring(frames))
  T.eq("no quit while idle", mock.count("quit"), 0)
  T.check("still pending after idle frames", mock.pending())
  mock.uninstall()
end

--------------------------------------------------------------------------------
T.suite("Escape and window close both dismiss")
--------------------------------------------------------------------------------
do
  mock.install({ keys = { 0, 27 } })
  local report = load_report()
  report.show(rows_for(PASSING), {})
  mock.pump(5)
  T.eq("Escape quits", mock.count("quit"), 1)
  T.check("no further frames scheduled", not mock.pending())
  mock.uninstall()

  mock.install({ keys = { 0, -1 } })
  local report2 = load_report()
  report2.show(rows_for(PASSING), {})
  mock.pump(5)
  T.eq("window close quits", mock.count("quit"), 1)
  T.check("no further frames scheduled after close", not mock.pending())
  mock.uninstall()
end

--------------------------------------------------------------------------------
T.suite("on_close fires exactly once on dismissal")
--------------------------------------------------------------------------------
do
  mock.install({ keys = { 0, 27 } })
  local report = load_report()
  local closed = 0
  report.show(rows_for(PASSING), { on_close = function() closed = closed + 1 end })
  mock.pump(5)
  T.eq("on_close called once", closed, 1)
  mock.uninstall()
end

--------------------------------------------------------------------------------
T.suite("Restart handoff quits once and re-enters on a later frame")
--------------------------------------------------------------------------------
-- The preview harness swaps fixtures from a key handler. Doing that by calling
-- show() from inside on_key would re-init a window and then have the outgoing
-- loop quit it, closing the window the user just asked for. The restart
-- contract exists so exactly one quit happens and re-entry lands on its own
-- frame.
do
  mock.install({ keys = { 0, 32 } }) -- idle frame, then space
  local report = load_report()
  local restarts = 0

  report.show(rows_for(PASSING), {
    on_key = function(ch)
      if ch == 32 then return "restart" end
      return nil
    end,
    on_restart = function() restarts = restarts + 1 end,
  })
  mock.pump(5)

  T.eq("exactly one quit for the restart", mock.count("quit"), 1)
  T.eq("on_restart invoked once", restarts, 1)
  T.eq("no second window opened by the outgoing loop", mock.count("init"), 1)
  mock.uninstall()
end

--------------------------------------------------------------------------------
T.suite("Unhandled keys do not dismiss the report")
--------------------------------------------------------------------------------
do
  mock.install({ keys = { 0, 120, 0 } }) -- 'x', which nothing handles
  local report = load_report()
  report.show(rows_for(PASSING), { on_key = function(_) return nil end })
  mock.pump(5)
  T.eq("unknown key does not quit", mock.count("quit"), 0)
  mock.uninstall()
end

--------------------------------------------------------------------------------
T.suite("A frame is painted before anything is drawn over it")
--------------------------------------------------------------------------------
do
  local m = render(PASSING)
  local log = m.log()
  local first_rect, first_text
  for i, e in ipairs(log) do
    if e.op == "rect" and not first_rect then first_rect = i end
    if e.op == "drawstr" and not first_text then first_text = i end
  end
  T.check("a background rect is drawn", first_rect ~= nil)
  T.check("background precedes the first text", first_rect and first_text
    and first_rect < first_text)
  T.check("gfx.update is called after drawing", m.count("update") >= 1)
  m.uninstall()
end
