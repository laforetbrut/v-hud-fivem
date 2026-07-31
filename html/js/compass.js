/*
    js/compass.js

    Four compasses over one heading.

    The tape is the interesting one. Drawing a strip of degrees and translating it is smooth
    but wraps badly: at 359 the strip jumps the whole way back to 0 and the eye catches it. It
    is drawn three times over instead - once at -360, once at 0, once at +360 - and the
    translation is taken modulo one width, so there is always tape either side and the wrap
    happens off screen.
*/

const Compass = (() => {

    const POINTS = [
        { deg: 0,   key: 'dir.n',  major: true },
        { deg: 45,  key: 'dir.ne', major: false },
        { deg: 90,  key: 'dir.e',  major: true },
        { deg: 135, key: 'dir.se', major: false },
        { deg: 180, key: 'dir.s',  major: true },
        { deg: 225, key: 'dir.sw', major: false },
        { deg: 270, key: 'dir.w',  major: true },
        { deg: 315, key: 'dir.nw', major: false },
    ];

    const TAPE_PX_PER_DEG = 2.6;     // how wide a degree is on the tape
    const TAPE_WIDTH = 360 * TAPE_PX_PER_DEG;
    const VISIBLE_SPAN = 120;        // degrees of the bar style that are on screen at once

    let root = null;
    let style = null;
    let refs = {};

    /* ------------------------------------------------------------------------------------
       Builders
       ------------------------------------------------------------------------------------ */

    const BUILDERS = {

        /* A fixed strip: the cardinals slide behind a centre marker. */
        bar() {
            const strip = U.make('div', { class: 'cmp-strip' });
            const marks = [];

            // Three copies so the strip never runs out on either side of the wrap.
            for (let copy = -1; copy <= 1; copy += 1) {
                for (const point of POINTS) {
                    const node = U.make('span', {
                        class: `cmp-mark${point.major ? ' cmp-mark--major' : ''}`,
                        text: S.t(point.key),
                    });
                    marks.push({ node, deg: point.deg + copy * 360 });
                    strip.appendChild(node);
                }
            }

            const degrees = U.make('span', { class: 'cmp-degrees', text: '0°' });

            return {
                node: U.make('div', { class: 'cmp-body', 'data-style': 'bar' }, [
                    U.make('div', { class: 'cmp-window' }, [strip]),
                    U.make('i', { class: 'cmp-pointer' }),
                    degrees,
                ]),
                marks, degrees, strip,
            };
        },

        /* A ruler with a tick every five degrees and a label every fifteen. */
        tape() {
            const strip = U.make('div', { class: 'cmp-tape' });

            for (let copy = -1; copy <= 1; copy += 1) {
                for (let deg = 0; deg < 360; deg += 5) {
                    const point = POINTS.find((p) => p.deg === deg);
                    const major = deg % 45 === 0;
                    const tick = U.make('i', {
                        class: `cmp-tick${major ? ' cmp-tick--major' : ''}`,
                        style: { left: `${(deg + copy * 360 + 360) * TAPE_PX_PER_DEG}px` },
                    });
                    strip.appendChild(tick);

                    if (point) {
                        strip.appendChild(U.make('span', {
                            class: `cmp-tapelabel${point.major ? ' cmp-tapelabel--major' : ''}`,
                            text: S.t(point.key),
                            style: { left: `${(deg + copy * 360 + 360) * TAPE_PX_PER_DEG}px` },
                        }));
                    }
                }
            }

            const degrees = U.make('span', { class: 'cmp-degrees', text: '0°' });

            return {
                node: U.make('div', { class: 'cmp-body', 'data-style': 'tape' }, [
                    U.make('div', { class: 'cmp-window' }, [strip]),
                    U.make('i', { class: 'cmp-pointer' }),
                    degrees,
                ]),
                strip, degrees, tape: true,
            };
        },

        /* A round face whose ring rotates under a fixed needle. */
        dial() {
            const ring = U.svg('g', { class: 'cmp-ring' });

            for (let deg = 0; deg < 360; deg += 15) {
                const major = deg % 45 === 0;
                const outer = U.polar(40, 40, 34, deg);
                const inner = U.polar(40, 40, major ? 26 : 30, deg);
                ring.appendChild(U.svg('line', {
                    class: `cmp-dialtick${major ? ' cmp-dialtick--major' : ''}`,
                    x1: outer.x, y1: outer.y, x2: inner.x, y2: inner.y,
                }));
            }

            for (const point of POINTS.filter((p) => p.major)) {
                const at = U.polar(40, 40, 19, point.deg);
                ring.appendChild(U.svg('text', {
                    class: 'cmp-dialtext',
                    x: at.x, y: at.y + 3,
                    'text-anchor': 'middle',
                    text: S.t(point.key),
                }));
            }

            const degrees = U.make('span', { class: 'cmp-degrees', text: '0°' });

            return {
                node: U.make('div', { class: 'cmp-body', 'data-style': 'dial' }, [
                    U.svg('svg', { class: 'cmp-dial', viewBox: '0 0 80 80' }, [
                        U.svg('circle', { class: 'cmp-dialface', cx: 40, cy: 40, r: 37 }),
                        ring,
                        U.svg('path', { class: 'cmp-needle', d: 'M40 8 L44 20 L40 17 L36 20 Z' }),
                    ]),
                    degrees,
                ]),
                ring, degrees,
            };
        },

        /* Cardinal and degrees, nothing else. The lightest of the four. */
        text() {
            const cardinal = U.make('span', { class: 'cmp-cardinal', text: 'N' });
            const degrees = U.make('span', { class: 'cmp-degrees', text: '0°' });

            return {
                node: U.make('div', { class: 'cmp-body', 'data-style': 'text' }, [cardinal, degrees]),
                cardinal, degrees,
            };
        },
    };

    /* ------------------------------------------------------------------------------------
       Building and updating
       ------------------------------------------------------------------------------------ */

    function setStyle(next) {
        if (!root) root = U.el('compass');
        if (!root) return;

        const chosen = BUILDERS[next] ? next : 'bar';
        if (chosen === style) return;
        style = chosen;

        refs = BUILDERS[chosen]();
        U.fill(root, [refs.node]);
    }

    /**
     * `heading` is a compass bearing: 0 is north and it grows clockwise. The Lua side does
     * that conversion so every consumer gets the same convention.
     */
    function update(heading, cardinal, settings) {
        if (!root) root = U.el('compass');
        if (!root || !refs.node) return;

        const options = settings.compass || {};

        U.attr(refs.node, 'data-degrees', options.degrees !== false);
        U.attr(refs.node, 'data-pointer', options.pointer !== false);
        U.attr(refs.node, 'data-cardinals', options.cardinals !== false);

        if (refs.degrees) {
            U.text(refs.degrees, `${String(Math.round(heading)).padStart(3, '0')}°`);
        }

        if (refs.cardinal) U.text(refs.cardinal, cardinal);

        if (refs.marks) {
            // The bar places each mark by how far it is from the current heading, wrapped to
            // the shorter way round so a mark never travels the long way across the strip.
            for (const mark of refs.marks) {
                let delta = mark.deg - heading;
                while (delta > 180) delta -= 360;
                while (delta < -180) delta += 360;

                const within = Math.abs(delta) <= VISIBLE_SPAN / 2;
                mark.node.style.left = `${50 + (delta / VISIBLE_SPAN) * 100}%`;
                mark.node.style.opacity = within ? String(1 - Math.abs(delta) / (VISIBLE_SPAN / 1.4)) : '0';
            }
        }

        if (refs.tape && refs.strip) {
            refs.strip.style.transform = `translateX(${-heading * TAPE_PX_PER_DEG - TAPE_WIDTH}px)`;
        }

        if (refs.ring) {
            refs.ring.style.transform = `rotate(${-heading}deg)`;
        }
    }

    function show(visible) {
        if (!root) root = U.el('compass');
        U.attr(U.el('el-compass'), 'data-visible', !!visible);
    }

    return { setStyle, update, show };

})();
