#!/usr/bin/env python3
"""Measure the renders written by tools/check-voice.sh.

Three questions. Does the default PERC patch behave like an 808 kick -- a low
sine that holds for around a second? Does SWEEP actually bend the pitch, which
is the thing that looked like a control and was not doing anything? And does a
held TONE note follow a parameter turned under it?

Pitch is read from zero crossings. The bodies are sines at these settings, so
crossings are the cleanest estimate available without a transform.
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
    return sr, ch, struct.unpack('<%df' % n, data[:n*4])

def rms(s, sr, t0, t1):
    a, b = int(t0 * sr), min(int(t1 * sr), len(s))
    if b <= a: return 0.0
    return math.sqrt(sum(v * v for v in s[a:b]) / (b - a))

def crossings(s, sr, t0, t1):
    """Upward zero crossings in a window, sub-sample interpolated.

    The body is a sine at these settings, so crossings are the cleanest
    pitch estimate available without a transform. Counting them over a
    window that spans the sweep is also the only honest way to see the
    sweep at all: it is over in 40ms, which is barely two cycles at the
    pitch it lands on.
    """
    a, b = int(t0 * sr), min(int(t1 * sr), len(s))
    seg = s[a:b]
    if not seg: return 0, None, None
    if max(abs(v) for v in seg) < 1e-4: return 0, None, None
    xs = []
    for i in range(1, len(seg)):
        if seg[i - 1] <= 0.0 < seg[i]:
            xs.append(i - 1 + (-seg[i - 1] / (seg[i] - seg[i - 1])))
    return len(xs), (xs[0] if xs else None), (xs[-1] if xs else None)

def f0(s, sr, t0, t1):
    n, first, last = crossings(s, sr, t0, t1)
    if n < 2: return 0.0
    return sr * (n - 1) / (last - first)

def cycles(s, sr, t0, t1):
    return crossings(s, sr, t0, t1)[0]

def fft(a):
    """Iterative radix-2 FFT. Zero crossings count sidebands, not the note,
    so anything spectral needs a transform however small."""
    n = len(a)
    j = 0
    a = list(a)
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit; bit >>= 1
        j |= bit
        if i < j: a[i], a[j] = a[j], a[i]
    ln = 2
    while ln <= n:
        ang = -2 * math.pi / ln
        wl = complex(math.cos(ang), math.sin(ang))
        for i in range(0, n, ln):
            w = complex(1)
            for k in range(i, i + ln // 2):
                u, v = a[k], a[k + ln // 2] * w
                a[k], a[k + ln // 2] = u + v, u - v
                w *= wl
        ln <<= 1
    return a

def centroid(s, sr, t0, t1, n=8192):
    """Spectral centroid over one window, in Hz. A carrier moved down by a
    factor of three takes its whole spectrum with it, so this reads the
    change whatever the sidebands are doing."""
    a = int(t0 * sr)
    seg = list(s[a:a + n])
    if len(seg) < n or max(abs(v) for v in seg) < 1e-5: return 0.0
    seg = [v * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)))
           for i, v in enumerate(seg)]
    sp = fft([complex(v) for v in seg])[:n // 2]
    mag = [abs(c) for c in sp]
    tot = sum(mag)
    if tot <= 0: return 0.0
    return sum(m * (i * sr / n) for i, m in enumerate(mag)) / tot

work = sys.argv[1]
fails = []
res = {}

print("\n  render     peak   cycles<60ms  f0 @300ms  rms@0.5s  rms@1.5s")
print("  " + "-" * 62)
for name in ("default", "flat"):
    p = os.path.join(work, f"perc-{name}.wav")
    if not os.path.exists(p):
        print(f"  {name:10s} NOT RENDERED"); fails.append(f"{name} not rendered"); continue
    sr, ch, s = read_wav_f32(p)
    if ch > 1: s = s[0::ch]
    r = dict(peak=max(abs(v) for v in s),
             cyc=cycles(s, sr, 0.001, 0.061),
             late=f0(s, sr, 0.30, 0.70),
             mid=rms(s, sr, 0.45, 0.55),
             end=rms(s, sr, 1.45, 1.55))
    res[name] = r
    print(f"  {name:10s} {r['peak']:5.3f}  {r['cyc']:10d} {r['late']:10.1f}"
          f"  {r['mid']:9.5f} {r['end']:9.5f}")
print()

d, f = res.get("default"), res.get("flat")
def want(ok, msg):
    print(("  ok    " if ok else "  FAIL  ") + msg)
    if not ok: fails.append(msg)

if d:
    want(0.05 < d["peak"] <= 1.0,
         f"the default hit sounds and stays under full scale ({d['peak']:.3f})")
    want(40 < d["late"] < 58,
         f"it settles on an 808 kick fundamental ({d['late']:.1f} Hz, want ~49)")
    want(d["mid"] > 0.01, f"still sounding half a second in ({d['mid']:.4f})")
    want(d["end"] < d["mid"] * 0.2, "and gone by a second and a half")
if d and f:
    want(d["cyc"] >= f["cyc"] + 1,
         f"SWEEP bends the pitch: {d['cyc']} cycles in the first 60ms against "
         f"{f['cyc']} with it centred")
    want(abs(d["late"] - f["late"]) < 3,
         f"and both land on the same pitch once it has settled "
         f"({d['late']:.1f} / {f['late']:.1f} Hz)")
# ------------------------------------------------------------------- tone
# A note is held for the whole render. In "live" the carrier's frequency
# multiplier is moved from 3 to 1 a second in. That value used to be latched
# at note on, so the held note carried on at the old pitch and the edit was
# only heard on the next note.
print("\n  render    centroid   centroid   rms@0.7s  rms@2.0s")
print("             @0.7s      @2.0s")
print("  " + "-" * 52)
tone = {}
for name in ("held", "live"):
    p = os.path.join(work, f"tone-{name}.wav")
    if not os.path.exists(p):
        print(f"  {name:10s} NOT RENDERED"); fails.append(f"tone-{name} not rendered"); continue
    sr, ch, s2 = read_wav_f32(p)
    if ch > 1: s2 = s2[0::ch]
    r = dict(before=centroid(s2, sr, 0.70, 0.90), after=centroid(s2, sr, 1.90, 2.10),
             rb=rms(s2, sr, 0.60, 0.90), ra=rms(s2, sr, 1.80, 2.20))
    tone[name] = r
    print(f"  {name:10s} {r['before']:8.1f} {r['after']:9.1f}"
          f"  {r['rb']:9.5f} {r['ra']:9.5f}")
print()

h, lv = tone.get("held"), tone.get("live")
if h:
    want(h["rb"] > 0.005 and h["ra"] > 0.005,
         "a held note keeps sounding for the whole render")
    want(abs(h["before"] - h["after"]) < h["before"] * 0.05,
         f"and holds its tone when nothing is turned "
         f"({h['before']:.0f} -> {h['after']:.0f} Hz centroid)")
if lv:
    want(lv["ra"] > 0.005, "the note is still sounding after the edit")
    # RAT 1 goes from 3 to 1, so the carrier and every sideband with it
    want(lv["after"] < lv["before"] * 0.6,
         f"turning RAT 1 under a held note is heard on that note "
         f"({lv['before']:.0f} -> {lv['after']:.0f} Hz centroid)")

print()
if fails:
    print(f"FAIL: {len(fails)} check(s)"); sys.exit(1)
print("PASS: PERC is an 808 kick, SWEEP sweeps, and held notes follow the bus")
