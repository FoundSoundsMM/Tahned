# TAHNED

A microtonal FM groovebox for **norns + grid 128**.

Generative sequencing, generative harmony, ever-evolving timbre. Wordless,
glyph-based, and reactive to whatever the patch is doing.

Everything is playable from the norns and the grid alone. The only thing it will
take from outside is a clock, and that is optional.

## The idea

**One integer lattice drives pitch, timbre and time.** A ratio `n/d` is spent
three ways: as an interval, as an FM operator ratio, and as a clock division.

A patch tuned in 7-limit just intonation has 7-limit *spectra* and 7-against-4
*rhythms*. In 13-EDO the operator ratios are 13-EDO steps, so the FM sidebands
land on notes that exist. Move the harmony and the timbre and the groove move
with it.

There is no separate sound-design mode. Changing the tuning is a compositional
act with timbral consequences.

## Install

```
;install https://github.com/FoundSoundsMM/tahned
```

Or clone into `~/dust/code/tahned`. Requires a grid 128 (16x8).

## Playing it

Nothing on screen is a word. The grid's brightness is the language:

| level | meaning |
|---|---|
| off | absent |
| dim | structure — where things can go |
| low | available but empty |
| mid | assigned |
| high | selected |
| brightest | firing right now |

**Column 1 selects the page.** Columns 2–16 are the page.

| | page | what it is |
|---|---|---|
| 1 | MAP | sixteen nodes as 2x2 glyphs, plus the selected node's six macros |
| 2 | PATCH | thirty-two gesture lanes into seventy-five destinations |
| 3 | FIELD | the physics arena — balls, walls, mirrors, attractors |
| 4 | LATTICE | the harmonic lattice: fifths across, thirds up |
| 5 | TIMBRE | six voices, fifteen steps of macro value each |
| 6 | GESTURE | all thirty-two modulation lanes |
| 7 | MORPH | the A/B/C barycentric pad and eight scenes |
| 8 | GROOVE | lane steps, mutes, ratchets |

### Keys

```
K1              shift (held)
K1 + K2         stop and reset          K1 + K3   play / pause
K2 + K3         perturb                 K1+K2+K3  undo perturb
K1 + col 1      set slots: tap to load, hold to save
K1 + E1         page
E1              focus            E2, E3   the two values for what is focused
```

`K2` and `K3` on their own do whatever the current page's corner glyphs show.

### The six macros

These are the whole timbre interface. You never touch an operator directly
unless you want to (PATCH page).

- **ODD** — a modulator at ratio 2 places sidebands at odd harmonics only
- **EVEN** — a modulator at unison gives the whole series
- **PARTIALS** — FM bandwidth is `2(I+1)fm`, so partial count *is* the index
- **TILT** — spectral slope, as index redistribution and not only EQ
- **FEEDBACK** — density into noise; the entropy axis
- **SKEW** — ratios pulled off the lattice. 0 is fused, high is beating clusters

The screen draws the actual computed spectrum of the selected voice while you
move them, so you can see what the macro is doing.

### Making it move

- **FIELD** — drag from one cell to another to launch a ball. Tap a cell to
  cycle wall / mirror / mirror / attractor / repeller. Balls run free at 60fps,
  but their strikes are quantised to each lane's division — that is what keeps
  it grooving while never repeating.
- **GESTURE** — hold a lane to record, tap to arm. Or set it to an LFO, a
  sample-and-hold, a drunk walk or a Lorenz attractor.
- **PATCH** — route any lane to any destination. Repeated presses walk the
  depth 0 → +1 → +2 → −1 → −2 → 0.
- **TIMBRE** — hold **two** keys in one voice row to set a modulation *range*
  rather than a value: the midpoint becomes the base and the span becomes a
  route from the selected gesture lane. One gesture, one patch.
- **LATTICE** — press cells to build a chord by hand, or let the walk do it.
  E2 is tension: low reaches for fifths and thirds, high for sevenths and
  elevenths.
- **PERTURB** (K2+K3) is a bounded random walk from where the parameters
  already are, scoped to the page you are looking at — never a re-roll, and
  always undoable.

## Tunings

Twelve EDOs and non-octave scales (Bohlen-Pierce, Carlos alpha/beta/gamma),
four prime-limit JI sets, and any Scala `.scl` file dropped into
`data/tunings/` or your norns data folder. Six are included:

```
harmonic_16_32   subharmonic_16_32   meantone_quarter
slendro          pelog               bohlen_pierce_ji
```

Each node can be in a different tuning at the same time.

## Development

```
make check    parse every lua file
make test     boot the script against a headless norns stand-in and drive
              every page, key and encoder. needs no norns and no SuperCollider
make sc       compile the engine class and build its SynthDefs. needs SuperCollider
make glyphs   regenerate docs/GLYPHS.md from lib/glyph.lua
```

`make test` is the useful one: it runs the real script against
`test/norns_stub.lua`, validates every LED coordinate and every value sent to
the engine, and asserts the sequencer still makes notes.

- [DESIGN.md](DESIGN.md) — the architecture and why it is shaped this way
- [docs/GLYPHS.md](docs/GLYPHS.md) — the glyph vocabulary, generated from source

## Status

Written and validated off-device: every module runs under the headless harness,
the engine class compiles, its SynthDefs build, and an offline render confirms
the macros do what the design says they do (all macros at zero gives a pure
sine; ODD at 0.95 gives odd harmonics at 83/81/100/46/77 against evens at
17/14/16/40/5).

**Not yet run on hardware.** The open question is CPU: six voices of four
operators plus transients plus softcut regeneration. Measure that first.
