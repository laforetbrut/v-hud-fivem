/*
    js/speedo.js

    Ten speedometers, all of them modelled on a real instrument cluster rather than on an
    abstract shape. Every dial has numbered graduations, a needle that sweeps a real arc, a
    redline where an engine has one, and a fuel gauge marked E to F.

    One builder does the dials. `dial()` takes a range, a sweep and a tick spacing and returns
    the SVG plus a setter; every face is then a few calls to it and a layout. That is what
    keeps ten realistic clusters to one file: the graduation maths is written once, and a face
    is a description of an instrument, not a pile of geometry.

    Faces, in menu order:
        minimal  classic  sport  digital  luxury  jdm  muscle  supercar  truck  retro
*/

const Speedo = (() => {

    const MAX_KMH = 260;             // the top of every speed scale
    const MAX_RPM = 9;               // thousands, the top of every rev scale
    const REDLINE_RPM = 7;           // where the red zone starts

    let root = null;
    let style = null;
    let refs = {};

    /* ------------------------------------------------------------------------------------
       The dial builder
       ------------------------------------------------------------------------------------ */

    /**
     * A round instrument.
     *
     *   cx, cy, r      centre and radius, in the face's own viewBox units
     *   from, to       needle sweep in degrees, 0 at twelve o'clock, clockwise. A real car
     *                  cluster sweeps about 250 degrees from lower-left to lower-right, so
     *                  -125 to 125 is the honest default.
     *   max            the value at `to`
     *   step           a minor tick every this many units
     *   labelEvery     a numbered major tick every this many units
     *   labelScale     divide the printed number by this (a tacho prints 1-9, not 1000-9000)
     *   redline        value the red zone starts at, or null
     *   needleClass    lets a face restyle its own needle
     *
     * Returns the SVG nodes and a `set(value)` that only touches the needle transform.
     */
    function dial(opts) {
        const {
            cx, cy, r, from = -125, to = 125, max, step, labelEvery,
            labelScale = 1, redline = null, needleClass = 'spd-needle',
            labelRadius = 0.72, tickClass = '', fontSize = 9,
        } = opts;

        const sweep = to - from;
        const angleFor = (value) => from + (U.clamp(value, 0, max) / max) * sweep;
        const parts = [];

        // The red zone goes down first so the graduations sit on top of it.
        if (redline !== null) {
            parts.push(U.svg('path', {
                class: 'spd-redline',
                d: U.arcPath(cx, cy, r * 0.92, angleFor(redline), to),
            }));
        }

        // The arc the ticks hang from - what makes an instrument read as an instrument.
        parts.push(U.svg('path', { class: 'spd-scale', d: U.arcPath(cx, cy, r, from, to) }));

        for (let value = 0; value <= max + 1e-9; value += step) {
            const angle = angleFor(value);
            const major = Math.abs(value % labelEvery) < 1e-9;
            const outer = U.polar(cx, cy, r, angle);
            const inner = U.polar(cx, cy, r - (major ? r * 0.16 : r * 0.09), angle);

            parts.push(U.svg('line', {
                class: `spd-tick${major ? ' spd-tick--major' : ''}${tickClass ? ' ' + tickClass : ''}`,
                x1: U.round(outer.x, 2), y1: U.round(outer.y, 2),
                x2: U.round(inner.x, 2), y2: U.round(inner.y, 2),
            }));

            if (major) {
                const at = U.polar(cx, cy, r * labelRadius, angle);
                parts.push(U.svg('text', {
                    class: 'spd-numeral',
                    x: U.round(at.x, 2), y: U.round(at.y + fontSize * 0.35, 2),
                    'text-anchor': 'middle',
                    'font-size': fontSize,
                    text: String(Math.round(value / labelScale)),
                }));
            }
        }

        const needle = U.svg('line', {
            class: needleClass,
            x1: cx, y1: cy, x2: cx, y2: cy - r * 0.86,
            style: `transform-origin: ${cx}px ${cy}px;`,
        });
        parts.push(needle);
        parts.push(U.svg('circle', { class: 'spd-hub', cx, cy, r: r * 0.09 }));

        return {
            parts,
            needle,
            set(value) {
                needle.style.transform = `rotate(${U.round(angleFor(value), 2)}deg)`;
            },
        };
    }

    /** A small strip gauge with lettered ends, for fuel (E-F) and temperature (C-H). */
    function stripGauge(labelLeft, labelRight, modifier) {
        const fill = U.make('i', { class: 'spd-fill' });
        const node = U.make('div', { class: `spd-strip spd-strip--${modifier}` }, [
            U.make('span', { class: 'spd-strip__cap', text: labelLeft }),
            U.make('div', { class: 'spd-track spd-strip__track' }, [fill]),
            U.make('span', { class: 'spd-strip__cap', text: labelRight }),
        ]);
        return { node, fill };
    }

    /** A quarter-arc fuel gauge tucked inside a dial, the way a real cluster does it. */
    function arcGauge(cx, cy, r, from, to, modifier) {
        const track = U.svg('path', { class: 'spd-arc-track', d: U.arcPath(cx, cy, r, from, to) });
        const fill = U.svg('path', {
            class: `spd-arc-fill spd-arc--${modifier}`,
            d: U.arcPath(cx, cy, r, from, to),
        });
        return { parts: [track, fill], fill };
    }

    const CHIP_ICONS = {
        belt:    'M5 3h4l6 18h-4L5 3zM19 3h-4M19 3v18h-4',
        // The dashboard door warning: a car seen from above with both doors swung open.
        door:    'M12 4v16M12 4 6 7v10l6 3M12 4l6 3v10l-6 3M4 9 2 11l2 2M20 9l2 2-2 2',
        bonnet:  'M3 16h18M5 16V9l4-4h6l4 4v7M9 5V3h6v2',
        nitro:   'M12 2c3 4 5 6.5 5 10a5 5 0 0 1-10 0c0-3.5 2-6 5-10z',
        harness: 'M12 3v18M6 6l12 12M18 6L6 18',
        engine:  'M5 9h3l2-2h4l2 2h3v6h-3l-2 2h-4l-2-2H5V9z',
        lights:  'M9 18h6M10 21h4M12 3a6 6 0 0 0-4 10.5V16h8v-2.5A6 6 0 0 0 12 3z',
        cruise:  'M12 4a8 8 0 1 0 8 8M12 12l5-5',
    };

    function chip(name) {
        return U.make('div', { class: 'spd-chip', 'data-chip': name, hidden: 'hidden' }, [
            U.svg('svg', { viewBox: '0 0 24 24' }, [U.svg('path', { d: CHIP_ICONS[name] || '' })]),
        ]);
    }

    const digits = (cls) => U.make('span', { class: cls, text: '0' });
    const unit = () => U.make('span', { class: 'spd-unit', text: 'KM/H' });
    const gear = () => U.make('span', { class: 'spd-gear', text: 'N' });
    const range = () => U.make('span', { class: 'spd-range' });

    /**
     * The odometer window.
     *
     * On a real cluster this is a small recessed panel, not another glowing readout - it is
     * a number you look up, never one you watch. Same here: quiet type, its own frame, and
     * hidden entirely when nothing is tracking a mileage.
     */
    const odo = () => U.make('span', { class: 'spd-odo' });

    /* ------------------------------------------------------------------------------------
       The ten faces
       ------------------------------------------------------------------------------------ */

    const FACES = {

        /* 1. minimal
           A modern digital readout with a real graduated speed arc over it: the number is what
           you read, the arc is what tells you where you are on the scale. What a current
           electric car puts in front of the driver, and the face the glass theme uses. */
        minimal() {
            const value = digits('spd-value');
            const u = unit(), g = gear(), r = range(), o = odo();
            const speed = arcGauge(110, 74, 62, -78, 78, 'speed');
            const fuel = stripGauge('E', 'F', 'fuel');

            // Graduations along the speed arc, unnumbered but real: every 20 km/h.
            const ticks = [];
            for (let v = 0; v <= MAX_KMH; v += 20) {
                const angle = -78 + (v / MAX_KMH) * 156;
                const a = U.polar(110, 74, 66, angle);
                const b = U.polar(110, 74, v % 60 === 0 ? 57 : 61, angle);
                ticks.push(U.svg('line', {
                    class: `spd-tick${v % 60 === 0 ? ' spd-tick--major' : ''}`,
                    x1: a.x, y1: a.y, x2: b.x, y2: b.y,
                }));
            }

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'minimal' }, [
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 220 96' }, [...ticks, ...speed.parts]),
                    U.make('div', { class: 'spd-centre' }, [
                        U.make('div', { class: 'spd-readout' }, [value, u]),
                        U.make('div', { class: 'spd-subrow' }, [g, r]),
                    ]),
                    fuel.node, o,
                ]),
                value, unit: u, gear: g, range: r, odo: o,
                speedArc: speed.fill, fuelFill: fuel.fill,
            };
        },

        /* 2. classic
           A single round instrument with a chrome bezel and a cream face, numbered every
           20 km/h, with a fuel needle in a small window. A car from before there were screens. */
        classic() {
            const value = digits('spd-value');
            const g = gear(), u = unit(), o = odo();

            const speed = dial({
                cx: 84, cy: 84, r: 68, max: MAX_KMH, step: 10, labelEvery: 20,
                needleClass: 'spd-needle spd-needle--classic', fontSize: 9,
            });
            const fuel = arcGauge(84, 84, 34, 150, 210, 'fuel');

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'classic' }, [
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 168 168' }, [
                        U.svg('defs', {}, [
                            U.svg('linearGradient', { id: 'chromeGradient', x1: '0', y1: '0', x2: '0', y2: '1' }, [
                                U.svg('stop', { offset: '0%', 'stop-color': '#f6f6f4' }),
                                U.svg('stop', { offset: '42%', 'stop-color': '#8c8c88' }),
                                U.svg('stop', { offset: '58%', 'stop-color': '#dedad2' }),
                                U.svg('stop', { offset: '100%', 'stop-color': '#5f5f5c' }),
                            ]),
                        ]),
                        U.svg('circle', { class: 'spd-bezel', cx: 84, cy: 84, r: 80 }),
                        U.svg('circle', { class: 'spd-face', cx: 84, cy: 84, r: 74 }),
                        ...fuel.parts,
                        U.svg('text', { class: 'spd-facelabel', x: 84, y: 132, 'text-anchor': 'middle', text: 'km/h' }),
                        ...speed.parts,
                    ]),
                    U.make('div', { class: 'spd-centre' }, [
                        U.make('div', { class: 'spd-readout' }, [value, u]), g, o,
                    ]),
                ]),
                value, unit: u, gear: g, odo: o, speedDial: speed, fuelArc: fuel.fill,
            };
        },

        /* 3. sport
           Twin instruments: tachometer on the left with its redline, speedometer on the right,
           gear between them. The layout every sports car has used for forty years. */
        sport() {
            const value = digits('spd-value');
            const g = gear(), u = unit(), r = range(), o = odo();

            const tach = dial({
                cx: 74, cy: 78, r: 58, max: MAX_RPM, step: 0.5, labelEvery: 1,
                redline: REDLINE_RPM, needleClass: 'spd-needle spd-needle--rpm', fontSize: 9,
            });
            const speed = dial({
                cx: 206, cy: 78, r: 58, max: MAX_KMH, step: 10, labelEvery: 40, fontSize: 8,
            });
            const fuel = stripGauge('E', 'F', 'fuel');

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'sport' }, [
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 280 156' }, [
                        U.svg('circle', { class: 'spd-face', cx: 74, cy: 78, r: 64 }),
                        U.svg('circle', { class: 'spd-face', cx: 206, cy: 78, r: 64 }),
                        U.svg('text', { class: 'spd-facelabel', x: 74, y: 112, 'text-anchor': 'middle', text: 'x1000 rpm' }),
                        U.svg('text', { class: 'spd-facelabel', x: 206, y: 112, 'text-anchor': 'middle', text: 'km/h' }),
                        ...tach.parts, ...speed.parts,
                    ]),
                    U.make('div', { class: 'spd-centre spd-centre--between' }, [
                        g, U.make('div', { class: 'spd-readout' }, [value, u]),
                    ]),
                    U.make('div', { class: 'spd-foot' }, [fuel.node, o, r]),
                ]),
                value, unit: u, gear: g, range: r, odo: o,
                speedDial: speed, tachDial: tach, fuelFill: fuel.fill,
            };
        },

        /* 4. digital
           A current digital cluster: the speed as large numerals, a horizontal rev bar with the
           redline picked out, fuel and coolant strips underneath. */
        digital() {
            const value = digits('spd-value spd-value--xl');
            const u = unit(), g = gear(), r = range(), o = odo();

            const segments = [];
            const revbar = U.make('div', { class: 'spd-revbar' });
            const COUNT = 30;
            for (let i = 0; i < COUNT; i += 1) {
                const rpm = (i / (COUNT - 1)) * MAX_RPM;
                segments.push(U.make('i', {
                    class: 'spd-revbar__seg',
                    'data-zone': rpm >= REDLINE_RPM ? 'red' : (rpm >= REDLINE_RPM - 1.5 ? 'mid' : 'low'),
                }));
            }
            for (const seg of segments) revbar.appendChild(seg);

            const scale = U.make('div', { class: 'spd-revscale' });
            for (let k = 0; k <= MAX_RPM; k += 1) {
                scale.appendChild(U.make('span', { text: String(k) }));
            }

            const fuel = stripGauge('E', 'F', 'fuel');
            const temp = stripGauge('C', 'H', 'temp');

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'digital' }, [
                    revbar, scale,
                    U.make('div', { class: 'spd-main' }, [
                        U.make('div', { class: 'spd-readout' }, [value, u]),
                        U.make('div', { class: 'spd-side' }, [g, r, o]),
                    ]),
                    U.make('div', { class: 'spd-strips' }, [fuel.node, temp.node]),
                ]),
                value, unit: u, gear: g, range: r, odo: o,
                revSegments: segments, fuelFill: fuel.fill, tempFill: temp.fill,
            };
        },

        /* 5. luxury
           A thin, finely graduated ring with the speed printed in the middle: the restrained
           German saloon reading of the same instrument. Fuel sits on an inner arc. */
        luxury() {
            const value = digits('spd-value');
            const u = unit(), g = gear(), r = range(), o = odo();

            const speed = dial({
                cx: 92, cy: 92, r: 78, from: -135, to: 135, max: MAX_KMH,
                step: 5, labelEvery: 20, needleClass: 'spd-needle spd-needle--thin',
                labelRadius: 0.78, fontSize: 8,
            });
            const fuel = arcGauge(92, 92, 46, 150, 210, 'fuel');

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'luxury' }, [
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 184 184' }, [
                        ...fuel.parts,
                        U.svg('text', { class: 'spd-facelabel', x: 92, y: 150, 'text-anchor': 'middle', text: 'km/h' }),
                        ...speed.parts,
                    ]),
                    U.make('div', { class: 'spd-centre' }, [
                        U.make('div', { class: 'spd-readout' }, [value, u]),
                        U.make('div', { class: 'spd-subrow' }, [g, r]), o,
                    ]),
                ]),
                value, unit: u, gear: g, range: r, odo: o, speedDial: speed, fuelArc: fuel.fill,
            };
        },

        /* 6. jdm
           Tachometer first, speed second: one big rev counter with a shift light, and the
           speed as a digital inset. How a Japanese coupe lays its cluster out. */
        jdm() {
            const value = digits('spd-value');
            const u = unit(), g = gear(), o = odo();

            const tach = dial({
                cx: 96, cy: 94, r: 80, from: -130, to: 130, max: MAX_RPM,
                step: 0.25, labelEvery: 1, redline: REDLINE_RPM,
                needleClass: 'spd-needle spd-needle--rpm', fontSize: 11,
            });
            const fuel = arcGauge(96, 94, 44, 155, 205, 'fuel');

            const shift = U.make('div', { class: 'spd-shift', text: 'SHIFT' });

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'jdm' }, [
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 192 192' }, [
                        U.svg('circle', { class: 'spd-face', cx: 96, cy: 94, r: 88 }),
                        ...fuel.parts,
                        U.svg('text', { class: 'spd-facelabel', x: 96, y: 44, 'text-anchor': 'middle', text: 'x1000 r/min' }),
                        ...tach.parts,
                    ]),
                    U.make('div', { class: 'spd-centre spd-centre--low' }, [
                        U.make('div', { class: 'spd-readout' }, [value, u]), g, o,
                    ]),
                    shift,
                ]),
                value, unit: u, gear: g, odo: o, tachDial: tach, fuelArc: fuel.fill, shift,
            };
        },

        /* 7. muscle
           Three round gauges in a wide chrome-rimmed panel: fuel, speed, revs. An American
           dashboard, where the instruments are separate objects sitting in a bezel. */
        muscle() {
            const value = digits('spd-value');
            const u = unit(), g = gear(), o = odo();

            const speed = dial({
                cx: 148, cy: 82, r: 62, max: MAX_KMH, step: 10, labelEvery: 40, fontSize: 9,
            });
            const tach = dial({
                cx: 250, cy: 86, r: 44, max: MAX_RPM, step: 1, labelEvery: 2,
                redline: REDLINE_RPM, needleClass: 'spd-needle spd-needle--rpm', fontSize: 8,
            });
            const fuelDial = dial({
                cx: 46, cy: 86, r: 40, from: -60, to: 60, max: 100, step: 25, labelEvery: 50,
                needleClass: 'spd-needle spd-needle--thin', fontSize: 0, labelRadius: 0.62,
            });

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'muscle' }, [
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 296 168' }, [
                        U.svg('rect', { class: 'spd-panel', x: 3, y: 3, width: 290, height: 150, rx: 14 }),
                        U.svg('circle', { class: 'spd-bezel spd-bezel--thin', cx: 46, cy: 86, r: 44 }),
                        U.svg('circle', { class: 'spd-bezel', cx: 148, cy: 82, r: 68 }),
                        U.svg('circle', { class: 'spd-bezel spd-bezel--thin', cx: 250, cy: 86, r: 48 }),
                        U.svg('circle', { class: 'spd-face', cx: 46, cy: 86, r: 40 }),
                        U.svg('circle', { class: 'spd-face', cx: 148, cy: 82, r: 64 }),
                        U.svg('circle', { class: 'spd-face', cx: 250, cy: 86, r: 44 }),
                        U.svg('text', { class: 'spd-facelabel', x: 46, y: 104, 'text-anchor': 'middle', text: 'FUEL' }),
                        U.svg('text', { class: 'spd-facelabel', x: 148, y: 118, 'text-anchor': 'middle', text: 'km/h' }),
                        U.svg('text', { class: 'spd-facelabel', x: 250, y: 106, 'text-anchor': 'middle', text: 'RPM x1000' }),
                        ...fuelDial.parts, ...speed.parts, ...tach.parts,
                    ]),
                    U.make('div', { class: 'spd-centre spd-centre--muscle' }, [
                        U.make('div', { class: 'spd-readout' }, [value, u]), g, o,
                    ]),
                ]),
                value, unit: u, gear: g, odo: o,
                speedDial: speed, tachDial: tach, fuelDial,
            };
        },

        /* 8. supercar
           A row of shift lights across the top, a big central rev ring, and the speed as the
           only number that matters. The layout of a modern mid-engined car. */
        supercar() {
            const value = digits('spd-value spd-value--xl');
            const u = unit(), g = gear(), r = range(), o = odo();

            const tach = dial({
                cx: 104, cy: 100, r: 84, from: -120, to: 120, max: MAX_RPM,
                step: 0.5, labelEvery: 1, redline: REDLINE_RPM,
                needleClass: 'spd-needle spd-needle--rpm', labelRadius: 0.76, fontSize: 9,
            });

            const lights = [];
            const lightRow = U.make('div', { class: 'spd-lights' });
            for (let i = 0; i < 11; i += 1) {
                const zone = i < 5 ? 'low' : (i < 8 ? 'mid' : 'red');
                const node = U.make('i', { class: 'spd-light', 'data-zone': zone });
                lights.push(node);
                lightRow.appendChild(node);
            }

            const fuel = stripGauge('E', 'F', 'fuel');

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'supercar' }, [
                    lightRow,
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 208 208' }, [...tach.parts]),
                    U.make('div', { class: 'spd-centre' }, [
                        U.make('div', { class: 'spd-readout' }, [value, u]),
                        U.make('div', { class: 'spd-subrow' }, [g, r]),
                    ]),
                    fuel.node, o,
                ]),
                value, unit: u, gear: g, range: r, odo: o,
                tachDial: tach, revLights: lights, fuelFill: fuel.fill,
            };
        },

        /* 9. truck
           Big, plain and complete: speed, revs, fuel and coolant, all four legible at a glance
           from a high seat. Nothing is styled that does not have to be read. */
        truck() {
            const value = digits('spd-value');
            const u = unit(), g = gear(), r = range(), o = odo();

            const speed = dial({
                cx: 84, cy: 88, r: 66, max: 200, step: 10, labelEvery: 40, fontSize: 10,
            });
            const tach = dial({
                cx: 214, cy: 88, r: 66, max: 6, step: 0.5, labelEvery: 1,
                redline: 4.5, needleClass: 'spd-needle spd-needle--rpm', fontSize: 10,
            });
            const fuel = stripGauge('E', 'F', 'fuel');
            const temp = stripGauge('C', 'H', 'temp');

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'truck' }, [
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 298 176' }, [
                        U.svg('rect', { class: 'spd-panel', x: 2, y: 2, width: 294, height: 158, rx: 8 }),
                        U.svg('circle', { class: 'spd-face', cx: 84, cy: 88, r: 72 }),
                        U.svg('circle', { class: 'spd-face', cx: 214, cy: 88, r: 72 }),
                        U.svg('text', { class: 'spd-facelabel', x: 84, y: 126, 'text-anchor': 'middle', text: 'km/h' }),
                        U.svg('text', { class: 'spd-facelabel', x: 214, y: 126, 'text-anchor': 'middle', text: 'x1000 rpm' }),
                        ...speed.parts, ...tach.parts,
                    ]),
                    U.make('div', { class: 'spd-centre spd-centre--between' }, [
                        U.make('div', { class: 'spd-readout' }, [value, u]),
                        U.make('div', { class: 'spd-side' }, [g, r, o]),
                    ]),
                    U.make('div', { class: 'spd-strips' }, [fuel.node, temp.node]),
                ]),
                value, unit: u, gear: g, range: r, odo: o,
                speedDial: speed, tachDial: tach, fuelFill: fuel.fill, tempFill: temp.fill,
            };
        },

        /* 10. retro
           The 1980s answer: an LCD bar graph for speed with a numeric readout beside it, and a
           segmented rev ladder. A Countach, a C4 Corvette, an 80s concept car. */
        retro() {
            const value = digits('spd-value spd-value--lcd');
            const ghost = U.make('span', { class: 'spd-value spd-value--lcd spd-lcd__ghost', text: '888' });
            const u = unit(), g = gear(), r = range(), o = odo();

            const bars = [];
            const ladder = U.make('div', { class: 'spd-ladder' });
            const BAR_COUNT = 26;
            for (let i = 0; i < BAR_COUNT; i += 1) {
                const node = U.make('i', { class: 'spd-ladder__bar' });
                bars.push(node);
                ladder.appendChild(node);
            }

            const scale = U.make('div', { class: 'spd-ladderscale' });
            for (let v = 0; v <= MAX_KMH; v += 65) {
                scale.appendChild(U.make('span', { text: String(v) }));
            }

            const revBars = [];
            const revLadder = U.make('div', { class: 'spd-revbar' });
            for (let i = 0; i < 16; i += 1) {
                const rpm = (i / 15) * MAX_RPM;
                const node = U.make('i', {
                    class: 'spd-revbar__seg',
                    'data-zone': rpm >= REDLINE_RPM ? 'red' : (rpm >= REDLINE_RPM - 1.5 ? 'mid' : 'low'),
                });
                revBars.push(node);
                revLadder.appendChild(node);
            }

            const fuel = stripGauge('E', 'F', 'fuel');

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'retro' }, [
                    U.make('div', { class: 'spd-lcd' }, [ghost, value, u]),
                    ladder, scale, revLadder,
                    U.make('div', { class: 'spd-foot' }, [g, fuel.node, o, r]),
                ]),
                value, unit: u, gear: g, range: r, odo: o,
                speedBars: bars, revSegments: revBars, fuelFill: fuel.fill,
            };
        },
    };

    /* ------------------------------------------------------------------------------------
       Building
       ------------------------------------------------------------------------------------ */

    // The warnings come first, left to right, because that is the order a driver scans in and
    // the two that matter - a door not shut and a belt not fastened - should never be at the
    // end of a row of decorations.
    const CHIP_ORDER = ['belt', 'door', 'bonnet', 'cruise', 'nitro', 'harness', 'engine', 'lights'];

    function buildChips() {
        const node = U.make('div', { class: 'spd-chips' }, CHIP_ORDER.map(chip));
        const refs = { node };

        for (const name of CHIP_ORDER) {
            refs[name] = node.querySelector(`[data-chip="${name}"]`);
        }

        return refs;
    }

    /** Rebuild for `next`. A no-op when the style has not changed, which is every call but the
     *  ones that follow a settings change. */
    function setStyle(next) {
        if (!root) root = U.el('speedo');
        if (!root) return;

        const face = FACES[next] ? next : 'minimal';
        if (face === style) return;
        style = face;

        refs = FACES[face]();
        const chips = buildChips();
        refs.chips = chips;
        refs.chipRow = chips.node;

        U.fill(root, [refs.node, chips.node]);
    }

    // The room a preview card gives a face, in CSS pixels. Fixed on purpose: the card is a
    // fixed-height box in a grid whose minimum column is 178px, so these are known without
    // measuring anything.
    const CARD_ROOM = { w: 176, h: 138 };

    /**
     * A face rendered into an arbitrary container, for the menu's preview cards.
     *
     * The scale is per face, because the ten range from 168px square to 298px wide and one
     * factor either shrinks the small ones to a smudge or lets the wide ones run out from
     * under their own label.
     *
     * It is computed from the face's DECLARED size against a known card, never from measuring
     * the DOM. Measuring meant waiting for a frame, and a card whose measurement never
     * arrived - or arrived while it was still zero - got a scale of zero and rendered blank.
     * That is what left every preview card empty in game while they rendered in a browser.
     */
    function preview(container, faceName, sample, size) {
        const face = FACES[faceName] || FACES.minimal;
        const built = face();

        const scale = (size && size.w && size.h)
            ? Math.min(CARD_ROOM.w / size.w, CARD_ROOM.h / size.h, 1)
            : 0.6;

        // Written BEFORE the node is inserted, so the very first paint is already correct.
        U.cssVar(container, '--preview-scale', U.round(Math.max(scale, 0.2), 3));

        U.fill(container, [built.node]);
        applyTo(built, sample);
    }

    /* ------------------------------------------------------------------------------------
       Updating
       ------------------------------------------------------------------------------------ */

    /** Set a stroked arc to `pct` of its own length. The length is measured once and cached on
     *  the node: getTotalLength forces a layout, and doing it per tick is the most expensive
     *  thing this page could do. */
    function setArc(node, pct) {
        if (!node) return;
        if (node.__length === undefined) node.__length = node.getTotalLength() || 0;
        if (!node.__length) return;

        U.attr(node, 'stroke-dasharray', `${U.round(node.__length, 1)} ${U.round(node.__length, 1)}`);
        U.attr(node, 'stroke-dashoffset', U.round(node.__length * (1 - U.clamp(pct, 0, 1)), 1));
    }

    /** Write `data` into a built face. Shared by the live HUD and the menu preview. */
    function applyTo(target, data) {
        const speed = U.clamp(data.speed || 0, 0, 999);
        const rpm = U.clamp(data.rpm || 0, 0, 1);
        const fuel = U.clamp(data.fuel === undefined ? 100 : data.fuel, 0, 100);
        const engine = U.clamp(data.engine === undefined ? 100 : data.engine, 0, 100);
        const revs = rpm * MAX_RPM;

        U.text(target.value, Math.round(speed));
        if (target.unit) U.text(target.unit, data.unitLabel || 'KM/H');
        if (target.gear) U.text(target.gear, data.gear === undefined ? 'N' : data.gear);
        if (target.range) U.text(target.range, data.range ? `${data.range} ${data.rangeUnit || 'KM'}` : '');

        // The odometer. Hidden outright when nothing is tracking a mileage, rather than shown
        // as a zero on every car in the city.
        if (target.odo) {
            const reading = data.odometer;
            U.show(target.odo, !!reading);
            if (reading) {
                U.text(target.odo, `${U.money(reading.value, ' ')} ${reading.unit}`);
            }
        }

        // Needles.
        if (target.speedDial) target.speedDial.set(speed);
        if (target.tachDial) target.tachDial.set(revs);
        if (target.fuelDial) target.fuelDial.set(fuel);

        // Arcs.
        setArc(target.speedArc, speed / MAX_KMH);
        setArc(target.fuelArc, fuel / 100);

        // Strips.
        if (target.fuelFill) target.fuelFill.style.width = `${U.round(fuel, 1)}%`;
        // Coolant is not a value the game exposes, so it is derived from engine health: a
        // healthy engine sits at operating temperature, a wrecked one runs hot. Honest enough
        // for a gauge whose only job is to look alive and warn about a dying engine.
        if (target.tempFill) target.tempFill.style.width = `${U.round(45 + (100 - engine) * 0.5, 1)}%`;

        // Segmented rev displays.
        if (target.revSegments) {
            const lit = Math.round(rpm * target.revSegments.length);
            target.revSegments.forEach((node, i) => U.attr(node, 'data-lit', i < lit));
        }

        if (target.revLights) {
            const lit = Math.round(rpm * target.revLights.length);
            target.revLights.forEach((node, i) => U.attr(node, 'data-lit', i < lit));
        }

        if (target.speedBars) {
            const lit = Math.round((speed / MAX_KMH) * target.speedBars.length);
            target.speedBars.forEach((node, i) => U.attr(node, 'data-lit', i < lit));
        }

        if (target.shift) U.attr(target.shift, 'data-on', revs >= REDLINE_RPM);
        U.attr(target.node, 'data-limiter', rpm > 0.94);
    }

    /** Per tick, from the live vehicle payload. */
    function update(data, settings) {
        if (!root) root = U.el('speedo');
        if (!root || !refs.node) return;

        const options = settings.speedometer || {};
        const on = !!data && settings.show.speedometer !== false;

        U.attr(root, 'data-on', on);
        if (!on || !data) return;

        applyTo(refs, {
            speed: data.speed,
            rpm: options.rpm ? data.rpm : 0,
            fuel: options.fuel ? data.fuel : 100,
            engine: data.engine,
            gear: options.gear ? data.gear : undefined,
            unitLabel: settings.units === 'mph' ? S.t('unit.mph') : S.t('unit.kmh'),
            range: options.range && options.fuel ? data.range : null,
            rangeUnit: settings.units === 'mph' ? 'MI' : 'KM',
            odometer: options.odometer ? data.odometer : null,
        });

        // An aircraft has an altimeter where a car has a gear.
        if (data.aircraft && options.altitude && refs.gear) {
            U.text(refs.gear, `${data.altitude || 0} ${S.t('unit.metres')}`);
        }

        const chips = refs.chips || {};
        const showChip = (node, visible, on_, alert, armed) => {
            if (!node) return;
            U.show(node, visible);
            U.attr(node, 'data-on', !!on_);
            U.attr(node, 'data-alert', !!alert);
            U.attr(node, 'data-armed', !!armed);
        };

        // The seatbelt is shown the whole time you are driving, not only once you are already
        // going fast enough for it to matter. Green fastened, red unfastened, and it only
        // flashes above 40 - so the state is always readable and the nagging is not constant.
        const belted = data.seatbelt === true;
        showChip(chips.belt, options.belt && !data.bicycle && data.driver,
            belted, !belted, false);
        U.attr(chips.belt, 'data-flash', !belted && data.speed > 40);

        // A door, bonnet or boot left open. Two separate warnings: a door you drive away with
        // is a mistake, a bonnet up usually means somebody is working on the car.
        const doors = data.doors || {};
        showChip(chips.door, !data.bicycle && doors.door === true, false, true);
        U.attr(chips.door, 'data-flash', doors.door === true && data.speed > 5);
        showChip(chips.bonnet, !data.bicycle && (doors.bonnet === true || doors.boot === true),
            false, true);

        showChip(chips.cruise, !data.bicycle, data.cruise);
        showChip(chips.nitro, options.nitro && data.nitro > 0,
            data.nitroActive, false, data.nitro > 0 && !data.nitroActive);
        showChip(chips.harness, options.harness && data.hasHarness, true);
        showChip(chips.engine, options.engine && !data.bicycle,
            data.engine > 60, data.engine < 25);
        showChip(chips.lights, !data.bicycle,
            data.lights && data.lights.on, data.lights && (data.lights.left || data.lights.right));

        U.show(refs.chipRow, !data.bicycle);
    }

    /** Clear the face when the player leaves the vehicle. */
    function hide() {
        if (!root) root = U.el('speedo');
        U.attr(root, 'data-on', false);
    }

    return { setStyle, update, hide, preview, FACES };

})();
