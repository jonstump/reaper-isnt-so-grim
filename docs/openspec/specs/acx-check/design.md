# Design: ACX Check

## Context

ACX Check is Phase 1's flagship and Weekend 1's first deliverable. `PLAN.md` identifies Audacity's ACX Check plugin as the single tool the user is most afraid of losing, and identifies the *reason* precisely: it does not merely pass or fail, it tells him **how far off each parameter is**. That distinction is the product.

Two ADRs constrain the design before it starts:

* [ADR-0004](../../../adrs/ADR-0004-acx-check-measurement.md) fixed the measurement architecture — stock Reaper `CalculateNormalization`, a two-pass noise-floor determination, `gfx` for the report, and sample peak as the headline convention.
* [ADR-0003](../../../adrs/ADR-0003-dependency-policy.md) fixed the ceiling at stock Reaper plus ReaPack, which this capability is the proof of: it needs nothing else.

The design problem left over is not "which approach" — ADR-0004 settled that — but how to arrange the pieces so that a single measurement path serves both interactive and post-render use, and so that the one genuinely risky element (level recovery by inversion) is isolated where it can be tested.

Note that no source code exists yet. This design describes the intended shape rather than documenting an existing one.

## Goals / Non-Goals

### Goals

* Report three measurements with measured value, allowed range, signed delta, and an actionable hint.
* Produce numbers that agree with Audacity's ACX Check on the same file, because that agreement is what converts a skeptical user into a trusting one.
* Run on stock Reaper with no extensions.
* Serve interactive checks and automatic post-render checks through one measurement path.
* Complete on a chapter-length file fast enough to be used mid-session.
* Never modify project state.

### Non-Goals

* **Fixing anything.** ACX Check measures and advises; it does not apply gain, compression, or noise reduction. Those are separate actions the user invokes deliberately.
* **Batch checking multiple items or a whole project.** v1 handles exactly one subject per invocation.
* **Loudness formats beyond ACX's three figures.** No LUFS reporting, no publisher-specific presets beyond a configurable threshold table.
* **A general-purpose metering UI.** The report is a static readout of one analysis, not a live meter.
* **Being correct where Audacity is wrong.** Where a defensible convention choice exists — notably sample peak versus true peak — matching Audacity wins, because disagreement destroys trust faster than technical purity builds it.

## Decisions

### Level recovery by inversion, isolated behind one function

**Choice**: `CalculateNormalization` returns the gain factor that would normalize a source to a requested target. The measured level is recovered by inverting that factor against the target. This inversion lives in exactly one function, used by all three measurements.

**Rationale**: ADR-0004 chose this API because the DSP is Reaper's own, which is what makes the numbers trustworthy. The inversion is the price. Isolating it means the project's single largest correctness risk sits behind one testable boundary rather than being smeared across three call sites — and the reference-signal validation in the spec tests exactly that function.

**Alternatives considered**:
- *Inline the inversion at each call site*: rejected — three chances to get the same arithmetic wrong, and no single place to test.
- *SWS `NF_*` functions returning levels directly*: rejected by ADR-0004; would remove the inversion but add an extension dependency for arithmetic stock Reaper already provides.

### One `PCM_source` boundary for both entry points

**Choice**: The interactive path (selected item) and the programmatic path (file on disk) both resolve to a `PCM_source` before any measurement happens. Everything downstream is identical.

**Rationale**: `PLAN.md` item 1a.4 wants the export action to auto-run the check on its output. If the two paths diverged, the post-render check would be a second implementation that could drift from the interactive one — and the whole point is that the numbers he sees after export are the same numbers he'd see checking by hand. A single boundary makes that guarantee structural rather than aspirational.

### Coarse rank, then precise measure, for the noise floor

**Choice**: Locate candidate quiet windows by scanning peak data, then measure the winning window with the same `CalculateNormalization` path used for RMS and peak.

**Rationale**: Noise floor is the only measurement that requires deciding *where* to measure. Scanning full sample data for the quietest window on a 60-minute file would break the performance requirement outright; peak data is orders of magnitude smaller and is sufficient to *rank* quietness. Measuring the winner with the trusted path means the reported figure has the same provenance as the other two — the scan chooses a region, it does not produce a number.

**Alternatives considered**:
- *Full-resolution scan*: rejected on performance.
- *Always require a manual room-tone selection*: rejected in ADR-0004 as a convenience regression against Audacity on the tool he is most protective of.
- *Deriving the noise floor from peak data directly*: rejected — the scan's ranking is approximate by design, and an approximate number is exactly what must not be reported.

**Deliberate non-dependency**: the ranking requires only relative quietness, so this design does **not** depend on peak data carrying RMS values. If it does, that is an optimization.

### Time selection as the override gesture

**Choice**: An existing time selection intersecting the subject is used as the noise-floor region, skipping the scan. There is no mode, dialog, or preference.

**Rationale**: The override costs nothing to build and nothing to teach, because selecting a range is a gesture he already performs constantly — and it is the same gesture the Noise Reduction wizard will use to capture room tone. Reinforcing one gesture across both tools is worth more than a settings panel.

### Thresholds as data, displayed in the report

**Choice**: The three thresholds live in one named table, separate from measurement and reporting logic, and the active values are printed alongside each measurement.

**Rationale**: `PLAN.md` item E5 in the reference request asks whether he delivers to ACX or to a publisher with its own spec sheet — an open question whose answer may not be ACX's numbers. Keeping thresholds as data means that answer costs one edit rather than a refactor. Displaying them removes any doubt about what the verdict was measured against, which matters when he is comparing our output to Audacity's.

### The hint is where the tug-of-war is resolved

