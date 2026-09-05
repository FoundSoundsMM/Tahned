# TAHNED — architecture

A microtonal FM groovebox for monome norns + grid 128.
Generative sequencing, generative harmony, ever-evolving timbre.
Wordless, glyph-based, patch-reactive interface.

**Hardware contract:** norns (3 keys, 3 encoders, 128x64 screen) + grid 128 (16x8). Nothing
else. No arc, no MIDI controller, no crow, no computer. The only permitted external
dependency is an optional clock/transport source for sync. Every function of the instrument
must be reachable and performable from that surface — this is a hard constraint on the whole
design, audited in §10.

Design ancestor: **Destiny Plus Programma 900** (2024) — an FPGA/ARM "harmonic musical
computer": 6 polytonal voices with odd/even/partials/tilt harmonic controls, four-quadrant
multiplication between voices, 32 gestural CV buffers, 6 interpolating morph inputs per
voice, A-B-C location morphing, a long stereo regeneration engine, and a desktop app whose
most interesting mode is a physics field of bouncing balls driving modulation.

We are not cloning it. We are stealing its stance: the instrument is a machine for generating
harmonic relationships, and every control is a macro over a spectrum rather than a knob on an
oscillator. Its designer's framing — "it's a computer, not a synthesizer" — is the useful part.

---

## 0. The spine

**One integer lattice drives pitch, timbre, and time.**

The single architectural commitment everything else hangs off. A rational `n/d` in the active
lattice can be spent three ways:

| spent as | meaning |
|---|---|
| pitch | interval from the node's fundamental — the tuning system |
| timbre | FM operator ratio — the spectrum of the voice |
| time | clock division / polyrhythm — the groove |

A patch in 7-limit JI has 7-limit *spectra* and 7-against-4 *rhythms*, automatically. In
13-EDO the operator ratios are 13-EDO steps, so sidebands land on notes that exist. Move the
harmony and the timbre and the groove move with it.

This is what makes generative material cohere instead of turning to soup, and it's the part
that's genuinely hard to get elsewhere — commercial FM boxes hardwire integer ratios and
12-TET.

Corollary: **there is no separate sound-design mode.** Changing the lattice is a
compositional act with timbral consequences.

---

## 1. What to take from the Programma 900

| P900 | TAHNED adaptation |
|---|---|
| 6 polytonal voices | 6 FM voice nodes, each with its own tuning table — polytonal in the strong sense (different EDOs/JI subsets sounding simultaneously) |
| odd / even / partials / tilt | the **spectral macros**, mapped onto FM (§3.2). You never touch an operator directly unless you want to |
| four-quadrant multiplication of voices | the **cross-matrix**: any voice can FM or ring-modulate any other, at audio rate (§3.4) |
| 32 gestural CV buffers, per-buffer speed + attenuation | 32 **gesture lanes** — recorded or generated modulation streams, independent rates, through the mod matrix (§6) |
| 6 interpolating morph inputs per voice | **snapshot morphing** — a node's full state is a point; morph interpolates in parameter space (§7) |
| 3-location A-B-C pan | A/B/C corners of a barycentric morph pad, of which pan is one destination |
| 3000-note MIDI record buffer + looper | pattern lanes with overdub, using the same gesture machinery for note data |
| 12 min stereo regeneration, buffer filters | softcut regeneration bus, 2 x 5:49 buffers, per-loop rate/filter/feedback (§8) |
| physics mode: balls, bounce, waves, magnetism | **the field** — a grid-native physics sequencer, the primary generative engine (§5.2) |
| pnp / drum mode | per-voice **transient element** — noise/impulse into the operator matrix, so the box makes its own percussion (§3.3) |
| dice / randomise all | **perturb** — scoped, weighted, undoable, not a re-roll (§5.5) |

Deliberately not taken: literal additive synthesis with 600 partials. Norns can't, and FM
reaches similar spectral territory for a fraction of the cost. The macros are the point, not
the synthesis method underneath them.

---

## 2. System map

```
        grid 128 (16x8)          keys / encoders          [optional clock in]
              |                        |                          |
              +------------+-----------+                          |
                           |                                      |
                      ui/ (8 pages)  <---- viz bus                |
                           |                  ^                   |
                           v                  |                   v
        +---------------- model --------------|------------- clock/transport
        |  nodes[16]  patch matrix  lattice  harmony  scenes      |
        +---------------------------------------------------------+
             |              |                |               |
        seq (lattice)   gestures[32]     morph engine    perturb
             |              |                |               |
             +------- event bus (typed) -----+---------------+
                       |                |
                       v                v
                 engine_ctl        softcut regen
                       |                |
                 Engine_Tahned.sc   (2 buffers)
                       |
                  [optional MIDI/crow out — never required]
```

