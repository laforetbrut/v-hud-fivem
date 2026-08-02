/*
    html/js/sound.js

    The stomach growl, synthesised rather than streamed.

    A growl is a low rumble with an irregular gurgle riding on it, which is a handful of
    oscillators and a noise burst - so it is generated here instead of shipping an audio file.
    That buys three things worth having:

      * no asset to stream, and nothing to go missing from a copied resource folder
      * an exact duration, capped where the config says, rather than whatever length a file is
      * it varies every time, so hearing it twice in a row does not sound like a bug

    Web Audio is only started on the first request, never at load: an AudioContext created
    before anything wants to make a sound is an AudioContext the browser may suspend, and in
    CEF it is one more thing to go wrong on a page that mostly draws rectangles.
*/

const Sound = (() => {

    let ctx = null;
    let master = null;
    let stopAt = 0;

    /** The context, created on first use. Null when Web Audio is not available at all, which
     *  is a perfectly survivable outcome - the caller just gets silence. */
    function context() {
        if (ctx) return ctx;

        const Ctor = window.AudioContext || window.webkitAudioContext;
        if (!Ctor) return null;

        try {
            ctx = new Ctor();
            master = ctx.createGain();
            master.gain.value = 0;
            master.connect(ctx.destination);
        } catch (err) {
            ctx = null;
        }

        return ctx;
    }

    /** CEF can hand back a suspended context. Resuming is a promise nobody waits on: if it
     *  succeeds the sound is already scheduled and plays, if it does not there is silence. */
    function wake() {
        if (ctx && ctx.state === 'suspended' && ctx.resume) {
            try { ctx.resume(); } catch (err) { /* nothing to do about it */ }
        }
    }

    /** A short burst of filtered noise: the gurgle on top of the rumble. */
    function gurgle(at, length, volume) {
        const frames = Math.max(1, Math.floor(ctx.sampleRate * length));
        const buffer = ctx.createBuffer(1, frames, ctx.sampleRate);
        const data = buffer.getChannelData(0);

        // Brown-ish noise: integrated white noise, which is weighted to the low end and sounds
        // like movement rather than hiss.
        let last = 0;
        for (let i = 0; i < frames; i += 1) {
            last = (last + 0.09 * (Math.random() * 2 - 1)) / 1.02;
            data[i] = last * 3.2;
        }

        const source = ctx.createBufferSource();
        source.buffer = buffer;

        const band = ctx.createBiquadFilter();
        band.type = 'bandpass';
        band.frequency.value = 140 + Math.random() * 160;
        band.Q.value = 1.4;

        const gain = ctx.createGain();
        gain.gain.setValueAtTime(0, at);
        gain.gain.linearRampToValueAtTime(volume, at + length * 0.25);
        gain.gain.linearRampToValueAtTime(0, at + length);

        source.connect(band);
        band.connect(gain);
        gain.connect(master);
        source.start(at);
        source.stop(at + length);
    }

    /*
        The rumble.

        A sine at 60Hz is a hum, not a stomach - which is what the first attempt sounded like.
        Three things make it read as a gut:

          * a SAWTOOTH, not a sine. The harmonics are what a resonant filter has to bite on;
            a pure tone has nothing to sweep through and stays a drone.
          * a resonant lowpass that sweeps up and back down across the burst. That sweep is the
            "rolling" quality, and it is doing most of the work here.
          * amplitude modulation at a few hertz, detuned per burst, so the sound churns instead
            of holding steady.

        The pitch is also lower than before, 30-46Hz rather than 52-78: a stomach is felt more
        than heard, and the higher it sits the more it sounds like machinery.
    */
    function rumble(at, length, volume) {
        const osc = ctx.createOscillator();
        osc.type = 'sawtooth';

        const base = 30 + Math.random() * 16;
        osc.frequency.setValueAtTime(base, at);
        const steps = 3 + Math.floor(Math.random() * 3);
        for (let i = 1; i <= steps; i += 1) {
            osc.frequency.linearRampToValueAtTime(
                base * (0.7 + Math.random() * 0.7),
                at + (length * i) / steps,
            );
        }

        // The sweep. Up into the low mids and back down, which is the churn.
        const low = ctx.createBiquadFilter();
        low.type = 'lowpass';
        low.Q.value = 6 + Math.random() * 4;
        low.frequency.setValueAtTime(90, at);
        low.frequency.exponentialRampToValueAtTime(280 + Math.random() * 220, at + length * 0.45);
        low.frequency.exponentialRampToValueAtTime(80, at + length);

        const gain = ctx.createGain();
        gain.gain.setValueAtTime(0, at);
        gain.gain.linearRampToValueAtTime(volume, at + length * 0.22);
        gain.gain.setValueAtTime(volume, at + length * 0.62);
        gain.gain.linearRampToValueAtTime(0, at + length);

        // The churn: a slow tremolo on top of the envelope.
        const lfo = ctx.createOscillator();
        lfo.type = 'sine';
        lfo.frequency.value = 3.2 + Math.random() * 4.5;
        const lfoDepth = ctx.createGain();
        lfoDepth.gain.value = volume * 0.55;
        lfo.connect(lfoDepth);
        lfoDepth.connect(gain.gain);
        lfo.start(at);
        lfo.stop(at + length);

        osc.connect(low);
        low.connect(gain);
        gain.connect(master);
        osc.start(at);
        osc.stop(at + length);
    }

    /** A liquid "bloop": a fast downward pitch sweep. Two or three of these per burst are what
     *  stop the sound being a machine and make it a gut. */
    function bloop(at, volume) {
        const osc = ctx.createOscillator();
        osc.type = 'sine';

        const from = 150 + Math.random() * 190;
        osc.frequency.setValueAtTime(from, at);
        osc.frequency.exponentialRampToValueAtTime(45 + Math.random() * 25, at + 0.09);

        const gain = ctx.createGain();
        gain.gain.setValueAtTime(0, at);
        gain.gain.linearRampToValueAtTime(volume, at + 0.012);
        gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.13);

        osc.connect(gain);
        gain.connect(master);
        osc.start(at);
        osc.stop(at + 0.16);
    }

    /**
     * Play a stomach growl.
     *
     * @param {number} seconds  total length, hard-capped by the caller's config
     * @param {number} volume   0-1
     */
    function growl(seconds, volume) {
        if (!context()) return;
        wake();

        const length = U.clamp(Number(seconds) || 3, 0.4, 10);
        // Test the ARGUMENT for undefined, not its coercion. `Number(undefined)` is NaN, never
        // undefined, so the default branch was unreachable and NaN fell through to U.clamp,
        // which floors it at 0 - a call with no volume played in complete silence.
        const level = U.clamp(volume === undefined ? 0.5 : volume, 0, 1);
        const now = ctx.currentTime;

        // Overlapping requests do not stack into a drone: a growl already playing is left to
        // finish and the new one is dropped.
        if (now < stopAt) return;
        stopAt = now + length;

        master.gain.cancelScheduledValues(now);
        master.gain.setValueAtTime(level, now);
        // The hard stop. Whatever is still scheduled inside the burst, the master is closed at
        // the cap, so the sound cannot outlast what the config allows.
        master.gain.setValueAtTime(level, now + length - 0.12);
        master.gain.linearRampToValueAtTime(0, now + length);

        // Two or three bursts spread across the window, each with its own rumble and gurgle.
        const bursts = length < 1.6 ? 1 : (length < 3.2 ? 2 : 3);
        for (let i = 0; i < bursts; i += 1) {
            const at = now + (length * i) / bursts + Math.random() * 0.12;
            const span = Math.min((length / bursts) * 0.85, length - (at - now) - 0.05);
            if (span <= 0.05) continue;

            rumble(at, span, 0.8);
            gurgle(at + span * 0.2, Math.min(span * 0.6, 0.5), 0.35);

            // One or two liquid blips inside the burst, at random offsets.
            const blips = 1 + Math.floor(Math.random() * 2);
            for (let b = 0; b < blips; b += 1) {
                bloop(at + span * (0.15 + Math.random() * 0.6), 0.32);
            }
        }
    }

    return { growl };

})();
