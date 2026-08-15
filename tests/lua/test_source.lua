-- Tests for scripts/acx/source.lua (input resolution and noise-floor region).
--
-- These trace to the WHEN/THEN pairs of SPEC-0001 REQ "Input Resolution",
-- REQ "Noise Floor Region Determination", REQ "Read-Only Operation", and
-- REQ "Analysis Performance", exercised against a stubbed `reaper` table.
--
-- What is provable headless: that both entry points converge on one source,
-- that every failure names its constraint, that a time selection wins over the
-- scan, that the ranking finds the quietest window, and — via the strict stub
-- below — that no mutating Reaper call is ever made. What is not: that
-- PCM_Source_GetPeaks lays its buffer out the way read_peaks assumes, and that
-- a real 60-minute file measures inside five seconds. Both need Reaper and are
-- tracked on epic #8, the way spike 9's empirical half was.

local source = require("acx.source")

--------------------------------------------------------------------------------
-- A `reaper` stub that fails the test on any call that could change the project.
--
-- The read-only requirement is the one that cannot be satisfied by reading the
-- code and believing it, so the stub inverts the burden: any name that looks
-- like a mutation is a violation unless it was explicitly allowed. That catches
-- a future edit reaching for SetEditCurPos far more reliably than a reviewer does.
--------------------------------------------------------------------------------
local MUTATING_PREFIX = { "Set", "Undo_", "Main_On", "Insert", "Delete", "Apply", "Move", "Update" }