Two buses, and they are why the UI can be as reactive as it needs to be:

- **event bus** — every musically meaningful thing (`note`, `trig`, `collision`, `mod`,
  `morph`, `patch_change`) is published as a typed table. Subsystems subscribe. Nothing calls
  anything else directly.
- **viz bus** — a subscriber holding a decaying envelope per (surface, address). Grid and
  screen renderers are *pure functions of model + viz state*. No draw code ever lives inside a
  sequencer callback. §9.4.

---

## 3. Engine — `Engine_Tahned.sc`

### 3.1 Voice structure

**6 voices**, allocated once at init and gated — no dynamic node churn, which matters on
norns' ARM. Each voice is **4 operators** with a full **4x4 modulation matrix** plus
self-feedback, rather than fixed DX-style algorithms. Continuous topology.

```
        +------------------- 4x4 index matrix M ------------------+
        |  op1 --> op2, op3, op4, op1(fb)                         |
        |  op2 --> ...                                            |
        +---------------------------------------------------------+
   op_n : freq = f0 * ratio[n]      (ratio drawn from the active lattice)
          phase mod = sum_k M[k][n] * out_k   + transient injection
          amp env = AD/AR per op, curve
   voice out = sum_n level[n] * out_n -> tilt -> drive -> pan(A/B/C) -> buses
```

Per-voice engine state:

```
f0, ratio[1..4], level[1..4], M[4][4] (16), fb,
attack[1..4], release[1..4], curve,
tilt, drive, panABC, xmod_src, xmod_depth, xmod_mode (fm|rm),
tr_amount, tr_decay, tr_colour, tr_dest,
send_regen, amp, gate
```

~50 values per voice. **None of these are edited directly by the player.** They are the
output of macro recipes (§3.2), the matrix page, and modulation. See §10 on why this matters
now that there's no arc and no external controller.

### 3.2 Spectral macros — the P900 translation

Six macros per voice. These *are* the timbre interface.

- **ODD** — a modulator at ratio 2 against a carrier at 1 places sidebands at `1±2k`, i.e.
  odd harmonics only. ODD pushes matrix energy toward ratio-2 relationships.
- **EVEN** — ratio 1 gives the full series including evens. EVEN crossfades the matrix toward
  ratio-1 relationships. ODD/EVEN together form a continuous square↔saw axis arrived at
  spectrally rather than by waveshape.
- **PARTIALS** — FM pair bandwidth is ≈ `2(I+1)·fm`, so partial count *is* the modulation
  index: `I ≈ N/2 − 1`. One macro, physically meaningful, distributed across the matrix by a
  per-operator weight curve.
- **TILT** — spectral slope. Two-stage: a one-pole shelf pair at voice output (cheap, smooth)
  *plus* index scaling weighted by operator ratio, so tilt genuinely redistributes energy
  rather than just EQing it.
- **FEEDBACK** — progressive harmonic density into noise. The entropy axis.
- **SKEW** — detunes ratios off the lattice. 0 = locked to the tuning system (fused,
  organ-like); high = inharmonic beating clusters. The single most Autechre-sounding control
  in the instrument; must be modulatable per-node and per-note.

A macro change runs a **recipe function** in Lua that computes ratios, levels and the 16
matrix cells, then ships them as one bundled engine command. Macros are the interface; the
matrix is the implementation. The matrix remains directly editable on the PATCH page for
people who want to break the recipes.

### 3.3 Transient element (drums without external gear)

Each voice carries a fifth, non-oscillator element: a filtered noise/impulse burst with its
own short envelope, injectable **into the operator matrix** rather than just summed. Noise
phase-modulating a sine is the classic route to hats, snares and metallic hits, and it means
a self-contained groovebox doesn't need a sample player or an external drum machine.

`tr_amount` / `tr_decay` / `tr_colour` / `tr_dest` (which operator it drives). At
`tr_amount = 0` the voice is a pure FM voice. This is the P900's "pnp/drum mode" done in a
way that fits the architecture instead of bolting on a sampler.

### 3.4 Cross-matrix (four-quadrant multiplication)

