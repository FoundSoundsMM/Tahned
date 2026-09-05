#!/usr/bin/env bash
# Renders a single tone voice offline and checks the voice-stealing choke:
# a choked voice must go quiet within a few milliseconds however long its own
# release is, and an untouched voice must keep sounding.
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
"$SC" -l "$WORK/conf.yaml" "$ROOT/tools/check-choke.scd" "$WORK" 2>&1 \
  | grep -iE "^wrote|ERROR|Exception" || true
for n in held cut; do
  rm -f "$WORK/choke-$n.wav"
  # scsynth can segfault on teardown after writing; judge by the file
  # scsynth segfaults on teardown after writing the file, so judge the render
  # by whether the wav appeared rather than by the exit code; the inner shell
  # keeps that crash from printing a signal message
  bash -c "'$SCSYNTH' -N '$WORK/choke-$n.osc' _ '$WORK/choke-$n.wav' \
    48000 WAV float -o 2 -i 0; true" >/dev/null 2>&1
  [ -s "$WORK/choke-$n.wav" ] || echo "render produced nothing: $n"
done
python3 "$ROOT/tools/check-choke.py" "$WORK"