local function is_mutating(name)
  for _, prefix in ipairs(MUTATING_PREFIX) do
    if name:sub(1, #prefix) == prefix then return true end
  end
  return false
end

-- @param api    table  the read-only calls this test wants to answer
-- @return table reaper, table violations (appended to on any mutating access)
local function strict_reaper(api)
  local violations = {}
  local guard = setmetatable(api or {}, {
    __index = function(_, name)
      if is_mutating(name) then
        return function()
          violations[#violations + 1] = name
          return 0
        end
      end
      return nil
    end,
  })
  return guard, violations
end

-- A minimal readable source: length in seconds, and a token standing in for the
-- PCM_source pointer.
local function fake_source(length)
  return { token = "PCM_source", length = length }
end

-- A `PCM_Source_GetPeaks` stub that records the (starttime, bucket count) it was
-- called with -- so a test can assert read_peaks asked for the right range --
-- and fills a quiet window at bucket indices [quiet_from, quiet_to), 1-based
-- and relative to whatever starttime the scan itself used, everywhere else at
-- `loud`. Pass quiet_from = nil to skip the quiet window and return `loud`
-- throughout.
local function fake_peaks_reader(quiet_from, quiet_to, loud, quiet)
  local calls = {}
  local function get_peaks(_, rate, starttime, numchannels, numsamples, _want_extra, buf)
    calls[#calls + 1] = { rate = rate, starttime = starttime, channels = numchannels, buckets = numsamples }
    local values = {}
    for b = 1, numsamples do
      local v = (quiet_from and b >= quiet_from and b < quiet_to) and quiet or loud
      for c = 0, numchannels - 1 do
        values[(b - 1) * numchannels + c + 1] = v
        values[numsamples * numchannels + (b - 1) * numchannels + c + 1] = -v
      end
    end
    buf.table = function() return values end
    return numsamples
  end
  return get_peaks, calls
end

local function reading_reaper(opts)
  opts = opts or {}
  local destroyed = {}
  local api = {
    CountSelectedMediaItems = function() return opts.selected or 0 end,
    GetSelectedMediaItem = function() return opts.item end,
    GetActiveTake = function() return opts.take end,
    GetMediaItemTake_Source = function() return opts.item_source end,
    PCM_Source_CreateFromFile = function() return opts.file_source end,
    PCM_Source_Destroy = function(s) destroyed[#destroyed + 1] = s end,
    GetMediaSourceLength = function(s) return s and s.length or nil end,
    GetMediaItemInfo_Value = function(_, name) return (opts.item_info or {})[name] or 0 end,
    GetMediaItemTakeInfo_Value = function(_, name) return (opts.take_info or {})[name] end,
    GetSet_LoopTimeRange = opts.time_selection and function(isSet)
      if isSet then error("GetSet_LoopTimeRange called with isSet = true") end
      return opts.time_selection[1], opts.time_selection[2]
    end or nil,
    PCM_Source_GetPeaks = opts.peaks,
    GetMediaSourceNumChannels = opts.peaks and function() return opts.channels or 1 end or nil,
    new_array = opts.peaks and function() return {} end or nil,
  }
  local guard, violations = strict_reaper(api)
  return guard, violations, destroyed
end

--------------------------------------------------------------------------------
T.suite("A file path and a selected item converge on one source")
--------------------------------------------------------------------------------
do
  local file_src = fake_source(120.0)
  local reaper = reading_reaper({ file_source = file_src })
  local resolved = source.resolve(reaper, { path = "/tmp/chapter-01.wav" })
  T.eq("a path resolves to its source", resolved.source, file_src)
  T.eq("the file path is the label", resolved.label, "/tmp/chapter-01.wav")
  T.near("length comes from the source", resolved.length, 120.0)
  T.check("a file we created is ours to destroy", resolved.owned == true)

  local item_src = fake_source(95.0)
  local r2 = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = item_src,
  })
  local from_item = source.resolve(r2)
  T.eq("a selected item resolves to its take's source", from_item.source, item_src)
  T.check("an item's source belongs to the take, not to us", from_item.owned == false)

  -- The point of the boundary: downstream sees the same shape either way.
  for _, field in ipairs({ "source", "length", "kind", "label", "owned" }) do
    T.check("both entry points populate " .. field,
      resolved[field] ~= nil and from_item[field] ~= nil)
  end
end

--------------------------------------------------------------------------------
T.suite("A path takes precedence over whatever is selected")
--------------------------------------------------------------------------------
do
  -- "regardless of the current item selection" — the post-render check must not
  -- change its answer because the user happened to click something.
  local file_src = fake_source(30.0)
  local reaper = reading_reaper({
    file_source = file_src, selected = 4, item = { "item" }, take = { "take" },
    item_source = fake_source(1.0),
  })
  local resolved = source.resolve(reaper, { path = "/tmp/rendered.wav" })
  T.eq("the path wins", resolved.source, file_src)
  T.eq("and it is reported as a file", resolved.kind, "file")
end

--------------------------------------------------------------------------------
T.suite("Every resolution failure names its constraint")
--------------------------------------------------------------------------------
do
  local none = reading_reaper({ selected = 0 })
  local subject, why = source.resolve(none)
  T.check("nothing selected resolves to nothing", subject == nil)
  T.contains("the message is the one the requirement quotes", why.message,
    "Select one media item, or run ACX Check on a rendered file")

  local many = reading_reaper({ selected = 3 })
  local _, too_many = source.resolve(many)
  T.contains("more than one names the constraint", too_many.message, "exactly one")
  T.contains("and says how many are selected", too_many.message, "3 media items")

  local bad_path = reading_reaper({ file_source = nil })
  local _, unreadable = source.resolve(bad_path, { path = "/tmp/missing.wav" })
  T.contains("an unreadable path is named", unreadable.message, "/tmp/missing.wav")
  T.contains("in plain language", unreadable.message, "could not be read")
  T.not_contains("with no raw code in the lead", unreadable.message, "0x")

  local empty = reading_reaper({ file_source = fake_source(0) })
  local _, zero = source.resolve(empty, { path = "/tmp/empty.wav" })
  T.check("a zero-length file is a failure, not a source", zero ~= nil)

  local no_take = reading_reaper({ selected = 1, item = { "item" }, take = nil })
  local _, takeless = source.resolve(no_take)
  T.contains("an item without an audio take says so", takeless.message, "no active audio take")
end

--------------------------------------------------------------------------------
T.suite("An undecodable file is released, not leaked")
--------------------------------------------------------------------------------
do
  -- CreateFromFile allocates even when the result turns out to be unusable.
  local dud = fake_source(0)
  local reaper, _, destroyed = reading_reaper({ file_source = dud })
  source.resolve(reaper, { path = "/tmp/broken.wav" })
  T.eq("the dud source is destroyed on the way out", destroyed[1], dud)

  -- And a good one is released only when we ask.
  local good = fake_source(10)
  local r2, _, destroyed2 = reading_reaper({ file_source = good })
  local resolved = source.resolve(r2, { path = "/tmp/fine.wav" })
  T.eq("nothing is destroyed while in use", #destroyed2, 0)
  source.release(r2, resolved)
  T.eq("release destroys what we created", destroyed2[1], good)

  -- An item's source must survive release: destroying it takes the user's media.
  local item_src = fake_source(10)
  local r3, _, destroyed3 = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = item_src,
  })
  local from_item = source.resolve(r3)
  source.release(r3, from_item)
  T.eq("an item's source is never destroyed", #destroyed3, 0)
end

--------------------------------------------------------------------------------
T.suite("Nothing in resolution or region selection writes project state")
--------------------------------------------------------------------------------
do
  -- REQ "Read-Only Operation", checked by making mutation impossible to do
  -- quietly. Anything Set*/Undo_*/Main_On*/Insert*/Delete*/Apply*/Move*/Update*
  -- records a violation instead of succeeding.
  local item_src = fake_source(600.0)
  local reaper, violations = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = item_src,
    item_info = { D_POSITION = 10.0, D_LENGTH = 600.0 },
    take_info = { D_STARTOFFS = 0.0, D_PLAYRATE = 1.0 },
    time_selection = { 100.0, 104.0 },
  })

  local resolved = source.resolve(reaper)
  local region = source.noise_region(reaper, resolved)
  source.release(reaper, resolved)

  T.eq("no mutating call was made", #violations, 0)
  T.check("and the work still happened", region ~= nil)
end

--------------------------------------------------------------------------------
T.suite("A time selection overrides the scan")
--------------------------------------------------------------------------------
do
  local reaper = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = fake_source(600.0),
    item_info = { D_POSITION = 10.0, D_LENGTH = 600.0 },
    take_info = { D_STARTOFFS = 0.0, D_PLAYRATE = 1.0 },
    time_selection = { 100.0, 104.0 },
    -- No peak API at all: if the scan ran, this suite would fail rather than
    -- quietly take a different path.
  })
  local resolved = source.resolve(reaper)
  local region = source.noise_region(reaper, resolved)
  T.eq("the region comes from the selection", region.source, "time-selection")
  T.near("start maps into source time", region.start, 90.0, 0.0001)
  T.near("stop maps into source time", region.stop, 94.0, 0.0001)