Each voice writes a private audio bus and reads one modulator bus at selectable depth, in FM
or RM mode. RM is the four-quadrant multiply: sum-and-difference spectra, which between two
lattice-related voices produce *lattice-valid* new pitches. A one-block feedback delay makes
cycles legal and stable.

This is "patch things together" at audio rate, not just modulation.

### 3.5 CPU budget

6 voices x (4 operators + 1 transient + tilt + cross-mod read) = 24 oscillators, 30
envelopes, 6 filters, all audio rate; mod matrix at control rate; plus softcut regen.

**Target: < 50% DSP with all 6 voices sounding, transients active and regen running.**
Dropping from 8 voices to 6 buys the transient element and the regen headroom. If it still
doesn't fit: reduce polyphony of the *cross-matrix* (allow only 3 of 6 voices to be
cross-modulated), never reduce operators.

Prototype this on hardware at M0 before anything else is built.

---

## 4. Tuning and harmony

### 4.1 Tuning — `lib/tuning.lua`

Three backends behind one interface, `tuning:ratio(degree) -> number`:

1. **EDO(n)** — any n. 12, 13, 17, 19, 22, 24, 31, 41, 53. Non-octave too: the interface takes
   a *period*, not an assumed 2/1, so Bohlen-Pierce (13 divisions of 3/1) and the Carlos
   scales work.
2. **JI lattice** — prime limits 3/5/7/11/13. A pitch is a vector of prime exponents; movement
   is a walk on the lattice. This backend is what makes §1 work, because the exponent vector
   *is* the operator-ratio recipe.
3. **Scala `.scl`** — parsed from `norns.state.data .. "tunings/"`. Simple text format, ~60
   lines of Lua. Ships with a starter set.

Per-node tuning assignment: node 1 in 11-limit JI while node 5 is in 13-EDO is legal, and is
what "polytonal" should mean. Reference pitch, period and per-node offset are all
modulation destinations — a slowly drifting reference is a legitimate device here.

Register offsets plus a wandering chord will walk a voice down to 10Hz, which is a
click train rather than a note. Pitches are therefore **folded** into 24Hz–7kHz by
whole periods before reaching the engine: folding preserves the pitch class, where
clamping would put the voice out of tune. Found by the harness (§14), not by ear —
which is the argument for having the harness.

### 4.2 Harmony — `lib/harmony.lua`

Generates and evolves chords rather than reading a scale table.

- **Lattice walk** — the current chord is a set of lattice points. Operators: move by a prime
  axis, invert about a point, rotate the set, contract/expand. Constrained by a configurable
  *harmonic distance budget* so it wanders without dissolving.
- **Voice leading** — assign new chord tones to the 6 voices minimising total lattice distance
  from the previous assignment (greedy match). Keeps motion smooth even when the chord jumps.
- **Density / register** — how many voices sound, spread across octaves or periods.
- **Tension** — a scalar biasing the walk toward or away from low-complexity intervals. This
  is *the* "harmonise" control: one number, generative consequences, fully modulatable.
- **Harmonic rhythm** — chord changes are sequenced, so they can be polyrhythmic against the
  note rhythm. Chords in 5 while notes run in 4 is where the character lives.

---

## 5. Generative sequencing — `lib/seq.lua`

Built on norns' `lattice` library: one clock, many sprockets with independent divisions, so
polyrhythm is free and survives tempo changes.

### 5.1 Lanes

Each node owns a lane: division, length, offset, swing/drift, and a **trigger source**:

- **field** — collisions from the physics arena (§5.2)
- **euclid** — (k, n, rot), the groovebox baseline
- **CA** — 1D elementary cellular automaton; rule number is a param, the row is the pattern
- **markov** — order-1/2 chain trained live on what you play *on the grid*
- **pattern** — recorded/overdubbed steps
- **derived** — a boolean function of two other lanes (AND / XOR / NOT / delay-by-n). The
  cheapest route to genuinely strange rhythm: XOR two euclids of coprime length and you get a
  long non-repeating pattern from two integers of storage.

Per-step conditions on every lane: probability, `every N`, `not N`, `first of N`, ratchet
count, tie. Conditions are what make a groovebox feel alive and they cost nothing.

### 5.2 The field — physics sequencer

The P900's ball mode, made grid-native and made the centrepiece.

