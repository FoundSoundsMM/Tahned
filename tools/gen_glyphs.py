#!/usr/bin/env python3
"""Regenerate docs/GLYPHS.md from lib/glyph.lua.

lib/glyph.lua is the source of truth for the wordless vocabulary; this only
produces a readable view of it, so the doc cannot drift from the code.
"""
import re
import sys

SRC = 'lib/glyph.lua'
OUT = 'docs/GLYPHS.md'

DESC = {
    'voice': 'an FM voice: two nested circles, the modulator around the carrier',
    'odd': 'odd harmonics present. the complement of `even`',
    'even': 'even harmonics present. the complement of `odd`',
    'partials': 'a rake. partial count is the modulation index',
    'tilt': 'spectral slope',
    'feedback': 'a loop, not quite closed',
    'skew': 'two combs pulled out of alignment: operators off the lattice',
    'transient': 'a spike with a decay tail: the noise element, where drums come from',
    'gesture': 'a recorded gesture lane',
    'speed': 'chevrons. count is magnitude, direction is sign',
    'atten': 'a wedge narrowing: attenuation',
    'ball': 'a ball with its trail, in the field',
    'morph': 'the barycentric pad, with the interpolation position inside it',
    'snapshot': 'three corners: the A / B / C snapshots',
    'regen': 'decaying echoes: the regeneration buffer',
    'prob': 'a die face: probability and conditions',
    'mute': 'a slash. drawn over whatever is muted',
    'lattice': 'the harmonic lattice mesh',
    'clock': 'a clock with a hand: divisions and ratios',
    'matrix': 'the modulation matrix, one cell filled',
    'map': 'the node map',
    'groove': 'lane steps',
    'n_voice': 'node type: VOICE (sounds)',
    'n_seq': 'node type: SEQ',
    'n_mod': 'node type: MOD (drives a gesture lane)',
    'n_logic': 'node type: LOGIC (a derived lane)',
    'n_fx': 'node type: FX (owns a regen loop)',
    'n_mult': 'node type: MULT (forwards and ratchets triggers)',
    'n_empty': 'node type: empty slot',
    'a_play': 'play',
    'a_stop': 'stop',
    'a_rec': 'record',
    'a_clear': 'clear',
    'a_copy': 'copy',
    'a_up': 'up',
    'a_down': 'down',
    'a_hold': 'shift is held',
    'a_link': 'route / link',
}

TAIL = """

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
the point: ratios (`7/4`), EDO steps (`4\\13`), and tempo. `glyph.num` and
`glyph.ratio` are the only functions here that draw text.
"""


def main():
    src = open(SRC).read()

    blocks = []
    for m in re.finditer(r'^defs\.(\w+)\s*=\s*\{(.*?)\n?\}', src, re.S | re.M):
        rows = re.findall(r'"([.#]+)"', m.group(2))
        if rows:
            blocks.append((m.group(1), rows, m.start()))

    sections = [(m.start(), m.group(1).strip())
                for m in re.finditer(r'^-- -+ (.+)$', src, re.M)]

    def section_for(pos):
        cur = 'concepts'
        for p, t in sections:
            if p < pos:
                cur = t
        return cur

    out = [
        '# TAHNED glyphs',
        '',
        'The wordless vocabulary. **This file is generated from `lib/glyph.lua`** - that',
        'table is the source of truth, this is a readable view of it. Regenerate with',
        '`make glyphs` after editing the table.',
        '',
        '`#` is a lit pixel. Glyphs are compiled once at load into horizontal runs, so a',
        '7x7 icon costs about ten `screen.rect` calls rather than 49 `screen.pixel` calls.',
        '',
    ]

    cur = None
    for name, rows, pos in blocks:
        sec = section_for(pos)
        if sec != cur:
            cur = sec
            out += ['', f'## {sec}', '']
        out.append(f'### `{name}`  ({len(rows[0])}x{len(rows)})')
        out.append('')
        if name in DESC:
            out += [DESC[name], '']
        out.append('```')
        out += rows
        out += ['```', '']

    open(OUT, 'w').write('\n'.join(out) + TAIL)
    print(f'wrote {OUT} - {len(blocks)} glyphs')
    missing = [n for n, _, _ in blocks if n not in DESC]
    if missing:
        print('no description for: ' + ', '.join(missing), file=sys.stderr)


if __name__ == '__main__':
    main()
