// Writes OSC scores that render voices offline, driven by the values the
// script actually sends for a default track rather than by numbers typed in
// here. Two things get asked:
//
//   perc  is the default patch an 808 kick, and does SWEEP bend the pitch
//   tone  does a note already sounding follow a parameter turned under it
var e, dir, defs, percScore, toneScore;

e = Engine_Tahned.new(nil, nil);
e.buildDefs(nil);

dir = thisProcess.argv[0] ? "/tmp";

// each line of the dump is "channel value"
defs = { |name|
	var f = File(dir ++ "/bus-" ++ name ++ ".txt", "r");
	var v = f.readAllString.split($\n).reject(_.isEmpty).collect { |l|
		l.split($ )[1].asFloat };
	f.close;
	v;
};

percScore = { |name|
	var v = defs.value(name);
	Score([
		[0.0, ['/d_recv', SynthDescLib.global[\tahned_perc_lp].def.asBytes]],
		// the noise buffer the repeatable-hit path plays; silent at these
		// settings, but PlayBuf still wants somewhere to point
		[0.0, ['/b_alloc', 0, 48000, 1]],
		[0.0, ['/c_setn', 0, 96] ++ v],
		[0.0, ['/s_new', \tahned_perc_lp, 1000, 0, 0,
			\bus, 0, \mbus, 96, \out, 0, \vel, 1, \note, 36, \nzbuf, 0]],
		[2.5, ['/c_set', 0, 0]]
	]).write(dir ++ "/perc-" ++ name ++ ".osc");
	("wrote perc " ++ name).postln;
};

// A note is started and held for the whole render. In `live` the carrier's
// frequency multiplier is moved from 3 to 1 a second in -- a value that used
// to be latched at note on, so nothing happened until the next note.
toneScore = { |name, change|
	var v = defs.value("tone");
	var ev = [
		[0.0, ['/d_recv', SynthDescLib.global[\tahned_tone_lp].def.asBytes]],
		[0.0, ['/c_setn', 0, 96] ++ v],
		[0.0, ['/s_new', \tahned_tone_lp, 1000, 0, 0,
			\bus, 0, \mbus, 96, \out, 0, \gate, 1, \hz, 220, \vel, 1]]
	];
	if(change) { ev = ev.add([1.0, ['/c_set', 9, 1]]) };
	ev = ev.add([2.5, ['/c_set', 0, 0]]);
	Score(ev).write(dir ++ "/tone-" ++ name ++ ".osc");
	("wrote tone " ++ name).postln;
};

["default", "flat"].do(percScore);
toneScore.value("held", false);
toneScore.value("live", true);
0.exit;
