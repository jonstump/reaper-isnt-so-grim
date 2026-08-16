---
status: draft
date: 2026-08-14
implements: [ADR-0004, ADR-0003]
---

# SPEC-0001: ACX Check

## Overview

ACX Check reports whether a narration take or rendered file meets ACX's audiobook delivery specifications, and — more importantly — **how far off each measurement is and what to do about it**. It replaces the Audacity plugin the user identifies as the single tool he is most afraid of losing in the move to Reaper.

The capability produces three measurements (RMS level, peak level, noise floor), compares each against a threshold, and presents the measured value, the allowed range, the signed delta, and a plain-English adjustment hint.

Governed by [ADR-0004](../../../adrs/ADR-0004-acx-check-measurement.md), which fixes the measurement architecture (stock Reaper `CalculateNormalization`, two-pass noise-floor determination, `gfx` report surface, sample peak to match Audacity), and [ADR-0003](../../../adrs/ADR-0003-dependency-policy.md), which fixes the runtime dependency ceiling at stock Reaper plus ReaPack.

Source context: `PLAN.md` Phase 1 item 1a.1.

## Requirements

### Requirement: Input Resolution

The capability SHALL accept its analysis subject in exactly two forms: a single selected media item in the current project, or an absolute path to an audio file on disk. Both forms MUST resolve to a single `PCM_source` and MUST be analyzed by identical downstream logic.

When invoked interactively with no file path, the capability MUST require exactly one selected media item. Zero or more than one selected item MUST produce a clear error naming the constraint, and MUST NOT analyze an arbitrary subset.

#### Scenario: Exactly one item selected

- **WHEN** the user runs ACX Check with exactly one media item selected and no file path argument
- **THEN** the capability analyzes that item's active take and produces a report

#### Scenario: No item selected

- **WHEN** the user runs ACX Check with no media item selected and no file path argument
- **THEN** the capability reports "Select one media item, or run ACX Check on a rendered file" and performs no analysis

#### Scenario: Multiple items selected

- **WHEN** the user runs ACX Check with two or more media items selected
- **THEN** the capability reports that exactly one item is required and names how many are currently selected, and performs no analysis

#### Scenario: File path supplied

- **WHEN** the capability is invoked with an absolute path to a readable audio file
- **THEN** it analyzes that file and produces a report, regardless of the current item selection

#### Scenario: Unreadable file path

- **WHEN** the capability is invoked with a path that does not exist or cannot be decoded
- **THEN** it reports the path and the reason in plain language, and performs no analysis

### Requirement: Measurement Source and Version Floor

All three measurements SHALL be derived from Reaper's native `CalculateNormalization` API. The capability MUST NOT depend on SWS, ReaImGui, js_ReaScriptAPI, or any other extension, per ADR-0003.

Because `CalculateNormalization` returns a normalization gain factor rather than a level, measured levels MUST be recovered by inverting that factor against the requested target. The inversion MUST be implemented in one place and MUST NOT be duplicated per measurement.

The capability SHALL detect the running Reaper version at startup and MUST refuse to proceed on versions below the minimum that provides `CalculateNormalization`, reporting the required version explicitly.

#### Scenario: Supported Reaper version

- **WHEN** the capability runs on a Reaper version that provides `CalculateNormalization`
- **THEN** it proceeds with analysis

#### Scenario: Unsupported Reaper version

- **WHEN** the capability runs on a Reaper version that does not provide `CalculateNormalization`
- **THEN** it reports the minimum required Reaper version and the version currently running, and performs no analysis

#### Scenario: No extension present

- **WHEN** the capability runs on a Reaper install with no extensions beyond ReaPack
- **THEN** all three measurements are produced successfully

### Requirement: Threshold Configuration

ACX's thresholds SHALL be defined as named values in a single location, separate from measurement and reporting logic. The defaults MUST be: RMS level between −23 and −18 dBFS inclusive, peak level at or below −3 dBFS, and noise floor at or below −60 dBFS.

