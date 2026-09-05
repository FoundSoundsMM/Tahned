// Writes one OSC score per effect for non-realtime rendering. Each gets a one
// second burst of noise and then silence, at the most extreme settings the
// params allow, so the tail can be measured afterwards.
//
// The master colour chain is in here too. It has no feedback loop, but it does
// hold half a second of audio in a buffer for GLITCH and a limiter at the end,
// and both of those are things that can keep making noise after the input has
// stopped.
var e, dir;

e = Engine_Tahned.new(nil, nil);
e.buildDefs(nil);

SynthDef(\nrt_src, { |out = 0|
	Out.ar(out, PinkNoise.ar(0.3 ! 2) * EnvGen.kr(Env([1, 1, 0], [1.0, 0.02])));
}).add;

// A second source, for the colour chain. Noise is a different signal on every
// render -- the levels move by a third between runs -- so "transparent" cannot
// be measured with it. Four sines are the same four sines every time.
SynthDef(\nrt_tone, { |out = 0|
	Out.ar(out, (Mix([
		SinOsc.ar(110), SinOsc.ar(370) * 0.7,
		SinOsc.ar(1300) * 0.5, SinOsc.ar(5200) * 0.3
	]) * 0.12 ! 2) * EnvGen.kr(Env([1, 1, 0], [1.0, 0.02])));
}).add;

dir = thisProcess.argv[0] ? "/tmp";

// the tone source on its own, so "transparent" can be measured against
// something rather than against a number somebody once wrote down
Score([
	[0.0, ['/d_recv', SynthDescLib.global[\nrt_tone].def.asBytes]],
	[0.0, ['/s_new', \nrt_tone, 1000, 0, 0, \out, 0]],
	[14.0, ['/c_set', 0, 0]]
]).write(dir ++ "/fx-dry.osc");
"wrote dry".postln;

[
	[\reverb, \tahned_reverb, [\shimfb, 1, \shim, 0.8, \size, 0.95, \level, 1]],
	[\delay,  \tahned_delay,  [\fbk, 0.98, \time, 0.2, \level, 1]],
	[\chorus, \tahned_chorus, [\fbk, 0.85, \depth, 1, \level, 1]],
	[\colour, \tahned_colour, [\crush, 1, \wow, 1, \wrate, 1, \saturn, 1,
		\tilt, 1, \loss, 1, \glitch, 1, \comp, 1, \drive, 1, \dtone, 1]],
	// everything at rest: the whole mix passes through this synth, so it has
	// to be audibly transparent when nothing is turned up
	[\colourOff, \tahned_colour, []],
].do { |c|
	var name = c[0], def = c[1], args = c[2];
	// the sends are fed noise, so their tails are measured on broadband
	// material; the colour chain is fed the repeatable tone
	var src = if(def == \tahned_colour) { \nrt_tone } { \nrt_src };
	Score([
		[0.0, ['/d_recv', SynthDescLib.global[src].def.asBytes]],
		[0.0, ['/d_recv', SynthDescLib.global[def].def.asBytes]],
		[0.0, ['/s_new', src, 1000, 0, 0, \out, 16]],
		[0.0, ['/s_new', def, 1001, 3, 1000] ++ [\in, 16, \out, 0] ++ args],
		[14.0, ['/c_set', 0, 0]]
	]).write(dir ++ "/fx-" ++ name ++ ".osc");
	("wrote " ++ name).postln;
};
0.exit;
