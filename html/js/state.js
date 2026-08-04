/*
    js/state.js

    What the page knows: the settings in force, the static payload the server sent once, and
    the last tick.

    The important function here is `applySettings`. It writes the whole design system - every
    colour, the radius, the gap, the scale, the glow - onto :root as custom properties, and
    then positions the seven HUD elements. Nothing below it re-renders on a settings change:
    the browser repaints from the new properties, which is why a colour slider recolours the
    HUD live with no visible cost.
*/

const S = (() => {

    const state = {
        ready: false,
        settings: null,
        statik: null,          // themes, speedometers, statuses, strings, locked paths
        locked: [],
        tick: {},
        vehicle: null,
    };

    /* ------------------------------------------------------------------------------------
       Strings
       ------------------------------------------------------------------------------------ */

    /**
     * The choice lists the server offers, already narrowed by Config.Policy.
     *
     * The menu builds every control from these rather than from its own idea of what exists,
     * so a gauge shape or a compass style the operator removed is never offered - not offered
     * and then refused, which would be a control that does nothing.
     */
    // What this build can render. Used as the fallback when the server did not send a list,
    // because a MISSING field must not read as "the operator removed every option" - that
    // silently deletes a control, which is a far worse failure than showing one option too
    // many. An operator removing something is an explicit, non-empty, shorter list.
    const ALL_CHOICES = {
        gaugeShapes: ['square', 'rounded', 'pill', 'circle', 'ring', 'radial',
            'dot', 'bar', 'segment', 'diamond', 'hex', 'icon'],
        surfaces: ['glass', 'tint', 'solid', 'none'],
        compassStyles: ['bar', 'tape', 'dial', 'text'],
        mapShapes: ['square', 'circle'],
        directions: ['row', 'column'],
        units: ['kmh', 'mph'],
    };

    function choices() {
        const from = (state.statik && state.statik.choices) || {};
        const out = { removed: U.asArray(from.removed) };

        for (const [key, everything] of Object.entries(ALL_CHOICES)) {
            const sent = U.asArray(from[key]);
            out[key] = sent.length > 0 ? sent : everything;
        }

        return out;
    }

    /** Translate. An unknown key comes back in brackets so a missing string is visible in the
     *  menu rather than rendering as an empty row nobody notices. */
    function t(key, ...args) {
        const table = state.statik && state.statik.strings;
        let value = (table && table[key]) || `[${key}]`;

        for (const arg of args) value = value.replace('%s', String(arg));
        return value;
    }

    /* ------------------------------------------------------------------------------------
       Locked paths
       ------------------------------------------------------------------------------------ */

    /** Whether the server locked `path`, or any ancestor of it. Mirrors Settings.isLocked in
     *  shared/settings.lua - the server enforces, this only draws the padlock. */
    function isLocked(path) {
        return U.asArray(state.locked)
            .some((locked) => locked === path || path.startsWith(`${locked}.`));
    }

    /* ------------------------------------------------------------------------------------
       Reading and writing settings by path
       ------------------------------------------------------------------------------------ */

    function get(path, fallback) {
        let node = state.settings;
        for (const part of path.split('.')) {
            if (node === null || typeof node !== 'object') return fallback;
            node = node[part];
        }
        return node === undefined ? fallback : node;
    }

    /**
     * Change one setting. Applies locally first so the HUD updates on this frame, then tells
     * Lua. The Lua side re-validates and sends the settings back, which corrects the optimism
     * if the value was refused.
     */
    function set(path, value) {
        if (isLocked(path)) return false;

        let node = state.settings;
        const parts = path.split('.');
        for (let i = 0; i < parts.length - 1; i += 1) {
            if (node === null || typeof node !== 'object') return false;
            node = node[parts[i]];
        }
        if (node === null || typeof node !== 'object') return false;

        node[parts[parts.length - 1]] = value;

        applySettings(state.settings);
        U.post('setPath', { path, value });
        return true;
    }

    /** Several at once, for the controls that move more than one key. */
    function setMany(changes) {
        for (const [path, value] of Object.entries(changes)) {
            if (isLocked(path)) continue;

            let node = state.settings;
            const parts = path.split('.');
            for (let i = 0; i < parts.length - 1; i += 1) node = node[parts[i]];
            node[parts[parts.length - 1]] = value;
        }

        applySettings(state.settings);
        queuePost(changes);
    }

    /* ------------------------------------------------------------------------------------
       Telling Lua

       The screen updates on every change, immediately - that is the feedback the player is
       looking at. The MESSAGE to Lua does not have to.

       Dragging an element fires pointermove sixty to a hundred and twenty times a second, and
       each one used to be its own NUI callback carrying one path. The last value in a burst
       is the only one that matters, so they are merged and sent once the pointer settles.

       `flushPost` is called when a drag ends, so a change is never left only on the page.
       ------------------------------------------------------------------------------------ */

    const POST_DELAY = 120;          // ms of quiet before a burst is sent
    let pending = null;
    let pendingTimer = null;

    function flushPost() {
        if (pendingTimer) { clearTimeout(pendingTimer); pendingTimer = null; }
        if (!pending) return;

        const changes = pending;
        pending = null;
        U.post('setPaths', { changes });
    }

    function queuePost(changes) {
        pending = pending || {};
        // Later values win, which is what "the last position of the drag" means.
        Object.assign(pending, changes);

        if (pendingTimer) clearTimeout(pendingTimer);
        pendingTimer = setTimeout(flushPost, POST_DELAY);
    }

    /* ------------------------------------------------------------------------------------
       Applying settings to the document
       ------------------------------------------------------------------------------------ */

    // No `money` element. A permanent cash readout is the thing every player turns off
    // first, so it is not built at all; `/cash` and `/bank` answer through the toast stack
    // instead, which is the part that was ever wanted.
    const ELEMENTS = ['status', 'speedo', 'compass', 'streets', 'voice', 'vehicle'];

    // Which `show` key decides whether each positioned element is drawn. `status` has none:
    // it is drawn whenever at least one gauge inside it is on, which status.js works out.
    const ELEMENT_VISIBILITY = {
        speedo: 'speedometer',
        compass: 'compass',
        streets: 'streets',
        voice: 'voice',
    };

    /* ------------------------------------------------------------------------------------
       Keeping everything on screen

       A HUD where every element is movable, every gauge has twelve shapes and every
       speedometer is a different size is a HUD where some combination will hang off an edge.
       Rather than hand-tuning a position per theme - which fixes the five shipped
       combinations and none of the thousands a player can build - each element is measured
       after it renders and nudged back inside.

       The measurement is the expensive part, so it runs on an animation frame after a change
       rather than per tick, and a ResizeObserver re-runs it when an element's own content
       changes size (a new cluster, a longer street name, a gauge column that grew).
       ------------------------------------------------------------------------------------ */

    /* ------------------------------------------------------------------------------------
       The minimap rectangle

       Published as CSS variables so the frame, the street banner and anything docked to the
       map all read one source. Expressed in vh because the game minimap is sized from the
       screen HEIGHT inside a 16:9 safe zone - a percentage of the WIDTH only lines up at one
       aspect ratio, which is why the border used to sit outside the map.

       The base numbers are the geometry qb-hud has shipped for years against these same
       natives; client/minimap.lua drives the game side with the matching values.
       ------------------------------------------------------------------------------------ */

    const MAP_SHAPES = {
        square: { left: 2.5, bottom: 6.3, w: 29.0, h: 18.5 },
        circle: { left: 3.4, bottom: 6.9, w: 27.0, h: 22.9 },
    };

    // The aspect-ratio correction client/minimap.lua applied to the native components, as a
    // fraction of the screen width. Latched from the `minimap` message; the frame has to
    // apply the same shift or it leaves the map on anything wider than 16:9.
    let mapAspect = 0;

    function setMapAspect(value) {
        if (typeof value !== 'number' || !isFinite(value)) return;
        mapAspect = value;
        applyMapGeometry(state.settings && state.settings.minimap);
    }

    function applyMapGeometry(minimap) {
        const root = document.documentElement;
        const base = MAP_SHAPES[(minimap && minimap.shape) || 'square'] || MAP_SHAPES.square;
        const scale = (minimap && minimap.scale) || 1;

        // The player's offsets are a percentage of the screen, matching the sliders and the
        // native calls; the rest of the rectangle is vh.
        const dx = ((minimap && minimap.x) || 0) + mapAspect * 100;
        const dy = (minimap && minimap.y) || 0;

        // The left edge is NOT scaled: client/minimap.lua scales the component's width and
        // height but leaves its origin alone, and the two sides have to agree or the border
        // drifts off the map at any scale but 1.
        U.cssVar(root, '--map-left', `calc(${U.round(base.left, 2)}vh + ${dx}vw)`);
        U.cssVar(root, '--map-bottom', `calc(${U.round(base.bottom, 2)}% + ${dy}vh)`);
        U.cssVar(root, '--map-w', `${U.round(base.w * scale, 2)}vh`);
        U.cssVar(root, '--map-h', `${U.round(base.h * scale, 2)}vh`);
        U.cssVar(root, '--map-radius', (minimap && minimap.shape) === 'circle' ? '50%' : 'var(--radius)');
    }

    const EDGE = 6;                  // px of breathing room at each screen edge
    let clampQueued = false;
    // Signature of everything that can move or resize an element. See the end of
    // applySettings: a change that does not touch it skips the settle passes.
    let lastGeometry = null;

    function clampIntoView() {
        clampQueued = false;

        // Nothing is positioned until the first settings message has been applied. Clamping
        // before that measures elements sitting at their CSS defaults - left:50%, top:50%,
        // no size - and writes corrections computed from positions nobody chose. Those
        // corrections then survive the real layout, which is how a HUD ended up flung into
        // the corners after a server restart.
        if (!state.ready || !state.settings) return;

        const width = window.innerWidth;
        const height = window.innerHeight;
        const nodes = [];

        // Clear every correction first and measure in a second pass. Measuring an element
        // whose neighbour still carries last frame's correction gives the wrong answer.
        for (const key of ELEMENTS) {
            const node = U.el(`el-${key}`);
            if (!node) continue;
            node.style.setProperty('--fix-x', '0px');
            node.style.setProperty('--fix-y', '0px');
            nodes.push(node);
        }

        /*
            Measure EVERY element first, then write. Never interleave.

            A `getBoundingClientRect` after a style write forces the browser to lay the page
            out again, synchronously, before it can answer. Reading and writing inside one
            loop therefore costs one forced reflow PER ELEMENT - and this runs up to three
            times per settings message, so dragging a slider was paying for a dozen of them a
            frame. That is what the HUD "refreshing" on every change actually was.

            Split in two, the whole pass costs exactly one layout.
        */
        const corrections = [];

        for (const node of nodes) {
            const box = node.getBoundingClientRect();
            if (!box.width && !box.height) continue;   // hidden, nothing to clamp

            // An element bigger than the screen cannot be clamped into it, and trying pins it
            // to an edge and leaves it there. Leave it alone and let it overflow.
            if (box.width >= width || box.height >= height) continue;

            let dx = 0;
            let dy = 0;

            if (box.left < EDGE) dx = EDGE - box.left;
            else if (box.right > width - EDGE) dx = Math.min(0, (width - EDGE) - box.right);

            if (box.top < EDGE) dy = EDGE - box.top;
            else if (box.bottom > height - EDGE) dy = Math.min(0, (height - EDGE) - box.bottom);

            // A correction larger than the screen is not a correction, it is a symptom: the
            // element was measured mid-layout, or a custom property it depends on had not
            // arrived. Refusing it means the worst case is an element slightly off the edge
            // for one frame, instead of one thrown into a corner and left there.
            if (Math.abs(dx) > width / 2) dx = 0;
            if (Math.abs(dy) > height / 2) dy = 0;

            if (dx || dy) corrections.push([node, dx, dy]);
        }

        for (const [node, dx, dy] of corrections) {
            if (dx) node.style.setProperty('--fix-x', `${Math.round(dx)}px`);
            if (dy) node.style.setProperty('--fix-y', `${Math.round(dy)}px`);
        }
    }

    /*
        Queue one clamp for the next frame.

        The guard is a latch, and a latch needs a way out. requestAnimationFrame does not fire
        while the page is not being composited - the game minimised, alt-tabbed, or the HUD
        hidden under a menu - so a clamp queued at that moment never ran, `clampQueued` stayed
        true, and every later call returned immediately. The clamp was then dead for the rest
        of the session, silently, and the HUD stopped correcting itself back on screen.

        So a timer runs alongside as the escape. Whichever arrives first does the work and
        clears the latch; the other finds nothing queued and returns.
    */
    function scheduleClamp() {
        if (clampQueued) return;
        clampQueued = true;

        const run = () => { if (clampQueued) clampIntoView(); };
        requestAnimationFrame(run);
        setTimeout(run, 250);
    }

    /* ------------------------------------------------------------------------------------
       The last frame the game sent

       Kept so that anything which REBUILDS a display can paint it immediately instead of
       waiting for the next tick. Both slots existed and were never written; they are what
       makes a settings change look instant rather than like a reload.
       ------------------------------------------------------------------------------------ */

    /** Store the tick payload. Called by app.js on every tick, before it renders. */
    function remember(data) {
        if (data) state.tick = data;
    }

    /** Re-apply the last payload to the gauges and the cluster. Safe to call at any time:
     *  with no tick yet it does nothing, and every renderer it calls is idempotent. */
    function repaint() {
        const data = state.tick;
        if (!data || !state.settings) return;

        Status.update(data, state.settings);
        if (data.vehicle) Speedo.update(data.vehicle, state.settings);
    }

    // Re-clamp when an element's own content changes size. ResizeObserver is what makes this
    // work for the speedometer, whose face is swapped for one 120px taller with no settings
    // change the observer could otherwise hook.
    if (typeof ResizeObserver === 'function') {
        const observer = new ResizeObserver(() => scheduleClamp());

        const observeAll = () => {
            for (const key of ELEMENTS) {
                const node = U.el(`el-${key}`);
                if (node) observer.observe(node);
            }
        };

        // Bound both ways round. A NUI page's scripts usually run AFTER DOMContentLoaded has
        // already fired, so waiting for that event alone leaves nothing observed - and then a
        // speedometer swapped for a taller one never re-clamps.
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', observeAll);
        } else {
            observeAll();
        }
    }

    window.addEventListener('resize', () => scheduleClamp());

    function applySettings(settings) {
        if (!settings) return;
        state.settings = settings;

        const root = document.documentElement;
        const hud = U.el('hud');

        /* Colours. Written one by one rather than as a block so that the browser only
           invalidates the properties that actually moved. */
        const colours = settings.colours || {};
        for (const [key, value] of Object.entries(colours)) {
            U.cssVar(root, `--c-${key === 'background' ? 'bg' : key}`, value);
        }

        /* Derived colours. A panel that is a fixed grey clashes with every theme but one, so
           it is mixed from the player's own background instead. */
        const bg = colours.background || '#0b0f14';
        const text = colours.text || '#f8fafc';
        const style = settings.style || {};

        /* The surface.
           Glass is a translucent GRADIENT, never a backdrop-filter: CEF composites the NUI
           over the finished frame, so a backdrop filter has nothing behind it to blur and
           paints solid black. The `blur` setting drives the gradient's softness and the
           edge highlight instead, which is the part of "frosted" that actually reads. */
        const surface = style.surface || 'glass';
        const SURFACE_ALPHA = { glass: 0.42, tint: 0.7, solid: 0.97, none: 0 };
        const alpha = SURFACE_ALPHA[surface] === undefined ? 0.82 : SURFACE_ALPHA[surface];
        const frost = U.clamp(style.blur === undefined ? 16 : style.blur, 0, 32) / 32;

        U.cssVar(root, '--c-panel', U.alpha(bg, alpha));
        U.cssVar(root, '--c-panel-solid', bg);
        U.cssVar(root, '--frost', frost);
        U.cssVar(root, '--c-line', U.alpha(text, surface === 'glass' ? 0.26 : 0.14));
        U.cssVar(root, '--c-line-strong', U.alpha(text, 0.34));
        U.cssVar(root, '--c-track', U.alpha(text, 0.14));
        U.cssVar(root, '--c-muted', U.alpha(text, 0.6));
        U.attr(hud, 'data-surface', surface);

        /* Blended colours.
           CSS color-mix() is dropped as invalid by FiveM's CEF - it predates Chromium 111 -
           so every blend the stylesheets want is computed here and published as a plain
           value. The names say what they are: `-aNN` is that colour at NN% alpha, `-dNN` is
           it darkened to NN% of itself over black. */
        const alphas = {
            accent: [8, 10, 12, 18, 20, 28, 30, 40, 55, 60],
            health: [10, 20, 28, 55],
            warning: [20, 32, 60],
            rpm: [60],
            fuel: [55],
        };
        for (const [key, steps] of Object.entries(alphas)) {
            const hex = colours[key] || '#ffffff';
            for (const step of steps) {
                U.cssVar(root, `--c-${key}-a${step}`, U.alpha(hex, step / 100));
            }
        }

        for (const step of [76, 88, 92, 94]) {
            U.cssVar(root, `--c-bg-d${step}`, U.mix(bg, '#000000', step));
        }

        // The settings panel: the player's background, warmed by a trace of their accent at
        // the top and shaded at the bottom, so it reads as a lit surface rather than a slab.
        U.cssVar(root, '--c-panel-tint', U.mix(bg, colours.accent || '#ffffff', 94));
        U.cssVar(root, '--c-panel-shade', U.mix(bg, '#000000', 88));

        /* Shape and scale.
           Two radii, and they are separate for a reason. `corner` is the GAUGE radius and the
           neon theme sets it to 999 to mean "fully round". Feeding that to the panels as well
           turned the settings panel into a 1000px circle, so the panel radius is the same
           value clamped to something a rectangle can wear. */
        const corner = style.corner === 999 ? 999 : U.clamp(style.corner, 0, 24);
        U.cssVar(root, '--gauge-radius', corner === 999 ? '999px' : `${corner}px`);
        U.cssVar(root, '--radius', `${Math.min(corner, 24)}px`);
        U.cssVar(root, '--gap', `${style.gap === undefined ? 8 : style.gap}px`);
        U.cssVar(root, '--hud-scale', settings.scale || 1);
        U.cssVar(root, '--hud-opacity', settings.opacity === undefined ? 1 : settings.opacity);
        U.cssVar(root, '--cine-height', `${(state.cineHeight || 0.12) * 100}%`);

        /* Flags the stylesheets branch on. */
        U.attr(hud, 'data-compact', !!settings.compact);
        U.attr(hud, 'data-glow', !!style.glow);
        U.attr(hud, 'data-outline', style.outline !== false);
        U.attr(hud, 'data-cinematic', !!settings.cinematic);

        const menu = U.el('menu');
        U.attr(menu, 'data-glow', !!style.glow);

        /* Positions. */
        for (const key of ELEMENTS) {
            const node = U.el(`el-${key}`);
            if (!node) continue;

            const position = (settings.positions || {})[key]
                || { x: 50, y: 50, anchor: 'left', anchorY: 'top', dock: 'free' };
            let dock = position.dock || 'free';

            // A round map gets its gauges on an arc that follows the curve rather than a
            // straight column standing beside a circle. Derived rather than stored, so it
            // follows the map shape without the player having to set it twice.
            if (key === 'status' && dock === 'map-right'
                && (settings.minimap || {}).shape === 'circle') {
                dock = 'map-arc';
            }

            U.attr(node, 'data-dock', dock);
            U.attr(node, 'data-anchor', position.anchor || 'left');
            U.attr(node, 'data-anchor-y', position.anchorY || 'top');

            if (dock === 'free') {
                node.style.left = `${position.x}%`;
                node.style.top = `${position.y}%`;
                node.style.right = '';
                node.style.bottom = '';
            } else {
                // The dock rules in hud.css own every edge; leaving an inline left/top here
                // would win the cascade and the element would ignore its dock.
                node.style.left = '';
                node.style.top = '';
                node.style.right = '';
                node.style.bottom = '';
            }

            if (key === 'status') Status.setArc(dock === 'map-arc');

            const showKey = ELEMENT_VISIBILITY[key];
            if (showKey) {
                U.attr(node, 'data-visible', !!(settings.show || {})[showKey]);
            }
        }

        scheduleClamp();

        applyMapGeometry(settings.minimap);

        /* The street banner can be sized to the minimap rather than to its own content. */
        const streets = settings.streets || {};
        U.attr(U.el('streets'), 'data-match', !!streets.matchMap);
        U.attr(U.el('streets'), 'data-upper', !!streets.uppercase);

        /* Sub-renderers that need to know the shape changed. */
        Status.render(settings);
        Speedo.setStyle(settings.speedometer ? settings.speedometer.style : 'minimal');
        Compass.setStyle(settings.compass ? settings.compass.style : 'bar');

        /*
            Repaint what was just rebuilt, now, from the last payload the game sent.

            A gauge shape or a speedometer face is REBUILT here and left empty, because the
            values only arrive on the tick. At 30fps that is 33ms of blank dial after every
            change - and since a change is exactly when the player is looking at the thing
            they changed, it reads as the HUD flickering rather than as one dropped frame.

            The tick is remembered by app.js on the way past, so this costs one extra apply of
            data already in memory: no message, no network, no measurement.
        */
        repaint();

        state.ready = true;
        U.attr(U.el('hud'), 'data-ready', true);

        /*
            Settle passes, but only when the GEOMETRY moved.

            The first clamp runs on the next animation frame, when the gauges have been built
            but the browser may not have finished laying them out - a cluster still 0px wide
            measures as nowhere near an edge. Two later passes catch the final geometry.

            They used to run on every settings message. Dragging a colour picker sends one per
            frame, and nothing about a colour can move an element, so the HUD was re-measuring
            and re-nudging itself continuously while the player scrubbed a hue. That is the
            other half of the "it refreshes every time I change something" feeling.

            The signature below lists everything that can change an element's size or place.
            A change to anything else skips the passes entirely.
        */
        const geometry = JSON.stringify([
            settings.scale, settings.compact, settings.positions,
            settings.minimap, settings.style && settings.style.gauge,
            settings.style && settings.style.direction, settings.style && settings.style.gap,
            settings.style && settings.style.corner, settings.style && settings.style.icons,
            settings.style && settings.style.values, settings.speedometer && settings.speedometer.style,
            settings.compass && settings.compass.style, settings.show, settings.streets,
        ]);

        if (geometry !== lastGeometry) {
            lastGeometry = geometry;
            scheduleClamp();
            setTimeout(scheduleClamp, 120);
            setTimeout(scheduleClamp, 600);
        }
    }

    /* ------------------------------------------------------------------------------------
       Boot
       ------------------------------------------------------------------------------------ */

    function boot(payload) {
        const statik = payload.static || {};

        // Every list in the payload goes through U.asArray. An empty Lua table encodes as a
        // JSON object, so a config list that ships empty - `locked` does - would otherwise
        // arrive as `{}` and break the first array method called on it.
        statik.locked = U.asArray(statik.locked);
        statik.themes = U.asArray(statik.themes);
        statik.speedometers = U.asArray(statik.speedometers);
        statik.layouts = U.asArray(statik.layouts);
        statik.statuses = U.asArray(statik.statuses);

        state.statik = statik;
        state.locked = statik.locked;
        state.cineHeight = (statik.cinematic && statik.cinematic.barHeight) || 0.12;

        Status.build(statik.statuses);
        applySettings(payload.settings);
    }

    return {
        get state() { return state; },
        get settings() { return state.settings; },
        get statik() { return state.statik; },
        t, choices, isLocked, get, set, setMany, applySettings, boot,
        setMapAspect, scheduleClamp, remember, repaint, flushPost,
        ELEMENTS,
    };

})();
