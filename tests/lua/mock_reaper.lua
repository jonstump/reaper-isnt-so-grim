-- Mock `reaper` and `gfx` globals so ReaScript UI code can be exercised
-- without Reaper. Development only — nothing under scripts/ requires this.
--
-- Records every drawing call so tests can assert on what was drawn, in what
-- colour, and in what order. This cannot tell you whether a report *looks*
-- right; it can tell you that the right primitives were emitted, that layout
-- arithmetic is sane, that the defer loop exits when it should, and that
-- monochrome mode is genuinely monochrome.
--
-- Behavioural fidelity notes:
--   * gfx.getchar() returns queued keys, then 0 forever — matching Reaper,
--     where 0 means "window open, no key". Loops are bounded by pump()'s
--     frame cap rather than by the queue running dry.
--   * reaper.defer(f) stores f; pump() runs it. One pump iteration is one
--     frame.

local M = {}

local log, keys, deferred, colour, saved

local function snapshot_colour()
  return { colour[1], colour[2], colour[3], colour[4] }
end

function M.install(opts)
  opts = opts or {}
  log = {}
  keys = {}
  for i, k in ipairs(opts.keys or {}) do keys[i] = k end
  deferred = nil
  colour = { 1, 1, 1, 1 }
  saved = { gfx = _G.gfx, reaper = _G.reaper }

  local gfx = { x = 0, y = 0, w = 0, h = 0, mode = 0, clear = 0 }

  function gfx.init(name, w, h, dock, x, y)
    gfx.w, gfx.h = w, h
    log[#log + 1] = { op = "init", name = name, w = w, h = h, dock = dock }
  end

  function gfx.setfont(idx, face, size, flags)
    log[#log + 1] = { op = "setfont", idx = idx, face = face, size = size }
  end

  function gfx.set(r, g, b, a)
    colour = { r, g, b, a or 1 }
    log[#log + 1] = { op = "set", r = r, g = g, b = b, a = a }
  end

  function gfx.rect(x, y, w, h, filled)
    log[#log + 1] = { op = "rect", x = x, y = y, w = w, h = h,
                      filled = filled, colour = snapshot_colour() }
  end

  function gfx.line(x1, y1, x2, y2, aa)
    log[#log + 1] = { op = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2,
                      colour = snapshot_colour() }
  end

  function gfx.drawstr(s)
    log[#log + 1] = { op = "drawstr", x = gfx.x, y = gfx.y,
                      text = s, colour = snapshot_colour() }
  end

  function gfx.measurestr(s)
    return #tostring(s) * 7, 15
  end

  function gfx.getchar()
    if #keys > 0 then return table.remove(keys, 1) end
    return 0 -- window open, no key pressed
  end

  function gfx.update() log[#log + 1] = { op = "update" } end
  function gfx.quit()   log[#log + 1] = { op = "quit" }   end

  local reaper = {}

  function reaper.defer(f) deferred = f end

  function reaper.get_action_context()
    return true, "/mock/scripts/dev/Script.lua", 0, 0, 0, 0, 0
  end

  function reaper.ShowConsoleMsg(s)
    log[#log + 1] = { op = "console", text = s }
  end

  _G.gfx = gfx
  _G.reaper = reaper
end

function M.uninstall()
  if saved then
    _G.gfx, _G.reaper = saved.gfx, saved.reaper
    saved = nil
  end
end

--- Run deferred frames. Returns the number of frames actually run.
function M.pump(max)
  max = max or 20
  local n = 0
  while deferred and n < max do
    local f = deferred
    deferred = nil
    f()
    n = n + 1
  end
  return n
end

function M.pending() return deferred ~= nil end
function M.log() return log end
function M.push_keys(t) for _, k in ipairs(t) do keys[#keys + 1] = k end end

---------------------------------------------------------------------------
-- Query helpers
---------------------------------------------------------------------------

local function filter(op)
  local out = {}
  for _, e in ipairs(log) do
    if e.op == op then out[#out + 1] = e end
  end
  return out
end

function M.ops(op) return filter(op) end
function M.texts() return filter("drawstr") end
function M.lines() return filter("line") end

function M.count(op) return #filter(op) end

--- True if any drawn string contains `needle`.
function M.drew_text(needle)
  for _, e in ipairs(filter("drawstr")) do
    if type(e.text) == "string" and e.text:find(needle, 1, true) then return e end
  end
  return nil
end

--- All lines drawn within a bounding box, useful for isolating one status
--- marker from the rest of the frame.
function M.lines_in(x, y, w, h)
  local out = {}
  for _, e in ipairs(filter("line")) do
    if e.x1 >= x and e.x1 <= x + w and e.y1 >= y and e.y1 <= y + h then
      out[#out + 1] = e
    end
  end
  return out
end

--- True when every colour used in the frame is a pure grey. This is the
--- automated half of SPEC-0001's colour-independence criterion — it proves
--- the monochrome path really removes hue, so a human check in that mode is
--- a genuine test of the remaining channels rather than a formality.
function M.all_colours_grey(tol)
  tol = tol or 0.0001
  for _, e in ipairs(log) do
    if e.op == "set" then
      if math.abs(e.r - e.g) > tol or math.abs(e.g - e.b) > tol then
        return false, e
      end
    end
  end
  return true
end

--- True when at least one colour has a visible hue.
function M.has_chromatic_colour(tol)
  tol = tol or 0.0001
  for _, e in ipairs(log) do
    if e.op == "set" then
      if math.abs(e.r - e.g) > tol or math.abs(e.g - e.b) > tol then return true end
    end
  end
  return false
end

return M
