/*
    js/status.js

    The status gauges: twelve shapes over one component.

    Every shape draws the same three things - an icon, a track and a fill - and differs only
    in geometry. That is why switching shape is instant: `build` runs once per shape change,
    and `update` afterwards touches one custom property and two attributes per gauge. Standing
    still, that is a handful of writes the browser rejects as unchanged.

    A gauge is described entirely by Config.Status on the Lua side, so adding one is a config
    edit and nothing here changes.
*/

const Status = (() => {

    const SHAPES = [
        'square', 'rounded', 'pill', 'circle', 'ring', 'radial',
        'dot', 'bar', 'segment', 'diamond', 'hex', 'icon',
    ];

    // Shapes drawn with SVG rather than with a box and a fill.
    const SVG_SHAPES = new Set(['circle', 'ring', 'radial', 'hex']);

    const RADIUS = 15.5;             // the ring radius inside a 40x40 viewBox
    const SEGMENTS = 10;             // blocks in the segmented shape
    const RADIAL_SWEEP = 270;        // degrees the radial shape covers

    let definitions = [];            // Config.Status, as sent by the server
    let nodes = new Map();           // key -> { root, fill, value, arc, segs }
    let shape = 'square';
    let listNode = null;

    /* ------------------------------------------------------------------------------------
       Building
       ------------------------------------------------------------------------------------ */

    /** Store the definitions the server sent. Called once, on boot. */
    function build(list) {
        definitions = Array.isArray(list) ? list.slice() : [];
        definitions.sort((a, b) => (a.order || 0) - (b.order || 0));
        listNode = U.el('status-list');
    }

    /** One gauge's DOM, for the current shape. */
    function makeGauge(definition) {
        const key = definition.key;
        const icon = U.svg('svg', { class: 'gauge__icon', viewBox: '0 0 24 24' }, [
            U.svg('path', { d: definition.icon || '' }),
        ]);
        const value = U.make('span', { class: 'gauge__value', text: '0' });

        const parts = [];
        const refs = { value };

        if (SVG_SHAPES.has(shape)) {
            const circumference = U.circumference(RADIUS);
            const sweep = shape === 'radial' ? RADIAL_SWEEP / 360 : 1;

            if (shape === 'hex') {
                // A hexagon traced as a polyline, so the same dash trick that fills a circle
                // fills a hexagon: the path length is the dasharray and the offset is the
                // value. No arc maths, and it animates identically.
                const points = hexPoints(20, 20, 16);
                const track = U.svg('polygon', { class: 'gauge__track', points });
                const arc = U.svg('polygon', { class: 'gauge__arc', points });
                refs.arc = arc;
                refs.length = null;      // measured after mount, see mountLengths
                parts.push(U.svg('svg', { class: 'gauge__svg', viewBox: '0 0 40 40' }, [
                    U.svg('g', { class: 'gauge__ring' }, [track, arc]),
                ]));
            } else {
                const dash = circumference * sweep;
                const track = U.svg('circle', {
                    class: 'gauge__track', cx: 20, cy: 20, r: RADIUS,
                    'stroke-dasharray': `${dash} ${circumference}`,
                });
                const arc = U.svg('circle', {
                    class: 'gauge__arc', cx: 20, cy: 20, r: RADIUS,
                    'stroke-dasharray': `${dash} ${circumference}`,
                    'stroke-dashoffset': dash,
                });
                refs.arc = arc;
                refs.length = dash;
                parts.push(U.svg('svg', { class: 'gauge__svg', viewBox: '0 0 40 40' }, [
                    U.svg('g', { class: 'gauge__ring' }, [track, arc]),
                ]));
            }

            parts.push(icon, value);

        } else if (shape === 'bar' || shape === 'pill') {
            const fill = U.make('i', { class: 'gauge__fill' });
            refs.fill = fill;
            parts.push(icon, U.make('div', { class: 'gauge__track-bar' }, [fill]), value);

        } else if (shape === 'segment') {
            const segs = [];
            const blocks = U.make('div', { class: 'gauge__segments' });
            for (let i = 0; i < SEGMENTS; i += 1) {
                const seg = U.make('i', { class: 'gauge__seg' });
                segs.push(seg);
                blocks.appendChild(seg);
            }
            refs.segs = segs;
            parts.push(icon, blocks, value);

        } else if (shape === 'icon' || shape === 'dot') {
            parts.push(icon, value);

        } else {
            // square, rounded, diamond
            const fill = U.make('i', { class: 'gauge__fill' });
            refs.fill = fill;
            parts.push(fill, icon, value);
        }

        const root = U.make('div', {
            class: 'gauge',
            'data-key': key,
            'data-shape': shape,
            'data-pulse': definition.pulse ? 'true' : 'false',
        }, parts);

        refs.root = root;
        refs.definition = definition;
        return refs;
    }

    /** The six corners of a hexagon, as an SVG points string. */
    function hexPoints(cx, cy, radius) {
        const out = [];
        for (let i = 0; i < 6; i += 1) {
            const point = U.polar(cx, cy, radius, i * 60);
            out.push(`${U.round(point.x, 2)},${U.round(point.y, 2)}`);
        }
        return out.join(' ');
    }

    /**
     * A polygon has no known length until it is in the document. Measured once after mount
     * and cached, because getTotalLength forces a layout and doing it per tick would be the
     * single most expensive thing on the page.
     */
    function mountLengths() {
        for (const refs of nodes.values()) {
            if (refs.arc && refs.length === null && typeof refs.arc.getTotalLength === 'function') {
                const length = refs.arc.getTotalLength();
                refs.length = length;
                refs.arc.setAttribute('stroke-dasharray', `${length} ${length}`);
                refs.arc.setAttribute('stroke-dashoffset', length);
            }
        }
    }

    /**
     * Rebuild the gauge list. Called when the shape changes, when the icon or value switches
     * move, and on boot. Not called per tick.
     */
    function render(settings) {
        if (!listNode) listNode = U.el('status-list');
        if (!listNode || !definitions.length) return;

        const style = settings.style || {};
        const nextShape = SHAPES.includes(style.gauge) ? style.gauge : 'square';
        const rebuild = nextShape !== shape || nodes.size === 0;
        shape = nextShape;

        U.attr(listNode, 'data-direction', style.direction === 'column' ? 'column' : 'row');
        U.attr(listNode, 'data-shape', shape);

        if (rebuild) {
            nodes = new Map();
            const fragment = document.createDocumentFragment();

            for (const definition of definitions) {
                const refs = makeGauge(definition);
                nodes.set(definition.key, refs);
                fragment.appendChild(refs.root);
            }

            U.fill(listNode, []);
            listNode.appendChild(fragment);
            mountLengths();
        }

        // Icons and numbers are attributes rather than a rebuild, so toggling them does not
        // throw away the transition state of every gauge on screen.
        const show = settings.show || {};
        for (const [key, refs] of nodes) {
            U.attr(refs.root, 'data-icons', style.icons !== false);
            U.attr(refs.root, 'data-values', style.values === true);
            U.attr(refs.root, 'data-hidden', show[key] === false);
        }

        // The whole cluster hides when every gauge in it is off, so an empty box is never
        // left sitting on screen with a border and nothing in it.
        const anyVisible = definitions.some((definition) => show[definition.key] !== false);
        U.attr(U.el('el-status'), 'data-visible', anyVisible);
    }

    /* ------------------------------------------------------------------------------------
       Updating
       ------------------------------------------------------------------------------------ */

    /** Whether this gauge is in its warning band. `invert` flips the comparison for stress. */
    function isWarning(definition, value) {
        if (definition.invert) {
            return definition.warnAbove !== undefined
                && definition.warnAbove !== null
                && value > definition.warnAbove;
        }
        return definition.warnBelow !== undefined
            && definition.warnBelow !== null
            && value < definition.warnBelow;
    }

    /**
     * Per tick. `data` is the tick payload; each gauge picks its own value out of it, which
     * keeps the payload flat and lets a custom gauge read from `data.custom`.
     */
    function update(data, settings) {
        if (!nodes.size) return;

        const style = settings.style || {};
        const show = settings.show || {};
        const hideFull = style.hideFull === true;

        for (const [key, refs] of nodes) {
            const definition = refs.definition;
            let value = data[key];

            if (value === undefined && data.custom) value = data.custom[key];
            if (value === undefined) value = 0;
            value = U.clamp(value, 0, 100);

            // `onlyWhenRelevant` is what stops oxygen and stamina sitting at full on screen
            // for the ninety-nine percent of the session they mean nothing.
            let hidden = show[key] === false;
            if (!hidden && definition.onlyWhenRelevant) {
                if (key === 'oxygen') hidden = !data.underwater;
                else if (key === 'stamina') hidden = !data.sprinting && value >= 99;
            }
            if (!hidden && hideFull && value >= 100 && key !== 'stress') hidden = true;
            if (!hidden && key === 'stress' && hideFull && value <= 0) hidden = true;

            U.attr(refs.root, 'data-hidden', hidden);
            if (hidden) continue;

            U.cssVar(refs.root, '--value', value);
            U.cssVar(refs.root, '--colour', `var(--c-${key})`);
            U.attr(refs.root, 'data-warn', isWarning(definition, value));
            U.text(refs.value, Math.round(value));

            if (refs.arc && refs.length) {
                const offset = refs.length * (1 - value / 100);
                U.attr(refs.arc, 'stroke-dashoffset', U.round(offset, 2));
            }

            if (refs.segs) {
                const lit = Math.round((value / 100) * SEGMENTS);
                for (let i = 0; i < refs.segs.length; i += 1) {
                    U.attr(refs.segs[i], 'data-lit', i < lit);
                }
            }
        }

        // Oxygen and stamina appear and disappear, so the arc has to re-space itself. It
        // returns immediately unless the visible set actually changed.
        layoutArc(false);
    }

    /* ------------------------------------------------------------------------------------
       The arc

       When the gauges are docked to a ROUND map they follow its curve instead of standing in
       a line beside it. The geometry cannot be CSS: the radius depends on the map's real
       pixel size, and the spread depends on how many gauges are visible right now - oxygen
       and stamina come and go, and a fixed set of angles would leave a hole where stamina
       used to be.
       ------------------------------------------------------------------------------------ */

    const ARC_SPAN = 116;            // degrees of arc the gauges are spread over
    let lastArcSignature = '';

    /** Place every visible gauge on the circle around the map. */
    function layoutArc(force) {
        if (!listNode || listNode.getAttribute('data-arc') !== 'true') return;

        const visible = [];
        for (const [key, refs] of nodes) {
            if (refs.root.getAttribute('data-hidden') !== 'true') visible.push(refs);
        }

        const box = listNode.getBoundingClientRect();
        if (!box.width || !box.height) return;

        // Re-place only when the set of visible gauges or the map size actually changed:
        // this runs off the tick, and writing six positions per frame is six layouts.
        const signature = `${visible.map((r) => r.definition.key).join()}|${Math.round(box.width)}x${Math.round(box.height)}`;
        if (!force && signature === lastArcSignature) return;
        lastArcSignature = signature;

        const cx = box.width / 2;
        const cy = box.height / 2;
        const gaugeSize = visible.length ? visible[0].root.getBoundingClientRect().width : 40;
        // Outside the circle, by half a gauge plus a little air. The map is an ellipse in the
        // general case, so the larger half-axis decides.
        const radius = Math.max(box.width, box.height) / 2 + gaugeSize * 0.55 + 6;

        const count = visible.length;
        const step = count > 1 ? ARC_SPAN / (count - 1) : 0;
        const start = count > 1 ? -ARC_SPAN / 2 : 0;

        visible.forEach((refs, index) => {
            const angle = ((start + step * index) - 90) * (Math.PI / 180);
            // -90 puts angle 0 at three o'clock, so the arc runs down the map's right side.
            const x = cx + radius * Math.cos(angle + Math.PI / 2);
            const y = cy + radius * Math.sin(angle + Math.PI / 2);

            refs.root.style.left = `${U.round(x, 1)}px`;
            refs.root.style.top = `${U.round(y, 1)}px`;
        });
    }

    /** Turn arc mode on or off. Called from state.js when the dock or the map shape changes. */
    function setArc(on) {
        if (!listNode) listNode = U.el('status-list');
        if (!listNode) return;

        U.attr(listNode, 'data-arc', !!on);
        lastArcSignature = '';

        if (!on) {
            // Hand the gauges back to flex: an inline left/top would survive the class change
            // and pin them where the arc left them.
            for (const [, refs] of nodes) {
                refs.root.style.left = '';
                refs.root.style.top = '';
            }
            return;
        }

        requestAnimationFrame(() => layoutArc(true));
    }

    /** The shape list, for the menu. Kept here so the menu cannot offer one that has no
     *  renderer behind it. */
    function shapes() {
        return SHAPES.slice();
    }

    return { build, render, update, shapes, setArc, layoutArc };

})();
