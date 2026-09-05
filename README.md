# tahned

An FM groovebox for [norns](https://monome.org/norns) and a grid 128.

Eight tracks. Each track runs one of three FM machines, each with its own
sequencer. Parameters are laid out eight to a page, and every one of them can
be locked to a single step.

> **Install the folder as `tahned`** (lowercase) in `~/dust/code/`. The
> `include()` paths depend on it.

## Machines

| | |
|---|---|
| **PERC** | Three-operator FM percussion. Pitch sweep, wavefolding on the body, a noise section and a transient. Each modulator keeps its own ratio and its own amount; they share one decay and one end level. One-shot voices. **Defaults are an 808 kick.** |
| **TONE** | Four-operator FM using the YMF262 (OPL3) waveform set, with the chip's own frequency multipliers, 6-bit operator levels and 3-bit feedback. Two ADSR envelopes, either of which can cycle. Every parameter is read live, so a note already sounding follows what you turn. Sixteen voices a track, oldest-first stealing. |
| **AMB** | A drone rather than a note player: six detuned FM partials that keep sounding, with eight trigger lanes the sequencer uses to cut rhythm and movement into the texture. |

Switching machine is non-destructive — each track keeps a slot per machine, so
its sound, sequencer settings and pattern are still there when you switch back.

## Pages

Every track has, in order:

1. **MASTER** — machine, level, pan, drive, three sends, width
2. **SEQ** — length, speed, swing, direction, rotate, probability, and two more
   depending on the machine (TONE also gets a **HARMONY** page)
3. **the machine's own pages** — three for PERC and AMB, four for TONE
4. **FILTER** — type (LP / BP / HP / comb), cutoff, res, envelope, keytrack, drive
5. **COLOUR** — crush, tape wow, saturation, compression
6. **LFO 1–4** — speed, multiplier, wave, mode, and **two destinations each**

Labels are capped at six characters, which is what fits in a 32px cell
without running into the section beside it. `tools/check-lua.lua` fails if a
longer one is ever added.

### Macros

A control that only ever moved with another one is not two controls. PERC
went from thirty-two parameters over four pages to twenty-four over three,
and COLOUR from eight to five, by pooling the pairs that were never set
apart:

| | |
|---|---|
| **M.DEC** / **M.END** | one decay and one end level for both of PERC's modulator envelopes, B kept tighter and lower than A |
| **N.DEC** | the noise envelope: its hold grows with its decay |
| **N.TONE** | the noise's character on one bipolar control — dark, coarse and grainy to the left, fine bright hiss to the right |
| **PHASE** | a locked start phase also locks the noise, so a hit set that way is identical every time |
| **BLIP** (AMB) | level and FM index together: a louder blip is a brighter one |
| **DEPTH** (AMB) | motion depth carries the amplitude wobble with it |
| **CRUSH** | bit depth and sample rate walked down together |
| **COMP** | ratio, attack and wet mix on one control |

There are no curve controls. Attacks are convex and decays and releases are
exponential, which is where the curve controls were always being left. The
slots they freed on TONE went to a real decay stage, so both of its
envelopes are ADSR rather than attack-sustain-release.

### Held notes

Every TONE parameter is read live off the control bus, so turning a ratio, an
algorithm or a waveform while a note is held is heard on that note. The
trade-off is at the other end: a parameter lock is heard for as long as its
step is current, rather than being captured for the whole of a note that
outlives the step. PERC is one-shot and latches everything at the trigger, so
its locks are exact.

Filter type picks between four separately compiled synthdefs rather than
switching at runtime, so the three filters you are not using cost nothing.

## Controls

| | |
|---|---|
| E1 | select track |
| E2 | move the cursor across the eight cells |
| E3 | edit the value under the cursor |
| K1 | shift |
| K2 / K3 | page back / forward — **pages do not wrap** |
| K2 + K3 | master |
| K1 + E2 | jump pages |
| K1 + E3 | coarse |

### Master

K2+K3 is the master page: the eight tracks with their patterns, transport,
and the three sends. E1 picks a track, E2 walks the master parameters, K1+E2
jumps between **CLOCK**, **CHORUS**, **DELAY** and **REVERB**, and E3 turns
whatever is under the cursor. The clock comes first, so E3 still lands on the
tempo the moment you get there. These are the same norns params that live in
the menu and save with the PSET — reaching for the menu to set a delay time
in the middle of a take is not a thing anybody wants to do.

On the grid, columns 1–8 pick the track, 10–12 set its machine, 14 mutes it,
and column 16 rows 1–2 are play/stop and reset. K3 also toggles play.
Selecting a track returns you to the page you last had open on it.

### Parameter locks

Hold a grid step and turn **E3** to lock the parameter under the cursor to
that step. **Hold several and the lock lands on all of them**, so a handful
of steps can be shaped in one gesture. A locked value is flagged on screen,
the header counts the pads down, and the lock reverts when the step passes.
Sequencer settings that mean something on a single step — probability,
ratchet, gate, density — lock the same way. While steps are held, **E1** sets
their velocity, and on TONE the keyboard writes notes onto all of them.

Writing a lock never pushes it at the engine. The track keeps its own value
and the change is only heard on the steps that carry it, as they come round,
so what you hear is always what the sequencer is playing rather than the
whole instrument following your hand.

A quick press toggles a step; a hold is a lock gesture and leaves it alone.

## The grid

What the 16×8 shows depends on the selected track's machine:

- **PERC** — all eight rows are steps, sixteen to a row, up to 128
- **TONE** — rows 1–4 are 64 steps, rows 5–8 an isomorphic keyboard (a scale
  degree per column, a third per row). Hold a step and play the keyboard to
  write notes onto it; play it with no step held to audition.
- **AMB** — the eight rows are the drone's eight trigger lanes (blip, gate,
  swell, shift, filter, shimmer, stutter, fold), sixteen steps each. Every lane
  has its own length and speed, so lanes drift against each other.

