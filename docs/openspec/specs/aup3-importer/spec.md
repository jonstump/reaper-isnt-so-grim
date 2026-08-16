---
status: draft
date: 2026-08-15
implements: [ADR-0005]
---

# SPEC-0002: `.aup3` Importer

## Overview

A standalone command-line tool that converts an Audacity `.aup3` project into a Reaper project directory: extracted audio files plus a `.rpp` that places them on the right tracks at the right times. It exists so the user's back catalogue opens in Reaper at all — `PLAN.md` Phase 2.

The gap is real. The only existing Audacity→Reaper converters read the *legacy* `.aup` XML format; modern Audacity writes `.aup3`, a SQLite database, and nobody has shipped a good converter for it. That makes this the project's most substantial open-source contribution and also its hardest piece, which is why it is Phase 2 rather than Phase 1.

Governed by [ADR-0005](../../../adrs/ADR-0005-license-and-clean-room.md), which sets both the MIT licence and the strict clean-room rule that shapes how the format may be learned. ADR-0005 is unusual among this project's decisions in that it constrains the *research method*, not just the result — so the clean-room discipline appears below as a requirement with scenarios, not as a note.

Two constraints are worth stating up front because they shape every requirement that follows:

- **The input files are irreplaceable.** These are years of the user's finished work. A converter that damages a source project is worse than no converter.
- **A plausible-looking wrong conversion is worse than a refusal.** Audio landing on the wrong track at the wrong time is a failure the user may not notice until they have built on top of it.

## Requirements

### Requirement: Command-Line Invocation

The importer SHALL be a standalone command-line program invoked with a path to an `.aup3` file, producing a directory containing the extracted audio and a single `.rpp` project file.

The importer MUST NOT require any package outside the Python 3 standard library. It MUST exit zero on a successful conversion and non-zero on any failure, so it can be used from a script.

The output directory SHALL default to the input project's basename. The importer MUST NOT overwrite an existing non-empty output directory unless explicitly told to.

#### Scenario: Successful conversion

- **WHEN** the importer is run against a readable `.aup3` project
- **THEN** it creates an output directory containing the extracted audio files and one `.rpp`, and exits zero

#### Scenario: Input file does not exist

- **WHEN** the importer is run against a path that does not exist
- **THEN** it reports the path and that it could not be found, converts nothing, and exits non-zero

#### Scenario: Input is not an Audacity project

- **WHEN** the importer is run against a file that is not a readable `.aup3` project
- **THEN** it reports what the file appears to be instead, converts nothing, and exits non-zero

#### Scenario: Output directory already has contents

- **WHEN** the target output directory exists and is not empty
- **THEN** the importer refuses, names the directory, and converts nothing unless overwriting was explicitly requested

### Requirement: Input Immutability

The importer SHALL NOT modify the input `.aup3` file in any way. It MUST open the project read-only, and MUST NOT write to it, create journal or write-ahead files beside it, or alter its metadata.

This holds on every exit path, including failures and interruptions.

#### Scenario: Source unchanged after success

- **WHEN** a conversion completes successfully
- **THEN** the input file's contents and modification time are identical to before the run

#### Scenario: Source unchanged after failure

- **WHEN** a conversion fails partway through for any reason
- **THEN** the input file's contents and modification time are identical to before the run, and no journal or auxiliary files remain beside it

### Requirement: Conversion Scope

The importer SHALL convert tracks, clips, clip **names**, clip positions, per-track gain, and audio. It MUST NOT convert envelopes, effects, or labels.

Clip names are called out explicitly because they are load-bearing rather than decorative. The narrator's retake workflow is to cut a flubbed passage onto a second track and rename that clip with the opening words of the line, then search the manuscript for that text when re-recording. A conversion that dropped names would preserve every sample and still destroy the workflow.

Anything present in the source project but outside this scope MUST be reported to the user by category, with a count — never silently dropped. The report is what tells the user whether the converted project is the whole story.

#### Scenario: Project containing out-of-scope elements

- **WHEN** a project containing envelopes, effects, or labels is converted
- **THEN** the conversion succeeds without them, and the summary names each category found and how many were skipped

#### Scenario: Project entirely within scope

- **WHEN** a project contains only tracks, clips, and audio
- **THEN** the summary reports nothing skipped

### Requirement: Timeline Placement Fidelity

Each converted clip SHALL appear on the track corresponding to its source track, at its source start time, within one sample period at the project's sample rate. Relative track order MUST be preserved.

This is the requirement the whole tool is judged by: the user's test is opening a converted project and finding their audio where they left it.

#### Scenario: Multiple tracks with offset clips

- **WHEN** a project with several tracks, each holding clips at known offsets, is converted
- **THEN** every clip appears on the corresponding track in the `.rpp` at its source start time, within one sample period

#### Scenario: Named clips

- **WHEN** a source clip carries a name
- **THEN** the corresponding item in the `.rpp` carries that name unchanged

#### Scenario: Track order preserved

- **WHEN** a project with multiple tracks is converted
- **THEN** the tracks appear in the `.rpp` in the same relative order as in the source project

### Requirement: Audio Extraction Fidelity

Extracted audio SHALL preserve the source's sample rate, bit depth, and channel count. The importer MUST NOT resample, dither, normalize, or apply gain to the extracted audio.

