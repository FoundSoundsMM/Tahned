# TAHNED glyphs

The wordless vocabulary. **This file is generated from `lib/glyph.lua`** - that
table is the source of truth, this is a readable view of it. Regenerate with
`make glyphs` after editing the table.

`#` is a lit pixel. Glyphs are compiled once at load into horizontal runs, so a
7x7 icon costs about ten `screen.rect` calls rather than 49 `screen.pixel` calls.


## 7x7 concepts

### `voice`  (7x7)

an FM voice: two nested circles, the modulator around the carrier

```
..###..
.#...#.
#.###.#
#.###.#
#.###.#
.#...#.
..###..
```

### `odd`  (7x7)

odd harmonics present. the complement of `even`

```
#.#.#.#
#.#.#.#
#.#.#.#
#.#.#.#
#.#.#.#
#.#.#.#
#######
```

### `even`  (7x7)

even harmonics present. the complement of `odd`

```
.#.#.#.
.#.#.#.
.#.#.#.
.#.#.#.
.#.#.#.
.#.#.#.
#######
```

### `partials`  (7x7)

a rake. partial count is the modulation index

```
......#
....#.#
....#.#
..#.#.#
..#.#.#
#.#.#.#
#######
```

### `tilt`  (7x7)

spectral slope

```
......#
.....##
....###
...####
..#####
.######
#######
```

### `feedback`  (7x7)

a loop, not quite closed

```
.#####.
#.....#
#......
#......
#.....#
#....##
.####.#
```

### `skew`  (7x7)

two combs pulled out of alignment: operators off the lattice

```
#.#.#.#
#.#.#.#
#.#.#.#
.......
.#.#.#.
.#.#.#.
.#.#.#.
```

### `transient`  (7x7)

a spike with a decay tail: the noise element, where drums come from

```
..#....
..#....
..##...
..#.#..
..#..#.
..#...#
#######
```

### `gesture`  (7x7)

a recorded gesture lane

```
#######
#.....#
#...#.#
#..#..#
#.#...#
#.....#
#######
```

### `speed`  (7x7)

chevrons. count is magnitude, direction is sign

```
.......
#..#..#
.#..#..
..#..#.
.#..#..
#..#..#
.......
```

### `atten`  (7x7)

a wedge narrowing: attenuation

```
#......
##.....
####...
######.
####...
##.....
#......
```

### `ball`  (7x7)

a ball with its trail, in the field

```
.......
.....#.
....###
#.#.###
....###
.....#.
.......
```

### `morph`  (7x7)

the barycentric pad, with the interpolation position inside it

```
...#...
..#.#..
..#.#..
.#...#.
.#.#.#.
#.....#
#######
```

### `snapshot`  (7x7)

three corners: the A / B / C snapshots

```
##...##
##...##
.......
.......
..###..
..###..
.......
```

### `regen`  (7x7)

decaying echoes: the regeneration buffer

```
#......
#.#....
#.#.#..
#.#.#.#
#.#.#..
#.#....
#......
```

### `prob`  (7x7)

a die face: probability and conditions

```
#######
#.....#
#.#...#
#..#..#
#...#.#
#.....#
#######
```

### `mute`  (7x7)

a slash. drawn over whatever is muted

```
.....#.
....#..
...#...
..#....
.#.....
#......
.......
```

### `lattice`  (7x7)

the harmonic lattice mesh

```
..#.#..
.#.#.#.
#.#.#.#
.#.#.#.
#.#.#.#
.#.#.#.
..#.#..
```

### `clock`  (7x7)

a clock with a hand: divisions and ratios

```
..###..
.#...#.
#..#..#
#..##.#
#.....#
.#...#.
..###..
```

### `matrix`  (7x7)

the modulation matrix, one cell filled

```
#######
#.#.#.#
#######
#.###.#
#######
#.#.#.#
#######
```

### `map`  (7x7)

the node map

```
##.##..
##.##..
.......
##.##..
##.##..
.......
.......
```

### `groove`  (7x7)

lane steps

```
.......
##.##.#
##.##.#
##.##.#
##.##.#
##.##.#
.......
```


## 5x5 node types

### `n_voice`  (5x5)

node type: VOICE (sounds)

```
.###.
#####
#####
#####
.###.
```

### `n_seq`  (5x5)

node type: SEQ

```
#....
.#...
..#..
...#.
....#
```

### `n_mod`  (5x5)

node type: MOD (drives a gesture lane)

```
..###
.#...
..#..
...#.
###..
```

### `n_logic`  (5x5)

node type: LOGIC (a derived lane)

```
###..
#..#.
#...#
#..#.
###..
```

### `n_fx`  (5x5)

node type: FX (owns a regen loop)

```
#..#.
.#..#
#..#.
.#..#
#..#.
```

### `n_mult`  (5x5)

node type: MULT (forwards and ratchets triggers)

```
#...#
.#.#.
..#..
.#.#.
#...#
```

### `n_empty`  (5x5)

node type: empty slot

```
.....
..#..
.#.#.
..#..
.....
```


## 5x5 actions

### `a_play`  (5x5)

play

```
#....
##...
###..
##...
#....
```

### `a_stop`  (5x5)

stop

```
.....
.###.
.###.
.###.
.....
```

### `a_rec`  (5x5)

record

```
.....
.###.
#####
.###.
.....
```

### `a_clear`  (5x5)

clear

```
#...#
.#.#.
..#..
.#.#.
#...#
```

### `a_copy`  (5x5)

copy

```
###..
#.#..
#.###
..#.#
..###
```

### `a_up`  (5x5)

up

```
..#..
.###.
#.#.#
..#..
..#..
```

### `a_down`  (5x5)

down

```
..#..
..#..
#.#.#
.###.
..#..
```

### `a_hold`  (5x5)

shift is held

```
#...#
#...#
#...#
#...#
#...#
```

### `a_link`  (5x5)

route / link

```
..###
..#..
.#.#.
..#..
###..
```


## The grid quad-glyphs

On the grid a node occupies a 2x2 block. Sixteen lit-corner patterns are
available; these seven are the ones that read at a glance. Defined in
`lib/node.lua` as `node.QUAD`, ordered `{top-left, top-right, bottom-left,
bottom-right}`.

```
  VOICE      SEQ        MOD        LOGIC      FX         MULT      EMPTY
  # #        #  .       .  #       # #        .  .       #  .      #  .
  # #        .  #       #  .       .  .       # #        #  .      .  .
```

The base pattern draws at the node's resting level; the whole block lifts to 15
when the node fires and decays back. See `lib/viz.lua`.

## Brightness grammar

Enforced on every page without exception. Seven levels, seven meanings.

| level | meaning |
|---|---|
| 0 | absent / off |
| 2 | structure - where things can go |
| 4 | available but empty |
| 8 | assigned / has content |
| 11 | selected / focused |
| 13 | held (finger down) |
| 15 | firing now, decaying back to its resting level |

## Values

Values are arcs and bars, never numbers. `glyph.arc` draws a 270-degree sweep;
`glyph.bar` a filled bar. Both take a `ghost` argument marking where modulation
is currently pushing the value - with no arc hardware, this is the only way to
see the patch moving a control.

The one exception to the wordless rule is numerals, and only where precision is
the point: ratios (`7/4`), EDO steps (`4\13`), and tempo. `glyph.num` and
`glyph.ratio` are the only functions here that draw text.