Playhead is full brightness, written steps scale with velocity, and every
fourth step stays faintly lit so the bars are readable.

### Leader and follower

A TONE track can name another TONE track as its **LEADER**. Its own FOLLOW
setting then decides what it does with the leader's harmony: take on the
leader's transposition (`DEGREE`), snap every note into the chord the leader is
currently sounding (`VOICE`), or play the leader's root in its own register
(`BASS`).

## Effects

Three sends — chorus, delay, and a reverb with pitch-shifted feedback for
shimmer — live in the norns params menu, along with a per-track colour chain of
bit and rate reduction, tape wow and flutter, saturation and compression.

On the reverb, **SIZE** sets the tail on its own and **SHIM FBK** regenerates
only the pitch-shifted path. They are deliberately not the same control: a
broadband loop around a reverb that already has its own decay multiplies the
two into a runaway rather than lengthening the tail.

## How the engine is wired

One SuperCollider engine drives all eight tracks. Each track owns a
96-channel control bus that Lua writes normalised values into, so a parameter
lock is just `(channel, value)` and nothing needs a special path:

```
ch  0..7   master   level pan drive sendCho sendDly sendRev width
ch  8..39  syn1..4  machine specific
ch 40..47  filter
ch 48..55  colour
ch 56..87  lfo1..4  spd mult wave mode, destA depA destB depB
ch 88..95  spare -- 88 is the LFO null destination
```

A track holds at most sixteen tone voices at once. A voice keeps its slot
until the server reports the node freed, not when the note is released, because
a voice with a long release is still a whole 4-operator FM synth — that is
exactly what makes a chord sequence with a long release run the server out of
CPU. Over the ceiling, the oldest *releasing* voice is stolen first and only
then the oldest held one, and a stolen voice is faded out over 15ms rather than
cut, so stealing does not click. Sixteen is above the largest chord one step
can resolve to, so the cap only ever eats the tail of an older chord.

Each track has a second, parallel *mod* bus holding LFO offsets only. The LFO
synth scatters into it using a dynamic-index `Out.kr`, so **any** channel above
can be a modulation destination without a routing matrix and without a cost per
destination. Voices read the sum of the two buses.

## Development

The checks all run on a desktop, with no norns and no running server:

```bash
./tools/check-engine.sh
```

Compiles the engine against the real SuperCollider class library and builds
every SynthDef graph, which catches UGen-level mistakes syntax checking cannot.
It then drives the voice allocator with stand-in synths to check the per-track
voice ceiling: that a chord fits under the cap untouched, that a releasing
voice keeps its slot until the server reports the node gone, and that stealing
takes a releasing voice before a held one.

```bash
lua tools/check-lua.lua
```

Stubs the norns API and actually runs the script: init, a redraw of every page
of every machine, page navigation, encoder edits, grid presses, parameter
locking, a run of all three sequencer types, and a save/load round trip. Its
`include()` deliberately does not cache, matching norns, so module-identity
mistakes surface here too.

```bash
./tools/check-fx.sh
```

Renders each send effect offline through `scsynth -N` — one second of noise
then silence, at the most extreme settings the params allow — and checks the
feedback loops decay, stay under full scale, and still leave a usable tail.

```bash
./tools/check-choke.sh
```

Renders one tone voice offline with a twelve second release and checks the
voice-stealing choke: silent within milliseconds of being stolen, and still
sounding when it is not.

```bash
lua tools/render-screen.lua preview   # then open preview/index.html
```

Implements the norns screen API as an SVG writer and runs the script's own
drawing code, so every page can be looked at without hardware.

## Not done yet

- Never run on hardware. Nothing here has made a sound outside an offline
  SynthDef build.
- Per-step micro-timing is not implemented.
- Amb lanes are fixed at 16 steps; per-lane speed carries the polyrhythm
  instead of longer lanes.
- Copy, paste and pattern chaining.
- MIDI in and out.
