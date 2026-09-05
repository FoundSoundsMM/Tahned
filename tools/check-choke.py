#!/usr/bin/env python3
"""Measure the renders written by tools/check-choke.sh.

Both voices have a 12 second release and are still gated on. The one sent
t_choke at 1.0s must be silent just after it; the untouched one must not be.
"""
import struct, sys, os

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
    ch, sr = fmt[1], fmt[2]
    n = len(data) // 4
    return sr, ch, struct.unpack('<%df' % n, data[:n*4])

def peak(path, t0, t1):
    sr, ch, s = read_wav_f32(path)
    a, b = int(t0 * sr) * ch, int(t1 * sr) * ch
    blk = s[a:min(b, len(s))]
    return max((abs(v) for v in blk), default=0.0)

work = sys.argv[1]
fails = 0

def check(what, ok, detail):
    global fails
    if ok:
        print("  ok    %s" % what)
    else:
        fails += 1
        print("  FAIL  %s\n        %s" % (what, detail))

print("\nvoice choke")
held_early = peak(os.path.join(work, "choke-held.wav"), 0.2, 0.9)
held_late  = peak(os.path.join(work, "choke-held.wav"), 1.1, 1.9)
cut_early  = peak(os.path.join(work, "choke-cut.wav"),  0.2, 0.9)
cut_late   = peak(os.path.join(work, "choke-cut.wav"),  1.1, 1.9)

check("an untouched voice sounds and keeps sounding",
      held_early > 0.01 and held_late > 0.01,
      "peak %.4f early, %.4f late -- the choke env ran without its trigger"
      % (held_early, held_late))
check("a choked voice sounds up to the steal",
      cut_early > 0.01, "peak %.4f before the choke" % cut_early)
check("a choked voice is silent 100ms later, despite a 12s release",
      cut_late < 1e-5, "peak %.6f after the choke" % cut_late)

print("\n== errors: %d" % fails)
sys.exit(1 if fails else 0)
