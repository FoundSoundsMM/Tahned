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

// Stands in for a Synth so the voice bookkeeping can run with no server.
TahnedFakeSynth {
	var <>sets, <>freeAction, <>alive = true;
	*new { ^super.new.sets_(List.new) }
	set { arg ...args; sets.add(args) }
	onFree { arg f; freeAction = f }
	// what the server reports back when the node actually goes away
	reportFree { alive = false; freeAction.value(this) }
	choked { ^sets.any { |a| a[0] == \t_choke } }
	released { ^sets.any { |a| a[0] == \gate and: { a[1] == 0 } } }
}
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
var e, n = 0, bad = 0, check, cap;
e = Engine_Tahned.new(nil, nil);
try { e.buildDefs(nil) } { |err| bad = 1; "\n!! BUILD ERROR: %\n".postf(err.errorString) };
SynthDescLib.global.synthDescs.keysDo { |k|
	if(k.asString.beginsWith("tahned")) { n = n + 1 } };
"\n== synthdefs built: %  errors: %\n".postf(n, bad);

// ------------------------------------------------------- voice stealing
// The cap only means anything if a releasing voice keeps its slot until the
// server frees it, so drive the bookkeeping directly with fake synths.
check = { |what, fn|
	var ok, err;
	ok = try { fn.value; true } { |e| err = e; false };
	if(ok) { "  ok    %\n".postf(what) }
		{ bad = bad + 1; "  FAIL  %\n        %\n".postf(what, err.errorString) };
};

"\nvoice allocation\n".post;
e.initVoices;
cap = Engine_Tahned.maxVoices;

check.("a held chord under the cap keeps every voice", {
	var syns = Array.fill(cap, { |i| var y = TahnedFakeSynth.new; e.allocVoice(0, i, y); y });
	if(e.live[0].size != cap) { Error("live is % not %".format(e.live[0].size, cap)).throw };
	if(syns.any(_.choked)) { Error("a voice was stolen inside the cap").throw };
});

check.("a released voice keeps its slot while it fades", {
	e.voices[0][0] !? { |v| e.releaseVoice(0, v) };
	if(e.live[0].size != cap) { Error("releasing dropped the voice early").throw };
});

check.("the next note steals the releasing voice, not a held one", {
	var victim = e.live[0].first;
	var fresh = TahnedFakeSynth.new;
	e.allocVoice(0, 999, fresh);
	if(victim.syn.choked.not) { Error("the releasing voice was not stolen").throw };
	if(e.live[0].size != cap) { Error("live is % not %".format(e.live[0].size, cap)).throw };
	if(e.live[0].includes(victim)) { Error("stolen voice still counted").throw };
	if(e.live[0].any { |x| x.syn !== fresh and: { x.syn.choked } }) {
		Error("a held voice was stolen while a releasing one was available").throw };
});

check.("with every voice held, the oldest held one goes", {
	var oldest = e.live[0].first;
	e.allocVoice(0, 1000, TahnedFakeSynth.new);
	if(oldest.syn.choked.not) { Error("oldest held voice was not stolen").throw };
	if(e.live[0].size != cap) { Error("cap exceeded: %".format(e.live[0].size)).throw };
});

check.("the server freeing a node gives the slot back", {
	var e0 = e.live[0].first;
	e0.syn.reportFree;
	if(e.live[0].size != (cap - 1)) { Error("slot not reclaimed").throw };
	if(e.voices[0][e0.id] === e0) { Error("freed voice still addressable by id").throw };
});

check.("retriggering an id releases the old voice and keeps its slot", {
	var old = TahnedFakeSynth.new;
	var sz;
	e.initVoices;
	e.allocVoice(1, 7, old);
	e.voices[1][7] !? { |v| e.releaseVoice(1, v) };
	e.allocVoice(1, 7, TahnedFakeSynth.new);
	sz = e.live[1].size;
	if(old.released.not) { Error("old voice not released").throw };
	if(sz != 2) { Error("live is % not 2".format(sz)).throw };
	if(e.voices[1][7].syn === old) { Error("id still points at the old voice").throw };
});

// freeTrack itself needs a server for vGroup.freeAll; this is the half of it
// that has to leave no voice behind
check.("clearing a track leaves no voice behind", {
	e.clearVoices(1);
	if(e.live[1].size != 0) { Error("live not cleared").throw };
	if(e.voices[1].size != 0) { Error("voices not cleared").throw };
});

"\n== errors: %\n".postf(bad);
if(bad > 0) { 1.exit } { 0.exit };
RUN
"$SC" -l "$WORK/conf.yaml" "$WORK/run.scd" 2>&1 \
  | grep -viE "^\s*(Found |Compiling director|NumPrimitives|Number of|Class tree|compile done|init_OSC|Cleaning|sclang|Requested|compiling class|numentries|[0-9]+ method|method table|Byte Code|compiled [0-9]+ files|localhost :|internal :|\*\*\* Welcome)" \
  | grep -v '^$'
