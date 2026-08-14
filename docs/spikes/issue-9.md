# Spike 9: Level recovery by inversion — findings

**Status:** formula proven headless; empirical confirmation in Reaper pending
**Issue:** [#9](https://github.com/jonstump/reaper-isnt-so-grim/issues/9) · Epic #8
**Governed by:** [SPEC-0001](../openspec/specs/acx-check/spec.md) REQ "Measurement Validation", [ADR-0004](../adrs/ADR-0004-acx-check-measurement.md)

## What was asked

`CalculateNormalization` returns the gain factor that would normalize a source
to a requested target, not a level. SPEC-0001's entire measurement architecture
rests on recovering levels by inverting that factor. This spike proves the
inversion and confirms the minimum Reaper version. ADR-0004 records this as the
single largest technical risk in the capability.

## Findings

### 1. The API semantics (from the official ReaScript docs)

Signature (Lua): `number reaper.CalculateNormalization(PCM_source source, integer normalizeTo, number normalizeTarget, number normalizeStart, number normalizeEnd)`

- `normalizeTo` mode bits: **0 = LUFS-I, 1 = RMS-I, 2 = peak, 3 = true peak, 4 = LUFS-M max, 5 = LUFS-S max**.
- `normalizeTarget` is in **dBFS** for modes 1/2/3, **LUFS** for 0/4/5.
- `normalizeStart`/`normalizeEnd` bound the analysis in seconds; both `0` means the full duration.
- The return value is a **linear gain factor** (a ratio, `WDL_VAL2DB(x) = 20·log10(x)`), not a dB value and not an integer status.

### 2. The inversion formula (proven headless)

```
measured_level_dBFS = target_dBFS − 20 · log10(gain_factor)
```

Because the factor is what-remains-to-be-applied: a factor > 1 (boost needed)
means the source is quieter than the target, so the measured level is below the
target; a factor < 1 (cut needed) means the opposite. This is the formula
pinned by `tests/lua/test_level_recovery.lua` (113 tests pass, including 10 new
ones), and it is the one the implementation must cite.

The inverse is equally useful for validation:

```
expected_gain = 10 ^ ((target_dBFS − level_dBFS) / 20)
```

### 3. Minimum Reaper version is 6.44, not 6.37

From REAPER's official changelog archive (v6.44, released 2022-01-07):

> - Media items: add support for various loudness measurements (LUFS, etc) when normalizing media items
> - ReaScript: add CalculateNormalization function

`CalculateNormalization` first appears in **v6.44**. It is absent from every
v6.30–v6.43 changelog. **ADR-0004's "6.37 or newer" is wrong and is corrected
in this PR** (ADR-0004, ADR-0003, README). The spec's version check must
report 6.44.

### 4. Mode mapping for ACX Check

| Measurement | Mode | Target |
|---|---|---|
| RMS level | 1 (RMS-I) | −23 dBFS (or the lower bound, see note) |
| Sample peak | 2 (peak) | 0 dBFS (then recover; peak is a single figure, any target works) |
| True peak (advisory) | 3 (true peak) | 0 dBFS |
| Noise floor | 1 (RMS-I) bounded to the quiet window | −23 dBFS |

Note on the RMS target: the inversion needs *a* target to invert against; the
recovered level is independent of the target chosen, so −23 (the ACX lower
bound) is a fine convention. What matters is that the same target is used for
the measurement and the inversion.

## What this PR ships

- `scripts/dev/level_recovery.lua` — the inversion, the reference-tone synthesizer, and the in-Reaper validation procedure. Development only, never shipped (per the ReaPack packaging rule).
- `tests/lua/test_level_recovery.lua` — headless proof of the formula, registered in `tests/lua/run.lua`.
- `docs/spikes/issue-9.md` — this document.
- Version floor corrected from 6.37 to 6.44 in ADR-0004, ADR-0003, and README.

## What remains (blocked on a machine with Reaper)

The empirical half: run the procedure in `scripts/dev/level_recovery.lua` inside
Reaper against synthesized reference tones (e.g. a −20 dBFS RMS sine) and
confirm the recovered levels match within 0.5 dB. This is the acceptance
criterion "The inversion formula is proven against reference signals". It
cannot run in this environment (no Reaper installed), so it is tracked on the
epic per the issue's acceptance criteria, which explicitly allow this story to
close with the Audacity-comparison task outstanding.

If the in-Reaper run ever disagrees by more than 0.5 dB, ADR-0004 must be
reopened rather than worked around.

## Sources

- Official ReaScript API docs: <https://www.reaper.fm/sdk/reascript/reascripthelp.html>
- REAPER changelog archive (v6.44 entry): <https://www.reaper.fm/download-old.php?ver=6x>
- WDL `db2val.h` (`VAL2DB`/`DB2VAL`): <https://github.com/juliansader/ReaExtensions/blob/master/js_ReaScriptAPI/Source%20code/WDL/db2val.h>
- Community usage confirming the linear-ratio return (mpl ReaScripts)
