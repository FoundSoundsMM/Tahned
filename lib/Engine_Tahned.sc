// Engine_Tahned
// FM groovebox for norns  --  8 tracks x { kick snare hat tom cymb | tone }
//
// Every track owns one 96-channel control bus. Lua writes normalised (0..1)
// values into it; the synthdefs do all range mapping. That keeps parameter
// locks uniform: a lock is just (channel, value).
//
//   ch  0..7   mix      level pan drive sendCho sendDly sendRev - -
//   ch  8..39  syn      instrument specific; see each synthdef for its map
//   ch 40..47  filter   type cutoff res envAmt envAtk envDec keytrk drive
//   ch 48..55  spare    COLOUR used to live here; it is on the master now
//   ch 56..87  lfo1..4  spd mult wave mode destA depA destB depB   (8 each)
//   ch 88..95  spare    88 is the LFO null destination
//
// A second, parallel "mod" bus per track holds LFO offsets only. The LFO synth
// scatters into it with a dynamic-index Out.kr, so any channel above can be a
// modulation destination for free. Voices read pBus + mBus.
//
// One more bus is global rather than per track: gBus, eight channels of
// PERFORM offset that every voice on every track reads alongside its own
// parameters. Each is -1..1 and does nothing at 0:
//
//   0 pitch  1 attack  2 decay  3 timbre  4 cutoff  5 res  6 fold  7 drive
//
// COLOUR is one chain on the summed mix rather than eight of them a track
// deep, so the tracks and the sends meet in mixBus and tahned_colour is the
// last thing before the output.

