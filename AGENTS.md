# AGENTS.md

Guidance for AI agents working in this repository. Read this before making changes.

## What this project is

An Audacity → Reaper transition kit for audiobook narrators. It ships two artifacts: a
`.ReaperConfigZip` (keymap, toolbar, templates, FX chains — imported once) and a ReaPack
repository of Lua ReaScripts (updated continuously). The flagship feature is **ACX Check**
(`SPEC-0001`), a Lua script that measures RMS, sample peak, and noise floor against ACX
delivery thresholds and reports deltas plus plain-English adjustment hints in a `gfx`
window.

**Current state:** design + partial implementation. The ACX Check evaluation and report
layers exist and are tested; the measurement layer (Reaper `CalculateNormalization`
integration), source resolution, and the entry point do not exist yet. The `config/`
and `importer/` (Phase 2 Python CLI) directories do not exist yet either. Do not invent
files for them.

## Architecture governance (read this first)

This repo uses the **SDD plugin** (`joestump/claude-plugin-sdd`) for architecture
governance. `CLAUDE.md` is the authoritative reference; the key points for agents:

- **ADRs** live in `docs/adrs/` (MADR format), **specs** in `docs/openspec/specs/`.
- **`SPEC-0001` (ACX Check) is the governing spec** for the current work. Every
  requirement is written as RFC 2119 SHALL/MUST statements with WHEN/THEN scenarios.
  The test suites trace directly to these scenarios.
- **`ADR-0003` is the dependency ceiling**: shipped runtime code may use **stock Reaper
  (6.44+) plus ReaPack only** — no SWS, no ReaImGui, no js_ReaScriptAPI, no third-party
  plugins. Adding one requires a new ADR. Development tooling is unconstrained, with one
  boundary: **a development dependency may never be imported by shipped code**.
- **`ADR-0004`** fixes the measurement architecture: stock Reaper `CalculateNormalization`,
  two-pass noise-floor determination, `gfx` report surface, sample peak as the pass/fail
  figure (true peak advisory only).
- **`ADR-0005` clean-room rule**: never read Audacity's source (or GPL tooling built on
  it, e.g. `audacity-project-tools`). The `.aup3` format is derived only from inspecting
  real files and public prose. Every non-obvious format fact carries a provenance note.
- **Governing comments**: source files carry `-- Governing: SPEC-0001 REQ "..."` /
  `-- Governing: ADR-0004` header comments tracing implementation to artifacts. Keep
  these accurate when you change code.
- Work on feature branches and open PRs; never commit to `main` directly.

## Commands

```sh
# Run the full test suite (plain Lua, no dependencies)
lua tests/lua/run.lua
```

- CI (`.github/workflows/tests.yml`) runs this same command on **Lua 5.3 and 5.4**
  because the ReaScript Lua version varies across supported Reaper versions. Passing on
  both is the bar. The local Homebrew `lua` is 5.5.1, so always sanity-check on a
  5.3/5.4 interpreter if available (`lua5.3`, `lua5.4`, or CI) — the suite is plain Lua
  and runs on all of them.
- The suite exits non-zero on any failure. There is no build step, no package manager,
  no linter, and no formatter configured.

## Code organization

```
scripts/
  acx/            # shipped ACX Check modules (the ReaPack package)
    thresholds.lua  # ACX threshold table; the ONLY place thresholds live
    evaluate.lua    # pure evaluation: measurements + thresholds -> report rows
    report.lua      # gfx window rendering of evaluated rows
  dev/            # development harness, NOT shipped
    fixtures.lua    # stubbed measurements for previewing the report
    ReportPreview.lua  # run from Reaper to eyeball the report against fixtures
tests/lua/        # plain-Lua test suite + mock harness
  run.lua           # minimal test runner (asserts via global T)
  mock_reaper.lua   # mocks the reaper/gfx globals so UI code runs headless
  test_evaluate.lua # tests for scripts/acx/evaluate.lua
  test_report.lua   # tests for scripts/acx/report.lua against the mock
docs/
  adrs/             # MADR architecture decision records
  openspec/specs/acx-check/  # SPEC-0001 spec.md + design.md
  audacity-reference-request.md
```

## Architecture and data flow

ACX Check is deliberately split so the parts that can be tested without Reaper are:

1. **`acx.thresholds`** — the ACX numbers (−23 to −18 dBFS RMS, ≤ −3 dBFS peak, ≤ −60
   dBFS noise floor), inclusive, plus `epsilon` (0.001) so boundary values pass. Changing
   a threshold MUST NOT require touching measurement or reporting code.
2. **`acx.evaluate`** — pure function. Input: a measurements table (levels in dBFS, any
   may be `nil` with a reason in `unavailable`). Output: three rows (`rms`, `peak`,
   `noise_floor`) each with `status` (`pass`/`fail`/`unavailable`), `value_text`,
   `limit_text`, `delta_text`, and a plain-English `hint`. No Reaper API, no I/O, no
   globals — this is the testable core.