An arena mapped 1:1 onto grid keys:
- **balls** (up to 8) — position, velocity, mass, trail
- **walls / mirrors** — placed by the player; angled reflectors redirect velocity
- **nodes** — dropped into the arena; a ball strike triggers the node, with **velocity →
  dynamics** and **angle of incidence → a modulation value**
- **attractors / repellers** — the P900's magnetism; inverse-square, clamped
- **wave offsets** — slow field distortion bending trajectories, so a stable pattern gradually
  destabilises

Runs at 60Hz on its own metro, independent of the clock, and **quantises its triggers to the
lane division**. This is critical: unquantised it's mush, quantised it's a sequencer that
never repeats but always grooves.

### 5.3 Gesture lanes as triggers

Any of the 32 gesture lanes (§6) can be thresholded into triggers, so recorded hand motion
becomes rhythm.

### 5.4 Time feel

Swing, humanise (timing + dynamics), and **drift** — per-lane slow tempo deviation resyncing
at loop boundaries. Drift is why this won't sound like a step sequencer.

### 5.5 Perturb — `lib/perturb.lua`

Scoped, weighted mutation. Choose scope (node / page / all), amount, and a *mask* of eligible
parameter classes. Perturbation is a random walk from the current value with a mostly-small,
rarely-large distribution — not a re-roll. Undo ring of the last 16 states. Reachable from
every page via the shift layer (§9.7), because on a self-contained instrument it's a
performance control, not a utility.

---

## 6. Gesture lanes — `lib/gesture.lua`

32 lanes. Direct descendant of the P900's CV buffers.

- **Length** up to 6 minutes at 100Hz = 36,000 floats/lane; all 32 full is 1.15M floats, too
  much for naive Lua tables. Store as **delta-encoded segments** with linear interpolation on
  playback; typical gestures compress 10–30x. Hard ceiling of 8MB for the pool, enforced.
- **Per lane**: speed multiplier (including negative and non-integer free-running rates),
  attenuation, offset, mode (loop / one-shot / ping-pong / trigger-locked), quantise-to-lattice.
- **Recording sources — all internal**: encoder motion, grid position on the field or morph
  pad, a held key's X/Y on any page, a ball's X or Y, the envelope of the audio bus, or
  another lane through a transform.
- **Generators** for lanes that aren't recorded: LFO, sample-and-hold, drunk walk, chaotic
  attractor (Lorenz/Hénon — good for correlated motion across 2–3 lanes at once).
- **Destinations**: any node param, any macro, field physics constants, harmony tension, lane
  divisions, regen params, and — optionally, never required — crow outs or MIDI CC.

Matrix: 32 sources x 64 destinations, stored sparse, bipolar depth, per-cell mode
(`add` / `multiply` / `sample-on-trig`).

---

## 7. Morph and scenes — `lib/morph.lua`

- A **snapshot** is the full model state minus the gesture pool: node params, macros, matrix,
  lanes, harmony state, field layout.
- **A/B/C corners** with a barycentric pad: position inside a triangle yields a weighted
  interpolation of three snapshots. Interpolation is type-aware — continuous params lerp,
  ratios interpolate *along the lattice* so intermediate states stay in tune, discrete params
  (rule numbers, lane sources) switch at a threshold with hysteresis.
- **Morph position is itself a modulation destination**, so a gesture lane drives the morph —
  the P900's interpolating morph inputs.
- **Scenes** (8) with chaining and per-scene morph targets, so a piece is a path through
  parameter space rather than a list of patterns.

---

## 8. Regeneration — `lib/regen.lua`

softcut, not the SC engine. 2 buffers x 5:49.

- 3 stereo loops: loop length (20ms → minutes), rate (negative and non-integer, lattice-
  derived), feedback ≥ 1.0 permitted behind a limiter, pre/post filter with mode + resonance,
  stereo spread.
- **Modes**: dub, granular (short randomised windows), freeze, time-stretch (rate/pitch
  decoupled via short-window overlap).
- The buffer is a **first-class source**: a lane can trigger playback of a random buffer
  position, making the delay a sampler of the piece's own past. This is the best idea in the
  P900's 12-minute regen buffers and it costs almost nothing here.

**Constraint found during implementation.** norns routes the *whole* engine output
into softcut as a single stereo tap (`audio.level_eng_cut`), so a per-voice regen
send is not possible without moving regeneration into the SC engine and giving up
softcut's 5:49 buffers. That is the wrong trade — the long buffer is the feature.
The regen send is therefore **global**; per-voice emphasis comes from voice gain.
An FX node owns a loop and controls it, but does not select what feeds it.