end

--------------------------------------------------------------------------------
T.suite("Time selection maps through take offset and playrate")
--------------------------------------------------------------------------------
do
  -- The measurement only knows the source's own timeline, so a take that starts
  -- 30 s into its source and plays at double speed has to be accounted for.
  local reaper = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = fake_source(600.0),
    item_info = { D_POSITION = 10.0, D_LENGTH = 600.0 },
    take_info = { D_STARTOFFS = 30.0, D_PLAYRATE = 2.0 },
    time_selection = { 20.0, 24.0 },
  })
  local resolved = source.resolve(reaper)
  local region = source.noise_region(reaper, resolved)
  T.near("offset and rate are both applied to start", region.start, 50.0, 0.0001)
  T.near("offset and rate are both applied to stop", region.stop, 58.0, 0.0001)
end

--------------------------------------------------------------------------------
T.suite("A time selection that misses the item does not count")
--------------------------------------------------------------------------------
do
  local reaper = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = fake_source(600.0),
    item_info = { D_POSITION = 10.0, D_LENGTH = 60.0 },
    take_info = { D_STARTOFFS = 0.0, D_PLAYRATE = 1.0 },
    time_selection = { 500.0, 520.0 }, -- well past the item
  })
  local resolved = source.resolve(reaper)
  local region, why = source.noise_region(reaper, resolved)
  -- No overlap and no peak API, so this falls through to the scan and reports
  -- that it could not read peak data — rather than silently using a range that
  -- is nowhere near the audio.
  T.check("a non-intersecting selection is not used", region == nil)
  T.contains("and the failure explains itself", why.message, "peak data could not be read")
  T.contains("while noting the other rows survive", why.doc, "RMS and peak are still measured")
end

--------------------------------------------------------------------------------
T.suite("A file on disk has no timeline for a selection to intersect")
--------------------------------------------------------------------------------
do
  local reaper = reading_reaper({
    file_source = fake_source(600.0),
    time_selection = { 0.0, 5.0 },
  })
  local resolved = source.resolve(reaper, { path = "/tmp/rendered.wav" })
  local region = source.noise_region(reaper, resolved)
  T.check("the selection is ignored for a file", region == nil or region.source ~= "time-selection")
end

