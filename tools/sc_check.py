#!/usr/bin/env python3
"""Compile Engine_Tahned.sc and build its SynthDefs without a norns.

The class library compile catches syntax and method errors; building the
SynthDef graphs catches UGen errors, which is where the real risk is -- a
graph function is only evaluated at runtime, so a bad argument to BLowShelf
would otherwise not surface until the engine loads on the device.

Needs SuperCollider installed. Set SCLANG to point at sclang if it is not in
the default macOS location.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

SCLANG = os.environ.get(
    'SCLANG', '/Applications/SuperCollider.app/Contents/MacOS/sclang')
ENGINE = 'lib/Engine_Tahned.sc'

STUB = '''
// minimal stand-ins so the engine class can be compiled off-device
CroneEngine {
	var <context, <doneCallback, <commands, <polls;
	*new { arg context, doneCallback; ^super.new.init(context, doneCallback) }
	init { arg ctx, cb;
		context = ctx; doneCallback = cb;
		commands = List.new; polls = List.new;
		this.alloc;
	}
	alloc {}
	free {}
	addCommand { arg name, format, func; commands.add([name, format, func]) }
	addPoll { arg name, func, periodic = true; polls.add([name, func, periodic]) }
}
'''


def extract_synthdefs(src):
    """Pull each SynthDef block out by brace matching."""
    defs = []
    for m in re.finditer(r'SynthDef\(\\\w+', src):
        i = src.index('{', m.end())
        depth, j = 0, src.index('{', m.end())
        while j < len(src):
            if src[j] == '{':
                depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        k = src.index(';', j)
        defs.append(src[m.start():k + 1].replace(').add;', ');'))
    return defs


def check_formats(src):
    """Every addCommand format string must match how the handler indexes msg."""
    bad = []
    for m in re.finditer(r'addCommand\((\\\w+),\s*"([^"]*)"', src):
        name, fmt = m.group(1), m.group(2)
        if any(c not in 'ifs' for c in fmt):
            bad.append(f'{name}: format "{fmt}" has a character that is not i, f or s')
    return bad


def main():
    if not os.path.exists(SCLANG):
        print(f'sclang not found at {SCLANG}; set SCLANG to override')
        return 2

    src = open(ENGINE).read()

    bad = check_formats(src)
    for b in bad:
        print('FAIL ' + b)

    tmp = tempfile.mkdtemp(prefix='tahned_sc_')
    classes = os.path.join(tmp, 'classes')
    os.makedirs(classes)
    open(os.path.join(classes, 'CroneStub.sc'), 'w').write(STUB)
    shutil.copy(ENGINE, classes)

    conf = os.path.join(tmp, 'sclang_conf.yaml')
    open(conf, 'w').write(
        f'includePaths:\n  - {classes}\nexcludePaths: []\n'
        'postInlineWarnings: false\n')

    defs = extract_synthdefs(src)
    scd = ['(', 'var d, ok = 0;', '"--- building synthdefs ---".postln;']
    for d in defs:
        scd += [f'd = {d}',
                '("  built " ++ d.name.asString ++ ", " '
                '++ d.allControlNames.size.asString ++ " controls").postln;',
                'ok = ok + 1;']
    scd += ['("--- " ++ ok.asString ++ " built ---").postln;',
            f'("--- {len(defs)} expected ---").postln;', '0.exit;', ')']
    scdpath = os.path.join(tmp, 'check.scd')
    open(scdpath, 'w').write('\n'.join(scd))

    try:
        p = subprocess.run([SCLANG, '-l', conf, scdpath],
                           capture_output=True, text=True, timeout=180)
        out = p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        print('FAIL sclang timed out')
        return 1

    errors = [ln for ln in out.splitlines()
              if 'ERROR' in ln or 'Parse error' in ln or 'error:' in ln]
    built = [ln for ln in out.splitlines() if ln.strip().startswith('built ')]

    for ln in built:
        print(ln.strip())
    for ln in errors:
        print('FAIL ' + ln.strip())

    shutil.rmtree(tmp, ignore_errors=True)

    if errors or bad or len(built) != len(defs):
        print(f'FAILED ({len(built)}/{len(defs)} synthdefs built)')
        return 1
    print(f'engine ok: class compiles, {len(built)} synthdefs build, '
          f'{len(re.findall(chr(92) + "s*addCommand", src))} commands')
    return 0


if __name__ == '__main__':
    sys.exit(main())
