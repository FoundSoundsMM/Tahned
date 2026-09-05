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
| **PERC** | Three-operator FM percussion. Pitch sweep, wavefolding on the body, separate noise and transient sections. Each modulator has its own decay envelope with an end level and its own modulation amount. One-shot voices. |
| **TONE** | Four-operator FM using the YMF262 (OPL3) waveform set, with the chip's own frequency multipliers, 6-bit operator levels and 3-bit feedback. Two function-generator envelopes with curve shaping on attack and release, either of which can cycle. Four voice polyphony. |
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
5. **COLOUR** — bit reduction, rate reduction, tape wow, saturation, compression
6. **LFO 1–4** — speed, multiplier, wave, mode, and **two destinations each**

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
| K2 + K3 | track select and transport |
| K1 + E2 | jump pages |
| K1 + E3 | coarse |

In track select: grid columns 1–8 pick the track, 10–12 set its machine, 14
mutes it, and column 16 rows 1–2 are play/stop and reset. K3 also toggles play.
Selecting a track returns you to the page you last had open on it.

### Parameter locks

Hold a grid step and turn **E3** to lock the parameter under the cursor to that
step alone. A locked value is flagged on screen and reverts when the step
passes. Sequencer settings that mean something on a single step — probability,
ratchet, gate, density — lock the same way. While a step is held, **E1** sets
that step's velocity.

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

Each track has a second, parallel *mod* bus holding LFO offsets only. The LFO
synth scatters into it using a dynamic-index `Out.kr`, so **any** channel above
can be a modulation destination without a routing matrix and without a cost per
destination. Voices read the sum of the two buses.

## Development

Both checks run on a desktop, with no norns and no running server:

```bash
./tools/check-engine.sh
```

Compiles the engine against the real SuperCollider class library and builds
every SynthDef graph, which catches UGen-level mistakes syntax checking cannot.

```bash
lua tools/check-lua.lua
```

Stubs the norns API and actually runs the script: init, a redraw of every page
of every machine, page navigation, encoder edits, grid presses, parameter
locking, a run of all three sequencer types, and a save/load round trip. Its
`include()` deliberately does not cache, matching norns, so module-identity
mistakes surface here too.

## Not done yet

- Never run on hardware. Nothing here has made a sound outside an offline
  SynthDef build.
- Per-step micro-timing is not implemented.
- Amb lanes are fixed at 16 steps; per-lane speed carries the polyrhythm
  instead of longer lanes.
- Copy, paste and pattern chaining.
- MIDI in and out.