--------------------------------------------------------------------------------
T.suite("The scan reads only the take's own span, not the whole underlying source")
--------------------------------------------------------------------------------
do
  -- A take starting 30 s into a 600 s source and playing 10 s of it: the scan
  -- must read [30, 40) -- sized off the take's own 10 s extent -- not sized off
  -- the full 600 s source, which (started at offset 30) would run 30 s past
  -- what the source actually contains.
  local get_peaks, calls = fake_peaks_reader(nil, nil, 0.5, 0.5)
  local reaper = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = fake_source(600.0),
    item_info = { D_POSITION = 0.0, D_LENGTH = 10.0 },
    take_info = { D_STARTOFFS = 30.0, D_PLAYRATE = 1.0 },
    peaks = get_peaks,
  })
  local resolved = source.resolve(reaper)
  source.noise_region(reaper, resolved)

  T.eq("exactly one scan call was made", #calls, 1)
  T.near("the scan starts at the take's own start offset, not source time 0",
    calls[1].starttime, 30.0, 0.0001)
  T.eq("the scan is sized off the take's 10 s extent, not the 600 s source",
    calls[1].buckets, math.floor(10.0 * source.SCAN_PEAK_RATE))
end

--------------------------------------------------------------------------------
T.suite("The scan's chosen window is reported at its real source-time position")
--------------------------------------------------------------------------------
do
  -- Same 30-40s take. Quiet stretch sits at source time [33, 34) -- bucket
  -- indices relative to the scan's own start (30), not to source time 0.
  local rate = source.SCAN_PEAK_RATE
  local quiet_from = math.floor((33.0 - 30.0) * rate) + 1
  local quiet_to = math.floor((34.0 - 30.0) * rate) + 1
  local get_peaks = fake_peaks_reader(quiet_from, quiet_to, 0.5, 0.001)
  local reaper = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = fake_source(600.0),
    item_info = { D_POSITION = 0.0, D_LENGTH = 10.0 },
    take_info = { D_STARTOFFS = 30.0, D_PLAYRATE = 1.0 },
    peaks = get_peaks,
  })
  local resolved = source.resolve(reaper)
  local region = source.noise_region(reaper, resolved)

  T.check("a region was found", region ~= nil)
  T.near("the window is reported at source time ~33s, not shifted back to ~3s",
    region.start, 33.0, 0.2)
end

--------------------------------------------------------------------------------
T.suite("A trimmed item shorter than the minimum window reports, even from a long source")
--------------------------------------------------------------------------------
do
  -- The underlying source is 600 s, but the take itself only plays 0.2 s of it.
  -- The subject that must clear the minimum is the take, not the source.
  local reaper = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = fake_source(600.0),
    item_info = { D_POSITION = 0.0, D_LENGTH = 0.2 },
    take_info = { D_STARTOFFS = 30.0, D_PLAYRATE = 1.0 },
  })
  local resolved = source.resolve(reaper)
  local region, why = source.noise_region(reaper, resolved)
  T.check("no region is invented from the long underlying source", region == nil)
  T.contains("the take's own 0.2s extent is named, not the 600s source", why.message, "0.20 s")
end

--------------------------------------------------------------------------------
T.suite("A reversed take's extent is still positive, and a time selection still wins")
--------------------------------------------------------------------------------
do
  -- D_PLAYRATE < 0 means the take plays backwards. It still consumes 10s of
  -- source material per 10s of project time -- the extent is a magnitude, not
  -- a direction -- so it must not go negative and spuriously trip the "too
  -- short" check ahead of an intersecting time selection, which REQ "Noise
  -- Floor Region Determination" says must win outright.
  local reaper = reading_reaper({
    selected = 1, item = { "item" }, take = { "take" }, item_source = fake_source(600.0),
    item_info = { D_POSITION = 0.0, D_LENGTH = 10.0 },
    take_info = { D_STARTOFFS = 30.0, D_PLAYRATE = -1.0 },
    time_selection = { 2.0, 8.0 },
  })
  local resolved = source.resolve(reaper)
  local region = source.noise_region(reaper, resolved)
  T.check("the time selection wins rather than a spurious too-short error", region ~= nil)
  T.eq("and it really came from the selection", region.source, "time-selection")
end

