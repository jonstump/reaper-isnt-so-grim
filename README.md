# Reaper Isn't So Grim

An Audacity → Reaper transition kit for audiobook narrators.

Reaper is a better tool than Audacity for long-form narration work — take lanes for
retakes, non-destructive item FX, ripple editing, region-per-chapter rendering — and it
is also genuinely intimidating on day one. This kit makes the first day feel familiar,
replicates the Audacity tools a narrator actually depends on, and then quietly teaches
the Reaper-native way of doing each of them so the training wheels can come off.

The bridge is a **bridge, not a destination**. Success is eventually deleting most of it.

> **Status: design phase.** The architecture decisions and the ACX Check specification
> are written; no configuration, scripts, or importer code exist yet. Everything in
> "What ships" below describes the intended artifacts, not files you can install today.
> See [Roadmap](#roadmap) for where things stand.

## The gaps this fills

Three things a narrator loses when moving off Audacity, none of which Reaper answers
out of the box:

- **ACX Check.** Audacity's plugin gives a one-click pass/fail against ACX's delivery
  specs. Reaper has no equivalent — SWS can compute loudness statistics and ACX
  publishes a Reaper setup guide, but nothing produces the readout narrators rely on.
  Our version reports what matters most: not the verdict, but **how far off each
  measurement is and what to do about it**.

  ```
  RMS level    -24.6 dB   (need -23 to -18)   ✗ 1.6 dB too quiet → raise gain ~2 dB
  Peak level    -4.1 dB   (need ≤ -3)         ✓ 1.1 dB of headroom
  Noise floor  -58.3 dB   (need ≤ -60)        ✗ 1.7 dB too noisy → revisit noise reduction
  ```

- **Noise reduction.** Reaper's equivalent of Audacity's select-noise-then-apply flow is
  ReaFir in subtract mode. It works the same way; nobody can find it.

- **Opening old projects.** The only Audacity→Reaper converters that exist read the
  *legacy* `.aup` XML format. Modern Audacity writes `.aup3`, a SQLite database, and
  nobody has shipped a good `.aup3 → .rpp` converter.

ACX Check and the importer are useful well beyond one person's install, which is why
this repo is public and MIT-licensed.

## What ships

Two artifacts, split by how fast they change ([ADR-0001](docs/adrs/ADR-0001-distribution-and-install-model.md)):

| Artifact | Contents | Delivery | Lifecycle |
|---|---|---|---|
| `ReaperIsntSoGrim.ReaperConfigZip` | Keymap, toolbar, theme/screensets, project templates, FX chains | `Preferences → General → Import configuration` | Imported once; thereafter only shrinks |
| ReaPack repository | `ACXCheck.lua`, `NoiseReductionWizard.lua`, export actions | ReaPack "Synchronize packages" | Updated continuously |

The config zip is imported **before** ReaPack is installed, so the first thing you see
is your own keyboard layout rather than a package manager.

**Runtime dependency ceiling: stock Reaper (6.44+) plus ReaPack. Nothing else**
([ADR-0003](docs/adrs/ADR-0003-dependency-policy.md)) — no SWS, no ReaImGui, no
js_ReaScriptAPI, no third-party plugins. Adding one is not forbidden; it costs one ADR.

## Installing

Not yet installable. When it is, step zero is non-negotiable:

1. **Export your current Reaper configuration** (`Preferences → General → Export
   configuration`). This makes rollback to stock Reaper a single import.
2. Import `ReaperIsntSoGrim.ReaperConfigZip`.
3. Install ReaPack, add this repository, synchronize.

The kit installs into your main Reaper install and touches only *user configuration* —
keymap, theme, toolbar, templates, scripts. None of that lives in project files, so a
`.rpp` from a collaborator opens identically, and existing projects are never modified.
A portable Reaper install remains a documented escape hatch if you want the bridge fully
quarantined.

## Roadmap

### Phase 1 — The Bridge

Replicate the tools and make Reaper feel familiar.

- **ACX Check** ([SPEC-0001](docs/openspec/specs/acx-check/spec.md)) — the flagship.
  Analyzes a selected item or a rendered file through one code path, reports RMS, sample
  peak, and noise floor against ACX thresholds (−23 to −18 dBFS RMS, ≤ −3 dBFS peak,
  ≤ −60 dBFS noise floor) with deltas and plain-English hints. Measurement is Reaper's
  own `CalculateNormalization`; the report is a `gfx` window
  ([ADR-0004](docs/adrs/ADR-0004-acx-check-measurement.md)).
- **Noise Reduction wizard** — walks you through ReaFir in subtract mode.
- **Voice chain FX preset** — ReaFir → ReaEQ → ReaComp → limiter, one click, non-destructive.
- **One-click exports** — audiobook chapter (ACX-targeted MP3, auto-running ACX Check on
  the result) and podcast (−16 LUFS).
- **Familiar surroundings** — Audacity-style keymap, a "Simple Edit" screenset, an
  eight-button toolbar, and Audiobook Chapter / Podcast Episode project templates.
- **A cheat sheet that teaches the differences** — *in Audacity you did X → here press Y
  → the Reaper-native way is Z, and why it's better.*

### Phase 2 — Light `.aup3` importer

A standalone Python CLI: `aup3-to-rpp myproject.aup3` → extracted WAVs plus a `.rpp`
project. Scope is deliberately tiny — tracks, clips, positions, gain, and audio. Not
envelopes, not effects, not labels (labels are the first candidate for v1.1). Python 3,
standard library only.

### Phase 3 — Build up and out

Retire the bridge one group of bindings at a time, introduce the Reaper-native
superpowers Audacity never had, and add a "why the Reaper way wins" line to the cheat
sheet with each swap.

Full detail, milestones, and acceptance tests live in [PLAN.md](PLAN.md).

## Repository layout

```
reaper-isnt-so-grim/
├── PLAN.md                    # project plan, phases, milestones, risks
├── docs/
│   ├── adrs/                  # architecture decision records (MADR)
│   ├── openspec/specs/        # specifications
│   ├── audacity-reference-request.md
│   └── cheatsheet.md          # planned
├── config/                    # planned — sources for the ReaperConfigZip
├── scripts/                   # planned — Lua ReaScripts
├── importer/                  # planned — Phase 2 Python CLI
└── build.py                   # planned — stdlib-only build
```

Everything under `config/` is declared in `config/manifest.json` with one of two truth
modes ([ADR-0002](docs/adrs/ADR-0002-config-source-of-truth-and-build.md)): `authored`
(the repo owns it, reviewed as a text diff — keymap, menus, `.RPP` templates) or
`extracted` (a blessed Reaper install owns it — FX chains, theme, screensets). Every
`extracted` entry carries a `regenerate` instruction recording the exact click path that
reproduces it, and the build fails without one.

## Documentation

| Document | Subject |
|---|---|
| [PLAN.md](PLAN.md) | Phases, milestones, acceptance tests, risks |
| [ADR-0001](docs/adrs/ADR-0001-distribution-and-install-model.md) | Config zip for the bridge, ReaPack for the scripts |
| [ADR-0002](docs/adrs/ADR-0002-config-source-of-truth-and-build.md) | Config truth modes; stdlib Python build |
| [ADR-0003](docs/adrs/ADR-0003-dependency-policy.md) | Stock Reaper + ReaPack is the runtime ceiling |
| [ADR-0004](docs/adrs/ADR-0004-acx-check-measurement.md) | ACX measurement with stock Reaper DSP, `gfx` report |
| [ADR-0005](docs/adrs/ADR-0005-license-and-clean-room.md) | MIT licence and the clean-room rule |
| [ADR-0006](docs/adrs/ADR-0006-personalization-base-profile-and-overlays.md) | Stock-Audacity base profile; personal deltas as overlays |
| [SPEC-0001](docs/openspec/specs/acx-check/spec.md) | ACX Check requirements and scenarios ([design](docs/openspec/specs/acx-check/design.md)) |
| [Audacity reference request](docs/audacity-reference-request.md) | Optional calibration material from the Audacity side |

This project uses the [SDD plugin](https://github.com/joestump/claude-plugin-sdd) for
architecture governance — see [CLAUDE.md](CLAUDE.md).

## Contributing

Work on feature branches and open a PR; never commit to `main` directly.

**Clean-room rule ([ADR-0005](docs/adrs/ADR-0005-license-and-clean-room.md)): Audacity's
source is not to be read by anyone working on this project.** The `.aup3` format is
derived only from inspecting real `.aup3` files and from public prose descriptions of the
format. This extends to GPL tooling built on Audacity's codebase, including
`audacity-project-tools` — its behaviour may be observed, its source may not be read.
Every non-obvious format fact carries a provenance note.

Test fixtures must be original or public-domain content only, contributed under the
repository licence. Narration is copyrighted work-for-hire; a publisher's material does
not belong in a public repo.

## Prior art

- [Ultraschall](https://ultraschall.fm/) — a podcast-focused overlay on Reaper, and proof
  the model works. This is a much smaller, narration-focused version of the same idea.
- [ReaPack](https://reapack.com/user-guide) — the standard channel for distributing Reaper scripts.
- [Zylann/audacity2reaper](https://github.com/Zylann/audacity2reaper) and
  [nershman's fork](https://github.com/nershman/audacity2.0reaper) — experimental
  `.aup` (legacy XML) converters.
- [ACX: Don't Fear the Reaper](https://www.acx.com/mp/blog/dont-fear-the-reaper) — ACX's own Reaper setup guide.

## Licence

[MIT](LICENSE).
