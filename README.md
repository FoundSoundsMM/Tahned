# tahned

An FM groovebox for [norns](https://monome.org/norns) and a grid 128.

Eight tracks. Each track runs one of six FM machines — five drums and a
polyphonic voice — each with its own sequencer. Parameters are laid out eight
to a page, and every one of them can be locked to a single step.

> **Install the folder as `tahned`** (lowercase) in `~/dust/code/`. The
> `include()` paths depend on it.

## Machines

Five of them are drums. A drum is one sound, not a synth with a page of
envelopes bolted to a page of operators, so each gets **one page of eight
controls** — the eight that move that particular drum around inside its own
family. Nothing is shared between them but the channel range: KICK's FM is not
HAT's FM, and each is free to spend its eight where that family needs them.
All five are one-shot, sine FM, and latch everything at the trigger, so their
parameter locks are exact.

| | |
|---|---|
| **KICK** | Sine body, pitch drop, one modulator, a click on top. `TUNE SWEEP S.TIME DECAY FM RATIO CLICK PUNCH`. **Defaults are an 808 kick** at 49 Hz. |
| **SNARE** | Two FM tones a fifth-and-a-bit apart for the shell, filtered noise for the wires, `SNAP` between them. `TUNE SNAP FM RATIO B.DEC N.DEC N.TONE CRACK` |
| **HAT** | Six partials cross-modulated by a seventh through a resonant high band — the 808's oscillator cluster done in FM. `TUNE SPREAD FM DECAY TONE RES NOISE OPEN` |
| **TOM** | A kick that keeps its pitch: a skin transient at the front and `WOOD` ringing a shell around it. `BEND` reaches as far as the kick's `SWEEP`; the default sits half an octave in. `TUNE BEND B.TIME DECAY FM RATIO SKIN WOOD` |
| **CYMB** | The hat's cluster taken long and dense, with `SWELL` running the attack backwards for a reverse crash. `TUNE SPREAD FM DECAY TONE SIZZLE SWELL DIRT` |
| **TONE** | Four-operator FM using the YMF262 (OPL3) waveform set, with the chip's own frequency multipliers, 6-bit operator levels and 3-bit feedback. Two ADSR envelopes, either of which can cycle, and the mod EG has **two destinations**. Every parameter is read live, so a note already sounding follows what you turn. Sixteen voices a track, oldest-first stealing. |

`SPREAD` on HAT and CYMB is the one control that decides whether a cluster is a
bell or a cymbal: it walks the six or eight partials off the harmonic series
and onto an inharmonic set, and everything between the two is available.

Switching machine is non-destructive — each track keeps a slot per machine, so
its sound, sequencer settings and pattern are still there when you switch back.

## Pages

Every track has, in order:

1. **MIX** — machine, level, pan, drive, three sends
2. **SEQ** — length, speed, time signature, swing, direction, rotate,
   probability, and ratchet (drums) or strum (TONE)
3. **STEP** — what one step does with the time it gets: `HOLD` and `HTYPE`,
   plus a note offset (drums) or the gate length (TONE)
4. **the machine's own pages** — one for each drum, TONE gets HARMONY plus four.
   HARMONY is the track's own voicing — octave, chord, inversion, spread, and
   who it follows. The key it voices *in* is not here: root and scale are the
   song's, on the master's SONG page
5. **FILTER** — type (LP / BP / HP / comb), cutoff, res, envelope, keytrack, drive.
   `TYPE` draws the shape of the type and nothing else; the resonant peak
   belongs to `RES`, which has a cell of its own
6. **LFO 1–4** — speed, multiplier, wave, mode, and **two destinations each**

which is nine pages for a drum and thirteen for TONE. COLOUR is not among them
any more: it is one chain on the master rather than eight of them a track deep.

There is no per-track **WIDTH**. A mid/side trim over a track that is mostly
one voice measured something rather than moved it, and it sat where the
control everybody actually reaches for should be. PAN places the track; the
image it arrives with is left alone.

Labels are capped at six characters, which is what fits in a 32px cell
without running into the section beside it. `tools/check-lua.lua` fails if a
longer one is ever added.

### What a cell draws

Every cell carries a small picture of its value rather than a generic bar, so
a page reads as a picture of the sound. There are no blank cells and no
placeholder bars: a control with nothing to draw was a control you had to
read the number of.

The pictures are built out of the same four parts, so eight cells read as one
page rather than as eight drawings that happen to share a screen:

| | |
|---|---|
| **ground** | a magnitude sits on the bottom row of its box and is read upward from it |
| **axis** | something bipolar, or a waveform, is read about the centre line instead, with a detent on the centre |
| **ghost** | the travel a control has *and has not* used, drawn dim under the value. Nothing is ever a lone mark with no scale behind it — you can always see how much of the range is left |
| **value** | the part that is true right now, at the level of the cell: brighter under the cursor |

A glyph never draws outside its box and never draws a second picture of the
cell beside it — `TYPE` has the filter's shape, `CUTOFF` has where the corner
is, `RES` has the peak, and none of the three repeats either of the others.
Where two controls really are the same kind of thing — four operator levels,
three send levels — they really do draw the same shape, because saying
otherwise would be a lie for the sake of variety.

Some of what that gets you:

- **a ratio is drawn as the two things it is a ratio between**, in two lanes:
  the modulator on top at the ratio the list holds, the carrier under it at
  one cycle. A ratio below one is a modulator slower than its carrier and
  looks it.
- **`SWEEP` and `S.TIME` are one glide between them.** `SWEEP` puts the
  settled note where the excursion has room to show — low for a pitch falling
  onto it, high for one rising — with the dotted line at the far edge as full
  depth, four octaves. The line is straight because the glide is. `S.TIME` is
  the same glide with the stretch of time it takes marked underneath, so it is
  a duration rather than a second amplitude curve.
- **an enum is drawn as its choices**: one slot a value, the one selected
  standing up out of the row, so `MULT`, `MODE`, `CYCLE`, `FOLLOW`, `LEADER`,
  `INVERT` and the rest all read as "third of eight" without counting.
- **`MACH` draws the machine** — where that drum puts its energy and for how
  long — rather than leaving the one cell that decides what the track *is*
  empty.
- **an LFO destination draws the patch**: the LFO, the arrow, and something on
  the end of it, or a broken arrow when there is nothing there. Which
  destination it is is spelled out underneath; whether this half of the LFO is
  patched at all is the thing you cannot otherwise see at a glance.

Two of them are not per cell at all:

- **envelopes are drawn once, across all of their cells.** An envelope
  generator is one shape, not four unrelated pictures of four numbers, so
  `ATK DEC SUS REL` share a single curve running the width of the run and each
  cell simply has part of it passing through. A long attack really does push
  the decay into the next box. The cursor brightens the segment it is on, not
  the box. The filter's `ATK DEC` is the same thing two cells wide.
- **an LFO's `SPD` cell is a scope.** It draws the wave that is actually
  selected, at the rate `SPD`, `MULT` and the tempo actually give it, scrolling
  in real time — so the cell answers *how fast, and moving how* rather than
  showing a number beside a generic sine. The window is a fixed two seconds,
  so a faster LFO fits more cycles into the same box. It shares its shapes and
  its rate formula with the engine, so what is drawn is what is running.

### What moves

Three things, and nothing else — a page that animates everywhere is a page
you cannot read:

- **the LFO scope**, always. A page called LFO whose speed cell sits still is
  not showing you the speed.
- **a field of noise**, but only while the cursor is on it. `SNAP`, `NOISE`,
  `SIZZLE`, `SKIN`, `N.TONE`, `GLITCH`, `LOSS` and `WOW` are fields rather
  than shapes, and a field has something to say by moving. Motion everywhere
  at once is noise; motion on the one cell you are turning is feedback.
- **an envelope run**, which lifts on the trigger and falls back over about a
  fifth of a second, so a page with an envelope on it has a pulse while the
  sequencer is playing rather than being a still picture of a shape that is in
  fact being fired eight times a bar.

The screen metro only redraws while something is actually moving, so a still
page costs nothing.

`tools/render-screen.lua` draws every page to SVG with the script's own
drawing code, which is how the set is judged without hardware:

```bash
lua tools/render-screen.lua preview
```

### Macros

A control that only ever moved with another one is not two controls. Each
drum fits its whole voice into eight, and TONE's two loop switches became one,
by pooling the pairs that were never set apart:

| | |
|---|---|
| **PUNCH** (KICK) | drives the body and tightens its front together: a kick that is harder is also a kick that is shorter |
| **N.TONE** (SNARE) | the wires' colour and their bandwidth on one bipolar control — dark and narrow to the left, bright and open to the right |
| **OPEN** (HAT) | stretches the decay and opens a tail behind it, which is the whole of the difference between a tick and a wash |
| **CYCLE** (TONE) | one switch over both envelopes — `OFF AMP MOD BOTH` — instead of a loop switch on each; the cell it frees is where the mod EG's second destination went |
| **CRUSH** | bit depth and sample rate walked down together |
| **COMP** | ratio, attack and wet mix on one control |
| **TONE** (drive) | tilts what goes *into* the master drive rather than what comes out, and is scaled by DRIVE so the stage is transparent with the drive down |

There are no curve controls. Attacks are convex and decays and releases are
exponential, which is where the curve controls were always being left. The
slots they freed on TONE went to a real decay stage, so both of its
envelopes are ADSR rather than attack-sustain-release.

### Held notes

Every TONE parameter is read live off the control bus, so turning a ratio, an
algorithm or a waveform while a note is held is heard on that note. The
trade-off is at the other end: a parameter lock is heard for as long as its
step is current, rather than being captured for the whole of a note that
outlives the step. The drums are one-shot and latch everything at the trigger,
so their locks are exact.

Filter type picks between four separately compiled synthdefs rather than
switching at runtime, so the three filters you are not using cost nothing.

## Controls

| | |
|---|---|
| E1 | select track |
| E2 | move the cursor across the eight cells |
| E3 | edit the value under the cursor — a lock-only cell only moves while a step is held |
| K1 | shift |
| K2 / K3 | page back / forward — **pages do not wrap** |
| K2 + K3 | master |
| K1 + E2 | jump pages |
| K1 + E3 | coarse |
| K1 + K3 | play / stop |
| K1 + K2 | reset every track to the top of its pattern |

### Master

K2+K3 opens a page set of its own, walked by the same two keys: **K3
advances, K2 goes back**, and neither wraps. E1 still picks a track, E2 moves
the cursor inside the page, E3 turns what is under it, and K1+E2 jumps a whole
page.

| | |
|---|---|
| 1 **OVER** | the eight tracks with their machine, their mute and the pattern each one is playing, its playhead walking |
| 2 **PERFORM** | eight offsets that land on every voice on every track at once — `PITCH ATTACK DECAY TIMBRE CUTOFF RES FOLD DRIVE`. Centre is no change, so the page is safe to leave where it is |
| 3 **MIX** | the eight track levels as faders. It is the same channel each track's own MIX page turns |
| 4 **COLOUR** | `CRUSH WOW W.RATE SATURN TILT LOSS GLITCH COMP` |
| 5 **SEND FX** | two controls each for the reverb, the delay, the chorus and the master drive |
| 6 **SONG** | tempo, and the key everything plays in — `BPM ROOT SCALE` |
| 7–9 | chorus, delay and reverb in full |

Everything from PERFORM on is a norns param, so it saves with the PSET and
sits in the menu too — but reaching for the menu to set a delay time in the
middle of a take is not a thing anybody wants to do. SEND FX is a shortcut
rather than a fourth copy: turning `R.SIZE` there and turning `SIZE` on the
reverb page are the same act.

On the grid, columns 1–6 pick the track, 8–13 set its machine, 15 mutes it,
and column 16 rows 1–2 are play/stop and reset. Selecting a track returns you
to the page you last had open on it.

### Parameter locks

Hold a grid step and turn **E3** to lock the parameter under the cursor to
that step. **Hold several and the lock lands on all of them**, so a handful
of steps can be shaped in one gesture. A locked value is flagged on screen,
the header counts the pads down, and the lock reverts when the step passes.
Sequencer settings that mean something on a single step — probability,
ratchet, gate, and everything on the STEP page — lock the same way. While
steps are held, **E1** sets their velocity, and on TONE the keyboard writes
notes onto all of them.

Writing a lock never pushes it at the engine. The track keeps its own value
and the change is only heard on the steps that carry it, as they come round,
so what you hear is always what the sequencer is playing rather than the
whole instrument following your hand.

A quick press toggles a step; a hold is a lock gesture and leaves it alone.

### Stages

`HOLD` and `HTYPE` are **lock-only**: their cells are struck out until a grid
pad is down, because a `HOLD` written across a whole track would just be a
slower track — the point is one step that stalls.

`HOLD` is the Metropolis stage: the sequencer stays on that step for that many
pulses instead of one, and `HTYPE` says what it does with them.

| | |
|---|---|
| **HOLD** | sounds once and sits there for the rest. A TONE note sustains across the whole stage and a drum's ratchets spread over it, rather than either stopping after the first pulse |
| **REPEAT** | sounds again on every pulse |
| **RAMP** | the same, walking the level up a step each pulse — quiet into loud |
| **FALL** | the same, walking it down to nothing |

The rest of the page is per step by nature too. A drum step has always carried
a note offset and until now nothing could write one; on TONE, how long a note
lasts is about the step rather than about the pattern, and it locks the same
way.

## The grid

What the 16×8 shows depends on the selected track's machine:

- **the drums** — all eight rows are steps, sixteen to a row, up to 128
- **TONE** — rows 1–4 are 64 steps, rows 5–8 an isomorphic keyboard (a scale
  degree per column, a third per row). Hold a step and play the keyboard to
  write notes onto it; play it with no step held to audition.

The lighting is a ladder, so a pattern reads without counting pads:

| | |
|---|---|
| dark | past the end of the sequence — **the length is visible on the pads** |
| faint | inside the sequence and empty: the floor the pattern sits on |
| a little brighter | every fourth step — the ruler a pattern is counted against |
| brighter | the playhead |
| brightest | a written step, scaled by its velocity, and brightest of all with the playhead on it |

### Time signatures and polyrhythm

Every sequencer carries its own **TSIG**, from `2/4` through `7/8` to `5/16`.
The denominator is the beat unit and it scales the step — `SPEED` counts steps
per beat unit either way, so a `/8` track runs at half the step length of a
`/4` one and the two pull against each other. The numerator groups those steps
into bars, which is what the sequencer counts against the clock.

The pads and the screen do not mark those bars. At `4/4 x1` a bar is sixteen
steps, so a sixteen step pattern got one marker at step 1 and the counting the
marks exist for never happened. Every fourth step is marked instead, whatever
metre the track is in.

A track left in `4/4` runs exactly as it always did, so nothing that never
touches this moves. Eight tracks each in their own metre is the point: a
7-step `7/8` track against a 16-step `4/4` one is a real polyrhythm rather
than two patterns of different lengths.

**ROTATE** is a read-time offset, never a rewrite, so turning it back puts
everything where it was. The grid and the screen look through the same
offset, so the pattern visibly slides under a playhead that keeps walking
left to right, and a pad always edits the step it is drawing.

### Leader and follower

A TONE track can name another TONE track as its **LEADER**. Its own FOLLOW
setting then decides what it does with the leader's harmony: take on the
leader's transposition (`DEGREE`), snap every note into the chord the leader is
currently sounding (`VOICE`), or play the leader's root in its own register
(`BASS`).

Both tracks are reading the same root and scale while they do it. The key is
one setting on the master's SONG page rather than a copy per track — eight
tracks in eight different scales was never a thing anybody reached for, and a
follower in a different scale from its leader is simply wrong.

## Effects

Three sends — chorus, delay, and a reverb with pitch-shifted feedback for
shimmer — plus one **colour chain across the whole mix**, the sends included.

The delay's two cut controls were labelled the wrong way round against the
engine — its high-pass, which is the one that removes lows, was called
`HICUT` — so they are `LOCUT` and `HICUT` the way every other delay names
them, and each draws the shelf it actually is.

On the reverb, **SIZE** sets the tail on its own and **SHIM FBK** regenerates
only the pitch-shifted path. They are deliberately not the same control: a
broadband loop around a reverb that already has its own decay multiplies the
two into a runaway rather than lengthening the tail.

### Colour

It used to be a chain per track, five controls deep, eight of them running at
once. It is one chain now, at the end of everything, with eight:

| | |
|---|---|
| **CRUSH** | bit depth and sample rate walked down together |
| **WOW** / **W.RATE** | tape wow and flutter |
| **SATURN** | tape saturation, and the top end it costs |
| **TILT** | one control pivoting the spectrum about 1k, the way a DJ isolator does — lows up and highs down, or the other way |
| **LOSS** | a codec rather than a filter. Dropping the quiet bins is what an mp3 actually does, and it is what makes the artefact recognisable: the survivors smear into the holes the discarded ones leave. The threshold is taken against a level-tracked copy, not against raw magnitudes — an absolute one is a gate, wiping a quiet passage and leaving a loud one alone, which is the opposite of what a codec does |
| **GLITCH** | keeps a rolling half second of the mix and, at random, stops reading live and loops a slice of it instead, with the odd hole punched through. The buffer is always recording, so a glitch is always of something that was really just played |
| **COMP** | ratio, attack and wet mix on one control |

The order is the order damage happens in on real gear — drive, quantise,
wobble, saturate, tilt, throw information away, break it, and only then ask
something to hold the level. **DRIVE** and its **TONE** are the head of the
same chain, but they belong to the SEND FX page rather than to COLOUR.

## How the engine is wired

One SuperCollider engine drives all eight tracks. Each track owns a
96-channel control bus that Lua writes normalised values into, so a parameter
lock is just `(channel, value)` and nothing needs a special path:

```
ch  0..7   mix      level pan drive sendCho sendDly sendRev -
ch  8..39  syn      machine specific -- each synthdef carries its own map
                    the drums use 8..15, TONE 8..38
ch 40..47  filter
ch 48..55  spare -- COLOUR used to live here
ch 56..87  lfo1..4  spd mult wave mode, destA depA destB depB
ch 88..95  spare -- 88 is the LFO null destination
```

One more bus is global rather than per track: eight channels of PERFORM
offset, read by every voice on every track alongside its own parameters. Each
is −1..1 and does nothing at 0, so the page can be left wherever it is.

Bipolar controls run −63..63 rather than −64..63, so their centre normalises
to exactly 0.5 and a control sitting at zero reaches the engine as nothing.
Off by one step it is inaudible on most of them; on DETUNE it was a six
second beat between carrier and modulator on every held note.

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

**BPM** is the one destination that is not a channel. The norns clock is not
on the control bus and the engine has no say over it, so an LFO pointed at BPM
is run in lua instead — `lib/core/lfo.lua`, which holds the wave shapes and
the rate formula the engine uses, so the two agree. It only takes the tempo
while the clock source is *internal*: with MIDI, Link or crow driving it the
tempo is not ours to move, and the destination quietly does nothing. The
tempo it found is handed back when the routing goes away. The first LFO with a
BPM destination and a depth wins; two of them fighting over one clock is not a
thing worth arranging.

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
of every machine and every master page, page navigation in both, encoder
edits, grid presses, parameter locking, a run of both sequencer types, and a
save/load round trip. Its `include()` deliberately does not cache, matching
norns, so module-identity mistakes surface here too.

```bash
./tools/check-fx.sh
```

Renders each effect offline through `scsynth -N` — one second of noise then
silence, at the most extreme settings the params allow — and checks the
feedback loops decay, stay under full scale, and still leave a usable tail.
The master colour chain goes through twice: once at its extreme, where it
still has to make a sound rather than silence, and once at rest, where the
whole mix passes through it and it has to be transparent. That half is fed
four sines rather than noise, because noise is a different signal on every
render and the levels move by a third between runs.

```bash
./tools/check-choke.sh
```

Renders one tone voice offline with a twelve second release and checks the
voice-stealing choke: silent within milliseconds of being stolen, and still
sounding when it is not.

```bash
./tools/check-voice.sh
```

Renders all five drums and TONE offline and measures them. The control bus is
filled by `tools/dump-defaults.lua`, which runs the script and captures what
it actually sends, so the check is against the defaults that ship rather than
numbers copied into a test. Every drum has to sound, stay under full scale,
put its energy where that drum lives and stop when it should — a kit whose hat
rings for two seconds is not a kit. KICK is held to the 808: 49 Hz, gone by
about six tenths. It also asks whether SWEEP bends the pitch at all, and
whether a held TONE note follows a ratio turned under it. A control that looks
like a control and does nothing is exactly what this exists to catch.

The kick's `SWEEP` and `S.TIME` were caught by it twice. The check passing is
not the same as the pair doing what it says: the time ran 2ms to 600ms on an
exponential, so the whole bottom half of `S.TIME` was under 20ms — one cycle at
the pitch a kick lands on, heard as a click rather than as a pitch moving — and
the pitch envelope was exponential too, which meant the drop was over in the
first tenth of whatever `S.TIME` claimed. The law is plain now, and it is the
same for the tom's `BEND`: the control is an offset in octaves, full right is
four octaves over the tuned pitch and full left is four under, and the glide
is linear in octaves over `S.TIME` — 10ms to one second — so the pitch arrives
on the note exactly when the time is up and every part of both knobs moves it.
It is a multiplier on whatever `TUNE` settled on, so the interval is the same
at every note and the scale has nothing to do with it.

```bash
lua tools/render-screen.lua preview   # then open preview/index.html
```

Implements the norns screen API as an SVG writer and runs the script's own
drawing code, so every page can be looked at without hardware. The contact
sheet is rebuilt from the same draws, so it cannot go stale.

## Not done yet

- Never run on hardware. Everything here has been rendered offline and
  measured, never played.
- Pattern data from before the channel map moved will not load; the version
  in the file is checked and a mismatch is refused rather than read wrong.
- Per-step micro-timing is not implemented.
- The drums have no ALGO: each one's routing is fixed, chosen for that drum.
  Eight controls is the budget and a routing switch is not the best use of one.
- Copy, paste and pattern chaining.
- MIDI in and out.
