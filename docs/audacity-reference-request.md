# What I need from you (Audacity side)

Hey — before I build the Reaper setup, I need to see how *you* actually work in Audacity, not how I imagine you do. The whole point is that day one in Reaper feels like your Audacity, so the more of this I get, the less guessing I do.

**None of this is urgent, and you don't have to do all of it.** If you only have fifteen minutes, do the four items in [The short version](#the-short-version) and stop. Everything else is bonus.

**A note on your client work:** please don't send me any actual audiobook material you've been paid to narrate. Anything I ask for as an audio or project file should be a throwaway — read a paragraph of something public domain (Project Gutenberg, a cereal box, whatever). I need the *shape* of your files, not the content.

---

## The short version

If you do nothing else, do these four:

1. **Your keyboard shortcuts, as a file** — `Edit → Preferences → Keyboard`, then click **Save…** and send me the `.xml` it writes. This is the single most valuable thing on this list: it tells me your exact muscle memory instead of me guessing which keys you actually press.
2. **A screenshot of your whole Audacity window**, mid-edit, with a real project open — toolbars, track panel, everything exactly as you keep it.
3. **A screenshot of ACX Check's output** — `Analyze → ACX Check` — ideally one that **passes** and one that **fails**, so I can see both readouts.
4. **Your Audacity version and OS** — `Help → About Audacity`, screenshot or just tell me. (This determines whether your old projects are `.aup3` or the older `.aup`, which changes how much work the importer is.)

---

## The full list

### A. How your Audacity is set up

| # | What | Where to find it | Send as |
|---|---|---|---|
| A1 | Keyboard shortcuts | `Edit → Preferences → Keyboard` → **Save…** | `.xml` file |
| A2 | Full window, mid-edit | Just take a screenshot with a project open | image |
| A3 | Installed plugins | Open the **Effect** menu and screenshot it; same for **Analyze**. If you have a Plugin Manager (`Effect → Plugin Manager` on newer versions), screenshot that too | images |
| A4 | Version + OS | `Help → About Audacity` | text or image |

> Menu paths below assume Audacity 3.2 or newer, where the Effect menu got reorganized into submenus. On older versions everything sits directly under **Effect** in one long list — if a path doesn't match, just look for the effect name.

### B. Your effect settings — the actual numbers

For each of these, open the effect and screenshot the dialog **with your usual values in it**. I don't need you to run them, just open them so I can see the numbers you've settled on. If you never use one, say so — that's useful too.

| # | Effect | Where |
|---|---|---|
| B1 | **Noise Reduction** — both the settings dialog *and*, if you can, a note on how long a room-tone selection you usually grab | `Effect → Noise Removal and Repair → Noise Reduction` |
| B2 | Compressor | `Effect → Volume and Compression → Compressor` |
| B3 | Normalize / Amplify / Loudness Normalization — whichever you use | `Effect → Volume and Compression → …` |
| B4 | Limiter | `Effect → Volume and Compression → Limiter` |
| B5 | Filter Curve EQ or Graphic EQ (if you use one) | `Effect → EQ and Filters → …` |
| B6 | Truncate Silence | `Effect → Special → Truncate Silence` |
| B7 | Export settings | `File → Export → Export as MP3` — screenshot the dialog including bitrate and mode |

### C. Your macros, if you have any

If you've ever built a Macro (`Tools → Macros` or `Macro Manager`), those are plain text files and they're a perfect recipe for what I need to rebuild. Zip up the whole `Macros` folder:

- **Windows:** `%AppData%\audacity\Macros`
- **macOS:** `~/Library/Application Support/audacity/Macros`
- **Linux:** `~/.config/audacity/Macros`

If that folder is empty or missing, no problem — it just means you don't use macros.

### D. Sample material (throwaway only — see the note at the top)

| # | What | Why I need it |
|---|---|---|
| D1 | **30–60 seconds of raw, unprocessed narration** — including a few seconds of pure room tone at the start, before you speak. Export as **WAV**, not MP3 | This is what I test ACX Check and the noise-reduction wizard against. The room tone at the head is the important part — it's what both tools key off of |
| D2 | **One or two small `.aup3` project files** — a couple of tracks, a few cuts, nothing fancy | These become the test fixtures for the Audacity→Reaper importer. I need real files because the format isn't documented anywhere; I have to read actual projects to figure it out |
| D3 | The **finished MP3** that came out of D1's session, if you still have it | Lets me check that my Reaper export lands in the same place yours does |

### E. Things only you can tell me (just write it out — no screenshots)

1. **Walk me through one chapter, start to finish.** Every step, in order, including the boring ones. "Open template, record, listen back, cut the bad takes, run noise reduction, run compressor, ACX Check, export, fill in metadata." I want the actual sequence, including anything you do out of superstition or habit.
2. **What do you do dozens of times per chapter?** The repeated motions are the ones worth putting on a button.
3. **What annoys you about Audacity?** Crashes, slowness, things that take too many clicks.
4. **What are you afraid of losing by switching?** You already told me ACX Check — is there anything else?
5. **Who are you delivering to?** ACX specifically, or a publisher with their own spec sheet? If it's a publisher, their spec doc would be extremely useful.
6. **Do you use labels?** If you drop label markers for pickups, retakes, or corrections, tell me — that changes what the importer needs to carry over.

---

## Where to send it

Zip the whole lot and send it however's easiest. I'll sort it into the repo.

For reference, this is where things land on my end:

```
docs/research/audacity-reference/
├── keyboard/          # A1 — the shortcuts .xml
├── screenshots/       # A2, A3, B1–B7
├── macros/            # C
└── notes.md           # E — your written answers
importer/tests/fixtures/   # D2 — the .aup3 projects
```

Audio samples (D1, D3) I'll keep out of the repo and reference separately — they're too big to belong in version control.

---

## What happens next

Once I have the short version, I can build the first three tools you named — ACX Check, the noise-reduction wizard, and your effect chain — and hand you something to try before the rest of the setup is finished. The full list makes the *rest* of it (keyboard, toolbar, templates) match your habits instead of my guesses.
