-- Governing: SPEC-0001 REQ "Report Presentation"
-- Governing: SPEC-0001 REQ "Status Indication Without Reliance on Colour"
-- Governing: ADR-0004 (gfx report surface, chosen over ReaImGui to avoid an extension)
--
-- Renders evaluated rows in a gfx window. Stock Reaper only — no ReaImGui,
-- no js_ReaScriptAPI, per ADR-0003.
--
-- Status is carried by three independent channels: a marker drawn from
-- primitives, a text label, and colour. Colour is an accelerator, never the
-- carrier — red/green deficiency affects roughly one in twelve men and
-- pass/fail is this report's primary signal. The marker is drawn with lines
-- rather than a font glyph so it cannot fail to render on a font that lacks
-- check and cross characters.

local M = {}

local W = 760
local PAD = 20
local HEADER_H = 52
local FOOTER_H = 30
local LINE_H = 20
local MARKER = 14

local function luminance(c)
  return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

local PALETTE = {
  bg          = { 0.11, 0.12, 0.13 },
  rule        = { 0.24, 0.25, 0.27 },
  text        = { 0.91, 0.92, 0.93 },
  text_dim    = { 0.62, 0.64, 0.66 },
  text_faint  = { 0.45, 0.47, 0.49 },
  pass        = { 0.31, 0.78, 0.44 },
  fail        = { 0.93, 0.37, 0.33 },
  unavailable = { 0.78, 0.70, 0.38 },
}

local STATUS = {
  pass        = { colour = "pass",        text = "PASS" },
  fail        = { colour = "fail",        text = "FAIL" },
  unavailable = { colour = "unavailable", text = "N/A"  },
}

local mono = false

local function set(name, alpha)
  local c = PALETTE[name] or PALETTE.text
  if mono then
    local l = luminance(c)
    gfx.set(l, l, l, alpha or 1)
  else
    gfx.set(c[1], c[2], c[3], alpha or 1)
  end
end

local function text_at(x, y, s, colour)
  set(colour or "text")
  gfx.x, gfx.y = x, y
  gfx.drawstr(s or "")
end

-- Status markers drawn from line primitives. Shape is the channel that
-- survives both greyscale and a font without check/cross glyphs.
local function draw_marker(x, y, status)
  set(STATUS[status] and STATUS[status].colour or "text_dim")
  local s = MARKER
  if status == "pass" then
    -- Check: short down-stroke, long up-stroke.
    gfx.line(x + 1,          y + s * 0.55, x + s * 0.40, y + s - 2, true)
    gfx.line(x + s * 0.40,   y + s - 2,    x + s - 1,    y + 1,     true)
    gfx.line(x + 1,          y + s * 0.55 + 1, x + s * 0.40, y + s - 1, true)
    gfx.line(x + s * 0.40,   y + s - 1,    x + s - 1,    y + 2,     true)
  elseif status == "fail" then
    -- Cross: two diagonals, doubled for weight.
    gfx.line(x + 1, y + 1, x + s - 1, y + s - 1, true)
    gfx.line(x + 2, y + 1, x + s - 1, y + s - 2, true)
    gfx.line(x + s - 1, y + 1, x + 1, y + s - 1, true)
    gfx.line(x + s - 2, y + 1, x + 1, y + s - 2, true)
  else
    -- Dash: unambiguously neither of the other two.
    gfx.line(x + 1, y + s * 0.5, x + s - 1, y + s * 0.5, true)
    gfx.line(x + 1, y + s * 0.5 + 1, x + s - 1, y + s * 0.5 + 1, true)
  end
end

local function row_height(row)
  local h = LINE_H * 2 + 6 -- headline + hint
  if row.detail then h = h + LINE_H end
  return h + 8
end

local function draw_row(row, y)
  local x = PAD
  draw_marker(x, y + 3, row.status)

  local col_label = x + MARKER + 12
  local col_value = col_label + 96
  local col_limit = col_value + 84
  local col_delta = col_limit + 132
  local col_state = W - PAD - 44

  text_at(col_label, y, row.label, "text")
  text_at(col_value, y, row.value_text or "", "text")
  text_at(col_limit, y, row.limit_text and ("(" .. row.limit_text .. ")") or "", "text_dim")
  if row.delta_text and row.delta_text ~= "" then
    text_at(col_delta, y, row.delta_text, row.status == "fail" and "fail" or "text_dim")
  end

  local st = STATUS[row.status] or STATUS.unavailable
  text_at(col_state, y, st.text, st.colour)

  -- Hint on its own line so a long recommendation never truncates.
  text_at(col_label, y + LINE_H + 3, row.hint or "", "text_dim")

  if row.detail then
    text_at(col_label, y + LINE_H * 2 + 3, row.detail, "text_faint")
  end
end

--- Show the report.
-- @param rows       table    output of acx.evaluate
-- @param opts       table    { title, subtitle, footer, monochrome }
function M.show(rows, opts)
  opts = opts or {}
  mono = opts.monochrome or false

  local h = HEADER_H + FOOTER_H
  for _, row in ipairs(rows) do h = h + row_height(row) end

  gfx.init(opts.title or "ACX Check", W, h, 0)
  gfx.setfont(1, "", 15)

  local function draw()
    set("bg")
    gfx.rect(0, 0, W, h, true)

    text_at(PAD, 14, opts.title or "ACX Check", "text")
    if opts.subtitle then
      text_at(PAD, 32, opts.subtitle, "text_faint")
    end

    set("rule")
    gfx.line(PAD, HEADER_H - 8, W - PAD, HEADER_H - 8, false)

    local y = HEADER_H
    for _, row in ipairs(rows) do
      draw_row(row, y)
      y = y + row_height(row)
    end

    set("rule")
    gfx.line(PAD, y + 2, W - PAD, y + 2, false)
    text_at(PAD, y + 10, opts.footer or "Esc to close", "text_faint")
  end

  -- Persists until dismissed; no timer, per REQ "Report Presentation".
  local function loop()
    local ch = gfx.getchar()
    if ch == -1 or ch == 27 then -- window closed, or Escape
      gfx.quit()
      if opts.on_close then opts.on_close() end
      return
    end
    if opts.on_key and ch > 0 then
      local handled = opts.on_key(ch)
      if handled == "quit" then gfx.quit() return end
    end
    draw()
    gfx.update()
    reaper.defer(loop)
  end

  loop()
end

M._internal = { luminance = luminance, palette = PALETTE, status = STATUS }

return M