Per-track gain MUST be expressed in the `.rpp` rather than baked into the extracted audio, so the conversion loses no information and the user can still adjust it.

#### Scenario: Format preserved

- **WHEN** a project's audio is at a given sample rate, bit depth, and channel count
- **THEN** the extracted audio files carry the same sample rate, bit depth, and channel count

#### Scenario: Gain is carried, not applied

- **WHEN** a source track has a non-unity gain
- **THEN** the extracted audio is unmodified and the `.rpp` carries the equivalent track gain

### Requirement: Clean-Room Format Derivation

Knowledge of the `.aup3` format SHALL derive only from two sources: inspection of real `.aup3` files, and public prose descriptions such as release notes, blog posts, and forum threads.

Audacity's source MUST NOT be read by anyone working on this importer. This extends to GPL-licensed tooling built on Audacity's codebase, including `audacity-project-tools` — its behaviour MAY be observed, its source MUST NOT be read.

Every non-obvious format fact MUST carry a provenance note recording where it came from, maintained in a format document alongside the importer. A fact without a provenance note is not permitted to inform the implementation.

Where inspection cannot resolve a detail, the permitted responses are to keep experimenting, to narrow scope, or to relicense the importer under a new ADR. Consulting GPL source MUST NOT be one of them.

#### Scenario: A format fact is established

- **WHEN** a non-obvious fact about the `.aup3` format is used by the implementation
- **THEN** the format document records that fact together with the source it was derived from

#### Scenario: A format detail resists inspection

- **WHEN** a format detail cannot be resolved by inspecting files or reading public prose
- **THEN** it is recorded as unresolved and the response is further experimentation, narrowed scope, or a new ADR — and Audacity's source remains unread

### Requirement: Refusal on Unrecognized Structure

The importer SHALL detect project structures it does not recognize and refuse to convert them, rather than guessing.

A refusal MUST name what was found and what was expected. A conversion that silently produces a plausible but wrong result is a worse outcome than a refusal, because the user may build on it before noticing.

Within a recognized structure, an individual unexpected element MUST be skipped and reported rather than aborting the whole conversion.

#### Scenario: Unrecognized project structure

- **WHEN** the importer opens a project whose structure it does not recognize
- **THEN** it reports what it found and what it expected, converts nothing, and exits non-zero

#### Scenario: Recognized structure with an unexpected element

- **WHEN** a project is otherwise recognized but contains one element the importer does not understand
- **THEN** that element is skipped and named in the summary, and the rest of the conversion proceeds

### Requirement: Fixture-Based Validation

Conversion correctness SHALL be validated against real Audacity projects, not synthetic ones alone.

The release criterion is the one named in `PLAN.md`: three of the user's real `.aup3` projects convert, open in Reaper, and place their audio on the right tracks at the right timestamps. This requirement MUST NOT be treated as satisfied by synthetic fixtures alone — a synthetic project exercises only the structures the author already understood, which is precisely the wrong test for reverse-engineered format knowledge.

Fixture audio MUST be original or public-domain content, contributed under the repository licence, and MUST NOT be committed to the repository.

#### Scenario: Real projects convert correctly

- **WHEN** three real `.aup3` projects are converted and the results are opened in Reaper
- **THEN** each project's audio appears on the right tracks at the right timestamps

#### Scenario: Real fixtures unavailable

- **WHEN** real project fixtures have not been obtained
- **THEN** this requirement remains unsatisfied and the importer is not considered releasable, regardless of how many synthetic fixtures pass

#### Scenario: A real project fails to convert

- **WHEN** a real project converts incorrectly or is refused
- **THEN** the discrepancy is investigated before release, and resolved by fixing the importer or by narrowing documented scope — not by adjusting the fixture

### Requirement: Error Handling Standards

All failure modes SHALL be surfaced in plain language naming both the cause and, where one exists, the corrective action.

Errors MUST be wrapped with contextual information at each layer boundary, so a failure deep in audio extraction reports which clip and which track it came from. Silent error swallowing MUST NOT occur — every failure MUST be either reported to the user or handled with a documented reason for suppression. Raw exception text and database error codes MUST NOT be presented as the primary message, though they MAY appear as supplementary detail.

#### Scenario: A single clip fails to extract

- **WHEN** one clip cannot be extracted from an otherwise readable project
- **THEN** the failure names the track and clip it belongs to, and the importer either completes the rest and reports the gap or exits non-zero — never reports success with audio silently missing

#### Scenario: An underlying error surfaces

- **WHEN** a database or file-system error occurs
- **THEN** the primary message describes what the importer was trying to do in plain language, with the underlying error text available as supplementary detail

### Requirement: Database Operation Standards

All access to the `.aup3` SQLite database SHALL follow structured data access patterns.

The connection MUST be opened in a read-only mode enforced by the database layer rather than by convention alone. Query parameters MUST use parameterized queries — string interpolation into SQL MUST NOT occur. The connection lifecycle MUST be explicitly managed, with the connection closed on every exit path including failures.

#### Scenario: Read-only enforcement

- **WHEN** the importer opens a project
- **THEN** the connection is opened read-only such that any write attempt fails at the database layer

#### Scenario: Connection released on failure

- **WHEN** a conversion fails partway through
- **THEN** the database connection is closed before the importer exits
