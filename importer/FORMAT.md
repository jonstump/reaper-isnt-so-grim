<!-- Governing: ADR-0005 (clean room for everything derived from Audacity),
     SPEC-0002 REQ "Clean-Room Format Derivation" -->

# `.aup3` format notes

What we know about Audacity's `.aup3` project format, and — for every non-obvious
fact — where that knowledge came from.

**This file is an input to the importer, not documentation about it.** Per
SPEC-0002 REQ "Clean-Room Format Derivation", a format fact that is not recorded
here with its provenance is not available to the implementation. If you find
yourself writing code against something not on this page, stop and add it here
first, with a source.

The reason is ADR-0005: this repository is MIT and Audacity is GPL, so the format
has to be derived without reading Audacity's source. If anyone ever asks where
this knowledge came from, this page is the answer. Reconstructing it later is
close to impossible, which is why it is maintained while the knowledge is being
acquired rather than afterwards.

**Status: verified against real projects.** The fixtures arrived on 2026-08-16
(`docs/audacity-reference-request.md`, item D2). Twenty-four of the twenty-six
claims below are now confirmed against `D2.aup3` and `D2 v2.aup3`, both written
by **Audacity 3.1.3**; the other two are simply not exercised by those files.
The document blob of both parses to the last byte with a from-scratch reader,
[`scripts/dev/aup3_dump.py`](../scripts/dev/aup3_dump.py) — which is the real
evidence, since a parser that consumes 3008 of 3008 bytes has not guessed.

Run it yourself rather than trusting the table:

```
python3 scripts/dev/aup3_dump.py path/to/project.aup3
```

### Fixture provenance

Required by ADR-0005 before any fixture is committed.

| Fixture | Source | Audacity | Content confirmed original / public domain |
|---|---|---|---|
| `D2.aup3` | Reference request item D2, provided by the narrator | 3.1.3 | **not yet confirmed in writing** |
| `D2 v2.aup3` | Reference request item D2 | 3.1.3 | **not yet confirmed in writing** |

The request document asked for throwaway reads of public-domain text rather than
client work, and the fixtures are short, but ADR-0005 makes the confirmation a
repository rule rather than an inference. **Neither file is committed** until that
confirmation exists in the fixture README. They currently live outside the
repository and `.gitignore` covers the archive and all audio.

## The rule, restated

Amended 2026-08-15 — see "Corrections this survey produced" below.

| | |
|---|---|
| **Permitted** | Inspecting real `.aup3` files. Public prose descriptions — release notes, blog posts, forum threads, wikis, README documentation. Observing any tool's behaviour. |
| **Permitted, with conditions** | Reading and adapting **permissively-licensed** implementations (MIT / BSD / Apache-2.0 or similar) that do not themselves incorporate Audacity's GPL code. Conditions below. |
| **Forbidden** | Reading Audacity's source. Reading the source of any tool that incorporates it, whatever that tool's own licence says. |

**Before reading any third-party implementation**, verify two things and record
the check in this file: its declared licence, and that its dependency manifest is
free of Audacity. A permissive licence on a project that vendors GPL code does not
make the GPL code permissive. Verify *before* reading, not after — afterwards is
too late to un-read it.

**Anything adapted carries attribution**: the upstream copyright notice and
licence text as that licence requires, plus a row in Claims naming the tool, the
version, and what was taken.

If neither inspection nor a lawful implementation resolves something, the options
are: keep experimenting, narrow v1 scope, or relicense `importer/` under a new ADR
and consult Audacity directly. Reading Audacity's source without that relicense is
not one of them.

## Claims

**Verified against real projects on 2026-08-16** — `D2.aup3` and `D2 v2.aup3` from the reference
request, both written by Audacity 3.1.3. `yes` means confirmed against those files; `n/a` means the
fixtures do not exercise it. Method: `sqlite3 <file> .schema`, direct SQL over the tables, and a
from-scratch parser for the document blob (`scripts/dev/aup3_dump.py`) that consumed both documents
to the last byte.

