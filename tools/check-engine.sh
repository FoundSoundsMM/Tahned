#!/usr/bin/env bash
# Offline check for lib/Engine_Tahned.sc: compiles the class against the real
# SuperCollider class library and builds every SynthDef graph, without needing
# a norns or a running server. Catches UGen-level mistakes, not just syntax.
set -euo pipefail
SC=${SC:-/Applications/SuperCollider.app/Contents/MacOS/sclang}
LIB=${LIB:-/Applications/SuperCollider.app/Contents/Resources/SCClassLibrary}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
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
QuartzComposerView { }   // headless sclang has no Qt GUI primitives
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
cat > "$WORK/run.scd" <<'RUN'
var e, n = 0, bad = 0;
e = Engine_Tahned.new(nil, nil);
try { e.buildDefs(nil) } { |err| bad = 1; "\n!! BUILD ERROR: %\n".postf(err.errorString) };
SynthDescLib.global.synthDescs.keysDo { |k|
	if(k.asString.beginsWith("tahned")) { n = n + 1 } };
"\n== synthdefs built: %  errors: %\n".postf(n, bad);
if(bad > 0) { 1.exit } { 0.exit };
RUN
"$SC" -l "$WORK/conf.yaml" "$WORK/run.scd" 2>&1 \
  | grep -viE "^\s*(Found |Compiling director|NumPrimitives|Number of|Class tree|compile done|init_OSC|Cleaning|sclang|Requested|compiling class|numentries|[0-9]+ method|method table|Byte Code|compiled [0-9]+ files|localhost :|internal :|\*\*\* Welcome)" \
  | grep -v '^$'
