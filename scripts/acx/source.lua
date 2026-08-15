-- Governing: SPEC-0001 REQ "Input Resolution",
--            SPEC-0001 REQ "Noise Floor Region Determination",
--            SPEC-0001 REQ "Read-Only Operation",
--            SPEC-0001 REQ "Analysis Performance",
--            ADR-0004 (coarse rank then precise measure, for the noise floor),
--            ADR-0003 (stock Reaper plus ReaPack only — no extension may appear here)
--
-- The source-handling layer: what to analyze, and where the noise floor gets
-- measured. Everything here is upstream of acx.measure — by the time a level is
-- taken, both entry points have converged on one PCM_source.
--
-- ONE BOUNDARY, TWO ENTRY POINTS. A selected media item and an absolute file
-- path both resolve here, and nothing downstream can tell which it was. That is
-- what makes story #13's post-render check structurally identical to a manual
-- one rather than a second implementation that can drift from it.
--
-- READ-ONLY. Nothing in this module writes project state — no cursor move, no
-- selection change, no undo point. Reaper is passed in rather than reached for
-- as a global, which is what lets tests hand in a reaper whose every mutating
-- call fails the test. That guard is the headless half of the requirement; the
-- other half is running it in Reaper and watching the undo history stay empty,
-- because ReaScript can create undo points as a side effect of calls that look
-- harmless.
--
-- THE SCAN RANKS, IT DOES NOT MEASURE. The coarse scan picks a region; the
-- number always comes from acx.measure's CalculateNormalization path, so the
-- noise floor has the same provenance as RMS and peak. Ranking uses relative
-- magnitude only and does not assume peak data carries RMS values (design.md,
-- "Deliberate non-dependency").

local M = {}

local err = require("acx.error")

-- The shortest stretch of room tone worth measuring. design.md carries this as
-- an open question, to be settled against narration sample D1; D1 has not
-- arrived, so 0.5 s is chosen as the working value and recorded here rather
-- than left implicit. The reasoning: long enough that an RMS reading over it is
-- stable at any rate a narrator records at, short enough that a densely-read
-- chapter with little silence still yields a qualifying window. Revisit when D1
-- lands — this constant is the only thing that changes.
M.MIN_ROOM_TONE_SEC = 0.5

-- Peak buckets per second requested from Reaper for the coarse scan. Twenty is
-- far finer than needed to rank a half-second window and still reads roughly
-- four orders of magnitude less data than the samples themselves.
M.SCAN_PEAK_RATE = 20

-- Hard ceiling on scan buckets, so the work stays bounded by the cap rather
-- than by source length. A 60-minute source at 20/s wants 72,000; anything
-- longer lowers its effective rate instead of growing the scan.
M.MAX_SCAN_BUCKETS = 100000

-- How many channels the scan will look at. Ranking relative quietness does not
-- get meaningfully better past a stereo pair, and the cap keeps a many-channel
-- source from multiplying the read.
M.MAX_SCAN_CHANNELS = 2

--------------------------------------------------------------------------------
-- Input resolution
--------------------------------------------------------------------------------

local function unreadable(label, why)
  return err.new({
    cause = string.format("%s could not be read as an audio file", label),
    fix = "check the path exists and is a format Reaper can decode, then run ACX Check again",
    detail = why,
  })
end

local function source_length(reaper, source)
  if not source then return nil end
  local length = reaper.GetMediaSourceLength(source)
  if type(length) ~= "number" or length <= 0 then return nil end
  return length
end

local function resolve_path(reaper, path)
  if type(path) ~= "string" or path == "" then
    return nil, err.new({
      cause = "no file path was supplied to analyze",
      fix = "pass an absolute path to a rendered audio file",
    })
  end

  local source = reaper.PCM_Source_CreateFromFile(path)
  local length = source_length(reaper, source)
  if not length then
    -- Creating a source that turns out to be undecodable still allocates one.
    -- Releasing it here is why a bad path costs nothing but the error.
    if source then reaper.PCM_Source_Destroy(source) end
    return nil, unreadable(path, source and "the file decoded to zero length" or nil)
  end

  return {
    kind = "file",
    label = path,
    source = source,
    length = length,
    -- We created it, so we destroy it. An item's source belongs to the take and
    -- destroying it would take the user's media with it.
    owned = true,
  }
end