Engine_Tahned : CroneEngine {

	classvar <nTracks = 8;
	classvar <nCh = 96;
	// Per-track voice ceiling. A releasing voice still costs a full 4-op FM
	// synth, so with a long release a chord sequence piles them up until the
	// server glitches. 16 is above the largest chord one step can resolve to,
	// so a cap never cuts a chord short -- only the tail of an older one.
	classvar <maxVoices = 16;
	classvar <fTypes;          // filter variants compiled into each voice
	classvar <machines;        // machine index -> synthdef stem
	classvar <toneMachine = 5; // the one polyphonic machine

	var <pBus;                 // Array[nTracks] of 64ch control Bus
	var <tBus;                 // Array[nTracks] of stereo audio Bus
	var <vGroup, <sGroup;      // voice / strip groups per track
	var <fxGroup, <outGroup;
	var <choBus, <dlyBus, <revBus;
	var <strip, <fx;
	var <voices;               // Array[nTracks] of IdentityDictionary(id -> entry)
	var <live;                 // Array[nTracks] of Array of entry, oldest first
	                           // entry: (syn: Synth, id: Integer, held: Boolean)
	                           // holds releasing voices too, which is the point
	var <machine;              // Array[nTracks] of Integer, indexes machines
	var <ftype;                // Array[nTracks] of Integer  cached filter variant
	var <mBus;                 // Array[nTracks] of 96ch modulation bus (LFO sum)
	var <gBus;                 // one 8ch global bus: the PERFORM offsets
	var <mixBus;               // where tracks and sends meet, before COLOUR
	var <colourS;              // the master colour chain
	var <ctlGroup, <voiceGroup;
	var <clearS, <lfoS;

	*initClass {
		fTypes = [\lp, \bp, \hp, \cmb];
		// machine index -> synthdef stem. Five drums and then TONE, matching
		// S.MACHINE on the lua side; the two must not drift apart.
		machines = ["tahned_kick", "tahned_snare", "tahned_hat", "tahned_tom",
			"tahned_cymb", "tahned_tone"];
	}

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	// ---------------------------------------------------------------- waves
	// OPL3 / YMF262 waveform set. ph is a 0..1 phasor.
	*oplWave { arg ph, w;
		var s = sin(ph * 2pi);
		var s2 = sin(ph * 4pi);
		var half = (ph < 0.5);
		^Select.ar(w, [
			s,                              // 0 sine
			s * half,                       // 1 half sine
			s.abs,                          // 2 abs sine
			s.abs * ((ph % 0.5) < 0.25),    // 3 pulse (quarter) sine
			s2 * half,                      // 4 even sine
			s2.abs * half,                  // 5 abs even sine
			(half * 2) - 1,                 // 6 square
			(1 - (ph * 2)).max(-1)          // 7 derived saw
		]);
	}

	// phase-modulated operator
	*op { arg freq, pm, w, iphase = 0;
		var ph = Phasor.ar(0, freq * SampleDur.ir, 0, 1);
		^Engine_Tahned.oplWave((ph + pm + iphase).wrap(0, 1), w);
	}

	// Lower-triangular routing coefficients for a 4 operator algorithm.
	// `a` is a control-rate UGen, so each coefficient has to be selected at
	// runtime rather than indexed out of the table in sclang.
	// returns [c43 c42 c32 c41 c31 c21 o4 o3 o2 o1]
	*algo4 { arg a;
		var m = [
			// 4>3>2>1                      linear chain
			[[1,0,0,0,0,1],[0,0,0,1]],
			// 4>3, (3,4)>2, 2>1
			[[1,1,1,0,0,1],[0,0,0,1]],
			// 4>2, 3>2, 2>1
			[[0,1,1,0,0,1],[0,0,0,1]],
			// 4>3>2, 4>1 parallel out 1+2
			[[1,0,1,1,0,0],[0,0,0.7,0.7]],
			// 4>3>1 and 2>1
			[[1,0,0,0,1,1],[0,0,0,1]],
			// 4>3, out 3+2+1, 4 modulates all
			[[1,1,0,1,0,0],[0,0.5,0.5,0.5]],
			// 4>1, 3>1, 2>1  (three modulators, one carrier)
			[[0,0,0,1,1,1],[0,0,0,1]],
			// all four parallel  (additive / organ)
			[[0,0,0,0,0,0],[0.5,0.5,0.5,0.5]]
		].collect { |r| r[0] ++ r[1] };
		^(0..9).collect { |k| Select.kr(a, m.collect { |r| r[k] }) };
	}

	// A plain sine operator taking its modulation in cycles, like *op. The
	// drums are all sine FM: the OPL waveform set belongs to TONE, and a
	// Select.ar over eight branches for a fixed sine is eight branches wasted.
	*sop { arg freq, pm = 0;
		^SinOsc.ar(freq.clip(0.1, 20000), pm * 2pi)
	}

	// The tail every drum voice shares: the track filter, the track drive, the
	// velocity curve, and the envelope that frees the synth once the longest
	// section it started has finished. `life` is what the voice itself thinks
	// it needs; the filter envelope is folded in here because only this knows
	// how long that is.
	*drumTail { arg ft, sig, p, g, note, vel, life;
		var cut  = p[41].linexp(0, 1, 30, 16000) * (2 ** (g[4] * 4));
		var res  = (p[42] + g[5]).clip(0, 1);
		var eAmt = (p[43] * 2) - 1;
		var fAtk = p[44].linexp(0, 1, 0.0005, 0.5) * (2 ** (g[1] * 3));
		var fDec = p[45].linexp(0, 1, 0.005, 3) * (2 ** (g[2] * 3));
		var ktrk = p[46];
		var drv  = (p[47] + g[7]).clip(0, 1);
		var fEnv = EnvGen.ar(Env([0, 1, 0], [fAtk, fDec], [2, -4]));
		var out  = Engine_Tahned.flt(ft, sig * (1 + (drv * 4)),
			cut * (2 ** (fEnv * eAmt * 5)) * (2 ** ((note - 36) / 12 * ktrk)),
			res) / (1 + (drv * 2));
		out = out * vel.pow(1.4) * 0.7;
		out = out * EnvGen.ar(Env([1, 1, 0],
			[(life.max(fDec + fAtk) * 1.3) + 0.1, 0.02]), doneAction: 2);
		^Pan2.ar(out, 0)
	}

	// ------------------------------------------------------------- filters
	// resolved at synthdef build time, so only one branch is ever compiled
	*flt { arg type, sig, cut, res;
		var c = cut.clip(20, 16000);
		^switch(type,
			\lp,  { MoogFF.ar(sig, c, res * 3.7) },
			\bp,  { BPF.ar(sig, c, (1 - (res * 0.96)).max(0.03)) * (1 + (res * 2)) },
			\hp,  { RHPF.ar(sig, c, (1 - (res * 0.96)).max(0.03)) },
			\cmb, { CombC.ar(sig * 0.6, 0.06,
			                 c.reciprocal.clip(0.00007, 0.06),
			                 res.linlin(0, 1, 0.02, 3.0)) + (sig * 0.4) }
		);
	}

	// The YMF262's own frequency multipliers. The chip has 16 register values
	// but repeats 10, 12 and 15, so those duplicates are dropped here.
	*mults { ^[0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15] }

	// drums want inharmonic ratios the chip never had
	*ratios { ^[0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 3.5, 4, 5, 6, 8, 11] }

	// -------------------------------------------------------------- alloc
	alloc {
		var s = context.server;

		machine = Array.fill(nTracks, { 0 });
		ftype   = Array.fill(nTracks, { 0 });
		this.initVoices;

		pBus = Array.fill(nTracks, { Bus.control(s, nCh) });
		mBus = Array.fill(nTracks, { Bus.control(s, nCh) });
		tBus = Array.fill(nTracks, { Bus.audio(s, 2) });
		gBus = Bus.control(s, 8);
		choBus = Bus.audio(s, 2);
		dlyBus = Bus.audio(s, 2);
		revBus = Bus.audio(s, 2);
		mixBus = Bus.audio(s, 2);

		ctlGroup   = Group.new(context.xg, \addToHead);
		voiceGroup = Group.after(ctlGroup);
		vGroup     = Array.fill(nTracks, { Group.new(voiceGroup, \addToTail) });
		sGroup     = Group.after(voiceGroup);
		fxGroup    = Group.after(sGroup);
		outGroup   = Group.after(fxGroup);

		this.buildDefs(s);
		s.sync;

		// mod bus is cleared, then written, before any voice reads it
		clearS = Array.fill(nTracks, { |i|
			Synth(\tahned_modclear, [\mbus, mBus[i].index], ctlGroup, \addToTail) });
		lfoS = Array.fill(nTracks, { |i|
			Synth(\tahned_lfo, [\bus, pBus[i].index, \mbus, mBus[i].index],
				ctlGroup, \addToTail) });

		// tracks and sends both land in mixBus, because COLOUR is one chain
		// over the whole thing rather than eight of them a track deep
		strip = Array.fill(nTracks, { |i|
			Synth(\tahned_strip, [
				\bus, pBus[i].index, \mbus, mBus[i].index, \gbus, gBus.index,
				\in, tBus[i].index, \out, mixBus.index,
				\cho, choBus.index, \dly, dlyBus.index, \rev, revBus.index
			], sGroup);
		});

		fx = IdentityDictionary[
			\cho -> Synth(\tahned_chorus, [\in, choBus.index, \out, mixBus.index], fxGroup),
			\dly -> Synth(\tahned_delay,  [\in, dlyBus.index, \out, mixBus.index], fxGroup),
			\rev -> Synth(\tahned_reverb, [\in, revBus.index, \out, mixBus.index], fxGroup)
		];

		colourS = Synth(\tahned_colour,
			[\in, mixBus.index, \out, context.out_b.index], outGroup);

		this.addCommands;
	}

	// ------------------------------------------------------------ synthdefs
	buildDefs { arg s;
		var rat = Engine_Tahned.ratios;      // percussion
		var mul = Engine_Tahned.mults;       // the chip's own, for tone

		fTypes.do { |ft|

			// ============================================================ KICK
			// A sine body dropped onto its fundamental, one modulator for the
			// buzz, and a click on top. PUNCH is the only macro here: it drives
			// the body and tightens its front together, because a kick that is
			// harder is also a kick that is shorter.
			//
			//  8 tune  9 sweep 10 s.time 11 decay 12 fm 13 ratio 14 click 15 punch
			SynthDef(("tahned_kick_" ++ ft).asSymbol, { |bus = 0, mbus = 0, gbus = 0,
				out = 0, vel = 1, note = 36|
				var p = Latch.kr(In.kr(bus, nCh) + In.kr(mbus, nCh), Impulse.kr(0));
				var g = Latch.kr(In.kr(gbus, 8), Impulse.kr(0));
				var tune = p[8].linlin(0, 1, -24, 24) + (g[0] * 24);
				var sdep = (p[9] * 2) - 1;
				var stim = p[10].linexp(0, 1, 0.01, 1.2) * (2 ** (g[2] * 2));
				var dec  = p[11].linexp(0, 1, 0.02, 4) * (2 ** (g[2] * 3));
				var idx  = p[12] * (2 ** (g[3] * 2));
				var rt   = Select.kr(p[13].round.clip(0, 15), rat);
				var clk  = p[14];
				var pun  = p[15];
				var atk  = 0.0008 * (2 ** (g[1] * 4));
				var base = (note + tune).midicps;
				// The drop, and it is the whole of what makes a kick a kick.
				// Two things had to be true before either control was worth
				// turning. The time has to reach far enough to be heard as a
				// pitch moving rather than as a click: over 0.002..0.6 the
				// bottom half of S.TIME was all under 20ms, which is one cycle
				// at the pitch a kick lands on, so most of the knob did
				// nothing. And the depth has to stay inside the audio band --
				// at four octaves the downward half started at 3Hz and the
				// front of the hit was simply missing, which is the other way
				// a control looks inert. Three octaves off a 49Hz fundamental
				// still reaches 390Hz, which is as far up as a kick wants.
				var swp  = EnvGen.ar(Env([1, 0], [stim], [-2.5]));
				var f    = base * (2 ** (swp * sdep * 3));
				var mod, body, amp, click, sig;

				mod  = Engine_Tahned.sop(f * rt) * idx;
				body = Engine_Tahned.sop(f, mod * 0.5);
				body = ((body * (1 + (pun * 6))).tanh) / (1 + (pun * 2.2));
				amp  = EnvGen.ar(Env([0, 1, 0],
					[atk, dec * (1 - (pun * 0.35))], [0, -4]));
				click = (HPF.ar(WhiteNoise.ar, 2200) + Impulse.ar(0))
					* EnvGen.ar(Env([1, 0], [0.007], [-8])) * clk * 1.4;

				sig = (body * amp) + click;
				Out.ar(out, Engine_Tahned.drumTail(ft, sig, p, g, note, vel,
					stim + dec));
			}).add;

			// =========================================================== SNARE
			// Two FM tones a fifth-and-a-bit apart for the shell, a filtered
			// noise bed for the wires, and SNAP balancing them. N.TONE is the
			// noise's colour and its bandwidth on one bipolar control: dark and
			// narrow to the left, bright and open to the right.
			//
			//  8 tune  9 snap 10 fm 11 ratio 12 b.dec 13 n.dec 14 n.tone 15 crack
			SynthDef(("tahned_snare_" ++ ft).asSymbol, { |bus = 0, mbus = 0, gbus = 0,
				out = 0, vel = 1, note = 36|
				var p = Latch.kr(In.kr(bus, nCh) + In.kr(mbus, nCh), Impulse.kr(0));
				var g = Latch.kr(In.kr(gbus, 8), Impulse.kr(0));
				var tune = p[8].linlin(0, 1, -24, 24) + (g[0] * 24);
				var snap = p[9];
				var idx  = p[10] * 4 * (2 ** (g[3] * 2));
				var rt   = Select.kr(p[11].round.clip(0, 15), rat);
				var bdec = p[12].linexp(0, 1, 0.01, 1.5) * (2 ** (g[2] * 3));
				var ndec = p[13].linexp(0, 1, 0.01, 2.5) * (2 ** (g[2] * 3));
				var ntn  = (p[14] * 2) - 1;
				var crk  = p[15];
				var atk  = 0.0006 * (2 ** (g[1] * 4));
				// a snare sits about two octaves over the trigger note; TUNE
				// trims around that rather than having to climb to it
				var f    = (note + tune + 21).midicps;
				var nlo  = ntn.linexp(-1, 1, 260, 3500);
				var nwd  = 0.5 + (ntn.abs * 1.2);
				var mod, t1, t2, body, bEnv, nz, nEnv, crack, sig;

				mod = Engine_Tahned.sop(f * rt) * idx;
				t1  = Engine_Tahned.sop(f, mod * 0.5);
				// the shell's second mode, which is what stops two detuned
				// sines from sounding like one sine
				t2  = Engine_Tahned.sop(f * 1.588, mod * 0.35);
				body = (t1 + (t2 * 0.7)) * 0.6;
				bEnv = EnvGen.ar(Env([0, 1, 0], [atk, bdec], [0, -4]));

				nz = LPF.ar(HPF.ar(WhiteNoise.ar, nlo),
					(nlo * (1 + (nwd * 8))).clip(300, 18000));
				nEnv = EnvGen.ar(Env([0, 1, 0], [0.0005, ndec], [0, -4]));

				crack = HPF.ar(WhiteNoise.ar, 4000)
					* EnvGen.ar(Env([1, 0], [0.009], [-8])) * crk * 1.2;

				sig = (body * bEnv * (1 - (snap * 0.85))) + (nz * nEnv * snap) + crack;
				Out.ar(out, Engine_Tahned.drumTail(ft, sig, p, g, note, vel,
					bdec.max(ndec)));
			}).add;

			// ============================================================= HAT
			// Six partials cross-modulated by a seventh and pushed through a
			// resonant high band -- the 808's square-oscillator cluster done in
			// FM. SPREAD walks the partials off the harmonic series, which is
			// the difference between a bell and a hat. OPEN is the one control
			// that turns a tick into a wash: it opens a tail behind the decay.
			//
			//  8 tune  9 spread 10 fm 11 decay 12 tone 13 res 14 noise 15 open
			SynthDef(("tahned_hat_" ++ ft).asSymbol, { |bus = 0, mbus = 0, gbus = 0,
				out = 0, vel = 1, note = 36|
				var har = [1, 2, 3, 4, 5, 6];
				var inh = [1, 1.41, 1.87, 2.51, 3.16, 4.24];
				var p = Latch.kr(In.kr(bus, nCh) + In.kr(mbus, nCh), Impulse.kr(0));
				var g = Latch.kr(In.kr(gbus, 8), Impulse.kr(0));
				var tune = p[8].linlin(0, 1, -24, 24) + (g[0] * 24);
				var sprd = p[9];
				var idx  = p[10] * 3 * (2 ** (g[3] * 2));
				var dec  = p[11].linexp(0, 1, 0.008, 1.2) * (2 ** (g[2] * 3));
				var tc   = p[12].linexp(0, 1, 700, 12000) * (2 ** (g[4] * 2));
				var res  = (p[13] + g[5]).clip(0, 1);
				var nlev = p[14];
				var open = p[15];
				var atk  = 0.0004 * (2 ** (g[1] * 4));
				var f    = (note + tune + 45).midicps;
				var rs   = har.collect { |h, i| h + ((inh[i] - h) * sprd) };
				var mod, amp, sig, life;

				mod = Engine_Tahned.sop(f * (rs[5] * 1.73)) * idx;
				sig = Mix(rs.collect { |r| Engine_Tahned.sop(f * r, mod * 0.4) }) * 0.28;
				sig = sig + (WhiteNoise.ar * nlev * 0.7);

				life = dec + (open * 2.5);
				amp = EnvGen.ar(Env([0, 1, 0.3 * open, 0],
					[atk, dec, dec + (open * 2.5)], [0, -4, -4]));
				sig = RHPF.ar(sig * amp, tc.clip(200, 16000),
					(1 - (res * 0.95)).max(0.05));

				Out.ar(out, Engine_Tahned.drumTail(ft, sig, p, g, note, vel, life));
			}).add;

			// ============================================================= TOM
			// A kick that keeps its pitch: a shallower, slower bend, a skin
			// transient at the front, and WOOD ringing a shell around it.
			//
			//  8 tune  9 bend 10 b.time 11 decay 12 fm 13 ratio 14 skin 15 wood
			SynthDef(("tahned_tom_" ++ ft).asSymbol, { |bus = 0, mbus = 0, gbus = 0,
				out = 0, vel = 1, note = 36|
				var p = Latch.kr(In.kr(bus, nCh) + In.kr(mbus, nCh), Impulse.kr(0));
				var g = Latch.kr(In.kr(gbus, 8), Impulse.kr(0));
				var tune = p[8].linlin(0, 1, -24, 24) + (g[0] * 24);
				var bend = (p[9] * 2) - 1;
				var btim = p[10].linexp(0, 1, 0.01, 1.2) * (2 ** (g[2] * 2));
				var dec  = p[11].linexp(0, 1, 0.03, 3) * (2 ** (g[2] * 3));
				var idx  = p[12] * 3 * (2 ** (g[3] * 2));
				var rt   = Select.kr(p[13].round.clip(0, 15), rat);
				var skin = p[14];
				var wood = p[15];
				var atk  = 0.0008 * (2 ** (g[1] * 4));
				var f0   = (note + tune + 7).midicps;
				// a tom bends about a fifth, not two octaves; the shallower
				// range is what keeps it a tom as the control is opened up.
				// Same curve as the kick, and for the same reason: at -4 the
				// bend was over long before B.TIME said it was.
				var swp  = EnvGen.ar(Env([1, 0], [btim], [-2.5]));
				var f    = f0 * (2 ** (swp * bend * 1.2));
				var mod, body, amp, hit, shell, sig;

				mod  = Engine_Tahned.sop(f * rt) * idx;
				body = Engine_Tahned.sop(f, mod * 0.5);
				amp  = EnvGen.ar(Env([0, 1, 0], [atk, dec], [0, -4]));

				hit = BPF.ar(WhiteNoise.ar, (f0 * 6).clip(200, 12000), 0.6)
					* EnvGen.ar(Env([1, 0], [0.02], [-6])) * skin * 2;
				// the shell: two modes rung by the hit rather than a second
				// oscillator, so WOOD colours the attack instead of adding to it
				shell = Ringz.ar(Impulse.ar(0), f0 * [2.7, 4.1], 0.09).sum
					* wood * 0.35;

				sig = (body * amp) + hit + shell;
				Out.ar(out, Engine_Tahned.drumTail(ft, sig, p, g, note, vel,
					btim + dec));
			}).add;

			// ============================================================ CYMB
			// The hat's cluster taken long and dense: eight partials, a noise
			// sizzle riding the tail, and SWELL running the attack backwards
			// for a reverse crash. DIRT folds the whole thing over.
			//
			//  8 tune  9 spread 10 fm 11 decay 12 tone 13 sizzle 14 swell 15 dirt
			SynthDef(("tahned_cymb_" ++ ft).asSymbol, { |bus = 0, mbus = 0, gbus = 0,
				out = 0, vel = 1, note = 36|
				var har = [1, 2, 3, 4, 5, 6, 7, 8];
				var inh = [1, 1.41, 1.87, 2.51, 3.16, 4.24, 5.37, 6.81];
				var p = Latch.kr(In.kr(bus, nCh) + In.kr(mbus, nCh), Impulse.kr(0));
				var g = Latch.kr(In.kr(gbus, 8), Impulse.kr(0));
				var tune = p[8].linlin(0, 1, -24, 24) + (g[0] * 24);
				var sprd = p[9];
				var idx  = p[10] * 5 * (2 ** (g[3] * 2));
				var dec  = p[11].linexp(0, 1, 0.1, 12) * (2 ** (g[2] * 3));
				var tc   = p[12].linexp(0, 1, 500, 9000) * (2 ** (g[4] * 2));
				var sizz = p[13];
				var swl  = p[14].linexp(0, 1, 0.001, 3) * (2 ** (g[1] * 3));
				var dirt = (p[15] + g[6]).clip(0, 1);
				var f    = (note + tune + 45).midicps;
				var rs   = har.collect { |h, i| h + ((inh[i] - h) * sprd) };
				var mod, amp, nz, sig;

				mod = Engine_Tahned.sop(f * (rs[7] * 1.41)) * idx;
				sig = Mix(rs.collect { |r| Engine_Tahned.sop(f * r, mod * 0.4) }) / 8;
				// the sizzle is on the tail, not the front: it follows the
				// envelope rather than sitting under it
				nz = HPF.ar(WhiteNoise.ar, 6000) * sizz * 0.5;
				sig = sig + nz;
				sig = Fold.ar(sig * (1 + (dirt * 8)), -1, 1) / (1 + (dirt * 2.5));

				amp = EnvGen.ar(Env([0, 1, 0], [swl, dec], [2, -4]));
				sig = HPF.ar(sig * amp, tc.clip(100, 14000));

				Out.ar(out, Engine_Tahned.drumTail(ft, sig, p, g, note, vel,
					swl + dec));
			}).add;

			// ============================================================ TONE
			// 4 operator FM, OPL3 waveform set, ADSR on both envelopes.
			//
			// Everything is read live off the bus rather than latched at note on,
			// so a parameter turned while a note is held is heard on that note.
			// The lag is what keeps a swept ratio or a switched algorithm from
			// clicking; it is also why a p-lock is heard for as long as its step
			// is current rather than for the whole of a note that outlives it.
			//
			//  8 algo   9 rat1  10 rat2  11 rat3  12 rat4 13 fdbk 14 detune 15 fine
			// 16 lvl1  17 lvl2  18 lvl3  19 lvl4  20 waveC 21 waveM 22 index 23 fold
			// 24 aAtk  25 aDec  26 aSus  27 aRel  28 cycle 29 vel  30 spread
			// 31 mAtk  32 mDec  33 mSus  34 mRel  35 destA 36 depA 37 destB 38 depB
			SynthDef(("tahned_tone_" ++ ft).asSymbol, { |bus = 0, mbus = 0, gbus = 0,
				out = 0, gate = 1, hz = 220, vel = 1, t_choke = 0|
				var p = (In.kr(bus, nCh) + In.kr(mbus, nCh)).lag(0.02);
				var g = In.kr(gbus, 8).lag(0.05);
				// syn1
				var algo  = p[8].round.clip(0, 7);
				var r1 = Select.kr(p[9].round.clip(0, 12), mul);
				var r2 = Select.kr(p[10].round.clip(0, 12), mul);
				var r3 = Select.kr(p[11].round.clip(0, 12), mul);
				var r4 = Select.kr(p[12].round.clip(0, 12), mul);
				var fbk   = p[13];                     // shown as the chip's 0..7
				var det   = ((p[14] * 2) - 1) * 0.03;
				var fine  = ((p[15] * 2) - 1) * 0.5;
				// syn2
				var l1 = p[16], l2 = p[17], l3 = p[18], l4 = p[19];
				var waveC = p[20].round.clip(0, 7);
				var waveM = p[21].round.clip(0, 7);
				var index = p[22].linlin(0, 1, 0, 6);
				var fold  = p[23];
				// syn3  amp ADSR. Curves are fixed: a convex attack and an
				// exponential decay and release, which is where the curve
				// controls were always being left.
				var aAtk = p[24].linexp(0, 1, 0.0008, 8) * (2 ** (g[1] * 3));
				var aDec = p[25].linexp(0, 1, 0.004, 8) * (2 ** (g[2] * 3));
				var aSus = p[26];
				var aRel = p[27].linexp(0, 1, 0.004, 12) * (2 ** (g[2] * 3));
				// CYCLE is one control over both envelopes: OFF, AMP, MOD, BOTH.
				// Two loop switches were never set apart, and folding them frees
				// the cell the mod EG's second destination needs.
				var cyc = p[28].round.clip(0, 3);
				var aLoop = Select.kr(cyc, [0, 1, 0, 1]);
				var mLoop = Select.kr(cyc, [0, 0, 1, 1]);
				var velAmp = p[29];
				var spread = (p[30] * 2) - 1;
				// syn4  mod ADSR, with two destinations rather than one, so the
				// same envelope can open the filter and push the index at once
				var mAtk = p[31].linexp(0, 1, 0.0008, 8) * (2 ** (g[1] * 3));
				var mDec = p[32].linexp(0, 1, 0.004, 8) * (2 ** (g[2] * 3));
				var mSus = p[33];
				var mRel = p[34].linexp(0, 1, 0.004, 12) * (2 ** (g[2] * 3));
				var mDstA = p[35].round.clip(0, 6);
				var mDepA = (p[36] * 2) - 1;
				var mDstB = p[37].round.clip(0, 6);
				var mDepB = (p[38] * 2) - 1;
				// filter
				var cut   = p[41].linexp(0, 1, 30, 16000) * (2 ** (g[4] * 4));
				var res   = (p[42] + g[5]).clip(0, 1);
				var fEnvA = (p[43] * 2) - 1;
				var fAtk  = p[44].linexp(0, 1, 0.0008, 4) * (2 ** (g[1] * 3));
				var fDec  = p[45].linexp(0, 1, 0.005, 8) * (2 ** (g[2] * 3));
				var ktrk  = p[46];
				var fDrv  = (p[47] + g[7]).clip(0, 1);

				var a4 = Engine_Tahned.algo4(algo);
				var c43 = a4[0], c42 = a4[1], c32 = a4[2];
				var c41 = a4[3], c31 = a4[4], c21 = a4[5];
				var o4 = a4[6], o3 = a4[7], o2 = a4[8], o1 = a4[9];
				// One-hot mask per destination, index 0 being OFF. Summing the
				// two depths through the masks means a destination named twice
				// simply gets both, and one named by neither gets nothing.
				var mskA = (0..6).collect { |i|
					Select.kr(mDstA, Array.fill(7, { |j| (i == j).binaryValue })) };
				var mskB = (0..6).collect { |i|
					Select.kr(mDstB, Array.fill(7, { |j| (i == j).binaryValue })) };
				var aGt = (gate * (1 - aLoop))
					+ (aLoop * gate * Impulse.kr(1 / (aAtk + aDec + aRel + 0.002)));
				var mGt = (gate * (1 - mLoop))
					+ (mLoop * gate * Impulse.kr(1 / (mAtk + mDec + mRel + 0.002)));

				var ampEg = EnvGen.ar(
					Env([0, 1, aSus, 0], [aAtk, aDec, aRel], [2, -4, -4], releaseNode: 2),
					aGt, doneAction: 2 * (1 - aLoop));
				var modEg = EnvGen.ar(
					Env([0, 1, mSus, 0], [mAtk, mDec, mRel], [2, -4, -4], releaseNode: 2),
					mGt);
				// what the mod EG contributes to each destination
				var md = (0..6).collect { |i|
					modEg * ((mDepA * mskA[i]) + (mDepB * mskB[i])) };
				var f = hz * (2 ** ((fine + (md[2] * 12) + (g[0] * 24)) / 12));
				var idx = (index * (1 + (md[1] * 2)) * (2 ** (g[3] * 2))).max(0);
				var fld = (fold + md[3] + g[6]).clip(0, 1);
				var fbA = (fbk + md[5]).clip(0, 1);
				var l4m = (l4 + md[6]).clip(0, 1);
				// SPREAD places the voice by its own pitch, so a chord opens out
				// across the field instead of every note landing in one spot --
				// which is what a pan offset would be, and MASTER PAN already is.
				var place = (spread * ((hz.cpsmidi - 60) / 24)).clip(-1, 1);

				var op4, op3, op2, op1, sig, fEnv, fbs;

				fbs = LocalIn.ar(1);
				op4 = Engine_Tahned.op(f * r4 * (1 + det), fbs * fbA * 0.4, waveM) * l4m;
				LocalOut.ar(op4);

				op3 = Engine_Tahned.op(f * r3 * (1 - det), op4 * c43 * idx * 0.2, waveM) * l3;
				op2 = Engine_Tahned.op(f * r2 * (1 + (det * 0.5)),
					((op4 * c42) + (op3 * c32)) * idx * 0.2, waveM) * l2;
				op1 = Engine_Tahned.op(f * r1,
					((op4 * c41) + (op3 * c31) + (op2 * c21)) * idx * 0.2, waveC) * l1;

				sig = (op4 * o4) + (op3 * o3) + (op2 * o2) + (op1 * o1);
				sig = Fold.ar(sig * (1 + (fld * 8)), -1, 1) * (1 / (1 + (fld * 2.5)));

				fEnv = EnvGen.ar(Env([0, 1, 0], [fAtk, fDec], [2, -4]), gate);
				sig = Engine_Tahned.flt(ft, sig * (1 + (fDrv * 4)),
					cut * (2 ** ((fEnv * fEnvA * 5) + (md[4] * 5)))
						* (2 ** ((hz.cpsmidi - 60) / 12 * ktrk)),
					res) / (1 + (fDrv * 2));

				FreeSelf.kr(aLoop * TDelay.kr(1 - gate, aRel + 0.05));
				sig = sig * ampEg * (1 - velAmp + (velAmp * vel)) * 0.28;
				// stolen voices fade out here and free themselves, whatever the
				// amp envelope's own release or loop setting is doing
				sig = sig * EnvGen.ar(Env([1, 0], [0.015]), t_choke, doneAction: 2);
				Out.ar(out, Pan2.ar(sig, place));
			}).add;
		};

		// ============================================================== LFO
		// Four LFOs per track, two destinations each. Each one scatters its
		// output into the track's mod bus with a dynamic-index Out.kr, so a
		// destination is just a channel number -- any parameter, no routing
		// matrix, no per-destination cost.
		SynthDef(\tahned_modclear, { |mbus = 0|
			ReplaceOut.kr(mbus, DC.kr(0) ! nCh);
		}).add;

		SynthDef(\tahned_lfo, { |bus = 0, mbus = 0, bpm = 120, t_trig = 0|
			var p = In.kr(bus, nCh);
			(0..3).do { |i|
				var b = 56 + (i * 8);
				var spd  = p[b];
				var mult = Select.kr(p[b + 1].round.clip(0, 7), [1, 2, 4, 8, 16, 32, 64, 128]);
				var wave = p[b + 2].round.clip(0, 7);
				var mode = p[b + 3].round.clip(0, 3);
				var dA   = p[b + 4].round.clip(0, nCh - 1);
				var depA = p[b + 5];
				var dB   = p[b + 6].round.clip(0, nCh - 1);
				var depB = p[b + 7];
				var mIs  = (0..3).collect { |k|
					Select.kr(mode, Array.fill(4, { |j| (k == j).binaryValue })) };
				var hz   = ((spd / 64) * mult * (bpm / 60) / 8).clip(0.001, 200);
				var rt   = t_trig * (mIs[1] + mIs[3]);
				var ph   = Phasor.kr(rt, hz * ControlDur.ir, 0, 1);
				var raw  = Select.kr(wave, [
					1 - (4 * (ph - 0.5).abs),      // tri
					sin(ph * 2pi),                 // sine
					((ph < 0.5) * 2) - 1,          // square
					1 - (ph * 2),                  // saw down
					(ph * 2) - 1,                  // ramp up
					(((1 - ph) ** 3) * 2) - 1,     // exp
					LFNoise1.kr(hz),               // smooth random
					LFNoise0.kr(hz)                // sample and hold
				]);
				var one = Sweep.kr(rt, hz) < 1;
				var val = Select.kr(mode, [raw, raw, Latch.kr(raw, t_trig), raw * one]);
				Out.kr(mbus + dA, val * depA);
				Out.kr(mbus + dB, val * depB);
			};
		}).add;

		// =========================================================== STRIP
		// per track: drive -> pan/level -> the mix bus + three sends.
		// The colour chain used to be here, eight deep; it is one chain on the
		// master now, so a track's strip is only what makes it a track.
		//
		// There is no width stage any more. A mid/side trim over a track that
		// is mostly one voice measured something rather than moved it, and it
		// sat where the control everybody actually reaches for should be. PAN
		// places the track; the image it arrives with is left alone.
		SynthDef(\tahned_strip, { |bus = 0, mbus = 0, gbus = 0, in = 0, out = 0,
			cho = 0, dly = 0, rev = 0|
			var p = (In.kr(bus, nCh) + In.kr(mbus, nCh)).lag(0.02);
			var g = In.kr(gbus, 8).lag(0.05);
			var lvl  = p[0], pan = (p[1] * 2) - 1, drv = (p[2] + g[7]).clip(0, 1);
			var sCho = p[3], sDly = p[4], sRev = p[5];
			var sig = In.ar(in, 2);

			sig = ((sig * (1 + (drv * 12))).tanh) / (1 + (drv * 2.2));

			sig = Balance2.ar(sig[0], sig[1], pan, lvl.squared * 1.4);
			sig = Limiter.ar(sig, 0.95, 0.005);

			Out.ar(out, sig);
			Out.ar(cho, sig * sCho.squared);
			Out.ar(dly, sig * sDly.squared);
			Out.ar(rev, sig * sRev.squared);
		}).add;

		// ========================================================== COLOUR
		// One chain over the summed mix, the sends included. The order is the
		// order damage happens in on real gear: drive, then quantise, then
		// wobble, then saturate, then tilt, then throw information away, then
		// break it, and only then ask something to hold the level.
		//
		// DRIVE and TONE belong to the SEND FX page rather than to COLOUR, but
		// they are the same signal path and the drive has to come first, so
		// they are two more arguments here rather than a synth of their own.
		//
		// LOSS is a codec rather than a filter. Dropping the quiet bins is what
		// an mp3 actually does, and it is what makes the artefact recognisable:
		// the survivors smear into the holes the discarded ones leave.
		//
		// GLITCH keeps a rolling half second of the mix and, at random, stops
		// reading live and loops a slice of it instead, with the odd dropout
		// through it. The buffer is always recording, so a glitch is always of
		// something that was really just played.
		SynthDef(\tahned_colour, { |in = 0, out = 0, crush = 0, wow = 0,
			wrate = 0.3, saturn = 0, tilt = 0, loss = 0, glitch = 0, comp = 0,
			drive = 0, dtone = 0.5|
			var sig = In.ar(in, 2);
			var bits = crush.linlin(0, 1, 16, 3);
			var srate = crush.linexp(0, 1, 48000, 1200);
			var wowR = wrate.linexp(0, 1, 0.12, 8);
			var cAtk = comp.linexp(0, 1, 0.08, 0.0006);
			var tg = tilt * 9;
			// TONE tilts what goes into the drive rather than what comes out,
			// which is the difference between choosing what distorts and
			// equalising a distortion that has already happened. It is scaled
			// by DRIVE so the stage is transparent with the drive down.
			var dtg = (dtone - 0.5) * 14 * drive;
			var dry, q, wob, amp, lossy, gBuf, wp, gTrg, gLen, gStart, rp, held;
			var win, drop, cmp;

			sig = BLowShelf.ar(sig, 400, 1, dtg.neg);
			sig = BHiShelf.ar(sig, 3000, 1, dtg);
			sig = ((sig * (1 + (drive * 14))).tanh) / (1 + (drive * 2.6));

			// bit + rate reduction, blended so the ends of the range are clean
			q = 0.5 ** (bits - 1);
			dry = sig;
			sig = Latch.ar(sig, Impulse.ar(srate));
			sig = (sig / q).round * q;
			sig = SelectX.ar(((16 - bits) / 13).max((48000 - srate) / 46800).clip(0, 1),
				[dry, sig]);

			// tape wow + flutter
			wob = (SinOsc.kr(wowR, [0, 0.3]) * 0.7) + (LFNoise2.kr(wowR * 7) * 0.3);
			sig = DelayC.ar(sig, 0.05, (0.012 + (wob * wow * 0.011)).clip(0.0002, 0.045));

			// SATURN: tape saturation, and the top end it costs
			sig = ((sig * (1 + (saturn * 5))).tanh) / (1 + (saturn * 1.8));
			sig = LPF.ar(sig, 18000 - (saturn * 10000));

			// TILT: one control pivoting the spectrum about 1k, the way a DJ
			// isolator does -- lows up and highs down, or the other way
			sig = BLowShelf.ar(sig, 500, 1, tg.neg);
			sig = BHiShelf.ar(sig, 2500, 1, tg);

			// LOSS: drop the quiet bins, smear what is left, lose the top.
			// The threshold is taken against a level-tracked copy rather than
			// against the raw magnitudes: an absolute one is a gate, wiping a
			// quiet passage and leaving a loud one alone, which is the opposite
			// of what a codec does.
			amp = Amplitude.kr(Mix(sig) * 0.5, 0.01, 0.25).max(0.002);
			lossy = IFFT(
				PV_MagSmear(
					PV_MagAbove(FFT({ LocalBuf(1024) } ! 2, sig / amp), loss * 9),
					(loss * 10).round)) * amp;
			lossy = LPF.ar(lossy, loss.linexp(0, 1, 18000, 2600));
			sig = SelectX.ar(loss.clip(0, 1), [sig, lossy]);

			// GLITCH
			gBuf = LocalBuf(SampleRate.ir * 0.5, 2).clear;
			wp = Phasor.ar(0, 1, 0, BufFrames.kr(gBuf));
			BufWr.ar(sig, gBuf, wp);
			gTrg = Dust.kr(glitch.linexp(0.0001, 1, 0.02, 14));
			gLen = (Latch.kr(TRand.kr(0.015, 0.14, gTrg), gTrg) * SampleRate.ir).max(64);
			gStart = Latch.ar(wp, T2A.ar(gTrg));
			rp = (gStart + Phasor.ar(T2A.ar(gTrg), 1, 0, gLen)) % BufFrames.kr(gBuf);
			held = BufRd.ar(2, gBuf, rp, 1, 2);
			// like the dropout below, this has to start closed: an envelope
			// that starts open hands the output to an empty buffer until the
			// first stutter fires
			win = EnvGen.ar(Env([0, 1, 1, 0],
				[0, Latch.kr(TRand.kr(0.04, 0.3, gTrg), gTrg), 0.003]), gTrg);
			sig = SelectX.ar((win * glitch).clip(0, 1), [sig, held]);
			// and the odd hole punched straight through. The envelope has to
			// start at zero: EnvGen sits at its first level until the trigger
			// arrives, so a hole that starts open holds the mix shut until the
			// first dropout fires.
			drop = 1 - (EnvGen.ar(Env([0, 1, 1, 0], [0, 0.03, 0.002]),
				Dust.kr(glitch.linexp(0.0001, 1, 0.01, 5))) * (glitch > 0.15));
			sig = sig * drop;

			cmp = Compander.ar(sig, sig, 0.22, 1, 0.28, cAtk, 0.18) * (1 + (comp * 2.2));
			sig = SelectX.ar(comp, [sig, cmp]);

			Out.ar(out, Limiter.ar(LeakDC.ar(sig), 0.95, 0.005));
		}).add;

		// =========================================================== CHORUS
		SynthDef(\tahned_chorus, { |in = 0, out = 0, rate = 0.4, depth = 0.5,
			spread = 0.7, fbk = 0.2, tone = 0.6, level = 1|
			var sig = In.ar(in, 2), fb = LocalIn.ar(2), wet;
			var base = 0.008;
			// all eight tracks can be sending at once, so bound the sum before
			// it reaches anything with feedback in it
			sig = Limiter.ar(LeakDC.ar(sig), 0.9, 0.01);
			sig = sig + (fb * fbk.clip(0, 0.85));
			wet = (0..2).collect { |i|
				var ph = i / 3;
				var mod = SinOsc.kr(rate * (1 + (i * 0.17)), [ph * 2pi, (ph + spread) * 2pi]);
				DelayC.ar(sig, 0.06, (base + (mod * depth * base * 0.9)).clip(0.0002, 0.05));
			};
			wet = Mix(wet) / 3;
			wet = LPF.ar(wet, tone.linexp(0, 1, 900, 16000));
			LocalOut.ar(LeakDC.ar(wet));
			Out.ar(out, Limiter.ar(wet * level, 0.95, 0.01));
		}).add;

		// ============================================================ DELAY
		SynthDef(\tahned_delay, { |in = 0, out = 0, time = 0.375, fbk = 0.45,
			hp = 0.15, lp = 0.75, ping = 0, mod = 0.1, level = 1|
			var sig = In.ar(in, 2), fb = LocalIn.ar(2), t, d;
			sig = Limiter.ar(LeakDC.ar(sig), 0.9, 0.01);
			t = Lag.kr(time, 0.25);
			t = t * (1 + (LFNoise2.kr(0.3 ! 2) * mod * 0.02));
			d = DelayC.ar(sig + (fb * fbk.clip(0, 0.98)), 8, t.clip(0.001, 8));
			d = HPF.ar(d, hp.linexp(0, 1, 20, 2000));
			d = LPF.ar(d, lp.linexp(0, 1, 400, 17000));
			// Soft clip with unity small signal gain. Scaling up after a tanh
			// would put the loop over unity on its own and self oscillate,
			// which is a saturated drone rather than a decaying repeat.
			d = (d * 1.5).tanh / 1.5;
			LocalOut.ar(LeakDC.ar(SelectX.ar(ping, [d, [d[1], d[0]]])));
			Out.ar(out, Limiter.ar(d * level, 0.95, 0.01));
		}).add;

		// =========================================================== REVERB
		// Shimmer: a pitch shifted copy of the tail folded back in.
		//
		// FreeVerb carries its own decay, so SIZE alone sets the tail length
		// and only the pitch shifted path is fed back. Wrapping a broadband
		// loop around the whole reverb, as this first did, makes the two
		// decays multiply into a runaway rather than a longer tail.
		//
		// FreeVerb's sustained gain climbs steeply with room -- its comb
		// feedback is 0.28*room+0.7 and each of the eight combs is scaled by
		// 0.015, so gain ~= 0.12 / (0.3 - 0.28*room), which passes 3 at the
		// top of the range. The shimmer feedback therefore has to shrink as
		// the room grows, or the two compound. SHIM FBK is scaled to keep the
		// round trip at 0.8 at worst, and the loop is soft clipped with unity
		// small signal gain and DC blocked so it can only shed energy.
		SynthDef(\tahned_reverb, { |in = 0, out = 0, size = 0.7, damp = 0.4,
			shim = 0.3, interval = 12, shimfb = 0.5, pre = 0.02,
			lowcut = 0.1, level = 1|
			var sig = In.ar(in, 2), fb = LocalIn.ar(2), verb, sh, node, room, g;
			// every track can be sending at once, so bound the sum first
			sig = Limiter.ar(LeakDC.ar(sig), 0.9, 0.01);
			sig = DelayC.ar(sig, 0.5, pre.clip(0, 0.45));

			room = size.linlin(0, 1, 0.1, 0.93);
			node = sig + fb;
			node = LPF.ar(node, damp.linexp(0, 1, 16000, 900));
			node = HPF.ar(node, lowcut.linexp(0, 1, 20, 900));
			verb = FreeVerb2.ar(node[0], node[1], 1, room, 0.3);

			sh = PitchShift.ar(verb, 0.12, 2 ** (interval / 12), 0, 0.01);
			g = shimfb.clip(0, 1) * shim.clip(0, 1)
				* (0.8 / (0.12 / (0.3 - (room * 0.28)))).clip(0.02, 0.9);
			LocalOut.ar(LeakDC.ar(((sh * g) * 2).tanh / 2));

			// FreeVerb's wet-only output sits well below its input
			Out.ar(out, Limiter.ar(verb * level * 1.6, 0.95, 0.01));
		}).add;
	}

	// ------------------------------------------------------------- voicing
	defFor { arg t, kind;
		^(kind ++ "_" ++ fTypes[ftype[t].clip(0, 3)]).asSymbol
	}

	// split out of alloc and freeTrack so the bookkeeping can be exercised
	// without a server behind it
	initVoices {
		voices = Array.newClear(nTracks);
		live   = Array.newClear(nTracks);
		nTracks.do { |t| this.clearVoices(t) };
	}

	clearVoices { arg t;
		voices[t] = IdentityDictionary.new;
		live[t]   = Array.new(maxVoices);
	}

	freeTrack { arg t;
		vGroup[t].freeAll;
		this.clearVoices(t);
	}

	// ------------------------------------------------------- voice stealing
	// `live` is the truth about what is running: a voice leaves it when the
	// server reports the node gone, not when the note is released.

	forgetVoice { arg t, e;
		live[t].remove(e);
		if(voices[t][e.id] === e) { voices[t].removeAt(e.id) };
	}

	// Choking runs a 15ms fade in the synth and frees it, so stealing does not
	// click and does not depend on the voice's own release or loop settings.
	chokeVoice { arg t, e;
		this.forgetVoice(t, e);
		e.syn.set(\t_choke, 1);
	}

	// Take the oldest voice that is already releasing; only if every voice is
	// still held does the oldest held one go, which is the usual last resort.
	stealVoice { arg t;
		var victim = live[t].detect { |e| e.held.not } ?? { live[t].first };
		victim !? { |e| this.chokeVoice(t, e) };
	}

	allocVoice { arg t, id, syn;
		var e = (syn: syn, id: id, held: true);
		live[t] = live[t].add(e);
		voices[t][id] = e;
		syn.onFree { this.forgetVoice(t, e) };
		while { live[t].size > maxVoices } { this.stealVoice(t) };
		^e
	}

	releaseVoice { arg t, e;
		e.held = false;
		e.syn.set(\gate, 0);
	}

	setMachine { arg t, m;
		this.freeTrack(t);
		machine[t] = m.clip(0, machines.size - 1);
	}

	// ------------------------------------------------------------ commands
	addCommands {

		this.addCommand(\machine, "ii", { |msg|
			this.setMachine(msg[1].asInteger.clip(0, nTracks - 1), msg[2].asInteger);
		});

		// filter type picks a compiled synthdef variant rather than a runtime
		// branch, so it is only read when the next voice starts
		this.addCommand(\ftype, "ii", { |msg|
			var t = msg[1].asInteger.clip(0, nTracks - 1);
			ftype[t] = msg[2].asInteger.clip(0, 3);
		});

		// one of the eight global PERFORM offsets, -1..1
		this.addCommand(\perf, "if", { |msg|
			gBus.setAt(msg[1].asInteger.clip(0, 7), msg[2]);
		});

		// the master colour chain
		this.addCommand(\colSet, "sf", { |msg|
			colourS !? { |c| c.set(msg[1].asSymbol, msg[2]) };
		});

		// one parameter channel on one track
		this.addCommand(\pset, "iif", { |msg|
			pBus[msg[1].asInteger.clip(0, nTracks - 1)]
				.setAt(msg[2].asInteger.clip(0, nCh - 1), msg[3]);
		});

		// a drum hit: the track's machine picks which of the five it is
		this.addCommand(\trig, "iff", { |msg|
			var t = msg[1].asInteger.clip(0, nTracks - 1);
			Synth(this.defFor(t, machines[machine[t].clip(0, machines.size - 2)]), [
				\bus, pBus[t].index, \mbus, mBus[t].index, \gbus, gBus.index,
				\out, tBus[t].index, \vel, msg[2], \note, msg[3]
			], vGroup[t]);
			lfoS[t].set(\t_trig, 1);
		});

		this.addCommand(\noteOn, "iiff", { |msg|
			var t = msg[1].asInteger.clip(0, nTracks - 1);
			var id = msg[2].asInteger;
			// re-triggering a sounding id releases the old voice rather than
			// orphaning it; it keeps its slot until the server frees it
			voices[t][id] !? { |e| this.releaseVoice(t, e) };
			this.allocVoice(t, id, Synth(this.defFor(t, "tahned_tone"), [
				\bus, pBus[t].index, \mbus, mBus[t].index, \gbus, gBus.index,
				\out, tBus[t].index, \hz, msg[3], \vel, msg[4]
			], vGroup[t]));
			lfoS[t].set(\t_trig, 1);
		});

		this.addCommand(\noteOff, "ii", { |msg|
			var t = msg[1].asInteger.clip(0, nTracks - 1);
			voices[t].removeAt(msg[2].asInteger) !? { |e| this.releaseVoice(t, e) };
		});

		this.addCommand(\allOff, "i", { |msg|
			var t = msg[1].asInteger.clip(0, nTracks - 1);
			voices[t].do { |e| this.releaseVoice(t, e) };
			voices[t] = IdentityDictionary.new;
		});

		this.addCommand(\lfoTrig, "i", { |msg|
			lfoS[msg[1].asInteger.clip(0, nTracks - 1)].set(\t_trig, 1);
		});

		this.addCommand(\tempo, "f", { |msg|
			lfoS.do { |l| l.set(\bpm, msg[1]) };
		});

		this.addCommand(\fxSet, "ssf", { |msg|
			fx[msg[1].asSymbol] !? { |f| f.set(msg[2].asSymbol, msg[3]) };
		});

		this.addCommand(\panic, "", { |msg|
			nTracks.do { |t| this.freeTrack(t) };
		});
	}

	free {
		clearS.do(_.free);
		lfoS.do(_.free);
		strip.do(_.free);
		fx.do(_.free);
		colourS.free;
		vGroup.do(_.free);
		[voiceGroup, ctlGroup, sGroup, fxGroup, outGroup].do(_.free);
		pBus.do(_.free);
		mBus.do(_.free);
		tBus.do(_.free);
		[choBus, dlyBus, revBus, mixBus, gBus].do(_.free);
	}
}