Changing a threshold MUST NOT require editing measurement or reporting code. The report MUST display the active thresholds alongside each measurement rather than assuming the reader knows them.

#### Scenario: Default thresholds applied

- **WHEN** the capability runs without threshold overrides
- **THEN** it evaluates against −23 to −18 dBFS RMS, −3 dBFS peak, and −60 dBFS noise floor

#### Scenario: Thresholds displayed

- **WHEN** a report is produced
- **THEN** each row shows the allowed range or limit for that measurement

### Requirement: Peak Measurement Convention

The headline peak measurement SHALL be **sample peak**, matching the convention used by Audacity's ACX Check, so that side-by-side comparison on the same file agrees.

True peak MUST also be computed. True peak MUST NOT determine pass or fail. When true peak exceeds sample peak by a configured margin, the report MUST show true peak as a clearly labeled secondary advisory line.

**Peak is not a ceiling-only test.** ACX specifies −3 dBFS as a maximum, but Audacity's ACX Check additionally warns when sample peak is *too low*, on the grounds that it signals over-compression or an under-recorded take. The capability MUST reproduce that warning, because the narrator reads it today and a check that silently drops it is less useful than the tool he is leaving.

A sample peak below the configured low-peak threshold MUST be reported as a **warning**, not a failure: the file still satisfies ACX's stated requirement, so it MUST NOT be presented as rejectable. The threshold SHALL live in the same named threshold table as every other value, per REQ "Threshold Configuration".

The exact value Audacity warns at is not yet established — a single observed data point is not a boundary — so it MUST be recovered by controlled observation and recorded before release, per REQ "Measurement Validation".

#### Scenario: Sample peak below the low-peak threshold

- **WHEN** sample peak is at or below the maximum but below the configured low-peak threshold
- **THEN** the peak row is reported as a warning, naming the measured value and explaining that the recording may be over-compressed or too quiet, and is not reported as a failure

#### Scenario: Sample peak comfortably within range

- **WHEN** sample peak is at or below the maximum and at or above the low-peak threshold
- **THEN** the peak row is reported as passing

#### Scenario: True peak close to sample peak

- **WHEN** true peak exceeds sample peak by less than the advisory margin
- **THEN** the report shows sample peak only

#### Scenario: True peak materially higher

- **WHEN** true peak exceeds sample peak by at least the advisory margin
- **THEN** the report shows sample peak as the pass/fail figure and true peak on a separate advisory line labeled as informational

#### Scenario: True peak does not change the verdict

- **WHEN** sample peak passes the threshold and true peak exceeds it
- **THEN** the peak row is reported as passing, with the true peak advisory shown

### Requirement: Noise Floor Region Determination

The noise floor SHALL be measured over a region of room tone rather than over the whole source, using a two-pass approach.

If a time selection exists and intersects the analysis subject, that intersection MUST be used as the measurement region and the scan MUST be skipped. Otherwise the capability MUST perform a coarse scan of the source's peak data to rank candidate quiet windows, then measure the highest-ranked window precisely using the same measurement source as the other two figures.

The coarse scan MUST NOT require reading every sample of the source. The candidate window MUST be at least a configured minimum duration. If the source is shorter than that minimum, the capability MUST report this rather than measuring an undersized window.

The report MUST display the start and end position of the region the noise floor was measured over.

#### Scenario: Time selection present

- **WHEN** a time selection exists that intersects the analysis subject
- **THEN** the noise floor is measured over that intersection and no scan is performed

#### Scenario: No time selection

- **WHEN** no time selection exists
- **THEN** the capability scans peak data to locate the quietest qualifying window and measures that window

#### Scenario: Measured region is disclosed

- **WHEN** any report is produced
- **THEN** the noise floor row shows the start and end position of the measured region

#### Scenario: Source shorter than minimum window