local function resolve_selection(reaper)
  local count = reaper.CountSelectedMediaItems(0)
  count = type(count) == "number" and count or 0

  if count == 0 then
    return nil, err.new({
      cause = "no media item is selected",
      -- The requirement quotes this sentence, so it is the corrective action
      -- verbatim rather than a paraphrase.
      fix = "Select one media item, or run ACX Check on a rendered file",
    })
  end

  if count > 1 then
    return nil, err.new({
      cause = string.format("%d media items are selected; ACX Check analyzes exactly one", count),
      fix = "select a single item, or run ACX Check on a rendered file",
    })
  end

  local item = reaper.GetSelectedMediaItem(0, 0)
  local take = item and reaper.GetActiveTake(item)
  if not take then
    return nil, err.new({
      cause = "the selected item has no active audio take",
      fix = "select an item containing audio, or run ACX Check on a rendered file",
    })
  end

  local source = reaper.GetMediaItemTake_Source(take)
  local length = source_length(reaper, source)
  if not length then
    return nil, unreadable("the selected item's take", nil)
  end

  local function item_value(name) return reaper.GetMediaItemInfo_Value(item, name) or 0 end
  local function take_value(name, fallback)
    local v = reaper.GetMediaItemTakeInfo_Value(take, name)
    return type(v) == "number" and v or fallback
  end

  return {
    kind = "item",
    label = "the selected item",
    source = source,
    length = length,
    owned = false,
    item = item,
    take = take,
    -- Kept so a time selection expressed in project time can be mapped onto the
    -- source's own timeline, which is the only timeline the measurement knows.
    position = item_value("D_POSITION"),
    item_length = item_value("D_LENGTH"),
    start_offset = take_value("D_STARTOFFS", 0),
    playrate = take_value("D_PLAYRATE", 1.0),
  }
end

-- Resolve the analysis subject to a single PCM_source.
-- @param reaper  table   the Reaper API table
-- @param opts    table|nil  { path = "/abs/path.wav" } to analyze a file;
--                           omit the path to analyze the selected item
-- @return table|nil resolved, table|nil error
function M.resolve(reaper, opts)
  opts = opts or {}
  if opts.path ~= nil then return resolve_path(reaper, opts.path) end
  return resolve_selection(reaper)
end

-- Release anything resolve allocated. Safe to call on any resolved subject;
-- an item's source is left alone because the take owns it.
function M.release(reaper, resolved)
  if resolved and resolved.owned and resolved.source then
    reaper.PCM_Source_Destroy(resolved.source)
    resolved.source = nil
  end
end

--------------------------------------------------------------------------------
-- Noise floor region
--------------------------------------------------------------------------------

-- Project time -> source time, honouring where the take starts inside its
-- source and how fast it plays back.
local function to_source_time(resolved, projectTime)
  local rate = (resolved.playrate ~= 0 and resolved.playrate) or 1.0
  return (projectTime - resolved.position) * rate + resolved.start_offset
end

-- The user's own gesture, when they made one. A time selection that overlaps
-- the subject wins outright and the scan never runs — no mode, no preference.
-- A file on disk has no place on the timeline, so nothing can intersect it.
local function time_selection_region(reaper, resolved)
  if resolved.kind ~= "item" then return nil end
  if type(reaper.GetSet_LoopTimeRange) ~= "function" then return nil end

  -- isSet = false, isLoop = false, allowautoseek = false: a pure read.
  local from, to = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if type(from) ~= "number" or type(to) ~= "number" or to <= from then return nil end

  local overlap_start = math.max(from, resolved.position)
  local overlap_stop = math.min(to, resolved.position + resolved.item_length)
  if overlap_stop <= overlap_start then return nil end

  return {
    start = to_source_time(resolved, overlap_start),
    stop = to_source_time(resolved, overlap_stop),
    source = "time-selection",
  }
end

-- Rank candidate windows by relative quietness. Pure: hand it magnitudes and it
-- returns the quietest window, with no Reaper and no opinion about what the
-- magnitudes mean. Deliberately a mean of magnitudes rather than anything
-- RMS-shaped — the ranking only has to order windows, and assuming peak data
-- carries RMS would be an optimization masquerading as a requirement.
-- @param peaks      table   magnitudes, one per bucket, in bucket order
-- @param rate       number  buckets per second
-- @param windowSec  number  desired window length in seconds
-- @return number|nil start seconds, number stop seconds, number mean magnitude
function M.rank_windows(peaks, rate, windowSec)
  local n = #peaks
  if n == 0 or type(rate) ~= "number" or rate <= 0 then return nil end

  local width = math.max(1, math.floor(windowSec * rate + 0.5))
  if n < width then return nil end

  local sum = 0
  for i = 1, width do sum = sum + peaks[i] end

  local best_sum, best_at = sum, 1
  for i = width + 1, n do
    sum = sum + peaks[i] - peaks[i - width]
    -- Strictly less-than, so the earliest of equally quiet windows wins and the
    -- choice is stable across runs.
    if sum < best_sum then
      best_sum, best_at = sum, i - width + 1
    end
  end

  return (best_at - 1) / rate, (best_at - 1 + width) / rate, best_sum / width
end

-- Effective bucket rate for a source, lowered so a very long source costs the
-- same scan as a merely long one.
function M.scan_rate(lengthSec)
  local rate = M.SCAN_PEAK_RATE
  local wanted = lengthSec * rate
  if wanted > M.MAX_SCAN_BUCKETS then
    rate = M.MAX_SCAN_BUCKETS / lengthSec
  end
  return rate
end

