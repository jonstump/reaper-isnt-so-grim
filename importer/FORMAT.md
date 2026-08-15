<!-- Governing: ADR-0005 (strict clean room for `.aup3` reverse engineering),
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

**Status: prose survey only.** Nothing below has been confirmed against a real
`.aup3` file — none have arrived yet (see `docs/audacity-reference-request.md`,
items D2/D1). Every entry is therefore a *claim* with a source, not a verified
fact. The `Verified` column is what changes when fixtures land.

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

`Verified` is `no` for everything until a real project can be opened and checked.

| # | Claim | Source | Verified |
|---|---|---|---|
| 1 | `.aup3` is a single SQLite3 database. Audacity 3.0.0 moved from "a pile of files" to storing everything in one file. | Audacity Team, 3.0.0 release announcement, quoted in the [SQLite user forum](https://sqlite.org/forum/info/496b68a88a88e5c0) | no |
| 2 | There is an `autosave` table holding project state written after each user action, as a serialized blob. | [audacity-project-tools README](https://github.com/audacity/audacity-project-tools) | no |
| 3 | There is a `project` table holding the project state as written on an explicit save. | audacity-project-tools README; independently stated by forum moderator *steve* with a screenshot of the table, [Audacity Forum thread 61618](https://forum.audacityteam.org/t/request-aup3-and-or-sqlite-documentation/61618) | no |
| 4 | `autosave` and `project` share the same schema: **two blobs**. One is "dictionary" data — a list of tag and attribute names. The second holds the project structure. | audacity-project-tools README | no |
| 5 | The project structure blob is **binary, not text**. | *steve*, Audacity Forum thread 61618 ("the project table contains the project structure in binary format"), consistent with claim 4's dictionary indirection | no |
| 6 | In a cleanly closed project, `autosave` is normally empty. | *steve*, Audacity Forum thread 61618 | no |
| 7 | There is a `sampleblocks` table holding the audio data. | audacity-project-tools README; *steve*, thread 61618 | no |
| 8 | Sample blocks are up to ~1 MB each. | audacity-project-tools README | no |
| 9 | A block holds roughly 5 seconds of mono audio at default settings. | audacity-project-tools README | no |
| 10 | **Audacity never updates a block in place.** When data changes it writes a new block, so block IDs are not necessarily sequential and stale blocks may persist. | audacity-project-tools README | no |

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
| 11 | The SQLite `application_id` for an `.aup3` project is `1096107097`. | `AudacityDatabase.cpp`, `AudacityProjectID` | no |
| 12 | Project version is packed as `major<<24 \| minor<<16 \| patch<<8 \| build`. The tool supports up to `3.7.0.0`. | `AudacityDatabase.cpp`, `MaxSupportedVersion` | no |
| 13 | `project` and `autosave` each hold the document in **two columns**: `dict` and `doc`, at row `id = 1`. | `ProjectBlobReader.cpp` | no |
| 14 | `dict` and `doc` are **concatenated in that order** and parsed as one continuous stream. | `ProjectBlobReader.cpp`, `ReadProjectBlob` | no |
| 15 | The stream is **not compressed**. It is read raw and parsed directly. | `ProjectBlobReader.cpp` → `BinaryXMLConverter.cpp`, no decompression stage between them | no |
| 16 | The document is a **tagged binary stream**. Each field opens with a `uint8` type tag from a 16-value set: `CharSize, StartTag, EndTag, String, Int, Bool, Long, LongLong, SizeT, Float, Double, Data, Raw, Push, Pop, Name`. | `BinaryXMLConverter.cpp`, `FieldTypes` | no |
| 17 | Tag and attribute names are **interned**: `FT_Name` carries `ID + length + name`, and every other field references a name by numeric ID. This is what the `dict` blob holds. | `BinaryXMLConverter.cpp`, `FieldTypes` layout comments | no |
| 18 | A `CharSize` field sets the byte-width used for subsequent string reads — string encoding is not fixed and must be read from the stream. | `BinaryXMLConverter.cpp`, `Stream::setCharSize` / `readString` | no |
| 19 | `sampleblocks` has at least the columns `blockid`, `sampleformat`, and `samples`. | `ProjectModel.cpp` queries | no |
| 20 | Sample formats are `int16` / `int24` / `float`, encoded as `0x00020001`, `0x00040001`, `0x0004000F`. | `SampleFormat.h`, `SampleFormat.cpp` | no |
| 21 | **`int24` occupies 3 bytes in memory but 4 bytes on disk.** `int16` is 2/2, `float` is 4/4. | `SampleFormat.cpp`, `BytesPerSample` vs `DiskBytesPerSample` | no |
| 22 | Document structure is `wavetrack` → `waveclip` → `sequence` → `waveblock`. | `ProjectModel.cpp` | no |
| 23 | `wavetrack` carries `name` and `rate` (int). `sequence` carries `maxsamples`, `numsamples` (int64) and `sampleformat`. `waveblock` carries `start` (int64) and `blockid` (int64). `waveclip` carries `offset`, `trimLeft`, `trimRight` (all double) and `name`. | `ProjectModel.cpp` attribute parsing; `ProjectModel.h` field types | no |
| 24 | **Positions use two different units.** `waveclip/@offset` is in **seconds** (double); `waveblock/@start` is a **sample index** within its sequence (int64). | `ProjectModel.h` field types | no |
| 25 | **A negative `blockid` means silence** — a block with no stored samples. | `ProjectModel.cpp`, `WaveBlock::isSilence` | no |
| 26 | Clips carry `trimLeft` / `trimRight` — the audible region is a subrange of the underlying sequence, not the whole of it. | `ProjectModel.cpp`, `WaveClip` attribute parsing | no |

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

Most of the original list was answered by claims 11–26. What is left:

- **Byte-level widths inside the tagged stream.** Claim 16 gives the field types
  and their layouts; it does not give how wide an ID is, or a length prefix, or
  whether values are little-endian. Reading `Stream::read<T>` more closely, or
  inspecting a real blob, resolves this. This is the last thing between here and
  a working parser.
- **Channel interleaving and endianness inside a `samples` blob.** Claims 20–21
  give the formats and their disk widths, but not whether a stereo block
  interleaves or whether each channel is its own sequence. The `wavetrack` /
  `channel` attribute suggests the latter — unconfirmed.
- **Where summary/peak data lives.** Still open. `audacity-project-tools` reads
  only `sampleformat` and `samples` from `sampleblocks`, so if summary columns
  exist it does not touch them. Not load-bearing for the importer — Reaper builds
  its own peaks — so this can stay open.
- **How multi-clip tracks and any implicit cross-fade behaviour are represented.**
  Claims 22 and 26 give the containment and trimming model, which is most of it;
  whether adjacent clips carry implicit behaviour is still unknown.
- **Whether the schema changed across 3.x releases.** Partly answered by claim 12
  — a version is stored and packed in a known way, and the tool declares support
  through 3.7.0.0 — but not *what* changed between versions.
- **The `autosave` / `project` interaction in practice.** Claim 6 says `autosave`
  is normally empty in a cleanly-closed project. What an importer should do when
  it is *not* empty — crash recovery state, presumably newer than `project` — is
  a design question the spec does not yet answer.

## Corrections this survey produced

The survey was worth doing before writing code: it contradicted two things the
project had already written down.

### `audacity-project-tools` is BSD-3-Clause, not GPL

ADR-0005 states:

> This extends to GPL-licensed tooling built on Audacity's codebase, including
> `audacity-project-tools`. Its *behaviour* may be observed; its source may not
> be read.

The premise is wrong. GitHub's repository metadata reports the project as
**BSD-3-Clause** (`gh api repos/audacity/audacity-project-tools --jq .license`),
which is permissive and MIT-compatible, requiring attribution rather than
copyleft reciprocity.

**Resolved 2026-08-15: ADR-0005 was amended and the restriction lifted for this
tool.** The open question was whether its *declared* licence matched its actual
composition — a permissive licence on a project that vendors GPL code would not
make the GPL code permissive. Checked, via repository metadata only:

| Check | Result |
|---|---|
| Declared licence | BSD-3-Clause (GitHub repository metadata) |
| Git submodules | none |
| Vendored third-party code (`3party/`) | SQLite only |
| Dependency manifest (`conanfile.txt`) | fmt, sqlite3, SQLiteCpp, gflags, utfcpp, boost — no Audacity |
| Size and shape | 16 files in `src/`; an independent reimplementation, not a fork |

So it is lawful to read for an MIT project, with attribution. ADR-0005's permitted
sources now include permissively-licensed implementations meeting exactly this
test, and Audacity's own source remains as forbidden as it was.

`src/` filenames alone — read as metadata, no file opened — indicate the tool
implements `ProjectBlobReader`, `BinaryXMLConverter`, `SampleFormat`, and
`WaveFile`. That is close to a one-to-one map onto the Unresolved list above,
which is why this correction matters more than a licence footnote usually would.

Nothing has been read yet. When it is, each fact taken lands in Claims with the
tool, the version, and what was taken.

### The project document is not XML

`PLAN.md:90` describes `.aup3` as "a SQLite database containing the project XML
plus audio sample blocks", and SPEC-0002's `design.md` calls reading the project
document "a well-understood text problem".

Claims 4 and 5 contradict both. The project structure is a binary blob paired
with a name dictionary — closer to a serialised object graph than to a text
document. The `.aup` format that preceded it *was* XML, which is the likely origin
of the confusion.

This matters for planning, not just accuracy: it moves decoding the project
document out of the "easy half" and next to sample-block decoding in difficulty.
Both `PLAN.md` and `design.md` should be corrected.

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
