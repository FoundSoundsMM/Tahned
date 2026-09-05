#!/usr/bin/env bash
# Renders the send effects offline and checks their feedback loops decay.
# Guards against the reverb and delay running away when signal is sent in.
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
"$SC" -l "$WORK/conf.yaml" "$ROOT/tools/check-fx.scd" "$WORK" 2>&1 \
  | grep -iE "^wrote|ERROR|Exception" || true
for n in dry reverb delay chorus colour colourOff; do
  # scsynth segfaults on teardown after writing the file, so judge the render
  # by whether the wav appeared rather than by the exit code
  rm -f "$WORK/fx-$n.wav"
  "$SCSYNTH" -N "$WORK/fx-$n.osc" _ "$WORK/fx-$n.wav" 48000 WAV float -o 2 -i 0 \
    >/dev/null 2>&1 || true
  [ -s "$WORK/fx-$n.wav" ] || echo "render produced nothing: $n"
done
python3 "$ROOT/tools/check-fx.py" "$WORK"
