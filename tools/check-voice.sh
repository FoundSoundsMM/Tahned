#!/usr/bin/env bash
# Renders voices offline at the defaults the script ships and measures them.
#
# PERC: that the default patch is an 808 kick, and that the pitch sweep does
# something -- SWEEP sitting at zero, doing nothing while looking like a
# control, is what this exists to catch.
#
# TONE: that a note already sounding follows a parameter turned under it,
# rather than keeping whatever was on the bus when it started.
set -euo pipefail
APP=${APP:-/Applications/SuperCollider.app/Contents}
SC=${SC:-$APP/MacOS/sclang}
SCSYNTH=${SCSYNTH:-$APP/Resources/scsynth}
LIB=${LIB:-$APP/Resources/SCClassLibrary}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK=${WORK:-$(mktemp -d)}
mkdir -p "$WORK/classes"
cp "$ROOT/lib/Engine_Tahned.sc" "$WORK/classes/"
cat > "$WORK/classes/_stubs.sc" <<'STUB'
CroneEngine {
	var <context, <doneCallback;
	*new { arg context, doneCallback; ^super.newCopyArgs(context, doneCallback) }
	addCommand { arg name, format, func; ^nil }
	addPoll { arg name, func; ^nil }
	alloc {} free {}
}
QuartzComposerView { }
STUB
cat > "$WORK/conf.yaml" <<CONF
includePaths:
  - $LIB
  - $WORK/classes
excludePaths:
  - $LIB/deprecated
  - $HOME/Library/Application Support/SuperCollider/Extensions
postInlineWarnings: false
CONF

# the bus contents come from the script itself, not from numbers typed here
lua "$ROOT/tools/dump-defaults.lua" perc       > "$WORK/bus-default.txt"
lua "$ROOT/tools/dump-defaults.lua" perc 9=0.5 > "$WORK/bus-flat.txt"
lua "$ROOT/tools/dump-defaults.lua" tone       > "$WORK/bus-tone.txt"

"$SC" -l "$WORK/conf.yaml" "$ROOT/tools/check-voice.scd" "$WORK" 2>&1 \
  | grep -iE "^wrote|ERROR|Exception" || true
for n in perc-default perc-flat tone-held tone-live; do
  rm -f "$WORK/$n.wav"
  # scsynth segfaults on teardown after writing the file, so judge the render
  # by whether the wav appeared rather than by the exit code
  "$SCSYNTH" -N "$WORK/$n.osc" _ "$WORK/$n.wav" 48000 WAV float -o 1 -i 0 \
    >/dev/null 2>&1 || true
  [ -s "$WORK/$n.wav" ] || echo "render produced nothing: $n"
done
python3 "$ROOT/tools/check-voice.py" "$WORK"
