// Writes OSC scores that render voices offline, driven by the values the
// script actually sends for a default track rather than by numbers typed in
// here. Two things get asked:
//
//   drums  does each machine sound, and is KICK an 808 kick whose SWEEP bends
//   tone   does a note already sounding follow a parameter turned under it
//
// The PERFORM bus sits at 192 and is left at zero, which is where it does
// nothing -- these renders are the instrument on its own.
var e, dir, defs, drumScore, toneScore;

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

drumScore = { |tag, machine|
	var v = defs.value(tag);
	var def = ("tahned_" ++ machine ++ "_lp").asSymbol;
	Score([
		[0.0, ['/d_recv', SynthDescLib.global[def].def.asBytes]],
		[0.0, ['/c_setn', 0, 96] ++ v],
		[0.0, ['/s_new', def, 1000, 0, 0,
			\bus, 0, \mbus, 96, \gbus, 192, \out, 0, \vel, 1, \note, 36]],
		[4.0, ['/c_set', 0, 0]]
	]).write(dir ++ "/voice-" ++ tag ++ ".osc");
	("wrote " ++ tag).postln;
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
			\bus, 0, \mbus, 96, \gbus, 192, \out, 0, \gate, 1, \hz, 220, \vel, 1]]
	];
	if(change) { ev = ev.add([1.0, ['/c_set', 9, 1]]) };
	ev = ev.add([2.5, ['/c_set', 0, 0]]);
	Score(ev).write(dir ++ "/voice-tone-" ++ name ++ ".osc");
	("wrote tone " ++ name).postln;
};

[["kick-default", "kick"], ["kick-flat", "kick"],
	["kick-body", "kick"], ["kick-bodyflat", "kick"], ["snare", "snare"],
	["hat", "hat"], ["tom", "tom"], ["cymb", "cymb"]].do { |c|
	drumScore.value(c[0], c[1]);
};
toneScore.value("held", false);
toneScore.value("live", true);
0.exit;