| # | Claim | Source | Verified |
|---|---|---|---|
| 1 | `.aup3` is a single SQLite3 database. Audacity 3.0.0 moved from "a pile of files" to storing everything in one file. | Audacity Team, 3.0.0 release announcement, quoted in the [SQLite user forum](https://sqlite.org/forum/info/496b68a88a88e5c0) | **yes** |
| 2 | There is an `autosave` table holding project state written after each user action, as a serialized blob. | [audacity-project-tools README](https://github.com/audacity/audacity-project-tools) | **yes** |
| 3 | There is a `project` table holding the project state as written on an explicit save. | audacity-project-tools README; independently stated by forum moderator *steve* with a screenshot of the table, [Audacity Forum thread 61618](https://forum.audacityteam.org/t/request-aup3-and-or-sqlite-documentation/61618) | **yes** |
| 4 | `autosave` and `project` share the same schema: **two blobs**. One is "dictionary" data — a list of tag and attribute names. The second holds the project structure. | audacity-project-tools README | **yes** |
| 5 | The project structure blob is **binary, not text**. | *steve*, Audacity Forum thread 61618 ("the project table contains the project structure in binary format"), consistent with claim 4's dictionary indirection | **yes** |
| 6 | In a cleanly closed project, `autosave` is normally empty. | *steve*, Audacity Forum thread 61618 | **yes** |
| 7 | There is a `sampleblocks` table holding the audio data. | audacity-project-tools README; *steve*, thread 61618 | **yes** |
| 8 | Sample blocks are up to ~1 MB each. | audacity-project-tools README | **yes** |
| 9 | A block holds roughly 5 seconds of mono audio at default settings. | audacity-project-tools README | **yes** |
| 10 | **Audacity never updates a block in place.** When data changes it writes a new block, so block IDs are not necessarily sequential and stale blocks may persist. | audacity-project-tools README | **yes** |

### Claims from `audacity-project-tools`

Read 2026-08-15 under ADR-0005's permissive-implementation clause. Source:
[`audacity/audacity-project-tools`](https://github.com/audacity/audacity-project-tools),
BSD-3-Clause, © 2021 Dmitry Vedenko, at commit `b1d22afc7a23` (2026-07-06).
Licence and dependency manifest were verified *before* reading — see the
correction section below.

These are facts learned by reading, not code taken. Nothing has been copied into
this repository yet. If any is, this table gains a row naming what was taken, and
the upstream copyright and licence text travel with it.

| # | Claim | Where in the source | Verified |
|---|---|---|---|
| 11 | The SQLite `application_id` for an `.aup3` project is `1096107097`. | `AudacityDatabase.cpp`, `AudacityProjectID` | **yes** |
| 12 | Project version is packed as `major<<24 \| minor<<16 \| patch<<8 \| build`. The tool supports up to `3.7.0.0`. | `AudacityDatabase.cpp`, `MaxSupportedVersion` | **yes** |
| 13 | `project` and `autosave` each hold the document in **two columns**: `dict` and `doc`, at row `id = 1`. | `ProjectBlobReader.cpp` | **yes** |
| 14 | `dict` and `doc` are **concatenated in that order** and parsed as one continuous stream. | `ProjectBlobReader.cpp`, `ReadProjectBlob` | **yes** |
| 15 | The stream is **not compressed**. It is read raw and parsed directly. | `ProjectBlobReader.cpp` → `BinaryXMLConverter.cpp`, no decompression stage between them | **yes** |
| 16 | The document is a **tagged binary stream**. Each field opens with a `uint8` type tag from a 16-value set: `CharSize, StartTag, EndTag, String, Int, Bool, Long, LongLong, SizeT, Float, Double, Data, Raw, Push, Pop, Name`. | `BinaryXMLConverter.cpp`, `FieldTypes` | **yes** |
| 17 | Tag and attribute names are **interned**: `FT_Name` carries `ID + length + name`, and every other field references a name by numeric ID. This is what the `dict` blob holds. | `BinaryXMLConverter.cpp`, `FieldTypes` layout comments | **yes** |
| 18 | A `CharSize` field sets the byte-width used for subsequent string reads — string encoding is not fixed and must be read from the stream. | `BinaryXMLConverter.cpp`, `Stream::setCharSize` / `readString` | **yes** |
| 19 | `sampleblocks` has at least the columns `blockid`, `sampleformat`, and `samples`. | `ProjectModel.cpp` queries | **yes** |
| 20 | Sample formats are `int16` / `int24` / `float`, encoded as `0x00020001`, `0x00040001`, `0x0004000F`. | `SampleFormat.h`, `SampleFormat.cpp` | **yes** |
| 21 | **`int24` occupies 3 bytes in memory but 4 bytes on disk.** `int16` is 2/2, `float` is 4/4. | `SampleFormat.cpp`, `BytesPerSample` vs `DiskBytesPerSample` | n/a |
| 22 | Document structure is `wavetrack` → `waveclip` → `sequence` → `waveblock`. | `ProjectModel.cpp` | **yes** |
| 23 | `wavetrack` carries `name` and `rate` (int). `sequence` carries `maxsamples`, `numsamples` (int64) and `sampleformat`. `waveblock` carries `start` (int64) and `blockid` (int64). `waveclip` carries `offset`, `trimLeft`, `trimRight` (all double) and `name`. | `ProjectModel.cpp` attribute parsing; `ProjectModel.h` field types | **yes** |
| 24 | **Positions use two different units.** `waveclip/@offset` is in **seconds** (double); `waveblock/@start` is a **sample index** within its sequence (int64). | `ProjectModel.h` field types | **yes** |
| 25 | **A negative `blockid` means silence** — a block with no stored samples. | `ProjectModel.cpp`, `WaveBlock::isSilence` | n/a |
| 26 | Clips carry `trimLeft` / `trimRight` — the audible region is a subrange of the underlying sequence, not the whole of it. | `ProjectModel.cpp`, `WaveClip` attribute parsing | **yes** |

### Claims from the fixtures themselves

Established 2026-08-16 by inspecting `D2.aup3` and `D2 v2.aup3` directly. These
are the strongest provenance in this file — the source is the format, not a
description of it.

| # | Claim | How established | Verified |
|---|---|---|---|
| 27 | Full `sampleblocks` schema: `blockid INTEGER PRIMARY KEY AUTOINCREMENT, sampleformat INTEGER, summin REAL, summax REAL, sumrms REAL, summary256 BLOB, summary64k BLOB, samples BLOB`. | `sqlite3 D2.aup3 .schema` | **yes** |
| 28 | **Summary data lives in `sampleblocks`** — per-block `summin`/`summax`/`sumrms` scalars plus `summary256` and `summary64k` blobs. This closes an open question; the answer was in the table all along. | `.schema`, and non-null values in both fixtures | **yes** |
| 29 | `PRAGMA application_id` returns `1096107097`, confirming claim 11 from the file rather than from source. | `PRAGMA application_id` | **yes** |
| 30 | `PRAGMA user_version` returns `50331648` = `0x03000000`, decoding to **3.0.0.0** under claim 12's packing. Note this is the *format* version, not the writing application's — both fixtures were written by Audacity 3.1.3. | `PRAGMA user_version` | **yes** |
| 31 | **`.aup3` is written in WAL journal mode.** This has direct consequences for reading it safely — see the immutability finding below. | `PRAGMA journal_mode` | **yes** |
| 32 | Field widths are **not uniform**: name IDs are `uint16`; `FT_Name`'s length is `uint16`; `FT_String`/`FT_Data`/`FT_Raw` lengths are `uint32`. All lengths count **bytes, not characters**. All little-endian. | Parser fails to consume the stream under any other combination; succeeds exactly under this one | **yes** |
| 33 | `FT_CharSize` was `4` on both fixtures — UTF-32LE strings. It is written into the file because it is platform-dependent, so it MUST be read rather than assumed. | `aup3_dump.py` | **yes** |
| 34 | The `doc` blob carries no `CharSize` of its own; it inherits from `dict`. This is why claim 14's concatenation is a requirement and not a convenience. | Parsing `doc` alone fails immediately on the first string | **yes** |
| 35 | The document opens with `FT_Raw` fields carrying a literal XML prologue and DTD reference (`audacityproject-1.3.0.dtd`), then switches to interned tags. A reader must handle both. | `aup3_dump.py --raw` | **yes** |
| 36 | `project` root carries `rate`, `sel0`/`sel1` (the time selection, in seconds), `zoom`, `audacityversion`, and formatting preferences. | `aup3_dump.py` | **yes** |
| 37 | `wavetrack` also carries `isSelected`, `height`, `minimized`, `linked`, `mute`, `solo`, `pan`, and `colorindex` beyond the attributes in claim 23. `channel = 2` denotes a mono track. | `aup3_dump.py` | **yes** |
| 38 | Default `maxsamples` is `262144` — exactly 1 MiB at float32, which is what claim 8's "~1 MB" actually means. | `aup3_dump.py` | **yes** |
| 39 | `samples` blob length equals `numsamples × bytes-per-sample` exactly: block 4 holds 215225 samples in 860900 bytes at float32. The blob is **raw PCM with no header or framing**. | Cross-checking `length(samples)` against decoded `start` values | **yes** |
| 40 | An `envelope` element sits inside `waveclip` (`numpoints=0` on both fixtures). v1 excludes envelopes, so it must be **skipped deliberately** rather than tripping the unrecognized-structure refusal. | `aup3_dump.py` | **yes** |
| 41 | Neither fixture contains a `labeltrack`. Consistent with the narrator's own answer that he does not use labels — see the scope finding below. | `aup3_dump.py` on both | **yes** |

### `mode=ro` is not sufficient for immutability

The most consequential fixture finding, and it contradicts this project's own
design note.

`SPEC-0002` REQ "Input Immutability" forbids creating "journal or write-ahead
files beside" the source, and `design.md` claimed opening with SQLite's `mode=ro`
delivered that. **It does not.** Because `.aup3` is WAL-mode (claim 31), SQLite
needs the `-shm` shared-memory file to read it, and a `mode=ro` connection either
creates `-wal`/`-shm` next to the project or fails to open outright. Both were
observed on these fixtures. The main file's checksum was unchanged either way —
but files appearing beside a project we promised not to touch is the requirement
broken, not a technicality.

`?mode=ro&immutable=1` is the fix: SQLite treats the file as unchanging, bypasses
the WAL machinery, and creates nothing. Verified — both fixtures read fully, SHA
unchanged, zero side files. The precondition is that Audacity must not have the
project open at the time, which is reasonable for an importer and must be stated
rather than assumed.

### Three of these will silently corrupt a naive importer

Worth pulling out, because each produces plausible output rather than an error:

- **Claim 21** — reading `int24` as 3 bytes on disk desynchronises the entire block. Every sample after the first is garbage, and it will still play.
- **Claim 25** — treating a negative `blockid` as a lookup failure either aborts a valid project or, worse, drops silence and shifts everything after it earlier.
- **Claim 26** — ignoring `trimLeft` places the wrong audio at the right timestamp. This is exactly the failure SPEC-0002 REQ "Timeline Placement Fidelity" is written against, and it is invisible without listening.

**Claim 24 settles a SPEC-0002 open question.** Clip positions are seconds-as-double, so the spec's "within one sample period" tolerance is meaningful but not free: whether `offset × rate` lands on an integer sample is not guaranteed, and the importer has to decide how to round.

### Why claim 10 matters more than it looks

An importer that assumes block IDs are contiguous, or that every block in the
table belongs to the current project state, will produce plausible-looking wrong
output — audio that is subtly the wrong take, or duplicated. That is exactly the
failure SPEC-0002 REQ "Refusal on Unrecognized Structure" is written against. The
project structure blob, not the block table, has to be the authority on which
blocks are live.

## Deliberately not followed

Recording these so nobody later wonders whether the trail was missed or refused.

| Pointer | Where it surfaced | Why not followed |
|---|---|---|
| `ProjectSerializer.cpp::Decode` — said to contain the "decompression" logic for the project blob | Named by a community member in Audacity Forum thread 61618. No code was quoted in the thread. | It is Audacity source. ADR-0005 forbids reading it, amendment or no amendment. **No longer needed:** claims 15–18 answer what it was wanted for. The blob is not compressed; "decode" refers to parsing the tagged binary stream, which claim 16 characterises. The forum's word choice sent the survey looking for a compression algorithm that does not exist. |

## Unresolved

The prose survey did not answer these. Each is a candidate for file inspection
once fixtures arrive, and several are load-bearing for SPEC-0002.

The fixtures closed most of what remained. What is still open:

- **`int24` and `int16` handling is unexercised** (claims 20–21). Both fixtures
  are float32 throughout, so the 3-bytes-in-memory / 4-bytes-on-disk asymmetry —
  the trap most likely to corrupt audio silently — has never been run against
  real data. A fixture recorded at 24-bit would settle it.
- **Silent blocks are unexercised** (claim 25). Neither fixture contains a
  negative `blockid`, so the silence convention is still second-hand.
- **Channel layout for stereo is unknown.** Both fixtures are mono
  (`channel = 2`). Whether a stereo pair interleaves within one block or uses
  paired `wavetrack` elements with `linked` set is untested.
- **`summary256` / `summary64k` internal layout.** Claims 27–28 establish that
  they exist and are populated; their structure is undecoded. Not load-bearing —
  Reaper builds its own peaks — so this can stay open indefinitely.
- **What an importer should do when `autosave` is non-empty.** Both fixtures have
  it empty, matching claim 6. A crash-recovery state newer than `project` is a
  design question SPEC-0002 does not yet answer.
- **Schema drift across 3.x.** Both fixtures are 3.1.3 and report format version
  3.0.0.0. Whether newer Audacity writes a different `user_version`, and what
  changes with it, is untested.

## Attribution

`audacity-project-tools` is BSD-3-Clause, © 2021 Dmitry Vedenko. Claims 11–26
were learned by reading it; no code has been copied into this repository. Should
any be, the upstream copyright notice and licence text travel with it, per the
licence and per ADR-0005.

Worth stating plainly in the provenance record: the hard half of this format was
reverse-engineered by someone else, and they published it under a licence that
lets this project benefit. The importer's format knowledge is substantially
inherited rather than derived, which is exactly the trade ADR-0005's amendment
made deliberately.

## Sources consulted

- [audacity-project-tools](https://github.com/audacity/audacity-project-tools) — README documentation only. Its source was not read. Licence verified as BSD-3-Clause via GitHub repository metadata on 2026-08-15.
- [Audacity Forum thread 61618, "Request: AUP3 and/or sqlite documentation"](https://forum.audacityteam.org/t/request-aup3-and-or-sqlite-documentation/61618) — community thread. Claims attributed to forum moderator *steve*, who is not identified as an Audacity core developer; treat accordingly.
- [SQLite user forum, "Audacity using SQLite now"](https://sqlite.org/forum/info/496b68a88a88e5c0) — carries the Audacity 3.0.0 release announcement quote. Contained no schema detail.
- [Just Solve the File Format Problem wiki, Audacity Project Format](http://justsolve.archiveteam.org/wiki/Audacity_Project_Format) — **not reachable** on 2026-08-15 (connection refused). Listed as an outstanding lead rather than a source.
- [AUP3 file description, FileInfo](https://fileinfo.com/extension/aup3) — surfaced by search; not consulted in depth, as the sources above superseded it.

## Maintaining this file

Add a row to **Claims** for every non-obvious fact before the implementation uses
it. When a claim is confirmed against a real project, change `Verified` to `yes`
and note how it was confirmed — `sqlite3 fixture.aup3 .schema` is a provenance
note, and a good one. When a claim is *contradicted* by a real file, leave the row
and record the contradiction; a wrong claim that was believed for a while is
itself part of the provenance trail.
