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
| `ProjectSerializer.cpp::Decode` — said to contain the decompression logic for the project blob | Named by a community member in Audacity Forum thread 61618. No code was quoted in the thread. | It is Audacity source. ADR-0005 forbids reading it. This is the single most useful-looking pointer found in the survey and it is being left alone on purpose. |

## Unresolved

The prose survey did not answer these. Each is a candidate for file inspection
once fixtures arrive, and several are load-bearing for SPEC-0002.

- **Column names** in any of the three tables. No source gave them.
- **How the project structure blob is encoded.** Compressed? With what? The
  dictionary blob implies tag/attribute names are interned and referenced by
  index, but the container format is unknown. This is the hardest open item.
- **How the dictionary blob is encoded**, and how entries in it are referenced
  from the structure blob.
- **Sample encoding inside `sampleblocks`** — bit depth, channel interleaving,
  endianness, whether a block is raw PCM or framed.
- **Where summary/peak data lives.** Audacity draws waveforms without decoding
  everything, so summaries exist somewhere; no source located them.
- **How clip positions are expressed** — samples or seconds. SPEC-0002 states a
  tolerance of one sample period, and whether that is exact or merely tight
  depends on this.
- **How multi-clip tracks and any implicit cross-fade behaviour are represented.**
- **Whether the schema changed across 3.x releases.** Relevant because the
  reference request asks which Audacity version produced the projects.

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
