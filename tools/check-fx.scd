// Writes one OSC score per send effect for non-realtime rendering. Each gets a
// one second burst of noise and then silence, at the most extreme settings the
// params allow, so the tail can be measured afterwards.
var e, dir;

e = Engine_Tahned.new(nil, nil);
e.buildDefs(nil);

SynthDef(\nrt_src, { |out = 0|
	Out.ar(out, PinkNoise.ar(0.3 ! 2) * EnvGen.kr(Env([1, 1, 0], [1.0, 0.02])));
}).add;

dir = thisProcess.argv[0] ? "/tmp";

[
	[\reverb, \tahned_reverb, [\shimfb, 1, \shim, 0.8, \size, 0.95, \level, 1]],
	[\delay,  \tahned_delay,  [\fbk, 0.98, \time, 0.2, \level, 1]],
	[\chorus, \tahned_chorus, [\fbk, 0.85, \depth, 1, \level, 1]],
].do { |c|
	var name = c[0], def = c[1], args = c[2];
	Score([
		[0.0, ['/d_recv', SynthDescLib.global[\nrt_src].def.asBytes]],
		[0.0, ['/d_recv', SynthDescLib.global[def].def.asBytes]],
		[0.0, ['/s_new', \nrt_src, 1000, 0, 0, \out, 16]],
		[0.0, ['/s_new', def, 1001, 3, 1000] ++ [\in, 16, \out, 0] ++ args],
		[14.0, ['/c_set', 0, 0]]
	]).write(dir ++ "/fx-" ++ name ++ ".osc");
	("wrote " ++ name).postln;
};
0.exit;
