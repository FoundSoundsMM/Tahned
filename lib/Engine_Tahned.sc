// Engine_Tahned
// 6 polytonal FM voices. 4 operators each, arranged as a modulation matrix:
// the feed-forward cascade (4->3->2->1) is zero-delay, the feedback half of the
// matrix comes back through LocalIn with one block of delay.
//
// The player never sets matrix cells directly. Six spectral macros run a recipe
// here at control rate; Lua adds sparse manual offsets on top.

Engine_Tahned : CroneEngine {
	classvar <nVoices = 6;

	var <voices, <master, <srcGroup, <fxGroup;
	var <mixBus, <vBus;
	var <amps;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var s = context.server;

		srcGroup = Group.new(context.xg);
		fxGroup  = Group.after(srcGroup);

		mixBus = Bus.audio(s, 2);
		// one mono bus per voice, for four-quadrant / cross modulation
		vBus = Array.fill(nVoices, { Bus.audio(s, 1) });

		amps = Array.fill(nVoices, 0.0);

		SynthDef(\tahned_voice, {
			arg out = 0, vbus = 0, xbus = 0,
			gate = 0, hz = 110, amp = 0.0, lag = 0.01,
			// operator ratios 2..4 come from the tuning lattice; op1 is the carrier at 1
			r2 = 1, r3 = 2, r4 = 3,
			// spectral macros
			mOdd = 0.3, mEven = 0.3, mPart = 0.3, mTilt = 0.5, mFb = 0.0, mSkew = 0.0,
			atk = 0.004, rel = 0.5, crv = -4,
			// transient element
			trAmt = 0, trDec = 0.06, trCol = 0.5,
			// cross modulation
			xdepth = 0, xmode = 0,
			pan = 0, drive = 1, gain = 1;

			var f0, ratios, skewK, freqs, idx, tiltw, dsc;
			var m21, m31, m41, m32, m43, m11;
			var fb, o1, o2, o3, o4, ops, envs, aenv, sig, x, tr, trEnv;
			// manual matrix offsets (row-major, [from][to]) and per-op output levels
			var man = \man.kr(Array.fill(16, 0));
			var lev = \lev.kr([1, 0, 0, 0]);
			var trW = \trW.kr([0, 1, 0, 0]);

			f0 = Lag.kr(hz, lag);

			// SKEW pulls the operators off the lattice. 0 = fused, 1 = beating clusters.
			skewK = [0, 0.0113, -0.0171, 0.0237];
			ratios = [1, r2, r3, r4] * (1 + (mSkew * skewK));
			freqs = f0 * ratios;

			// PARTIALS is the modulation index: FM bandwidth ~ 2(I+1)fm
			idx = (mPart.pow(1.6)) * 9;

			// TILT weights the index by operator ratio, so it redistributes energy
			// rather than only EQ-ing the result. 0.5 is neutral.
			tiltw = ratios.collect({ |r| r.pow((mTilt * 2) - 1).clip(0.05, 20) });

			// ...and shortens or lengthens the decay of the high operators with it
			dsc = ratios.collect({ |r| r.pow(-0.6 + (mTilt * 1.2)).clip(0.15, 1.6) });

			// --- the recipe --------------------------------------------------
			// ratio 1 against the carrier gives the whole harmonic series (EVEN),
			// ratio 2 gives odd harmonics only (ODD), op4 supplies combination tones.
			m21 = (idx * mEven * tiltw[1])            + man[4];
			m31 = (idx * mOdd  * tiltw[2])            + man[8];
			m41 = (idx * mOdd * mEven * 0.6 * tiltw[3]) + man[12];
			m32 = (idx * 0.35 * mPart)                + man[9];
			m43 = (idx * 0.25 * mPart)                + man[13];
			m11 = (mFb * 3)                           + man[0];

			envs = 4.collect({ |i|
				EnvGen.ar(Env.perc(atk, (rel * dsc[i]).max(0.005), 1, crv), gate)
			});

			// transient element: filtered noise burst injected into the phase of
			// whichever operators trW selects. this is where the drums come from.
			trEnv = EnvGen.ar(Env.perc(0.0004, trDec.max(0.002), 1, -8), gate);
			tr = LPF.ar(WhiteNoise.ar, trCol.linexp(0, 1, 180, 12000)) * trEnv * trAmt * 8;

			// cross modulation source, one block late so cycles are legal
			x = InFeedback.ar(xbus, 1);

			// feedback half of the matrix
			fb = LocalIn.ar(4);

			o4 = SinOsc.ar(freqs[3],
				(fb[3] * m11 * 0) + (fb[0] * man[3]) + (fb[1] * man[7]) + (fb[2] * man[11]) + (fb[3] * man[15])
				+ (tr * trW[3])
			) * envs[3];

			o3 = SinOsc.ar(freqs[2],
				(o4 * m43) + (fb[0] * man[2]) + (fb[1] * man[6]) + (fb[2] * man[10])
				+ (tr * trW[2])
			) * envs[2];

			o2 = SinOsc.ar(freqs[1],
				(o4 * man[14]) + (o3 * m32) + (fb[0] * man[1]) + (fb[1] * man[5])
				+ (tr * trW[1])
			) * envs[1];

			o1 = SinOsc.ar(freqs[0],
				(o4 * m41) + (o3 * m31) + (o2 * m21) + (fb[0] * m11)
				+ (tr * trW[0])
				+ (x * xdepth * (1 - xmode) * 6)
			) * envs[0];

			ops = [o1, o2, o3, o4];
			LocalOut.ar(ops);

			sig = Mix(ops * lev);

			// ring modulation: the four-quadrant multiply. between two voices that
			// are lattice-related this generates lattice-valid new pitches.
			sig = sig * (1 - (xdepth * xmode) + (xdepth * xmode * x * 2));

			// TILT, second stage
			sig = BLowShelf.ar(sig, 700, 1, (0.5 - mTilt) * 16);
			sig = BHiShelf.ar(sig, 2600, 1, (mTilt - 0.5) * 16);

			aenv = EnvGen.ar(Env.perc(atk, rel, 1, crv), gate);
			sig = sig * aenv * amp * gain;

			sig = (sig * drive).tanh / drive.max(1).sqrt;
			sig = LeakDC.ar(sig);

			Out.ar(vbus, sig);
			Out.ar(out, Pan2.ar(sig, pan));
		}).add;

		SynthDef(\tahned_master, {
			arg in = 0, out = 0, gain = 1;
			var sig = In.ar(in, 2) * gain;
			sig = Limiter.ar(sig, 0.96, 0.005);
			SendReply.kr(Impulse.kr(15), '/tahned_level', [Amplitude.kr(Mix(sig) * 0.5)]);
			Out.ar(out, sig);
		}).add;

		context.server.sync;

		voices = Array.fill(nVoices, { |i|
			Synth.new(\tahned_voice, [
				\out, mixBus.index,
				\vbus, vBus[i].index,
				\xbus, vBus[(i + 1) % nVoices].index
			], srcGroup);
		});

		master = Synth.new(\tahned_master, [
			\in, mixBus.index, \out, context.out_b.index
		], fxGroup);

		this.addPoll(\level, { amps[0] }, periodic: true);

		OSCFunc({ |msg|
			amps[0] = msg[3];
		}, '/tahned_level', context.server.addr);

		// --- commands ----------------------------------------------------

		// gate a voice on at a frequency. amp 0 releases.
		this.addCommand(\vgate, "iff", { |msg|
			var v = msg[1].asInteger.clip(0, nVoices - 1);
			if (msg[3] > 0) {
				voices[v].set(\hz, msg[2], \amp, msg[3], \gate, 1);
			} {
				voices[v].set(\gate, 0);
			};
		});

		this.addCommand(\voff, "i", { |msg|
			voices[msg[1].asInteger.clip(0, nVoices - 1)].set(\gate, 0);
		});

		// retune without retriggering
		this.addCommand(\vhz, "if", { |msg|
			voices[msg[1].asInteger.clip(0, nVoices - 1)].set(\hz, msg[2]);
		});

		// one spectral macro: 0 odd, 1 even, 2 partials, 3 tilt, 4 feedback, 5 skew
		this.addCommand(\vmacro, "iif", { |msg|
			var keys = [\mOdd, \mEven, \mPart, \mTilt, \mFb, \mSkew];
			var v = msg[1].asInteger.clip(0, nVoices - 1);
			var k = msg[2].asInteger.clip(0, 5);
			voices[v].set(keys[k], msg[3]);
		});

		// all six macros at once, for morph and gesture updates
		this.addCommand(\vmacros, "iffffff", { |msg|
			var v = msg[1].asInteger.clip(0, nVoices - 1);
			voices[v].set(
				\mOdd, msg[2], \mEven, msg[3], \mPart, msg[4],
				\mTilt, msg[5], \mFb, msg[6], \mSkew, msg[7]
			);
		});

		// operator ratios out of the tuning lattice
		this.addCommand(\vratios, "ifff", { |msg|
			var v = msg[1].asInteger.clip(0, nVoices - 1);
			voices[v].set(\r2, msg[2], \r3, msg[3], \r4, msg[4]);
		});

		this.addCommand(\vmatrix, "iffffffffffffffff", { |msg|
			var v = msg[1].asInteger.clip(0, nVoices - 1);
			voices[v].setn(\man, msg[2..17].collect(_.asFloat));
		});

		this.addCommand(\vlevels, "iffff", { |msg|
			var v = msg[1].asInteger.clip(0, nVoices - 1);
			voices[v].setn(\lev, msg[2..5].collect(_.asFloat));
		});

		this.addCommand(\venv, "ifff", { |msg|
			var v = msg[1].asInteger.clip(0, nVoices - 1);
			voices[v].set(\atk, msg[2], \rel, msg[3], \crv, msg[4]);
		});

		// transient element: amount, decay, colour, and the four injection weights
		this.addCommand(\vtr, "ifffffff", { |msg|
			var v = msg[1].asInteger.clip(0, nVoices - 1);
			voices[v].set(\trAmt, msg[2], \trDec, msg[3], \trCol, msg[4]);
			voices[v].setn(\trW, msg[5..8].collect(_.asFloat));
		});

		// cross matrix: which voice to read, how deep, 0 = FM / 1 = ring
		this.addCommand(\vxmod, "iiff", { |msg|
			var v = msg[1].asInteger.clip(0, nVoices - 1);
			var src = msg[2].asInteger.clip(0, nVoices - 1);
			voices[v].set(\xbus, vBus[src].index, \xdepth, msg[3], \xmode, msg[4]);
		});

		this.addCommand(\vpan, "if", { |msg|
			voices[msg[1].asInteger.clip(0, nVoices - 1)].set(\pan, msg[2]);
		});

		this.addCommand(\vgain, "if", { |msg|
			voices[msg[1].asInteger.clip(0, nVoices - 1)].set(\gain, msg[2]);
		});

		this.addCommand(\vdrive, "if", { |msg|
			voices[msg[1].asInteger.clip(0, nVoices - 1)].set(\drive, msg[2]);
		});

		this.addCommand(\vlag, "if", { |msg|
			voices[msg[1].asInteger.clip(0, nVoices - 1)].set(\lag, msg[2]);
		});

		this.addCommand(\mgain, "f", { |msg| master.set(\gain, msg[1]); });

		this.addCommand(\panic, "", { |msg|
			voices.do({ |v| v.set(\gate, 0) });
		});
	}

	free {
		voices.do(_.free);
		master.free;
		srcGroup.free;
		fxGroup.free;
		mixBus.free;
		vBus.do(_.free);
	}
}
