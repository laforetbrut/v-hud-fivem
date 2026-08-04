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
    const ARC_MAX_TILT = 18;         // how far down the arc may be rotated to clear the banner
    const DEG = 180 / Math.PI;
    let lastArcSignature = '';
    // The visible-gauge key set, kept separately so the tick can rule the arc out without
    // measuring anything. See the note in layoutArc.
    let lastArcKeys = null;

    /** Place every visible gauge on the circle around the map. */
    function layoutArc(force) {
        if (!listNode || listNode.getAttribute('data-arc') !== 'true') return;

        const visible = [];
        for (const [key, refs] of nodes) {
            if (refs.root.getAttribute('data-hidden') !== 'true') visible.push(refs);
        }

        /*
            The cheap gate comes FIRST, and that is the whole point of this block.

            This function is called at the end of every update(), which has just finished
            writing to the DOM. Measuring here forces the browser to lay the page out
            synchronously before it can answer - so reading the box before deciding whether
            there was any work to do cost one forced reflow per tick, sixty times a second,
            to almost always conclude that nothing had changed.

            The set of visible gauges is readable without measuring anything. When it has not
            changed there is nothing to re-space, so nothing is measured.

            A change in the MAP's size or place does need a re-space and is not visible in
            that key set - it arrives instead through setArc() on a settings change and
            through the ResizeObserver below, both of which pass force = true.
        */
        const keys = visible.map((r) => r.definition.key).join();
        if (!force && keys === lastArcKeys) return;

        const box = listNode.getBoundingClientRect();
        if (!box.width || !box.height) return;

        // box.top is part of the signature because the downward tilt below is limited by how
        // much screen is left under the map: moving the map re-decides the layout.
        const signature = `${keys}|${Math.round(box.width)}x${Math.round(box.height)}@${Math.round(box.top)}`;
        if (!force && signature === lastArcSignature) return;
        lastArcKeys = keys;
        lastArcSignature = signature;

        const cx = box.width / 2;
        const cy = box.height / 2;
        const gaugeSize = visible.length ? visible[0].root.getBoundingClientRect().width : 40;
        // Outside the circle, by half a gauge plus a little air. The map is an ellipse in the
        // general case, so the larger half-axis decides.
        const radius = Math.max(box.width, box.height) / 2 + gaugeSize * 0.55 + 6;

        const count = visible.length;
        const step = count > 1 ? ARC_SPAN / (count - 1) : 0;
        const half = count > 1 ? ARC_SPAN / 2 : 0;

        /*
            The arc is rotated DOWNWARD rather than centred on three o'clock.

            Six gauges spread over 116 degrees need more vertical room than the map itself
            occupies, so the ends of the arc always reach past the map's top and bottom edges.
            Those two directions are not equivalent: the street banner is the lid of the map,
            and below the map there is nothing. So the overshoot is pushed downward, and the
            top gauge stops eating into the banner.

            The tilt is the shortfall at the top, not a fixed nudge, so it is zero whenever the
            gauges already fit - a short list on a large map is left centred.
        */
        const clear = Math.asin(U.clamp((cy - gaugeSize / 2 - 2) / radius, 0, 1)) * DEG;

        // ...but never so far that the bottom gauge is pushed off the screen. On a map already
        // sitting low, that limit is the binding one.
        const room = (window.innerHeight - 4 - gaugeSize / 2) - (box.top + cy);
        const roomTilt = Math.asin(U.clamp(room / radius, 0, 1)) * DEG - half;

        const tilt = U.clamp(Math.min(half - clear, roomTilt), 0, ARC_MAX_TILT);
        const start = -half + tilt;

        visible.forEach((refs, index) => {
            const angle = ((start + step * index) - 90) * (Math.PI / 180);
            // -90 puts angle 0 at three o'clock, so the arc runs down the map's right side.
            const x = cx + radius * Math.cos(angle + Math.PI / 2);
            const y = cy + radius * Math.sin(angle + Math.PI / 2);

            refs.root.style.left = `${U.round(x, 1)}px`;
            refs.root.style.top = `${U.round(y, 1)}px`;
        });

        /*
            Tell the street banner how far the arc reaches above the map.

            The tilt above pushes the overshoot downward as far as the screen allows, but six
            gauges over 116 degrees still need more height than there is between the banner and
            the bottom of the screen, so some of it stays at the top. Rather than guess a
            clearance in CSS, the banner is moved up by the amount actually measured here: it
            is exact at any resolution, any HUD scale, and any number of visible gauges, and it
            is zero the moment the arc does fit.
        */
        const topY = cy + radius * Math.sin(start * (Math.PI / 180)) - gaugeSize / 2;
        U.cssVar(document.documentElement, '--arc-overshoot', `${Math.max(0, U.round(-topY, 1))}px`);
    }

    /*
        Watch the gauge list's own box.

        Since the tick stopped measuring, a map that is resized, rescaled or reshaped has no
        other way of telling the arc to re-space itself. ResizeObserver fires only when the
        box genuinely changes, so this costs nothing while the map sits still - which is the
        whole session, apart from the moment a player drags the size slider.

        Armed once and left armed; observing the same node twice is a no-op in the spec, but
        the flag keeps it obvious.
    */
    let listObserved = false;

    function observeList() {
        if (listObserved || !listNode || typeof ResizeObserver !== 'function') return;
        listObserved = true;
        new ResizeObserver(() => layoutArc(true)).observe(listNode);
    }

    /** Turn arc mode on or off. Called from state.js when the dock or the map shape changes. */
    function setArc(on) {
        if (!listNode) listNode = U.el('status-list');
        if (!listNode) return;

        U.attr(listNode, 'data-arc', !!on);
        lastArcSignature = '';
        lastArcKeys = null;

        // The map's own box is what the arc is drawn around, and the tick no longer measures
        // it. This is what notices a map that was resized, rescaled or reshaped - the one
        // change the visible-gauge gate cannot see.
        observeList();

        if (!on) {
            // Hand the gauges back to flex: an inline left/top would survive the class change
            // and pin them where the arc left them.
            for (const [, refs] of nodes) {
                refs.root.style.left = '';
                refs.root.style.top = '';
            }
            // No arc, nothing above the map, so the banner takes its clearance back.
            U.cssVar(document.documentElement, '--arc-overshoot', '0px');
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
