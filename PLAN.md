# Reaper Isn't So Grim
## An Audacity → Reaper transition kit — project plan & spec (v0.6)

**Repo:** `~/Repos/reaper-isnt-so-grim`

**For:** An audiobook narrator / voice editor (with podcasting as a secondary use) moving from Audacity to Reaper who finds Reaper intimidating — but who *wants to learn Reaper for its differences*, not have Reaper permanently disguised as Audacity. Audiobook production is the primary workflow, so ACX compliance and long-form narration editing drive every design decision; podcast support comes along for the ride.

**His own words, which set the strategy:**
1. "I'd rather learn Reaper for its differences" — the familiar setup is a **bridge, not a destination**.
2. Replicate his Audacity plugins and workflows first so it's familiar — **ACX Check** is the tool he's most worried about losing.
3. "Then start building up and out from there as I learn Reaper."
4. Confirmed killer tool: **light importing from Audacity + teaches the differences.**

**Guiding principle (KISS):** We are not writing an app (an interactive learning companion is filed as an option for later — see Phase 3). Reaper is already infinitely customizable — the core product is a *configuration package plus a handful of small Lua scripts*, delivered as a single file he imports once. Everything familiar we give him should also quietly teach the Reaper-native way, so the training wheels can come off.

---

## Why this approach works (prior art)