-- The analysis subject's own extent in source time, and where it starts in
-- source time. For a file this is the whole source, starting at 0. For an item
-- it is the take's own span -- item_length (project time) run through playrate
-- -- which is NOT the underlying source's full length: a take trimmed from its
-- head or tail plays only part of a longer source, and scanning or bounds-
-- checking against the full source instead of the take's span reads outside
-- what the take actually plays and reports positions the take doesn't cover.
--
-- Uses |playrate|: a reversed take (negative D_PLAYRATE) still consumes the
-- same amount of source material per second of project time, just backwards.
-- The signed rate is for mapping a direction (to_source_time); this is a
-- magnitude, and a negative extent would make an intersecting time selection
-- lose to a spurious "too short" error below instead of winning outright.
local function subject_extent(resolved)
  if resolved.kind ~= "item" then
    return resolved.length, 0
  end

  local rate = math.abs((resolved.playrate ~= 0 and resolved.playrate) or 1.0)
  local extent = (resolved.item_length or 0) * rate
  local start = resolved.start_offset or 0
  -- Clamp to what's actually left in the source, in case item/take metadata is
  -- stale relative to the source.
  local available = resolved.length - start
  if available > 0 and extent > available then extent = available end
  return extent, start
end

-- Read coarse peak magnitudes from Reaper.
--
-- THIS IS THE UNVERIFIED SEAM, in the same sense spike 9's CalculateNormalization
-- call was: the buffer layout PCM_Source_GetPeaks writes is documented but not
-- confirmed on this machine, because confirming it needs Reaper. The ranking it
-- feeds is pinned headless; this adapter is what an in-Reaper run must check.
-- Expected layout: numsamplesperchannel * numchannels maxima, followed by the
-- same count of minima. Magnitude is max(|max|, |min|) per bucket, then the
-- loudest channel of each bucket, so a quiet window has to be quiet everywhere.
-- @return peaks|nil, rate, scan_start  scan_start is where bucket 1 sits in
--   source time -- callers must add it back to any offset rank_windows returns.
local function read_peaks(reaper, resolved)
  if type(reaper.PCM_Source_GetPeaks) ~= "function" or type(reaper.new_array) ~= "function" then
    return nil
  end

  local extent, start = subject_extent(resolved)
  local rate = M.scan_rate(extent)
  local buckets = math.max(1, math.floor(extent * rate))
  local channels = reaper.GetMediaSourceNumChannels and reaper.GetMediaSourceNumChannels(resolved.source) or 1
  channels = math.max(1, math.min(M.MAX_SCAN_CHANNELS, type(channels) == "number" and channels or 1))

  local buf = reaper.new_array(buckets * channels * 2)
  local got = reaper.PCM_Source_GetPeaks(resolved.source, rate, start, channels, buckets, 0, buf)
  if type(got) == "number" and got <= 0 then return nil end

  local values = buf.table and buf:table() or buf
  local peaks = {}
  for b = 1, buckets do
    local worst = 0
    for c = 0, channels - 1 do
      local hi = values[(b - 1) * channels + c + 1] or 0
      local lo = values[buckets * channels + (b - 1) * channels + c + 1] or 0
      local magnitude = math.max(math.abs(hi), math.abs(lo))
      if magnitude > worst then worst = magnitude end
    end
    peaks[b] = worst
  end
  return peaks, rate, start
end

-- Decide where the noise floor gets measured.
-- @return table|nil region { start, stop, source }, table|nil error
function M.noise_region(reaper, resolved, opts)
  opts = opts or {}
  local minimum = opts.min_room_tone_sec or M.MIN_ROOM_TONE_SEC

  local extent = subject_extent(resolved)
  if extent < minimum then
    return nil, err.new({
      cause = string.format(
        "the source is %.2f s long, shorter than the %.2f s minimum room-tone window",
        extent, minimum),
      fix = "check a longer source, or select a quiet range by hand",
      -- Reported, not fatal: the requirement is explicit that RMS and peak still
      -- come back when only the noise floor cannot be placed.
      doc = "RMS and peak are still measured; only the noise-floor row is unavailable",
    })
  end

  -- The user's selection is honoured as given, including when it is shorter than
  -- the minimum: they pointed at that range deliberately, and second-guessing a
  -- deliberate gesture is worse than measuring a short window.
  local chosen = time_selection_region(reaper, resolved)
  if chosen then return chosen end

  local peaks, rate, scan_start = read_peaks(reaper, resolved)
  if not peaks or #peaks == 0 then
    return nil, err.new({
      cause = "the source's peak data could not be read, so no room-tone region could be located",
      fix = "select a quiet range by hand and run ACX Check again",
      doc = "RMS and peak are still measured; only the noise-floor row is unavailable",
    })
  end

  local start, stop = M.rank_windows(peaks, rate, minimum)
  if not start then
    return nil, err.new({
      cause = "no room-tone window long enough to measure could be found in the source",
      fix = "select a quiet range by hand and run ACX Check again",
      doc = "RMS and peak are still measured; only the noise-floor row is unavailable",
    })
  end

  -- rank_windows returns times relative to bucket 1, which sits at scan_start
  -- (the take's start offset) in source time, not at source time 0.
  return { start = scan_start + start, stop = scan_start + stop, source = "scan" }
end

-- Exposed for tests.
M._internal = {
  to_source_time = to_source_time,
  time_selection_region = time_selection_region,
  read_peaks = read_peaks,
  subject_extent = subject_extent,
}

return M
