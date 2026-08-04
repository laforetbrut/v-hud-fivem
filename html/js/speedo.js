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
        return { node, fill, strip: node };
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

    /*
        The tell-tales.

        Drawn as the symbols on a real dashboard, because those are the only warning icons a
        driver already knows how to read: the headlamp with its rays slanting down for dipped
        beam and straight for main beam, the solid triangles for the indicators, the engine
        block, the fuel pump.

        Each entry is a list of parts so a symbol can mix a solid body with stroked rays -
        which is what makes a headlamp read as a headlamp rather than as a blob.
    */
    const CHIP_ICONS = {
        belt:    [{ d: 'M5 3h4l6 18h-4L5 3zM19 3h-4M19 3v18h-4' }],
        // The dashboard door warning: a car seen from above with both doors swung open.
        door:    [{ d: 'M12 4v16M12 4 6 7v10l6 3M12 4l6 3v10l-6 3M4 9 2 11l2 2M20 9l2 2-2 2' }],
        bonnet:  [{ d: 'M3 16h18M5 16V9l4-4h6l4 4v7M9 5V3h6v2' }],
        nitro:   [{ d: 'M12 2c3 4 5 6.5 5 10a5 5 0 0 1-10 0c0-3.5 2-6 5-10z' }],
        harness: [{ d: 'M12 3v18M6 6l12 12M18 6L6 18' }],
        engine:  [{ d: 'M5 9h3l2-2h4l2 2h3v6h-3l-2 2h-4l-2-2H5V9z' }],
        cruise:  [{ d: 'M12 4a8 8 0 1 0 8 8M12 12l5-5' }],

        // Mechanical wear, from the mechanic script. Each one is the symbol a real dashboard
        // uses, so nothing here needs a legend.
        // A disc with pad marks either side.
        brakes:  [{ d: 'M12 5a7 7 0 1 0 0 14 7 7 0 0 0 0-14M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6M2 9v6M22 9v6' }],
        // The thermometer in waves: coolant temperature.
        radiator: [{ d: 'M10 4a2 2 0 0 1 4 0v9a4 4 0 1 1-4 0zM12 8v6M3 20c1.5-1.5 3-1.5 4.5 0M16.5 20c1.5-1.5 3-1.5 4.5 0' }],
        // A battery with its terminals.
        electronics: [{ d: 'M3 8h18v10H3zM7 5h3v3H7M14 5h3v3h-3M6 13h4M15 13h4M17 11v4' }],
        // The oil can.
        injector: [{ d: 'M3 17v-5h7l3-3h4v3h4l-3 5zM7 12V9h4M13 20c1.6-2.2 2.4-3.6 2.4-4.4a2.4 2.4 0 0 0-4.8 0c0 .8.8 2.2 2.4 4.4z' }],
        // A gear wheel, for the clutch and the transmission.
        clutch:  [{ d: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2' }],
        transmission: [{ d: 'M6 5v14M12 5v14M18 5v14M4 5h16M6 12h12' }],
        // The axle: a shaft with a wheel at each end.
        axle:    [{ d: 'M4 8v8M20 8v8M4 12h16M8 10v4M16 10v4' }],
        suspension: [{ d: 'M12 3v3M12 18v3M9 6h6M9 18h6M12 6c-3 1.5-3 3 0 4.5s3 3 0 4.5' }],

        // Dipped beam: rays slant DOWN. Main beam: rays are STRAIGHT. That one difference is
        // the whole convention, and it is why the two symbols must not be merged.
        lights: [
            { d: 'M3 5h4a7 7 0 0 1 0 14H3z', fill: true },
            { d: 'M13 7l8 3M13 12l8 3M13 17l8 3' },
        ],
        beam: [
            { d: 'M3 5h4a7 7 0 0 1 0 14H3z', fill: true },
            { d: 'M13 8h8M13 12h8M13 16h8' },
        ],

        left:  [{ d: 'M14 4 5 12l9 8z', fill: true }],
        right: [{ d: 'M10 4l9 8-9 8z', fill: true }],

        fuel:  [{ d: 'M4 21V5a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v16M3 21h12M5 11h7M16 9v6a2 2 0 0 0 4 0V9l-3-3' }],
        brake: [{ d: 'M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16M12 8v5M12 15.6v.8M2 8c-1.4 2.6-1.4 5.4 0 8M22 8c1.4 2.6 1.4 5.4 0 8' }],
    };

    /*
        The lamp colour, per tell-tale, fixed rather than themed.

        A blue main-beam lamp is blue in every car ever built, and a red warning is red. These
        do NOT follow the player's accent colour: the whole value of the symbols is that they
        mean the same thing everywhere, and a pink low-fuel light means nothing to anybody.
    */
    const CHIP_LAMPS = {
        // A real car has no "belt fastened" lamp, only a red "belt undone" one. This HUD shows
        // both states on purpose - green fastened, red undone - because in a game you cannot
        // feel the strap, and a lamp that is dark whether you are belted or not answers
        // nothing. So the resting colour is GREEN and the fault state turns it red.
        belt: 'green',
        door: 'red', bonnet: 'red', brake: 'red',
        engine: 'green', fuel: 'amber',
        lights: 'green', left: 'green', right: 'green', cruise: 'green',
        beam: 'blue',
        nitro: 'accent', harness: 'accent',
        // Wear lamps. They only ever appear as a fault, so the resting colour never shows.
        brakes: 'red', radiator: 'red', electronics: 'red', injector: 'red',
        clutch: 'amber', transmission: 'amber', axle: 'amber', suspension: 'amber',
    };

    // The wear lamps, in the order a driver would want to know about them: stop first, then
    // things that will strand you, then things that are merely getting worse.
    const WEAR_CHIPS = [
        'brakes', 'radiator', 'injector', 'electronics',
        'clutch', 'transmission', 'axle', 'suspension',
    ];

    function chip(name) {
        const parts = (CHIP_ICONS[name] || []).map((part) => U.svg('path', {
            d: part.d,
            class: part.fill ? 'spd-chip__solid' : '',
        }));

        return U.make('div', {
            class: 'spd-chip',
            'data-chip': name,
            'data-lamp': CHIP_LAMPS[name] || 'green',
            hidden: 'hidden',
        }, [U.svg('svg', { viewBox: '0 0 24 24' }, parts)]);
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
                speedArc: speed.fill, fuelFill: fuel.fill, fuelStrip: fuel.strip,
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
                    // #chromeGradient lives in index.html, not here: see the note beside it.
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 168 168' }, [
                        U.svg('circle', { class: 'spd-bezel', cx: 84, cy: 84, r: 80 }),
                        U.svg('circle', { class: 'spd-face', cx: 84, cy: 84, r: 74 }),
                        ...fuel.parts,
                        // No printed "km/h" on a single-dial face: the digital readout sits in
                        // the lower third and prints the unit itself, so the painted one is
                        // both redundant and exactly where the readout plate covers it.
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
                speedDial: speed, tachDial: tach, fuelFill: fuel.fill, fuelStrip: fuel.strip,
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
                revSegments: segments, fuelFill: fuel.fill, fuelStrip: fuel.strip, tempFill: temp.fill,
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
                // Pushed out toward the rim so the "260" at the end of the sweep clears the
                // readout plate below the hub.
                labelRadius: 0.85, fontSize: 8,
            });
            const fuel = arcGauge(92, 92, 46, 150, 210, 'fuel');

            return {
                node: U.make('div', { class: 'spd-body', 'data-style': 'luxury' }, [
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 184 184' }, [
                        ...fuel.parts,
                        // Unit printed by the readout, not on the face - see the classic dial.
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
                    // No backing plate. Three chrome-rimmed gauges floating over the scene is
                    // what a muscle car dash looks like; the rounded box they used to sit on
                    // read as a widget stuck on the screen.
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 296 168' }, [
                        U.svg('circle', { class: 'spd-bezel spd-bezel--thin', cx: 46, cy: 86, r: 44 }),
                        U.svg('circle', { class: 'spd-bezel', cx: 148, cy: 82, r: 68 }),
                        U.svg('circle', { class: 'spd-bezel spd-bezel--thin', cx: 250, cy: 86, r: 48 }),
                        U.svg('circle', { class: 'spd-face', cx: 46, cy: 86, r: 40 }),
                        U.svg('circle', { class: 'spd-face', cx: 148, cy: 82, r: 64 }),
                        U.svg('circle', { class: 'spd-face', cx: 250, cy: 86, r: 44 }),
                        // Only the two outer gauges are labelled. The big one in the middle is
                        // obviously the speedometer, its readout prints KM/H, and a label there
                        // sits exactly where the readout plate lands.
                        U.svg('text', { class: 'spd-facelabel', x: 46, y: 104, 'text-anchor': 'middle', text: 'FUEL' }),
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
                tachDial: tach, revLights: lights, fuelFill: fuel.fill, fuelStrip: fuel.strip,
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
                    // No backing plate - see the note on the muscle face.
                    U.svg('svg', { class: 'spd-svg', viewBox: '0 0 298 176' }, [
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
                speedDial: speed, tachDial: tach, fuelFill: fuel.fill, fuelStrip: fuel.strip, tempFill: temp.fill,
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
                speedBars: bars, revSegments: revBars, fuelFill: fuel.fill, fuelStrip: fuel.strip,
            };
        },
    };

    /* ------------------------------------------------------------------------------------
       Building
       ------------------------------------------------------------------------------------ */

    // The warnings come first, left to right, because that is the order a driver scans in and
    // the two that matter - a door not shut and a belt not fastened - should never be at the
    // end of a row of decorations.
    //
    // The indicators sit at the two ends, the way they do on a dashboard, so a glance at the
    // left of the row means "turning left" without reading anything.
    const CHIP_ORDER = [
        'left',
        'belt', 'door', 'bonnet', 'brake', 'fuel', 'engine',
        'brakes', 'radiator', 'injector', 'electronics',
        'clutch', 'transmission', 'axle', 'suspension',
        'cruise', 'nitro', 'harness',
        'lights', 'beam',
        'right',
    ];

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

        // A scale and NOTHING else.
        //
        // The face stays in normal flow and the frame centres it with flexbox. That matters
        // for more than tidiness: while the face was `position: absolute`, the frame had no
        // in-flow content, so its max-content width was zero - and CEF's UA stylesheet puts
        // `align-items: flex-start` on the <button> these cards used to be, which sizes every
        // child to its content. A zero-width frame with `overflow: hidden` clipped the entire
        // instrument away, which is exactly how these cards came to render empty in game while
        // being perfect in a browser that dropped that UA rule years ago.
        //
        // `transform` does not affect layout, so the unscaled face is centred first and the
        // scaled paint always lands inside the frame.
        built.node.style.transformOrigin = '50% 50%';
        built.node.style.transform = `scale(${U.round(Math.max(scale, 0.2), 3)})`;

        U.fill(container, [built.node]);

        // Painted now so the card is never empty, and remembered so it can be painted AGAIN
        // once it is actually in the document. The first pass runs against a detached node,
        // where every path measures zero length and every arc is skipped; only the second one
        // can draw them. Text and tell-tales need no measurement and are right immediately.
        container.__preview = { built: built, sample: sample };
        applyTo(built, sample);
    }

    /** Re-paint every preview card under `root`. Called once the cards are in the document,
     *  which is the first moment an SVG path can report its own length. */
    function settlePreviews(root) {
        const scope = root || document;
        const cards = scope.querySelectorAll ? scope.querySelectorAll('.spd-preview') : [];

        for (let i = 0; i < cards.length; i++) {
            const stored = cards[i].__preview;
            if (stored) applyTo(stored.built, stored.sample);
        }
    }

    /* ------------------------------------------------------------------------------------
       Updating
       ------------------------------------------------------------------------------------ */

    /** Set a stroked arc to `pct` of its own length. The length is measured once and cached on
     *  the node: getTotalLength forces a layout, and doing it per tick is the most expensive
     *  thing this page could do.
     *
     *  A zero is NOT cached, and that is the whole point of the guard. getTotalLength returns 0
     *  for a path that is not in the document yet, so a face built off-document measured zero,
     *  cached the zero, and never drew an arc again once it was inserted - which is exactly how
     *  the menu preview cards ended up blank while the live cluster was fine. */
    function setArc(node, pct) {
        if (!node) return;

        if (!node.__length) {
            const length = node.getTotalLength ? (node.getTotalLength() || 0) : 0;
            if (!length) return;      // off-document, or a degenerate path: try again next call
            node.__length = length;
        }

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
        if (target.fuelFill) {
            target.fuelFill.style.width = `${U.round(fuel, 1)}%`;
            // The strip has no numbers, so the only way it can say "low" rather than merely
            // "short" is to change colour at the reserve mark.
            const mark = (data.thresholds && data.thresholds.lowFuel) || 25;
            if (target.fuelStrip) U.attr(target.fuelStrip, 'data-low', fuel <= mark);
        }
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
            // The operator's warning thresholds. Without this the fuel strip's reserve mark
            // fell back to its hard-coded 25 and ignored Config.Cluster.lowFuel, so the strip
            // turned red at a different level from the lamp beside it.
            thresholds: data.thresholds,
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
        /*
            Shown to PASSENGERS too, not only to the driver.

            A passenger can buckle - qb-smallresources' toggle has no driver check - and the
            ejection logic throws unbelted passengers through the windscreen exactly like the
            driver. Hiding the lamp from them meant the one seat that most needs telling had
            no way to see whether the belt was on.

            The belt state itself is the local player's own, so a passenger sees their own
            belt, not the driver's.
        */
        const belted = data.seatbelt === true;
        showChip(chips.belt, options.belt && !data.bicycle, belted, !belted, false);
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
        /*
            The engine lamp answers two questions with one symbol, the way a real one does.

            Lit green   the engine is running and in good health
            Red         the engine is damaged, running or not - that is a fault either way
            Dark        the engine is off

            `data.engine` is the engine's HEALTH, not whether it is turning over. Reading only
            that meant a switched-off car in perfect condition sat there with a green lamp.
        */
        const limits = data.thresholds || {};
        const running = data.engineOn !== false;
        showChip(chips.engine, options.engine && !data.bicycle,
            running && data.engine > 60, data.engine < (limits.engineFault === undefined ? 25 : limits.engineFault));

        // The handbrake, and the low-fuel lamp at the reserve mark. Both appear only when they
        // have something to say, which is the whole point of a warning lamp.
        showChip(chips.brake, !data.bicycle && data.handbrake === true, false, true);

        // The reserve light. The threshold is the operator's, not a number invented here -
        // servers with a fast fuel drain want it earlier than servers without one.
        const lowFuel = limits.lowFuel === undefined ? 25 : limits.lowFuel;
        const criticalFuel = limits.lowFuelCritical === undefined ? 8 : limits.lowFuelCritical;
        showChip(chips.fuel, options.fuel && !data.bicycle && data.fuel <= lowFuel, false, true);
        U.attr(chips.fuel, 'data-flash', data.fuel <= criticalFuel);

        /*
            Mechanical wear, from whichever mechanic script is installed.

            A worn part lights its lamp; a healthy one shows nothing at all. That is not the
            same rule as the seatbelt, and deliberately: a dashboard that permanently displays
            eight healthy components is a dashboard nobody scans. `data.parts` is nil on a
            server with no mechanic script, so every one of these stays hidden and the row is
            exactly what it was before.
        */
        const parts = data.parts || {};
        const worn = data.partWarning === undefined ? 50 : data.partWarning;
        for (const key of WEAR_CHIPS) {
            const level = parts[key];
            const bad = typeof level === 'number' && level < worn;
            showChip(chips[key], options.parts !== false && !data.bicycle && bad, false, true);
            // Below half of the warning threshold it is not "wearing", it is about to fail.
            U.attr(chips[key], 'data-flash', bad && level < worn / 2);
        }

        /*
            The lights.

            Dipped beam is shown the whole time you are in a car, lit or not, because "are my
            lights on" is a question you ask in the dark and an absent symbol cannot answer it.
            Main beam and the indicators appear only while they are ON - a permanently dim
            main-beam lamp is clutter, and a dim indicator arrow is a lie.
        */
        const lights = data.lights || {};
        showChip(chips.lights, !data.bicycle, lights.on === true);
        showChip(chips.beam, !data.bicycle && lights.high === true, true);

        showChip(chips.left, !data.bicycle && lights.left === true, true);
        showChip(chips.right, !data.bicycle && lights.right === true, true);
        // Indicators blink. A steady arrow does not read as an indicator.
        U.attr(chips.left, 'data-flash', lights.left === true);
        U.attr(chips.right, 'data-flash', lights.right === true);

        U.show(refs.chipRow, !data.bicycle);
    }

    /** Clear the face when the player leaves the vehicle. */
    function hide() {
        if (!root) root = U.el('speedo');
        U.attr(root, 'data-on', false);
    }

    /**
     * Every tell-tale this cluster can show, as { key, lamp, node }, in dashboard order.
     *
     * The menu draws a legend from this. Symbols are only self-explanatory to somebody who
     * already drives; "I do not understand what these icons mean" is a fair complaint about a
     * row of warning lamps, and the answer is to say what each one is somewhere you can look
     * it up rather than to replace the symbols with words on the cluster itself.
     */
    function legend() {
        return CHIP_ORDER.map((key) => ({
            key,
            lamp: CHIP_LAMPS[key] || 'green',
            node: chip(key),
        }));
    }

    /** The path data for a tell-tale, so the settings menu can put the same symbol beside the
     *  switch that controls it. Returns null for a key that has no lamp. */
    function lampIcon(key) {
        const parts = CHIP_ICONS[key];
        return parts ? parts.map((p) => ({ d: p.d, fill: !!p.fill })) : null;
    }

    return { setStyle, update, hide, preview, settlePreviews, legend, lampIcon, FACES };

})();