- **Ultraschall** proves the model: it's a beloved podcast-focused overlay on Reaper — custom theme, custom actions, tailored workflow — distributed as an installer on top of a normal Reaper install. We're building a much smaller, personal version of the same idea, tuned to *his* Audacity habits and to audiobook narration instead of podcasting. ([ultraschall.fm](https://ultraschall.fm/), [manual](https://ultraschall.github.io/ultraschall-manual/en/docs/introduction/))
- **Reaper natively supports exporting/importing an entire configuration** as a single `.ReaperConfigZip` (Preferences → General → Export/Import configuration). That's our distribution format — no installer to write. ([reapertips guide](https://www.reapertips.com/post/how-to-export-backup-reaper), [X-Raym's config tooling](https://www.extremraym.com/en/reaper-config-zip/))
- **ReaPack + SWS** are the standard ecosystem for distributing scripts and getting extra actions (loudness normalize, etc.). ([reapack.com](https://reapack.com/user-guide), [sws-extension.org](https://sws-extension.org/whatsnew.php))
- **The importer gap is real:** the only Audacity→Reaper converters ([Zylann/audacity2reaper](https://github.com/Zylann/audacity2reaper), [nershman's fork](https://github.com/nershman/audacity2.0reaper)) are experimental and only read the *legacy* `.aup` XML format. Modern Audacity uses `.aup3`, a SQLite database — nobody has shipped a good `.aup3 → .rpp` converter. That's a genuinely useful open-source contribution, but it's also the hardest piece, so it's **Phase 2, not Phase 1**. (Same story for ACX Check: Audacity has a beloved plugin, Reaper has no one-click equivalent — both gaps we fill are real.)

---

## The three phases

### Phase 1 — The Bridge (familiar setup + his tool stack replicated)

**Deliverable:** one `ReaperIsntSoGrim.ReaperConfigZip` + a one-page printable cheat sheet.

This is his items 1 and 2 combined: replicate the plugins and workflows first so day one feels familiar, with ACX Check as the flagship.

#### 1a. His tools, replicated

1. **ACX Check for Reaper** — the headline feature. Audacity's ACX Check plugin has no direct Reaper equivalent: SWS can compute loudness statistics, and ACX's own blog has a [Reaper setup guide](https://www.acx.com/mp/blog/dont-fear-the-reaper), but nothing gives the one-click **pass/fail readout against ACX specs** (RMS between −23 and −18 dB, peaks ≤ −3 dB, noise floor ≤ −60 dB) that he relies on. We write `ACXCheck.lua`: select an item (or point it at a rendered file) and get a report that does what he values most about the Audacity plugin — it tells you **how far off each parameter you are**, not just pass/fail. For each of the three measurements: the measured value, the allowed range, the delta, and a plain-English adjustment hint. Something like:

   ```
   RMS level    -24.6 dB   (need -23 to -18)   ✗ 1.6 dB too quiet → raise gain ~2 dB
   Peak level    -4.1 dB   (need ≤ -3)         ✓ 1.1 dB of headroom
   Noise floor  -58.3 dB   (need ≤ -60)        ✗ 1.7 dB too noisy → revisit noise reduction
   ```

   Because the deltas are known, the hints can be specific: too quiet by X → suggest exactly X dB of gain (and warn if that would push peaks past −3 dB, since raising RMS and keeping peaks legal is the classic ACX tug-of-war). This closes his single biggest stated gap — and it's genuinely useful to the wider Reaper audiobook community.
2. **Noise Reduction wizard** (the #1 Audacity tool people miss). Audacity's flow is: select noise → get profile → apply. Reaper's equivalent is **ReaFir in subtract mode**, which works the same way but nobody can find it. A small Lua script walks him through it: "Select a second of room tone → OK → now it's removed from the whole track." ([ReaFir vs Audacity comparison](https://www.homebrewaudio.com/9603/reafir-madness-hidden-noise-reduction-tool-in-reaper/), [ReaFIR vs ReaGate guide](https://simpleclean.app/blog/remove-background-noise-in-reaper))
3. **"Voice chain" FX preset** — ReaFir (noise) → ReaEQ (high-pass + presence) → ReaComp (gentle compression) → limiter. One click on any track. Equivalent to his Audacity effect stack but non-destructive — which is itself the first "Reaper difference" worth teaching.
4. **One-click exports as custom actions:** *Audiobook chapter* (192kbps CBR MP3 targeting ACX specs, auto-running ACXCheck on the result — render, see your numbers and deltas, adjust if needed, done) and, secondarily, *Podcast* (MP3 normalized to −16 LUFS via Reaper's render normalization).
5. **Truncate silence** equivalent — bind Reaper's dynamic-split/strip-silence to a friendly action.

#### 1b. Familiar surroundings

1. **Keymap** — remap Reaper's keys to match Audacity muscle memory. The big ones:
   | Audacity habit | Key | Reaper action to bind |
   |---|---|---|
   | Play/Stop (return to start) | `Space` | Play/stop (Reaper default differs: it stops *at* cursor — bind Audacity-style behavior) |
   | Split clip at cursor | `Ctrl+I` | Split items at edit cursor |
   | Delete selection & close gap | `Ctrl+K` / `Delete` | Cut selected area of items (ripple) |
   | Zoom in/out | `Ctrl+1/2/3` | Zoom actions |
   | Export | `Ctrl+Shift+E` | File: Render |
   | Undo history depth | — | Reaper's undo is already better; nothing to do |

2. **Theme + layout** — pick a clean minimal theme (Reaper 7 default theme with a simplified layout, or a flat community theme), hide everything he doesn't need: no docker, no mixer on launch, big track panels, one toolbar. Save as a **screenset/layout called "Simple Edit"** so he can always get back to it with one key.

3. **Curated toolbar** — replace Reaper's default toolbar with ~8 big buttons matching what he actually clicks in Audacity: Record, Play, Stop, Split, Delete+ripple, Noise Reduction (our script), ACX Check, Export. Nothing else.

4. **Project templates** — "Audiobook Chapter" first (1 narration track, voice chain pre-loaded, ACX-targeted render preset, ripple editing on so cut mistakes close the gap like Audacity) and "Podcast Episode" second (2–4 voice tracks, FX pre-loaded). New project = pick template = zero setup.

5. **Cheat sheet that teaches the differences** — one page, three columns: *"In Audacity you did X → here press Y → the Reaper-native way is Z (and why it's better)."* This is half the intimidation cure by itself, and it starts the "learn Reaper for its differences" journey on day one instead of hiding it.

**Acceptance test:** buddy imports one file, opens the Audiobook Chapter template, and can record narration → cut a flubbed line → run noise reduction → export an MP3 that passes ACX Check — without touching a menu he doesn't recognize. For one real chapter, his old Audacity workflow and the new Reaper workflow produce comparable output in fewer steps.

### Phase 2 — Light `.aup3` importer (open his old projects)

**Deliverable:** a standalone Python CLI: `aup3-to-rpp myproject.aup3 → myproject/` containing extracted WAVs + a `.rpp` Reaper project.

- `.aup3` is a SQLite database containing the project XML plus audio sample blocks ([format background](https://liliputing.com/audacity-3-0-released-with-new-project-file-format-open-source-cross-platform-audio-editor/), official [audacity-project-tools](https://github.com/audacity/audacity-project-tools) shows recovery/extraction is feasible).
- `.rpp` is plain text and well understood — generating one is the easy half.
- **Scope ruthlessly (KISS):** v1 converts *tracks, clips, positions, gain, and audio*. It does NOT convert envelopes, effects, or labels (labels → maybe Reaper markers in v1.1 — narrators often use them for pickup points and corrections, so this is the first upgrade to consider). Effects don't transfer anyway — that's what Phase 1's FX chains are for. "Light importing" is exactly what he confirmed he wants; resist scope creep.
- Clean-room note: read the format by inspecting files, don't port Audacity's GPL source.
- Python 3, stdlib only (`sqlite3` is built in) — same dependency-free spirit as Zylann's converter.

**Acceptance test:** open three of his real `.aup3` projects; audio lands on the right tracks at the right timestamps.

### Phase 3 — Build up and out (learn Reaper's differences)

This phase is deliberately loose — it's driven by what he bumps into as he uses the bridge. Options, roughly in order of effort:

1. **Graduation path** — as habits form, progressively retire the bridge: swap Audacity keybindings back to Reaper defaults one group at a time, introduce Reaper-native superpowers Audacity never had — many of which are *made* for audiobook work: take lanes for retakes and punch-ins (record over a flubbed line without destroying anything), non-destructive item FX, ripple editing modes, razor edits, region-per-chapter rendering to batch-export a whole book. Each swap gets a one-line "here's why the Reaper way wins" note added to the cheat sheet.
2. **"Difference of the week" nudges** — a tiny startup script that shows one Reaper-native tip per session (dismissible, off-switch included). Zero-cost teaching that doesn't require him to go read manuals.
3. **Optional: interactive learning companion app** — *filed as an option after the importer, only if he finds interactive learning helpful.* A small self-contained HTML app: "How do I do X?" lookup (searchable Audacity→Reaper translations), short practice drills, and an ACX-spec explainer. Nice-to-have, not core; the config package must stand on its own without it.

**Acceptance test:** he records, edits, and delivers a full ACX-passing chapter without reaching for anything labeled "Audacity," and can name three things Reaper does for audiobook work that Audacity couldn't.

---

## Repo layout (Claude Code-ready)

```
reaper-isnt-so-grim/
├── README.md                  # install instructions for the buddy (screenshots)
├── config/                    # Phase 1 — source files for the ReaperConfigZip
│   ├── keymap.ReaperKeyMap
│   ├── toolbar/               # toolbar .ini + icons
│   ├── templates/             # .RPP project templates
│   └── fxchains/              # .RfxChain voice-chain presets
├── scripts/                   # Phase 1 — Lua ReaScripts
│   ├── ACXCheck.lua           # the flagship
│   ├── NoiseReductionWizard.lua
│   ├── ExportPodcast.lua
│   └── ExportAudiobookACX.lua
├── importer/                  # Phase 2 — Python CLI
│   ├── aup3_to_rpp.py
│   └── tests/ + fixture .aup3 files
└── docs/
    └── cheatsheet.md          # → render to PDF
```

Workflow notes: work on feature branches, PR into main (never commit to main directly). Phase 1 needs a machine with Reaper installed to author/test the config — Claude Code writes the scripts, keymap and templates; you verify in Reaper. Phase 2's importer is fully testable headless (pure Python + text output), so it's the most Claude-Code-friendly phase.

## Milestones

1. **Weekend 1:** ACXCheck.lua + Noise Reduction wizard + voice chain — his named must-haves, deliverable even before the full config package.
2. **Weekend 2:** the rest of the bridge (keymap, toolbar, templates, cheat sheet) → give it to him, watch him use it, take notes.
3. **Weekend 3+:** `.aup3` light importer.
4. **Ongoing:** Phase 3 graduation path, tuned to what he actually struggles with; companion app only if he asks for interactive learning.

## Compatibility with his editor's Reaper projects

He occasionally works with an editor who already uses Reaper. The kit is safe for that collaboration: everything we ship is user configuration (keymap, theme, toolbar, templates, scripts), none of which is stored in project files. A `.rpp` from his editor opens identically on the customized install, and nothing we do modifies existing projects — templates only apply to new ones. Safety measures baked into the install steps:

- **Step zero of the README:** export his current config (Preferences → General → Export configuration) before importing ours, so rollback to stock Reaper is one click.
- **Optional quarantine:** if he ever wants the bridge fully isolated, install it into a Reaper *portable install* (a self-contained second Reaper in its own folder — the Ultraschall model) and leave his main install vanilla.
- Missing third-party plugin warnings when opening the editor's projects are unrelated to the kit (they'd happen on vanilla Reaper too) — worth a line in the cheat sheet so he doesn't blame the bridge.

## Risks & gotchas

- **Keymap conflicts:** remapping Space/playback behavior touches Reaper defaults that tutorials — and his editor — will assume. The cheat sheet should note where we diverged, so YouTube tutorials and "press S to split"-style advice from his editor still make sense to him.
- **aup3 format is undocumented** — expect fixture-driven reverse engineering; keep v1 scope tiny.
- **Biggest real risk is adoption, not code:** if the first session in Reaper goes badly he'll retreat to Audacity. That's why Phase 1 is the bridge (his tools + familiar setup) and not the importer — first impressions are the actual product.
- **The bridge becoming a crutch:** he explicitly wants to learn Reaper's differences, so every familiar shim should point at the native way (cheat sheet column 3, graduation path). Success is eventually deleting most of Phase 1.