---

## 9. Interface

### 9.1 Wordless rule

No words. Not on screen, not in grid semantics. The only text anywhere is **numerals**, and
only where precision is the point: ratios (`7/4`), EDO numbers (`13`), clock divisions
(`5:4`), BPM. Everything else is shape, brightness, position and motion.

Flagging this as an assumption: a fully numeral-free build is possible but makes deliberate
tuning much harder, and ratios read as glyphs anyway.

### 9.2 Grid brightness grammar

Consistent on every page. Learn it once:

```
 0   absent / off
 2   structure — the grid showing you where things can go
 4   available but empty
 8   assigned / has content
11   selected / focused
13   held (finger down)
15   firing now (decays back to its resting level)
```

Nothing is ever lit at an arbitrary level. Every brightness means one of these seven things.
This is the load-bearing element of the wordless design — enforce it without exception.

### 9.3 Grid 2x2 quad-glyphs

On node pages a node occupies a **2x2 block**, giving 16 distinguishable lit-corner patterns —
enough for a real type vocabulary at grid resolution:

```
  VOICE      SEQ        MOD        LOGIC      FX         MULT      EMPTY
  # #        #  .       .  #       # #        .  .       #  .      #  .
  # #        .  #       #  .       .  .       # #        #  .      .  .
```

The base pattern draws at structure/assigned brightness; the whole block flashes to 15 on
activity and decays with a per-node envelope. The map page becomes a live readout of the
patch firing, readable from across the room.

