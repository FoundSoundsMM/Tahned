// Writes OSC scores that render one tone voice, to prove the voice-stealing
// choke actually silences and frees a voice with a long release.
//
//   held   gate 1 throughout, t_choke never touched
//   choke  same, but t_choke set at 1.0s
//
// The held render must still be sounding at the end: if the choke envelope
// ran at synth start rather than waiting for its trigger, every voice would
// free itself immediately and this render would be silent.
var e, dir, def, score;

e = Engine_Tahned.new(nil, nil);
e.buildDefs(nil);
dir = thisProcess.argv[0] ? "/tmp";
def = \tahned_tone_lp;

// The voice latches its parameters from the control bus at note-on, so the
// bus has to carry a sounding patch before /s_new: carrier at full level,
// sustaining, 12s release, filter open.
score = { |choke|
	var msgs = [
		[0.0, ['/d_recv', SynthDescLib.global[def].def.asBytes]],
		[0.0, ['/c_set', 16, 1.0]],    // l1  carrier level
		[0.0, ['/c_set', 26, 1.0]],    // aHold  sustain level
		[0.0, ['/c_set', 27, 1.0]],    // aRel   -> 12s
		[0.0, ['/c_set', 41, 1.0]],    // cut    -> 16kHz
		[0.0, ['/c_set', 31, 0.5]],    // spread centre
		[0.01, ['/s_new', def, 1000, 0, 0, \bus, 0, \mbus, 96, \out, 0, \hz, 220, \vel, 1]],
	];
	if(choke) { msgs = msgs.add([1.0, ['/n_set', 1000, \t_choke, 1]]) };
	Score(msgs.add([2.0, ['/c_set', 0, 0]]));
};

score.(false).write(dir ++ "/choke-held.osc");
score.(true).write(dir ++ "/choke-cut.osc");
"wrote choke scores".postln;
0.exit;
