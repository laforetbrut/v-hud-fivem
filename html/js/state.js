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
        U.post('setPaths', { changes });
    }

    /* ------------------------------------------------------------------------------------
       Applying settings to the document
       ------------------------------------------------------------------------------------ */

    const ELEMENTS = ['status', 'speedo', 'compass', 'streets', 'money', 'voice', 'vehicle'];

    // Which `show` key decides whether each positioned element is drawn. `status` has none:
    // it is drawn whenever at least one gauge inside it is on, which status.js works out.
    const ELEMENT_VISIBILITY = {
        speedo: 'speedometer',
        compass: 'compass',
        streets: 'streets',
        money: 'money',
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

    const EDGE = 6;                  // px of breathing room at each screen edge
    let clampQueued = false;

    function clampIntoView() {
        clampQueued = false;

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

        for (const node of nodes) {
            const box = node.getBoundingClientRect();
            if (!box.width && !box.height) continue;   // hidden, nothing to clamp

            let dx = 0;
            let dy = 0;

            if (box.left < EDGE) dx = EDGE - box.left;
            else if (box.right > width - EDGE) dx = Math.min(0, (width - EDGE) - box.right);

            if (box.top < EDGE) dy = EDGE - box.top;
            else if (box.bottom > height - EDGE) dy = Math.min(0, (height - EDGE) - box.bottom);

            if (dx) node.style.setProperty('--fix-x', `${Math.round(dx)}px`);
            if (dy) node.style.setProperty('--fix-y', `${Math.round(dy)}px`);
        }
    }

    function scheduleClamp() {
        if (clampQueued) return;
        clampQueued = true;
        requestAnimationFrame(clampIntoView);
    }

    // Re-clamp when an element's own content changes size. ResizeObserver is what makes this
    // work for the speedometer, whose face is swapped for one 120px taller with no settings
    // change the observer could otherwise hook.
    if (typeof ResizeObserver === 'function') {
        const observer = new ResizeObserver(() => scheduleClamp());
        document.addEventListener('DOMContentLoaded', () => {
            for (const key of ELEMENTS) {
                const node = U.el(`el-${key}`);
                if (node) observer.observe(node);
            }
        });
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

        /* The surface. Each mode is one alpha and one filter, and picking them here rather
           than in CSS is what lets the blur radius be a slider. */
        const surface = style.surface || 'glass';
        const SURFACE_ALPHA = { glass: 0.34, tint: 0.7, solid: 0.97, none: 0 };
        const alpha = SURFACE_ALPHA[surface] === undefined ? 0.82 : SURFACE_ALPHA[surface];

        U.cssVar(root, '--c-panel', U.alpha(bg, alpha));
        U.cssVar(root, '--c-panel-solid', bg);
        U.cssVar(root, '--panel-blur', surface === 'glass' ? `blur(${style.blur || 16}px) saturate(1.4)` : 'none');
        U.cssVar(root, '--c-line', U.alpha(text, surface === 'glass' ? 0.24 : 0.14));
        U.cssVar(root, '--c-line-strong', U.alpha(text, 0.34));
        U.cssVar(root, '--c-track', U.alpha(text, 0.14));
        U.cssVar(root, '--c-muted', U.alpha(text, 0.6));
        U.attr(hud, 'data-surface', surface);

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
                || { x: 50, y: 50, anchor: 'left', anchorY: 'top' };
            node.style.left = `${position.x}%`;
            node.style.top = `${position.y}%`;
            U.attr(node, 'data-anchor', position.anchor || 'left');
            U.attr(node, 'data-anchor-y', position.anchorY || 'top');

            const showKey = ELEMENT_VISIBILITY[key];
            if (showKey) {
                U.attr(node, 'data-visible', !!(settings.show || {})[showKey]);
            }
        }

        scheduleClamp();

        /* The street banner can be sized to the minimap rather than to its own content. */
        const streets = settings.streets || {};
        U.attr(U.el('streets'), 'data-match', !!streets.matchMap);
        U.attr(U.el('streets'), 'data-upper', !!streets.uppercase);

        /* Sub-renderers that need to know the shape changed. */
        Status.render(settings);
        Speedo.setStyle(settings.speedometer ? settings.speedometer.style : 'minimal');
        Compass.setStyle(settings.compass ? settings.compass.style : 'bar');

        state.ready = true;
        U.attr(U.el('hud'), 'data-ready', true);
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
        t, isLocked, get, set, setMany, applySettings, boot,
        ELEMENTS,
    };

})();