**Choice**: The RMS hint computes the required gain, then checks whether that gain would push sample peak past its threshold. If it would, the hint recommends dynamics processing and states no gain figure at all.

**Rationale**: Raising RMS toward −18 raises peaks toward −3; this is the central tension of ACX mastering. A hint that says "raise gain 2 dB" when doing so would breach the peak limit is not merely unhelpful, it is confidently wrong advice to a user who has explicitly chosen to trust this tool. Withholding the number in that case is the correct behaviour — a gain figure that cannot be applied is worse than no figure.

### Read-only, including the undo history

**Choice**: The capability touches no project state at all, and produces no undo entry.

**Rationale**: An analysis tool that moves the edit cursor or adds an undo step teaches the user that running it has consequences, which discourages running it. It should be as consequence-free as looking at a waveform. The undo-history clause is explicit because ReaScript can create undo points as a side effect of otherwise harmless calls.

### Two channels beyond colour for pass/fail

**Choice**: Every row carries a glyph and text in addition to colouring.

**Rationale**: ADR-0004 chose `gfx` specifically so colour could make pass/fail readable pre-attentively. Red–green colour vision deficiency affects roughly one in twelve men, and pass/fail is this report's primary signal — so colour must be an accelerator, never the carrier. `PLAN.md`'s own mockup already uses ✓/✗ glyphs, so this costs nothing.

## Architecture

```mermaid
sequenceDiagram
    participant U as User / Export action
    participant E as Entry point
    participant S as Source resolver
    participant N as Noise-floor locator
    participant M as Measurement core
    participant H as Hint engine
    participant R as gfx report

    alt Interactive
        U->>E: Run ACX Check (one item selected)
        E->>S: Resolve active take
    else After render
        U->>E: Run with rendered file path
        E->>S: Resolve file
    end

    S-->>E: PCM_source (single boundary)

    E->>M: Measure RMS over full range
    M-->>E: gain factor → invert → level
    E->>M: Measure sample peak + true peak
    M-->>E: gain factor → invert → level

    E->>N: Determine room-tone region
    alt Time selection intersects subject
        N-->>E: Use selection (no scan)
    else No time selection
        N->>N: Scan peak data, rank quiet windows
        N-->>E: Highest-ranked window
    end
    E->>M: Measure RMS bounded to that region
    M-->>E: gain factor → invert → noise floor

    E->>H: Three levels + active thresholds
    H->>H: Delta per measurement
    H->>H: RMS low? Would gain breach peak limit?
    alt Headroom sufficient
        H-->>E: "raise gain X dB"
    else Would breach peak
        H-->>E: "compress or limit; gain alone will not work"
    end

    E->>R: Rows: value, range, delta, hint, glyph+text+colour
    R-->>U: Report (persists until dismissed)

    Note over E,R: No project state written. No undo entry created.
```

## Risks / Trade-offs

* **The inversion may not recover levels correctly.** This is the largest risk in the capability and ADR-0004 already gates it. → Validate against synthesized reference signals *before* building anything on top. A negative result sends ADR-0004 back for revision and puts SWS back on the table.
* **Our numbers may disagree with Audacity's on real material.** He will believe Audacity, correctly, since he has no reason not to. → Comparison against his own ACX Check output is a release blocker in the spec, not a nice-to-have. The fixtures for this are already requested in `docs/audacity-reference-request.md` (items A3, D1, D3).
* **The noise-floor scan may pick the wrong region** — a held breath or a truncated tail can read quieter than genuine room tone, producing a confidently wrong number. → The measured region is displayed in the report so a bad pick is visible, and the time-selection override is always available. Mitigated, not eliminated.
* **`gfx` HiDPI and font metrics are hand-maintained.** → Accepted in ADR-0004 as the price of avoiding a ReaImGui dependency. Keep the layout simple enough that scaling problems stay cosmetic.
* **Performance on long sources depends on the coarse scan staying coarse.** → The spec makes "MUST NOT read full sample data" a requirement rather than an implementation note, so a future change that quietly reads everything fails the spec rather than just getting slower.
* **A user can close the report without reading it** and upload a failing file. → Accepted. The alternative — blocking or deleting a render — introduces a destructive action into the flagship's happy path, which is worse.

## Migration Plan

Greenfield; no migration. Delivery sequence:

1. **Spike the inversion** against reference signals. This gates everything else and is the first work item in Weekend 1.
2. Build the measurement core and source resolver behind the single `PCM_source` boundary.
3. Build the noise-floor locator, initially with the time-selection path only, then the scan.
4. Build the hint engine, including the tug-of-war case, which needs its own deliberately-constructed test fixture.
5. Build the `gfx` report.
6. Validate against his Audacity output once fixtures arrive.
7. Wire the post-render invocation into the audiobook export action.

Ships via ReaPack per ADR-0001, independently of the config package — Milestone 1 explicitly delivers this before the bridge exists.

## Open Questions

* **What is the minimum room-tone window duration?** Long enough for a stable RMS reading, short enough that a source with little silence still yields one. Needs a value chosen against his real narration sample (D1).
* **What advisory margin should trigger the true-peak line?** A threshold too low makes it appear constantly and become noise; too high and it never appears when it matters.
* **Does he actually deliver to ACX's numbers?** Reference request item E5 asks. If he delivers to a publisher with its own spec sheet, the threshold table's defaults may need to change — the design accommodates this, but the answer is not yet known.
* **Should the report offer a copy-to-clipboard action?** A publisher may ask him for numbers. Cheap to add, but adds a control to a window whose value is its simplicity.
* **What is the exact minimum Reaper version** that provides `CalculateNormalization`? The spec requires detecting and reporting it; the precise value must be confirmed against Reaper's changelog before the version check is written.