--------------------------------------------------------------------------------
T.suite("The ranking finds the quietest qualifying window")
--------------------------------------------------------------------------------
do
  -- Ten seconds at 10 buckets/s, loud throughout except a quiet stretch at 4-6 s.
  local rate = 10
  local peaks = {}
  for i = 1, 100 do peaks[i] = 0.5 end
  for i = 41, 60 do peaks[i] = 0.001 end

  local start, stop, mean = source.rank_windows(peaks, rate, 1.0)
  T.near("the window starts in the quiet stretch", start, 4.0, 0.15)
  T.near("and is the requested length", stop - start, 1.0, 0.0001)
  T.near("the ranked window really is quiet", mean, 0.001, 0.0005)

  -- Ranking is on relative magnitude only: scaling every value must not change
  -- which window wins. This is design.md's deliberate non-dependency — nothing
  -- here assumes the numbers are RMS, or dB, or anything but comparable.
  local scaled = {}
  for i, v in ipairs(peaks) do scaled[i] = v * 1000 end
  local scaled_start = source.rank_windows(scaled, rate, 1.0)
  T.near("scaling all magnitudes picks the same window", scaled_start, start, 0.0001)

  -- Stability: among equally quiet windows the earliest wins, every run.
  local flat = {}
  for i = 1, 50 do flat[i] = 0.2 end
  local flat_start = source.rank_windows(flat, rate, 1.0)
  T.near("a flat source picks the first window", flat_start, 0.0, 0.0001)

  T.check("too few buckets to fill a window yields nothing",
    source.rank_windows({ 0.1, 0.2 }, rate, 1.0) == nil)
  T.check("no buckets at all yields nothing", source.rank_windows({}, rate, 1.0) == nil)
  T.check("a nonsense rate yields nothing", source.rank_windows({ 0.1 }, 0, 1.0) == nil)
end

--------------------------------------------------------------------------------
T.suite("A source shorter than the minimum window reports rather than measures")
--------------------------------------------------------------------------------
do
  local reaper = reading_reaper({ file_source = fake_source(0.2) })
  local resolved = source.resolve(reaper, { path = "/tmp/tiny.wav" })
  local region, why = source.noise_region(reaper, resolved)
  T.check("no region is invented", region == nil)
  T.contains("the source length is named", why.message, "0.20 s")
  T.contains("so is the minimum it fell short of", why.message, "0.50 s")
  T.contains("and the other two measurements are explicitly unaffected", why.doc,
    "RMS and peak are still measured")
end

--------------------------------------------------------------------------------
T.suite("The scan stays bounded rather than growing with the source")
--------------------------------------------------------------------------------
do
  -- REQ "Analysis Performance": the coarse scan must not read the full sample
  -- data. At 44.1 kHz a 60-minute stereo source is ~159 million samples; the
  -- scan is capped in the tens of thousands of buckets regardless of length.
  local hour = 60 * 60
  local rate = source.scan_rate(hour)
  local buckets = math.floor(hour * rate)
  T.check("an hour's scan stays under the bucket ceiling", buckets <= source.MAX_SCAN_BUCKETS)
  T.check("and is a tiny fraction of the sample count", buckets < (hour * 44100) / 1000)

  -- A ten-hour source costs the same scan as an hour, not ten times as much.
  local long = 10 * hour
  local long_buckets = math.floor(long * source.scan_rate(long))
  T.check("a very long source does not grow the scan", long_buckets <= source.MAX_SCAN_BUCKETS)

  -- Short sources keep the full rate, so resolution is not thrown away.
  T.near("a short source scans at the full rate", source.scan_rate(60), source.SCAN_PEAK_RATE, 0.0001)

  -- The ranking itself is linear in buckets, so the ceiling bounds the work.
  local many = {}
  for i = 1, source.MAX_SCAN_BUCKETS do many[i] = (i % 7) / 7 end
  local ranked = source.rank_windows(many, source.SCAN_PEAK_RATE, source.MIN_ROOM_TONE_SEC)
  T.check("ranking a full-ceiling scan still returns a window", ranked ~= nil)
end

--------------------------------------------------------------------------------
T.suite("The minimum room-tone window is configurable, not baked in")
--------------------------------------------------------------------------------
do
  T.near("the chosen default is recorded", source.MIN_ROOM_TONE_SEC, 0.5, 0.0001)

  -- design.md leaves this open pending narration sample D1. When D1 lands the
  -- value changes here and nothing else, so an override has to actually work.
  local reaper = reading_reaper({ file_source = fake_source(1.0) })
  local resolved = source.resolve(reaper, { path = "/tmp/short.wav" })
  local region, why = source.noise_region(reaper, resolved, { min_room_tone_sec = 3.0 })
  T.check("an overridden minimum is enforced", region == nil)
  T.contains("and reported", why.message, "3.00 s")
end