3. **`acx.report`** — renders rows in a `gfx` window. Binds `gfx`/`reaper` at call time.
   Persists until Escape or window close (no timer). Status is carried by **three
   independent channels**: a line-primitive marker (check/cross/dash), a text label, and
   colour — colour is an accelerator, never the sole carrier (colour-vision accessibility
   requirement).

The measurement layer (per ADR-0004/SPEC-0001) will feed `evaluate` from Reaper's
`CalculateNormalization`, recovering levels by **inverting the normalization gain factor
against the requested target**, implemented in one place. It does not exist yet (issue #9
is the spike that validates this). A selected item and a rendered file must resolve to a
single `PCM_source` and flow through one code path.

### Key non-obvious behaviours in `evaluate` (all test-covered)

- **RMS tug-of-war rule**: when RMS is too low, the gain that would fix it is only
  recommended if applying it keeps sample peak ≤ −3. If it would breach peak, the hint
  says "compress or limit; gain alone cannot fix this", sets `blocked_by_peak = true`,
  and **deliberately states no gain figure** (a number that cannot be applied is worse
  than no number). If peak is `nil`, the hint states the gain but flags that peak could
  not be measured to confirm safety.
- **Passing rows state their margin** ("1.1 dB of headroom"), never blank.
- **True peak never changes the verdict**; it only adds an advisory detail line when it
  exceeds sample peak by the `true_peak_advisory_margin` (0.3 dB).
- **Unavailable measurements degrade per-row**, not wholesale — a source too short for a
  noise floor still reports RMS and peak.
- The noise floor row discloses the region it measured ("measured over 0:12.40 – 0:13.10").

## Testing approach

- Plain-Lua runner, zero dependencies (ADR-0003: dev tooling must never be imported by
  shipped code). `tests/lua/run.lua` sets `package.path` to include `./scripts/?.lua`,
  defines a global `T` (with `T.suite`, `T.check`, `T.eq`, `T.near`, `T.contains`,
  `T.not_contains`), requires each suite, and exits non-zero on failure.
- **New test files must be added to the `suites` list in `tests/lua/run.lua`** — they are
  not auto-discovered.
- `tests/lua/mock_reaper.lua` installs mock `gfx`/`reaper` globals that record every
  drawing call, so UI code runs headless. Key idioms:
  - `mock.install({ keys = {...} })` then `mock.uninstall()` around each test.
  - `mock.pump(n)` runs deferred frames (one pump iteration = one frame).
  - Query helpers: `mock.ops("init")`, `mock.drew_text(needle)`, `mock.lines_in(x,y,w,h)`,
    `mock.all_colours_grey()`, `mock.count(op)`.
  - `report.lua` is re-required fresh after installing the mock
    (`package.loaded["acx.report"] = nil`) because it binds globals at call time.
- **Test conventions**: every scenario traces to a WHEN/THEN pair in SPEC-0001; suites
  are named after the scenario. Tests assert on what was drawn (primitives, geometry,
  text), not on how it looks — visual correctness still requires Reaper.

## Gotchas and non-obvious patterns

- **Module naming**: `require("acx.evaluate")` maps to `scripts/acx/evaluate.lua` via the
  `package.path` set in `run.lua` and in `ReportPreview.lua` (which derives its path from
  `reaper.get_action_context()`). The dev harness builds its own path with `..` so it
  works when loaded from Reaper.
- **The `report.show` restart contract**: a caller must NOT call `show()` from inside
  `on_key` — the outgoing `gfx` loop would quit the new window. Return `"restart"` from
  `on_key`; the loop tears down, quits once, and re-enters via `on_restart` on its own
  frame. `ReportPreview.lua` and `test_report.lua` ("Restart handoff") both rely on this.
- **`M._internal` tables** in `evaluate.lua` and `report.lua` expose internals for tests
  (`range_delta`, `range_margin`, `fmt_db`, `fmt_time`, `luminance`, `PALETTE`, `STATUS`).
  Follow this pattern rather than exporting internals publicly.
- **Fixtures must be original or public-domain content** (ADR-0005); narration is
  copyrighted work-for-hire and does not belong in the repo.
- **`scripts/dev/` is never shipped** — the ReaPack package lists `scripts/acx/` and the
  entry point only. Keep dev harnesses out of shipped paths.
- `.sdd/issues/` holds tracker issues (SDD); `.qmd/` is a local semantic index. Both are
  gitignored. Don't treat them as source of truth for code.

## Project status / where the work is

Per the SDD tracker and spec, the remaining ACX Check work is: the measurement core
(issue #10), source resolution + noise floor + read-only guarantee (issue #11), the
post-render invocation seam (issue #13), and the level-recovery spike (issue #9). The
report and evaluation layers (issue #12) are done. `scripts/dev/ReportPreview.lua` is the
tool for eyeballing the report in Reaper before the measurement layer exists.
