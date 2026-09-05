#!/usr/bin/env python3
"""Measure the tails rendered by tools/check-fx.sh.

The input is one second of noise followed by silence. A healthy feedback loop
decays after the burst; a loop with gain at or over unity holds level or grows,
which is what "overloading feedback" sounds like.

The master colour chain is measured the same way, twice: once with everything
at its extreme, where it still has to make a sound rather than silence, and
once at rest, where the whole mix passes through it and it has to be
transparent.
"""
import struct, sys, os, math

def read_wav_f32(path):
    d = open(path, 'rb').read()
    assert d[:4] == b'RIFF' and d[8:12] == b'WAVE', "not a wav"
    pos, fmt, data = 12, None, None
    while pos + 8 <= len(d):
        cid, sz = d[pos:pos+4], struct.unpack('<I', d[pos+4:pos+8])[0]
        body = d[pos+8:pos+8+sz]
        if cid == b'fmt ':
            fmt = struct.unpack('<HHIIHH', body[:16])
        elif cid == b'data':
            data = body
        pos += 8 + sz + (sz & 1)
    ch, sr, bits = fmt[1], fmt[2], fmt[5]
    assert bits == 32, f"expected float32, got {bits}"
    n = len(data) // 4
    s = struct.unpack('<%df' % n, data[:n*4])
    return sr, ch, s

def windows(samples, ch, sr, win=0.5):
    step = int(sr * win) * ch
    for i in range(0, len(samples) - step, step):
        blk = samples[i:i+step]
        peak = max(abs(v) for v in blk)
        rms = math.sqrt(sum(v*v for v in blk) / len(blk))
        yield i / (sr*ch), peak, rms

work = sys.argv[1]
fails = 0
print("\n  effect     peak    burst     t=2s     t=6s     t=12s    verdict")
print("  " + "-" * 68)
dry_burst = None
for name in ("dry", "reverb", "delay", "chorus", "colour", "colourOff"):
    p = os.path.join(work, f"fx-{name}.wav")
    if not os.path.exists(p):
        print(f"  {name:10s} NOT RENDERED"); fails += 1; continue
    sr, ch, s = read_wav_f32(p)
    w = list(windows(s, ch, sr))
    at = lambda t: next((r for r in w if r[0] >= t), w[-1])
    peak = max(r[1] for r in w)
    burst = at(0.5)[2]
    a, b, c = at(2.0)[2], at(6.0)[2], at(12.0)[2]
    # a tail already below the noise floor has decayed; it cannot keep falling
    SILENT = 1e-5
    def fell(x, y): return y < SILENT or y < x * 0.9
    decaying = fell(a, b) and fell(b, c)
    clipped = peak > 1.0
    # the reverb is rendered at full shimmer, where a usable tail should still
    # be sounding after three seconds -- stable but inaudible is not a fix
    tail_ok = (name != "reverb") or (at(3.0)[2] > 1e-4)
    if name == "dry":
        dry_burst = burst
        print(f"  {name:10s} {peak:6.3f} {burst:8.5f}         the bare source")
        continue
    # silence passes every test above, so an effect also has to have made a
    # sound while there was one going in
    sounds = burst > 1e-3
    # at rest the colour chain is in the path of everything, so it is measured
    # against the bare source rather than against a level typed in here
    clean = (name != "colourOff") or (
        dry_burst is not None and 0.8 < (burst / dry_burst) < 1.25)
    ok = decaying and not clipped and tail_ok and sounds and clean
    why = "ok" if ok else " ".join(x for x in (
        "CLIPS" if clipped else "",
        "" if sounds else "SILENT",
        "" if clean else "NOT TRANSPARENT",
        "" if decaying else "NOT DECAYING",
        "" if tail_ok else "TAIL TOO SHORT") if x)
    print(f"  {name:10s} {peak:6.3f} {burst:8.5f} {a:8.5f} {b:8.5f} {c:8.5f}  {why}")
    if not ok: fails += 1
print()
if fails:
    print(f"FAIL: {fails} effect(s) unstable"); sys.exit(1)
print("PASS: every effect sounds, decays, and stays under full scale")