16 node slots, of which **at most 6 may be VOICE type** (the engine's polyphony). The
remaining slots are non-sounding: mod, logic, fx-send, mult.

### 9.4 Reactive visuals — `lib/viz.lua`

The viz bus keeps `{level, decay, style}` per address, where style selects render treatment
(solid / dither / outline — the screen's 16 levels plus dithering give more separable states
than brightness alone).

- **Grid** at 30Hz baseline, 60Hz on the field page. Every event writes a spike decaying
  exponentially; decay time is per-event-type — a trig snaps, a morph glides.
- **Screen** at 30Hz with dirty-flagging. Default view is the **patch graph**: nodes as
  glyphs, connections as lines, signal shown as *sparks travelling the edges* at each lane's
  division. You can read the polyrhythm off the screen.
- **Live spectral rake** per voice: an 18x12 drawing of actual computed partial positions and
  amplitudes for the current ratios and index. Sweeping ODD visibly thins it to alternating
  lines. This is the wordless replacement for a parameter readout, and it teaches the
  instrument while you play it. With no arc, this is the primary feedback for timbre editing —
  make it good.
- **Ghost arcs**: a modulated parameter draws a second, dimmer arc showing where modulation is
  currently pushing it. Essential now that there's no arc hardware showing modulated position.

### 9.5 Screen glyph set — `lib/glyph.lua`, `docs/GLYPHS.md`

7x7 and 9x9 bitmaps from a single table, used identically everywhere:

| concept | glyph |
|---|---|
| FM voice | two nested circles, arrow outer→inner |
| operator ratio | stacked dot-pairs (n over d) |
| odd / even | comb with alternating tick heights |
| partials | a rake, vertical lines of increasing length |
| tilt | a wedge |
| feedback | loop arrow |
| skew | two combs offset from one another |
| transient | a spike with a decay tail |
| gesture lane | squiggle in a box |
| speed | chevrons; count = magnitude, direction = sign |
| attenuation | shrinking wedge |
| ball / field | dot with motion trail + wall tick |
| morph | triangle with interior dot at the morph position |
| snapshot A/B/C | three corner dots, filled = active |
| regen | concentric decaying arcs |
| probability | die face |
| mute | slash |
| lattice | rhombus mesh |
| clock ratio | circle with N ticks |
| CA rule | the 8-cell rule bitmap, drawn literally |

Values are **arcs and bars**, never numbers. A param is a 270° arc with a filled sweep;
bipolar params fill from centre.

### 9.6 Grid pages

Column 1 = page select (8 rows, structure brightness; current page at 11).
Columns 2–16 = content (15x8).

```
1 MAP      4x4 of 2x2 node quad-glyphs (cols 2-9) + macro strip (cols 10-15):
           6 rows of horizontal bar meters = the selected node's six macros,
           press anywhere in a row to set that macro; 2 spare rows = node type picker
2 PATCH    mod matrix. rows = 8 sources (4 banks), cols = 15 destinations (banked).
           repeated presses step depth 0 -> +1 -> +2 -> -1 -> -2 -> 0, shown as brightness;
           sign shown by blink phase
3 FIELD    the physics arena. press to place/remove walls; hold to place a node;
           drag-then-release to launch a ball along the drag vector
4 LATTICE  x = 3-limit axis, y = 5-limit axis, banked for 7/11/13. lit = in current chord;
           press to add/remove; the harmony walk animates across it live
5 TIMBRE   6 voice rows x 15-step macro value; the macro being edited is chosen on row 7
           (6 keys, one per macro); row 8 = per-voice mute. holding two keys in a row sets
           a modulation *range* rather than a value
6 GESTURE  32 lanes as 2 banks of 16 (rows 1-2 and 3-4, 8 wide): hold to record, press to
           arm, brightness = live lane amplitude. rows 5-6 = speed, rows 7-8 = attenuation
7 MORPH    barycentric pad (cols 2-13); A/B/C at three corners; the interpolation position
           is a moving bright cell. cols 14-15 = scene launch (8 scenes)
8 GROOVE   8 lanes x 13 steps with conditions shown as blink patterns; cols 14-15 =
           mutes and fills
```

### 9.7 Shift layer

Holding **K1** puts the grid into its second function layer. Per page:

```
MAP      copy/paste node, clear node, node type assign
PATCH    clear row/column, invert depths
FIELD    clear walls, freeze balls, gravity/magnetism strength on the macro strip
LATTICE  change tuning backend and period; per-node tuning assignment
TIMBRE   copy voice, initialise voice, transient element controls
GESTURE  clear lane, lane mode (loop/one-shot/ping-pong), source select
MORPH    store to A / B / C, scene chain edit
GROOVE   lane trigger-source select, division, length, euclid params
```

Plus, on any page: **K1 + page column** = set slots (save/load, 8 slots, position is the
name — no text entry anywhere).

### 9.8 Keys and encoders

```
E1        focus — cycles the focused object on the current page (node / lane / gesture)
E2, E3    the two primary continuous values for (page, focus), from a per-page table;
          always drawn as arcs with ghost-arc modulation display
K1        shift (held)
K2, K3    context actions, drawn as glyphs in the screen's bottom corners
K1+E1     page
K1+E2/E3  the secondary continuous pair for the current page
K1+K2     stop / reset
K1+K3     play / pause
K2+K3     perturb, scoped to the current page
K1+K2+K3  undo perturb
```

K2 and K3 pressed *together* is the only key combination no page uses, which is
why perturb gets it: the audit in Sec. 10 requires perturb to reach every page, and
K1+K2 / K1+K3 were already spent on transport. A page's own K2/K3 action is
withheld until release and suppressed if the other key went down first, so the
combination never fires a page action by accident.

Transport keys follow the external source when one is selected (§11), and drive the internal
clock otherwise.

---

## 10. Control-surface completeness audit

The hard constraint from §0 of the hardware contract. Every subsystem must have a home. No
subsystem may be reachable *only* through the norns params menu.

| subsystem | primary control | secondary |
|---|---|---|
| voice macros (6 x 6) | TIMBRE page rows; MAP macro strip | E2/E3 when a node is focused |
| operator matrix | PATCH page (direct cell edit) | recipe functions drive it by default |
| transient element | TIMBRE shift layer | — |
| cross-matrix (voice→voice) | PATCH page, dedicated destination bank | — |
| tuning system + period | LATTICE shift layer | — |
| per-node tuning | LATTICE shift + node select | — |
| chord / harmony walk | LATTICE page | tension on E3 |
| harmony tension, density | LATTICE page E2/E3 | mod destination |
| lane trigger source | GROOVE shift layer | — |
| lane division / length / euclid | GROOVE shift layer | E2/E3 |
| step conditions | GROOVE page, per-step hold + E2 | — |
| field: walls, balls, attractors | FIELD page | — |
| field physics constants | FIELD shift layer, macro strip | mod destinations |
| gesture record / arm / clear | GESTURE page + shift | — |
| gesture speed / attenuation | GESTURE page rows 5–8 | — |
| mod matrix routing | PATCH page | — |
| snapshots A/B/C | MORPH shift layer | — |
| morph position | MORPH pad | mod destination |
| scenes + chaining | MORPH page cols 14–15 | shift for chain edit |
| regen loops | MAP macro strip with an FX node focused | mod destinations |
| perturb | K2+K3 together on any page, scope = current page | K1+K2+K3 undoes |
| mixer / levels | TIMBRE row 8 (mute) + macro strip amp | — |
| save / load sets | K1 + page column, 8 slots | params PSET as a mirror |
| clock source, tempo | K1+E2 on any page | params menu |

**Anything that fails this audit gets cut or gets a home. No exceptions** — a parameter with
no physical control on a self-contained instrument is a parameter that doesn't exist.

---

## 11. Clock, transport, and optional outputs

- **Clock**: norns' built-in clock sources (internal / MIDI / Link / crow) are all supported
  as-is; this is the one sanctioned external dependency. `clock.transport.start/stop/reset`
  callbacks drive the sequencer, and K1+K2/K3 mirror them locally.
- **Optional outputs, never required**: MIDI out in MPE mode (one channel per voice,
  per-note pitch bend for arbitrary cents — this lets the tuning engine drive external gear),
  and crow CV from any gesture lane. Both default to off and neither appears in the control
  audit, because the instrument must be complete without them.
- **No external inputs** beyond clock. No MIDI-in requirement, no crow-in requirement. The
  markov chains train on grid input; gesture lanes record from the grid, encoders and internal
  signals.

---

## 12. Data model and persistence

- **params** — norns `params` for everything belonging in a PSET: tempo feel, per-voice macros
  (6 x 6), regen, mixer, tuning selection, matrix depths as a group. ~180 params, grouped per
  node. The menu is a fallback and a MIDI-mapping surface, not the interface.
- **Not in params** (too large or too structured): gesture pool, field layout, lane patterns,
  snapshots, matrix topology. These serialise to `norns.state.data .. "sets/<n>.tah"` as a
  `tab.save` table, written via `params.action_write` / `action_read` so save and load remain
  a single gesture (K1 + page column, §9.7).
- Snapshots reference the gesture pool by id; the pool is global to a set.
- Version field in the file header with a migration function table, from commit one.

---

## 13. File layout

```
tahned.lua                  entry: init, redraw, key/enc, grid connect
lib/
  Engine_Tahned.sc          SuperCollider engine
  engine_ctl.lua            command bundling, param registration, recipe -> engine
  model.lua                 the single state table + accessors
  bus.lua                   typed event bus (pub/sub)
  node.lua                  node objects, types, macro recipes
  patch.lua                 mod matrix, sparse, bipolar depths
  tuning.lua                EDO / JI lattice / scala
  harmony.lua               chord generation, lattice walk, voice leading
  seq.lua                   lattice sprockets, lanes, conditions
  field.lua                 physics arena
  gesture.lua               32 lanes, storage, generators
  morph.lua                 snapshots, barycentric interpolation, scenes
  regen.lua                 softcut regeneration
  perturb.lua               scoped weighted mutation + undo ring
  viz.lua                   decay envelopes, the reactive layer
  glyph.lua                 bitmap glyph table + draw helpers
  ui/
    grid_ui.lua             page dispatch, shift layer, brightness grammar helpers
    page_map.lua  page_patch.lua  page_field.lua  page_lattice.lua
    page_timbre.lua  page_gesture.lua  page_morph.lua  page_groove.lua
    screen_ui.lua           patch graph, spectral rakes, ghost arcs
data/
  tunings/*.scl             starter tuning set
docs/
  DESIGN.md   GLYPHS.md
```

---

## 14. Build order

Each milestone is playable on the hardware. Never build a milestone you can't hear.

Status as built: **M0–M8 are implemented and validated off-device.** Nothing has
run on hardware yet, so every "done when" below is satisfied under the headless
harness (`make test`), the SuperCollider class/SynthDef check (`make sc`) and an
offline NRT render — except the CPU measurement in M0, which by definition needs
the device.

| M | scope | done when |
|---|---|---|
| M0 | `Engine_Tahned.sc`: 1 voice, 4 ops, matrix, envelopes, transient. **Measure DSP on hardware.** | you can make an FM tone and a hi-hat, and you know the real cost of one voice — *graph builds and renders; DSP cost still unmeasured* |
| M1 | `tuning.lua`, 6 voices, spectral macros, recipe functions | a macro sweep audibly does the odd/even thing in 13-EDO and in 7-limit JI |
| M2 | `bus.lua`, `viz.lua`, `glyph.lua`, MAP page, screen patch graph + spectral rakes | pressing a node fires it and the whole surface visibly reacts |
| M3 | `seq.lua`: euclid, pattern, conditions, derived lanes; GROOVE page; clock/transport | it grooves, syncs, and is an instrument |
| M4 | `harmony.lua` + LATTICE page | chords evolve unattended and stay in tune |
| M5 | `gesture.lua`, `patch.lua`, PATCH + GESTURE pages, ghost arcs | modulation is recordable and routable from the grid alone |
| M6 | `field.lua` + FIELD page at 60fps | balls sequence the patch, quantised |
| M7 | `morph.lua`, scenes, `perturb.lua`, set save/load | a 20-minute unattended piece that doesn't repeat and doesn't collapse |
| M8 | `regen.lua`, control audit sweep (§10), persistence + migration, `GLYPHS.md` | ships |

Optional MIDI/crow output lands after M8, or never.

---

## 14b. Verifying without the device

`test/norns_stub.lua` is a headless stand-in for the norns API — screen, grid,
engine, params, clock, metro, softcut, poll, and a `lattice` that advances on a
virtual pulse counter. `test/run.lua` boots the real script against it and drives
every page, every key, both shift states, drags, two-finger gestures, record
cycles, perturb, save/load and all 22 tunings, then soaks for 20 seconds and
asserts the sequencer is still producing notes.

The stub is deliberately strict where it is cheap to be: it rejects out-of-range
LED coordinates and levels, non-integer LED levels, NaN or infinite values sent to
the engine, non-string arguments to `screen.text`, and values outside musical
range on `vgate` / `vratios`. Four real bugs came out of it on the first run —
nodes placed outside the arena, perturb having no hardware binding at all, base
parameter changes never reaching the engine, and softcut being sent 3,600
redundant commands a second. A fifth (sub-audio pitches) came from the range
assertions.

`make sc` compiles the engine class against a stub `CroneEngine` and builds both
SynthDefs, which is where UGen errors surface — a graph function is only evaluated
at runtime, so a bad argument would otherwise wait until the device.

## 15. Decisions

Settled:
- **grid 128** (16x8) — the page column in §9.6 depends on it
- **no arc** — all six macros live on the grid (TIMBRE rows, MAP macro strip) and on E2/E3;
  modulated position is shown by ghost arcs on screen, §9.4
- **6 voices** — matches the P900, buys headroom for the transient element and regen
- **self-contained** — clock/transport is the only permitted external dependency; §10 is the
  audit that enforces it

Settled during the build:
- **16 node slots, at most 6 VOICE** — the other ten are MOD, LOGIC, FX, MULT and SEQ,
  each of which does something real rather than being decoration (§9.3).
- **Regen send is global**, forced by norns' softcut routing (§8).
- **Perturb is K2+K3** (§9.8), because K1+K2/K3 are transport.
- **Pitches fold, they don't clamp** (§4.1).

Still open:
- Numerals for ratios and divisions (§9.1) — confirm that exception, or go fully glyph.
- GROOVE shows 13 steps (§9.6). 15 with mutes on the shift layer is the alternative;
  play it before deciding.
- The MULT node currently ratchets into one target lane. Fanning out to several
  would be more useful and costs nothing but UI.

---

## 16. Risks

1. **CPU.** The 4x4 matrix x 6 voices plus transients is the gamble. M0 exists to measure it
   before anything else is built. Fallback: restrict the cross-matrix, never the operators.
2. **Gesture storage.** 32 x 6min isn't free in Lua. Delta-segment format must be in place at
   M5, not retrofitted.
3. **Wordless legibility.** The failure mode is a beautiful instrument nobody can learn.
   Mitigations: the brightness grammar (§9.2) enforced everywhere without exception; the
   spectral rake always visible so at least one glyph teaches the synthesis; and the control
   audit (§10) guaranteeing nothing hides.
4. **No arc, six macros.** Editing six continuous values per voice with two encoders and one
   grid row each is the tightest part of the design. If TIMBRE proves clumsy at M2, the fix is
   the held-key-range gesture (two keys in a row = a range, not a value), not more pages.
5. **Generative mush.** Everything moving at once is the genre's failure mode. Mitigations:
   the field quantises, the harmony walk has a distance budget, perturb is a bounded walk, and
   every generative subsystem has a depth of 0.
6. **Scope.** M0–M3 is already a complete instrument. M4–M8 are each optional. Ship early.
