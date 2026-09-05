// Engine_Tahned
// FM groovebox for norns  --  8 tracks x { perc | tone | amb }
//
// Every track owns one 64-channel control bus. Lua writes normalised (0..1)
// values into it; the synthdefs do all range mapping. That keeps parameter
// locks uniform: a lock is just (channel, value).
//
//   ch  0..7   master   level pan drive sendCho sendDly sendRev width -
//   ch  8..39  syn1..4  instrument specific
//   ch 40..47  filter   type cutoff res envAmt envAtk envDec keytrk drive
//   ch 48..55  colour   srrBits srrRate wowDepth wowRate tapeSat compAmt compAtk compMix
//   ch 56..87  lfo1..4  spd mult wave mode destA depA destB depB   (8 each)
//   ch 88..95  spare    88 is the LFO null destination
//
// A second, parallel "mod" bus per track holds LFO offsets only. The LFO synth
// scatters into it with a dynamic-index Out.kr, so any channel above can be a
// modulation destination for free. Voices read pBus + mBus.

Engine_Tahned : CroneEngine {

	classvar <nTracks = 8;
	classvar <nCh = 96;
	// Per-track voice ceiling. A releasing voice still costs a full 4-op FM
	// synth, so with a long release a chord sequence piles them up until the
	// server glitches. 16 is above the largest chord one step can resolve to,
	// so a cap never cuts a chord short -- only the tail of an older one.
	classvar <maxVoices = 16;
	classvar <fTypes;          // filter variants compiled into each voice

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
	var <drone;                // Array[nTracks] of Synth or nil (amb)
	var <machine;              // Array[nTracks] of Integer  0 perc 1 tone 2 amb
	var <ftype;                // Array[nTracks] of Integer  cached filter variant
	var <mBus;                 // Array[nTracks] of 96ch modulation bus (LFO sum)
	var <ctlGroup, <voiceGroup;
	var <clearS, <lfoS;
	var <nzBuf;                // fixed noise, for repeatable drum hits

	*initClass {
		fTypes = [\lp, \bp, \hp, \cmb];
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

	// 3 operator routing for perc. returns [cBA cCA cCB oC oA oB]
	*algo3 { arg a;
		var m = [
			[[1,1,0],[1,0,0]],        // B>A>C
			[[0,1,1],[1,0,0]],        // A>C, B>C
			[[1,0,1],[1,0,0]],        // B>A, B>C
			[[1,1,1],[1,0,0]],        // B>A>C and B>C
			[[1,1,0],[0.8,0.4,0]],    // B>A>C, A audible
			[[0,1,0],[0.7,0,0.5]],    // A>C, B audible
			[[0,0,1],[0.7,0.5,0]],    // B>C, A audible
			[[0,0,0],[0.5,0.4,0.4]]   // all parallel
		].collect { |r| r[0] ++ r[1] };
		^(0..5).collect { |k| Select.kr(a, m.collect { |r| r[k] }) };
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

	// percussion wants inharmonic ratios the chip never had
	*ratios { ^[0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 3.5, 4, 5, 6, 8, 11] }

	// -------------------------------------------------------------- alloc
	alloc {
		var s = context.server;

		machine = Array.fill(nTracks, { 0 });
		ftype   = Array.fill(nTracks, { 0 });
		this.initVoices;
		drone   = Array.newClear(nTracks);

		// one second of noise, so NOISE RESET can make a hit sound identical
		nzBuf = Buffer.alloc(s, s.sampleRate, 1);
		nzBuf.sine1(Array.fill(64, { 1.0.rand }), true, true, true);

		pBus = Array.fill(nTracks, { Bus.control(s, nCh) });
		mBus = Array.fill(nTracks, { Bus.control(s, nCh) });
		tBus = Array.fill(nTracks, { Bus.audio(s, 2) });
		choBus = Bus.audio(s, 2);
		dlyBus = Bus.audio(s, 2);
		revBus = Bus.audio(s, 2);

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

		strip = Array.fill(nTracks, { |i|
			Synth(\tahned_strip, [
				\bus, pBus[i].index, \mbus, mBus[i].index,
				\in, tBus[i].index, \out, context.out_b.index,
				\cho, choBus.index, \dly, dlyBus.index, \rev, revBus.index
			], sGroup);
		});

		fx = IdentityDictionary[
			\cho -> Synth(\tahned_chorus, [\in, choBus.index, \out, context.out_b.index], fxGroup),
			\dly -> Synth(\tahned_delay,  [\in, dlyBus.index, \out, context.out_b.index], fxGroup),
			\rev -> Synth(\tahned_reverb, [\in, revBus.index, \out, context.out_b.index], fxGroup)
		];

		this.addCommands;
	}

	// ------------------------------------------------------------ synthdefs
	buildDefs { arg s;
		var rat = Engine_Tahned.ratios;      // percussion
		var mul = Engine_Tahned.mults;       // the chip's own, for tone

		fTypes.do { |ft|

			// ============================================================ PERC
			// Three operator FM percussion, laid out the way the machine this
			// borrows from does it: each modulator carries its own decay
			// envelope with an end level and its own modulation amount, which
			// is what gives FM drums their snap.
			SynthDef(("tahned_perc_" ++ ft).asSymbol, { |bus = 0, mbus = 0, out = 0,
				vel = 1, note = 36, nzbuf = 0|
				var p = Latch.kr(In.kr(bus, nCh) + In.kr(mbus, nCh), Impulse.kr(0));
				// syn1  fm
				var tune  = p[8].linlin(0, 1, -24, 24);
				var stim  = p[9].linexp(0, 1, 0.002, 1.2);
				var sdep  = (p[10] * 2) - 1;
				var algo  = p[11].round.clip(0, 7);
				var waveC = p[12].round.clip(0, 7);
				var waveM = p[13].round.clip(0, 7);
				var fdbk  = p[14];
				var fold  = p[15];
				// syn2  one modulation envelope per operator
				var ratA = Select.kr(p[16].round.clip(0, 15), rat);
				var decA = p[17].linexp(0, 1, 0.002, 4);
				var endA = p[18];
				var modA = p[19];
				var ratB = Select.kr(p[20].round.clip(0, 15), rat);
				var decB = p[21].linexp(0, 1, 0.002, 4);
				var endB = p[22];
				var modB = p[23];
				// syn3  body
				var bhld = p[24].linexp(0, 1, 0.0005, 2);
				var bdec = p[25].linexp(0, 1, 0.005, 8);
				var phC  = p[26];
				var blev = p[27];
				var nrst = p[28].round.clip(0, 1);
				var nrm  = p[29].round.clip(0, 1);
				var batk = p[30].linexp(0, 1, 0.0002, 0.3);
				var bcrv = p[31].linlin(0, 1, 0, -12);
				// syn4  noise and transient
				var nhld  = p[32].linexp(0, 1, 0.0005, 1);
				var ndec  = p[33].linexp(0, 1, 0.003, 6);
				var tran  = p[34].round.clip(0, 3);
				var tlev  = p[35];
				var nbase = p[36].linexp(0, 1, 40, 8000);
				var nwdth = p[37];
				var ngran = p[38];
				var nlev  = p[39];
				// filter
				var cut   = p[41].linexp(0, 1, 30, 16000);
				var res   = p[42];
				var fEnvA = (p[43] * 2) - 1;
				var fAtk  = p[44].linexp(0, 1, 0.0005, 0.5);
				var fDec  = p[45].linexp(0, 1, 0.005, 3);
				var ktrk  = p[46];
				var fDrv  = p[47];

				var a3 = Engine_Tahned.algo3(algo);
				var cBA = a3[0], cCA = a3[1], cCB = a3[2];
				var oC = a3[3], oA = a3[4], oB = a3[5];

				var base = (note + tune).midicps;
				var sweep = EnvGen.ar(Env([1, 0], [stim], [-4]));
				var f = base * (2 ** (sweep * sdep * 4));

				// phase reset for operator C: 0..90 degrees, or free running
				var phase = Select.kr(phC > 0.99, [phC.linlin(0, 0.99, 0, 0.25), Rand(0, 1)]);

				var envA = EnvGen.ar(Env([1, endA], [decA], [-4]));
				var envB = EnvGen.ar(Env([1, endB], [decB], [-4]));
				var opA, opB, opC, sig, body, nz, nzEnv, tr, fEnv, fb;

				fb = LocalIn.ar(1);
				opB = Engine_Tahned.op(f * ratB, fb * fdbk * 0.4, waveM) * envB;
				LocalOut.ar(opB);
				opA = Engine_Tahned.op(f * ratA, opB * cBA * modB * 4, waveM) * envA;
				opC = Engine_Tahned.op(f,
					((opA * cCA * modA) + (opB * cCB * modB)) * 4, waveC, phase);

				sig = (opC * oC) + (opA * oA * modA) + (opB * oB * modB);

				// wavefold applies to the body only; noise and transient stay clean
				sig = Fold.ar(sig * (1 + (fold * 8)), -1, 1) * (1 / (1 + (fold * 2.5)));
				body = EnvGen.ar(Env([0, 1, 1, 0], [batk, bhld, bdec], [2, 0, bcrv]));
				sig = sig * body * blev;

				// noise reset plays a fixed buffer so a hit can be repeatable
				nz = Select.ar(nrst, [
					WhiteNoise.ar,
					PlayBuf.ar(1, nzbuf, 1, 1, 0, loop: 1)
				]);
				// grain: latching the noise thins white down to something coarse
				nz = Latch.ar(nz, Impulse.ar(ngran.linexp(0, 1, 20000, 200)));
				nz = LPF.ar(HPF.ar(nz, nbase), (nbase * (1 + (nwdth * 30))).clip(40, 18000));
				nz = nz * Select.ar(nrm, [DC.ar(1), opC]);
				nzEnv = EnvGen.ar(Env([0, 1, 1, 0], [0.0005, nhld, ndec], [0, 0, -4]));
				nz = nz * nzEnv * nlev;

				tr = Select.ar(tran, [
					Impulse.ar(0) * 6,
					HPF.ar(WhiteNoise.ar, 5000) * EnvGen.ar(Env.perc(0.0001, 0.006)),
					SinOsc.ar(EnvGen.ar(Env([2400, 180], [0.012], [-8]))),
					Ringz.ar(Impulse.ar(0), 2600 * [1, 1.71], 0.05).sum * 0.4
				]) * tlev;

				sig = sig + nz + tr;

				fEnv = EnvGen.ar(Env([0, 1, 0], [fAtk, fDec], [2, -4]));
				sig = Engine_Tahned.flt(ft, sig * (1 + (fDrv * 4)),
					cut * (2 ** (fEnv * fEnvA * 5)) * (2 ** ((note - 36) / 12 * ktrk)),
					res) / (1 + (fDrv * 2));

				sig = sig * vel.pow(1.4) * 0.7;
				sig = sig * EnvGen.ar(Env([1, 1, 0],
					[bhld + nhld + bdec.max(ndec).max(fDec) * 1.4 + 0.12, 0.02]),
					doneAction: 2);
				Out.ar(out, Pan2.ar(sig, 0));
			}).add;

			// ============================================================ TONE
			// 4 operator FM, OPL3 waveform set, ASR function generators.
			SynthDef(("tahned_tone_" ++ ft).asSymbol, { |bus = 0, mbus = 0, out = 0, gate = 1, hz = 220, vel = 1,
				t_choke = 0|
				var pm = In.kr(bus, nCh) + In.kr(mbus, nCh);
				var pc = pm.lag(0.015);
				var pl = Latch.kr(pm, Impulse.kr(0));
				// syn1
				var algo  = pl[8].round.clip(0, 7);
				var r1 = Select.kr(pl[9].round.clip(0, 12), mul);
				var r2 = Select.kr(pl[10].round.clip(0, 12), mul);
				var r3 = Select.kr(pl[11].round.clip(0, 12), mul);
				var r4 = Select.kr(pl[12].round.clip(0, 12), mul);
				var fbk   = pc[13];                     // shown as the chip's 0..7
				var det   = ((pc[14] * 2) - 1) * 0.03;
				var fine  = ((pl[15] * 2) - 1) * 0.5;
				// syn2
				var l1 = pc[16], l2 = pc[17], l3 = pc[18], l4 = pc[19];
				var waveC = pl[20].round.clip(0, 7);
				var waveM = pl[21].round.clip(0, 7);
				var index = pc[22].linlin(0, 1, 0, 6);
				var fold  = pc[23];
				// syn3  amp function generator
				var aAtk = pl[24].linexp(0, 1, 0.0008, 8);
				var aAcv = pl[25].linlin(0, 1, 8, -8);
				var aHold = pl[26];
				var aRel = pl[27].linexp(0, 1, 0.004, 12);
				var aRcv = pl[28].linlin(0, 1, 8, -8);
				var aLoop = pl[29].round.clip(0, 1);
				var velAmp = pc[30];
				var spread = (pc[31] * 2) - 1;
				// syn4  mod function generator
				var mAtk = pl[32].linexp(0, 1, 0.0008, 8);
				var mAcv = pl[33].linlin(0, 1, 8, -8);
				var mHold = pl[34];
				var mRel = pl[35].linexp(0, 1, 0.004, 12);
				var mRcv = pl[36].linlin(0, 1, 8, -8);
				var mDest = pl[37].round.clip(0, 5);
				var mDep  = (pc[38] * 2) - 1;
				var mLoop = pl[39].round.clip(0, 1);
				// filter
				var cut   = pc[41].linexp(0, 1, 30, 16000);
				var res   = pc[42];
				var fEnvA = (pc[43] * 2) - 1;
				var fAtk  = pl[44].linexp(0, 1, 0.0008, 4);
				var fDec  = pl[45].linexp(0, 1, 0.005, 8);
				var ktrk  = pc[46];
				var fDrv  = pc[47];

				var a4 = Engine_Tahned.algo4(algo);
				var c43 = a4[0], c42 = a4[1], c32 = a4[2];
				var c41 = a4[3], c31 = a4[4], c21 = a4[5];
				var o4 = a4[6], o3 = a4[7], o2 = a4[8], o1 = a4[9];
				// one-hot mask for the mod-EG destination
				var msk = (0..5).collect { |i|
					Select.kr(mDest, Array.fill(6, { |j| (i == j).binaryValue })) };
				var aGt = (gate * (1 - aLoop)) + (aLoop * gate * Impulse.kr(1 / (aAtk + aRel + 0.002)));
				var mGt = (gate * (1 - mLoop)) + (mLoop * gate * Impulse.kr(1 / (mAtk + mRel + 0.002)));

				var ampEg = EnvGen.ar(
					Env([0, 1, aHold, 0], [aAtk, 0.001, aRel], [aAcv, 0, aRcv], releaseNode: 2),
					aGt, doneAction: 2 * (1 - aLoop));
				var modEg = EnvGen.ar(
					Env([0, 1, mHold, 0], [mAtk, 0.001, mRel], [mAcv, 0, mRcv], releaseNode: 2),
					mGt);
				var me = modEg * mDep;
				var f = hz * (2 ** ((fine + (me * 12 * msk[1])) / 12));
				var idx = (index * (1 + (me * 2 * msk[0]))).max(0);
				var fld = (fold + (me * msk[2])).clip(0, 1);
				var fbA = (fbk + (me * msk[4])).clip(0, 1);
				var l4m = (l4 + (me * msk[5])).clip(0, 1);

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
					cut * (2 ** ((fEnv * fEnvA * 5) + ((me * 5) * msk[3])))
						* (2 ** ((hz.cpsmidi - 60) / 12 * ktrk)),
					res) / (1 + (fDrv * 2));

				FreeSelf.kr(aLoop * TDelay.kr(1 - gate, aRel + 0.05));
				sig = sig * ampEg * (1 - velAmp + (velAmp * vel)) * 0.28;
				// stolen voices fade out here and free themselves, whatever the
				// amp envelope's own release or loop setting is doing
				sig = sig * EnvGen.ar(Env([1, 0], [0.015]), t_choke, doneAction: 2);
				Out.ar(out, Pan2.ar(sig, spread));
			}).add;
			// ============================================================= AMB
			// persistent FM drone.  six detuned partials, plus eight trigger
			// lanes the sequencer uses to cut rhythm into the texture.
			SynthDef(("tahned_amb_" ++ ft).asSymbol, { |bus = 0, mbus = 0, out = 0, gate = 1, note = 36,
				v0 = 0, v1 = 0, v2 = 0, v3 = 0, v4 = 0, v5 = 0, v6 = 0, v7 = 0,
				t_l0 = 0, t_l1 = 0, t_l2 = 0, t_l3 = 0, t_l4 = 0, t_l5 = 0, t_l6 = 0, t_l7 = 0|

				var p = (In.kr(bus, nCh) + In.kr(mbus, nCh)).lag(0.05);
				// syn1 spectrum
				var root  = p[8].linlin(0, 1, -24, 24);
				var harm  = p[9];
				var tilt  = (p[10] * 2) - 1;
				var index = p[11].linlin(0, 1, 0, 4);
				var sprd  = p[12];
				var drift = p[13];
				var nVoi  = p[14].linlin(0, 1, 1, 6);
				var fold  = p[15];
				// syn2 motion
				var mRate = p[16].linexp(0, 1, 0.008, 6);
				var mDep  = p[17];
				var chaos = p[18];
				var shim  = p[19];
				var shInt = Select.kr(p[20].round.clip(0, 3), [2, 3, 4, 6]);
				var glide = p[21].linexp(0, 1, 0.002, 8);
				var width = p[22];
				var subL  = p[23];
				// syn3 grain / lanes
				var bDec  = p[24].linexp(0, 1, 0.005, 1.5);
				var bPit  = p[25].linlin(0, 1, 0, 36);
				var bIdx  = p[26].linlin(0, 1, 0, 8);
				var bLvl  = p[27];
				var stutT = p[28].linexp(0, 1, 0.01, 0.4);
				var gDep  = p[29];
				var swAmt = (p[30] * 2) - 1;
				var swlT  = p[31].linexp(0, 1, 0.02, 6);
				// syn4 envelope
				var eAtk = p[32].linexp(0, 1, 0.01, 20);
				var eAcv = p[33].linlin(0, 1, 8, -8);
				var eHold = p[34];
				var eRel = p[35].linexp(0, 1, 0.05, 20);
				var eRcv = p[36].linlin(0, 1, 8, -8);
				var shRng = p[37].linlin(0, 1, 0, 24);
				var aMod = p[38];
				// filter
				var cut  = p[41].linexp(0, 1, 30, 16000);
				var res  = p[42];
				var fEnA = (p[43] * 2) - 1;
				var ktrk = p[46];
				var fDrv = p[47];

				var shift = Lag.kr(Latch.kr((v3 * 2 - 1) * shRng, t_l3), glide);
				var f0 = Lag.kr((note + root + shift).midicps, glide);

				var motion = LFNoise2.kr(mRate ! 6) * mDep;
				var jitter = LFNoise1.kr((mRate * 4) ! 6) * chaos;
				var parts, sig, blip, sub, env, fEnv, gateDip, stut, swell, shimEnv, foldEnv;

				parts = (0..5).collect { |i|
					var ord = i + 1;
					var ratio = (ord ** (1 + (harm * 0.6)))
						* (1 + (sprd * i * 0.031))
						* (1 + (drift * motion[i] * 0.02));
					var mratio = ratio * (1 + (harm * 2) + (jitter[i] * 0.5));
					var amp = (1 / (ord ** (1.1 - tilt)))
						* (ord <= nVoi.round).max(0)
						* (1 + (motion[i] * 0.4));
					var m = Engine_Tahned.op(f0 * mratio, 0, 0);
					Engine_Tahned.op(f0 * ratio,
						m * (index + (jitter[i] * 2)).max(0) * 0.2, 0) * amp;
				};
				sig = Mix(parts) * 0.4;

				// upper-octave sparkle -- lane 5 bursts it
				shimEnv = (shim + (EnvGen.ar(Env.perc(0.01, 1.2), t_l5) * v5)).clip(0, 1);
				sig = sig + (Engine_Tahned.op(f0 * shInt, 0, 0) * shimEnv * 0.25);
				sub = Engine_Tahned.op(f0 * 0.5, 0, 0) * subL * 0.5;

				// lane 0  blip: a short FM ping riding on the drone's root
				blip = Engine_Tahned.op(f0 * (2 ** (bPit / 12)),
						Engine_Tahned.op(f0 * (2 ** (bPit / 12)) * 2, 0, 0)
							* EnvGen.ar(Env.perc(0.001, bDec * 0.6), t_l0) * bIdx * 0.2, 0)
					* EnvGen.ar(Env.perc(0.001, bDec, 1, -6), t_l0) * bLvl * v0;

				// lane 7  wavefold accent
				foldEnv = (fold + (EnvGen.ar(Env.perc(0.005, 0.6), t_l7) * v7)).clip(0, 1);
				sig = Fold.ar((sig + sub) * (1 + (foldEnv * 8)), -1, 1)
					* (1 / (1 + (foldEnv * 2.5)));

				// lane 1  gate chop,  lane 6  stutter,  lane 2  swell
				gateDip = 1 - (EnvGen.ar(Env([1, 1, 0], [stutT, 0.004], [0, 2]), t_l1) * gDep * v1);
				stut = 1 - (EnvGen.ar(Env([1, 0], [stutT * 2], [-2]), t_l6)
					* (LFPulse.ar(1 / (stutT * 0.25), 0, 0.5) * v6));
				swell = 1 + (EnvGen.ar(Env([0, 1, 0], [swlT, swlT * 1.5], [4, -4]), t_l2) * v2 * 2);

				sig = sig * gateDip * stut * swell;

				// lane 4  filter accent
				fEnv = EnvGen.ar(Env([0, 1, 0], [0.005, 0.8], [2, -4]), t_l4) * v4;
				sig = Engine_Tahned.flt(ft, sig * (1 + (fDrv * 4)),
					cut * (2 ** (((fEnv * swAmt) + (LFNoise2.kr(mRate) * mDep * fEnA)) * 4))
						* (2 ** ((note - 36) / 12 * ktrk)),
					res) / (1 + (fDrv * 2));

				sig = sig + blip;

				env = EnvGen.ar(Env([0, 1, eHold.max(0.02), 0], [eAtk, 0.01, eRel],
					[eAcv, 0, eRcv], releaseNode: 2), gate, doneAction: 2);
				sig = sig * env * (1 - (aMod * 0.5 * (1 - LFNoise2.kr(mRate).range(0, 1))));

				Out.ar(out, Pan2.ar(sig, 0, 1 - (width * 0.3)) * 0.8
					+ Pan2.ar(DelayC.ar(sig, 0.04, 0.017 * width), 0.9 * width, width * 0.3));
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
		// per track: drive -> bit/rate reduction -> tape wow -> saturation
		//            -> compression -> width/pan/level -> out + three sends
		SynthDef(\tahned_strip, { |bus = 0, mbus = 0, in = 0, out = 0, cho = 0, dly = 0, rev = 0|
			var p = (In.kr(bus, nCh) + In.kr(mbus, nCh)).lag(0.02);
			var lvl  = p[0], pan = (p[1] * 2) - 1, drv = p[2];
			var sCho = p[3], sDly = p[4], sRev = p[5], width = p[6];
			var bits = p[48].linlin(0, 1, 16, 2);
			var srate = p[49].linexp(0, 1, 48000, 700);
			var wowD = p[50], wowR = p[51].linexp(0, 1, 0.12, 8);
			var sat  = p[52];
			var cAmt = p[53], cAtk = p[54].linexp(0, 1, 0.0004, 0.12), cMix = p[55];
			var sig = In.ar(in, 2);
			var dry, q, wow, comp, m, sd;

			sig = ((sig * (1 + (drv * 12))).tanh) / (1 + (drv * 2.2));

			// bit + rate reduction, blended so the ends of the range are clean
			q = 0.5 ** (bits - 1);
			dry = sig;
			sig = Latch.ar(sig, Impulse.ar(srate));
			sig = (sig / q).round * q;
			sig = SelectX.ar(((16 - bits) / 14).max((48000 - srate) / 47300).clip(0, 1),
				[dry, sig]);

			// tape wow + flutter
			wow = (SinOsc.kr(wowR, [0, 0.3]) * 0.7) + (LFNoise2.kr(wowR * 7) * 0.3);
			sig = DelayC.ar(sig, 0.05, (0.012 + (wow * wowD * 0.011)).clip(0.0002, 0.045));
			sig = ((sig * (1 + (sat * 5))).tanh) / (1 + (sat * 1.8));
			sig = LPF.ar(sig, 18000 - (sat * 10000));

			comp = Compander.ar(sig, sig, 0.22, 1, 0.28, cAtk, 0.18) * (1 + (cAmt * 2.2));
			sig = SelectX.ar(cMix, [sig, comp]);

			// mid/side width
			m = (sig[0] + sig[1]) * 0.5;
			sd = (sig[0] - sig[1]) * 0.5 * (width * 2);
			sig = [m + sd, m - sd];

			sig = Balance2.ar(sig[0], sig[1], pan, lvl.squared * 1.4);
			sig = Limiter.ar(sig, 0.95, 0.005);

			Out.ar(out, sig);
			Out.ar(cho, sig * sCho.squared);
			Out.ar(dly, sig * sDly.squared);
			Out.ar(rev, sig * sRev.squared);
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
		drone[t] = nil;
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

	startDrone { arg t;
		drone[t] = Synth(this.defFor(t, "tahned_amb"), [
			\bus, pBus[t].index, \mbus, mBus[t].index, \out, tBus[t].index
		], vGroup[t]);
	}

	setMachine { arg t, m;
		this.freeTrack(t);
		machine[t] = m.clip(0, 2);
		if(machine[t] == 2) { this.startDrone(t) };
	}

	// ------------------------------------------------------------ commands
	addCommands {

		this.addCommand(\machine, "ii", { |msg|
			this.setMachine(msg[1].asInteger.clip(0, nTracks - 1), msg[2].asInteger);
		});

		// filter type picks a compiled synthdef variant rather than a runtime branch
		this.addCommand(\ftype, "ii", { |msg|
			var t = msg[1].asInteger.clip(0, nTracks - 1);
			var f = msg[2].asInteger.clip(0, 3);
			if(ftype[t] != f) {
				ftype[t] = f;
				if(machine[t] == 2) { this.freeTrack(t); this.startDrone(t) };
			};
		});

		// one parameter channel on one track
		this.addCommand(\pset, "iif", { |msg|
			pBus[msg[1].asInteger.clip(0, nTracks - 1)]
				.setAt(msg[2].asInteger.clip(0, nCh - 1), msg[3]);
		});

		this.addCommand(\trig, "iff", { |msg|
			var t = msg[1].asInteger.clip(0, nTracks - 1);
			Synth(this.defFor(t, "tahned_perc"), [
				\bus, pBus[t].index, \mbus, mBus[t].index, \out, tBus[t].index,
				\vel, msg[2], \note, msg[3], \nzbuf, nzBuf.bufnum
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
				\bus, pBus[t].index, \mbus, mBus[t].index, \out, tBus[t].index,
				\hz, msg[3], \vel, msg[4]
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

		// amb: fire one of the eight rhythm lanes into the drone
		this.addCommand(\ambTrig, "iif", { |msg|
			var t = msg[1].asInteger.clip(0, nTracks - 1);
			var l = msg[2].asInteger.clip(0, 7);
			drone[t] !? { |d|
				d.set(("v" ++ l).asSymbol, msg[3], ("t_l" ++ l).asSymbol, 1);
			};
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
			nTracks.do { |t|
				this.freeTrack(t);
				if(machine[t] == 2) { this.startDrone(t) };
			};
		});
	}

	free {
		clearS.do(_.free);
		lfoS.do(_.free);
		strip.do(_.free);
		fx.do(_.free);
		vGroup.do(_.free);
		[voiceGroup, ctlGroup, sGroup, fxGroup, outGroup].do(_.free);
		pBus.do(_.free);
		mBus.do(_.free);
		tBus.do(_.free);
		[choBus, dlyBus, revBus].do(_.free);
		nzBuf.free;
	}
}