- **WHEN** the analysis subject is shorter than the configured minimum room-tone window
- **THEN** the capability reports that the source is too short to measure a noise floor, and still reports RMS and peak

### Requirement: Delta Calculation and Adjustment Hints

For each measurement the capability SHALL report the measured value, the allowed range or limit, the signed delta from the nearest threshold boundary, and a plain-English adjustment hint.

When RMS is below the allowed range, the hint MUST state the gain required to reach the range. Before recommending gain, the capability MUST determine whether applying that gain would push sample peak above the peak threshold. If it would, the hint MUST NOT state a gain figure and MUST instead recommend dynamics processing (compression or limiting).

When a measurement passes, the hint MUST state the available margin rather than being blank.

#### Scenario: RMS too low with sufficient headroom

- **WHEN** RMS is below the allowed range and the required gain would leave sample peak at or below the peak threshold
- **THEN** the hint states the required gain in dB

#### Scenario: RMS too low without headroom

- **WHEN** RMS is below the allowed range and the required gain would push sample peak above the peak threshold
- **THEN** the hint recommends compression or limiting, states that gain alone cannot resolve it, and does not state a gain figure

#### Scenario: RMS above the allowed range

- **WHEN** RMS exceeds the allowed range
- **THEN** the hint states the reduction in dB required to reach the range

#### Scenario: Noise floor too high

- **WHEN** the noise floor exceeds its limit
- **THEN** the hint states the delta and recommends revisiting noise reduction

#### Scenario: All measurements pass

- **WHEN** all three measurements fall within their thresholds
- **THEN** each row reports its available margin

### Requirement: Report Presentation

The report SHALL be presented in a `gfx` window containing one row per measurement, each showing measured value, allowed range or limit, delta, and hint.

The window MUST be dismissible by pressing Escape and by closing the window. The report MUST remain open until dismissed and MUST NOT auto-close on a timer.

#### Scenario: Report opens with three rows

- **WHEN** analysis completes successfully
- **THEN** a window opens showing rows for RMS level, peak level, and noise floor

#### Scenario: Dismissal by keyboard

- **WHEN** the report window has focus and the user presses Escape
- **THEN** the window closes

#### Scenario: Report persists

- **WHEN** a report window is open and the user does not interact with it
- **THEN** the window remains open indefinitely

### Requirement: Status Indication Without Reliance on Colour

Measurement status SHALL be conveyed through at least two independent channels in addition to colour: a distinct glyph per state, and text.

The report MUST NOT rely on colour as the sole differentiator between states. Red–green colour vision deficiency is common, and status is the report's primary signal.

There are **three** reportable states, and they carry different meanings that MUST NOT be collapsed into one another:

| State | Meaning |
|---|---|
| **Pass** | The measurement satisfies its threshold. |
| **Warning** | The measurement satisfies ACX's stated requirement but merits human attention — currently a sample peak below the low-peak threshold, per REQ "Peak Measurement Convention". |
| **Fail** | The measurement violates its threshold and the file would be rejected. |

Flattening a warning into a pass hides a real signal; flattening it into a failure tells the narrator a deliverable file is broken. Each state MUST therefore be distinguishable from **both** others, not merely from its neighbour — a warning glyph that reads as a variant of either pass or fail defeats the requirement.

A fourth presentation state, unavailable, already exists for measurements that could not be produced (per REQ "Error Handling Standards"); it is not a status verdict and is unaffected by this requirement.

#### Scenario: Failing measurement

- **WHEN** a measurement falls outside its threshold
- **THEN** its row shows a failure glyph, failure text, and failure colouring

#### Scenario: Warning measurement

- **WHEN** a measurement satisfies its threshold but falls within a warning band
- **THEN** its row shows a warning glyph, warning text, and warning colouring, each distinct from both the passing and the failing presentation

#### Scenario: Passing measurement

- **WHEN** a measurement falls within its threshold and outside any warning band
- **THEN** its row shows a pass glyph, pass text, and pass colouring

#### Scenario: Colour removed

- **WHEN** the report is rendered without colour information
- **THEN** passing, warning, and failing rows remain mutually distinguishable by glyph and text alone

### Requirement: Read-Only Operation

The capability SHALL NOT modify project state. It MUST NOT alter items, takes, take FX, track FX, item positions, the time selection, the edit cursor position, or the undo history.

Running ACX Check MUST leave the project in a state indistinguishable from before it ran.

#### Scenario: Project state preserved

- **WHEN** ACX Check runs to completion on a selected item
- **THEN** the edit cursor, time selection, item selection, and item properties are unchanged

#### Scenario: No undo entry

- **WHEN** ACX Check runs to completion
- **THEN** no new entry appears in the project's undo history

### Requirement: Programmatic Invocation After Render

The capability SHALL be invocable programmatically with a file path so that the audiobook export action can run it automatically on its rendered output, per `PLAN.md` item 1a.4.

A failing check MUST NOT block, cancel, or reverse the render. The render SHALL always complete, and the report SHALL be presented afterward showing any failures and their deltas.

#### Scenario: Export with passing result

- **WHEN** the audiobook export action completes and the rendered file passes all thresholds
- **THEN** the render is retained and the report shows all three measurements passing

#### Scenario: Export with failing result

- **WHEN** the audiobook export action completes and the rendered file fails one or more thresholds
- **THEN** the render is retained unmodified and the report opens showing the failures, deltas, and hints

#### Scenario: Analysis failure does not affect the render

- **WHEN** the audiobook export action completes but ACX Check cannot analyze the output
- **THEN** the render is retained and the analysis error is reported

### Requirement: Error Handling Standards

All failure modes SHALL be surfaced to the user in plain language naming both the cause and, where one exists, the corrective action.

Errors MUST NOT be silently swallowed — every failure MUST either be reported to the user or handled with a documented reason for suppression. Raw API return codes MUST NOT be presented as the primary error message, though they MAY appear as supplementary detail.

#### Scenario: Measurement API failure

- **WHEN** the measurement call fails for a source that resolved successfully
- **THEN** the capability reports that measurement failed, names the affected measurement, and performs no partial or fabricated reporting for that value

#### Scenario: Partial results

- **WHEN** one measurement fails and the others succeed
- **THEN** the report shows the successful measurements and marks the failed one as unavailable with its reason

### Requirement: Analysis Performance

Analysis of a chapter-length source SHALL complete quickly enough to be usable mid-session rather than only at the end of one.

Analysis of a 60-minute stereo source MUST complete within 5 seconds on typical consumer hardware. The noise-floor coarse scan MUST NOT read the full sample data of the source.

#### Scenario: Chapter-length source

- **WHEN** ACX Check runs on a 60-minute stereo source
- **THEN** the report appears within 5 seconds

#### Scenario: Short source

- **WHEN** ACX Check runs on a source under 5 minutes
- **THEN** the report appears without perceptible delay

### Requirement: Measurement Validation

Measurement correctness SHALL be validated before release, because a wrong reading is worse than no reading — the user will submit against these numbers.

The level-recovery inversion MUST be validated against synthesized reference signals of known level. Measurements MUST additionally be compared against Audacity's ACX Check output on the same source material. A disagreement greater than 0.5 dB on any of the three measurements MUST block release until resolved, regardless of which tool is subsequently found to be correct.

#### Scenario: Reference signal validation

- **WHEN** the capability analyzes a synthesized signal of known RMS and peak level
- **THEN** the reported values match the known values within 0.5 dB

#### Scenario: Agreement with Audacity

- **WHEN** the capability and Audacity's ACX Check analyze the same source file
- **THEN** the three reported measurements agree within 0.5 dB

#### Scenario: Disagreement blocks release

- **WHEN** any measurement disagrees with Audacity's ACX Check by more than 0.5 dB
- **THEN** the discrepancy is treated as a release blocker and investigated before shipping
