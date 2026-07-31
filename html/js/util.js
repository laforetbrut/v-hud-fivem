/*
    js/util.js

    The small helpers every other file uses. No state, no DOM caching, nothing that has to be
    torn down. Loaded first because everything below it assumes `U` exists.
*/

const U = (() => {

    const SVG_NS = 'http://www.w3.org/2000/svg';

    /* ------------------------------------------------------------------------------------
       DOM
       ------------------------------------------------------------------------------------ */

    const el = (id) => document.getElementById(id);

    /**
     * Build an element. `attrs` sets attributes, except `class`, `text` and `html`, which do
     * the obvious thing, and any key starting with `on`, which binds a listener.
     */
    function make(tag, attrs = {}, children = []) {
        const node = document.createElement(tag);
        applyAttrs(node, attrs);
        append(node, children);
        return node;
    }

    /** The same, in the SVG namespace. createElement produces an inert element for SVG. */
    function svg(tag, attrs = {}, children = []) {
        const node = document.createElementNS(SVG_NS, tag);
        applyAttrs(node, attrs, true);
        append(node, children);
        return node;
    }

    function applyAttrs(node, attrs, isSvg) {
        for (const [key, value] of Object.entries(attrs)) {
            if (value === null || value === undefined || value === false) continue;

            if (key === 'class') {
                node.setAttribute('class', value);
            } else if (key === 'text') {
                node.textContent = value;
            } else if (key === 'html') {
                node.innerHTML = value;
            } else if (key === 'style' && typeof value === 'object') {
                Object.assign(node.style, value);
            } else if (key.startsWith('on') && typeof value === 'function') {
                node.addEventListener(key.slice(2).toLowerCase(), value);
            } else if (isSvg) {
                node.setAttributeNS(null, key, value);
            } else {
                node.setAttribute(key, value);
            }
        }
    }

    function append(node, children) {
        const list = Array.isArray(children) ? children : [children];
        for (const child of list) {
            if (child === null || child === undefined || child === false) continue;
            node.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
        }
    }

    /** Replace a node's children in one operation rather than clearing and appending. */
    function fill(node, children) {
        node.textContent = '';
        append(node, children);
    }

    /**
     * Set an attribute only when it changed. Every tick writes a dozen of these and the
     * browser invalidates style on each write, including the ones that set what was already
     * there - which, standing still, is all of them.
     */
    function attr(node, name, value) {
        if (!node) return;
        const next = String(value);
        if (node.getAttribute(name) === next) return;
        node.setAttribute(name, next);
    }

    /**
     * Show or hide with the `hidden` attribute.
     *
     * This exists because `attr(node, 'hidden', false)` writes hidden="false", and `hidden` is
     * a boolean attribute: its PRESENCE hides the element, whatever the value says. Setting it
     * to "false" hides the element just as firmly as setting it to "true", which is a bug that
     * reads as "the chip never comes back" and takes a while to see.
     */
    function show(node, visible) {
        if (!node) return;
        if (visible) node.removeAttribute('hidden');
        else if (!node.hasAttribute('hidden')) node.setAttribute('hidden', '');
    }

    /** The same guard for text. */
    function text(node, value) {
        if (!node) return;
        const next = String(value);
        if (node.textContent === next) return;
        node.textContent = next;
    }

    /** The same guard for a custom property. */
    function cssVar(node, name, value) {
        if (!node) return;
        const next = String(value);
        if (node.style.getPropertyValue(name) === next) return;
        node.style.setProperty(name, next);
    }

    /**
     * Whatever came over from Lua, as an array.
     *
     * This is not defensiveness for its own sake. An EMPTY Lua table has no way to say whether
     * it was meant to be a list or a map, and json.encode writes it as `{}` - so a config list
     * that happens to be empty arrives here as an object and every array method on it throws.
     * Config.Policy.locked ships empty, so that is the default install.
     *
     * A non-empty list arrives as a real array and passes straight through.
     */
    function asArray(value) {
        if (Array.isArray(value)) return value;
        if (value && typeof value === 'object') return Object.values(value);
        return [];
    }

    /* ------------------------------------------------------------------------------------
       Numbers
       ------------------------------------------------------------------------------------ */

    const clamp = (value, min, max) => Math.min(max, Math.max(min, Number(value) || 0));

    /** 0-1 of the way from `min` to `max`, clamped. */
    const ratio = (value, min, max) => clamp((value - min) / (max - min), 0, 1);

    const round = (value, places = 0) => {
        const factor = 10 ** places;
        return Math.round((Number(value) || 0) * factor) / factor;
    };

    /**
     * Group thousands with `separator`. Intl.NumberFormat would do this, but it allocates a
     * formatter per call unless one is cached per locale, and this runs on every money event.
     */
    function money(value, separator = ' ') {
        const number = Math.abs(Math.round(Number(value) || 0));
        const sign = (Number(value) || 0) < 0 ? '-' : '';
        return sign + String(number).replace(/\B(?=(\d{3})+(?!\d))/g, separator);
    }

    /* ------------------------------------------------------------------------------------
       Colour
       ------------------------------------------------------------------------------------ */

    /** `#rrggbb` to {r,g,b}. Anything else comes back as mid grey rather than as null, so no
     *  caller has to guard, and a bad colour is visible rather than crashing a render. */
    function rgb(hex) {
        const match = /^#?([\da-f]{6})$/i.exec(String(hex || ''));
        if (!match) return { r: 128, g: 128, b: 128 };

        const int = parseInt(match[1], 16);
        return { r: (int >> 16) & 255, g: (int >> 8) & 255, b: int & 255 };
    }

    /** `rgba()` from a hex and an alpha. Used for the derived panel and track colours. */
    function alpha(hex, a) {
        const { r, g, b } = rgb(hex);
        return `rgba(${r}, ${g}, ${b}, ${a})`;
    }

    /** Perceived brightness, 0-255. Decides whether text over a colour should be black. */
    function luminance(hex) {
        const { r, g, b } = rgb(hex);
        return 0.299 * r + 0.587 * g + 0.114 * b;
    }

    /**
     * Blend two hex colours: `pct` percent of `a`, the rest of `b`. Returns `#rrggbb`.
     *
     * This exists because CSS `color-mix()` DOES NOT WORK in FiveM. Its CEF is built on an
     * older Chromium than the one that shipped color-mix (111), so every declaration using it
     * is dropped as invalid - which is why the settings panel rendered with no background at
     * all and the game showed straight through it. Anything that needs a blended colour is
     * computed here and published as a plain custom property instead.
     */
    function mix(a, b, pct) {
        const ca = rgb(a);
        const cb = rgb(b);
        const t = clamp(pct, 0, 100) / 100;
        const channel = (x, y) => Math.round(x * t + y * (1 - t));
        const hex = (n) => n.toString(16).padStart(2, '0');

        return `#${hex(channel(ca.r, cb.r))}${hex(channel(ca.g, cb.g))}${hex(channel(ca.b, cb.b))}`;
    }

    /* ------------------------------------------------------------------------------------
       SVG geometry
       ------------------------------------------------------------------------------------ */

    /** A point on a circle, with 0 degrees at twelve o'clock and angles going clockwise. */
    function polar(cx, cy, radius, degrees) {
        const rad = ((degrees - 90) * Math.PI) / 180;
        return { x: cx + radius * Math.cos(rad), y: cy + radius * Math.sin(rad) };
    }

    /** An arc path from `startDeg` to `endDeg`, for a stroked (not filled) arc. */
    function arcPath(cx, cy, radius, startDeg, endDeg) {
        const start = polar(cx, cy, radius, endDeg);
        const end = polar(cx, cy, radius, startDeg);
        const large = endDeg - startDeg <= 180 ? 0 : 1;
        return `M ${start.x} ${start.y} A ${radius} ${radius} 0 ${large} 0 ${end.x} ${end.y}`;
    }

    /** The circumference of a circle, which is the dasharray a progress ring needs. */
    const circumference = (radius) => 2 * Math.PI * radius;

    /* ------------------------------------------------------------------------------------
       Timing
       ------------------------------------------------------------------------------------ */

    /** Call `fn` at most once per `ms`, with the last call winning. */
    function debounce(fn, ms) {
        let timer = null;
        return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => fn(...args), ms);
        };
    }

    /* ------------------------------------------------------------------------------------
       Share codes

       A settings export is a string a player can paste into Discord, so it has to survive
       being copied out of a chat message: no newlines, no quotes, nothing a client will turn
       into a smart quote. Base64 over UTF-8, with the padding stripped and a version prefix
       so a future format change can be recognised rather than silently mis-parsed.
       ------------------------------------------------------------------------------------ */

    const SHARE_PREFIX = 'VHUD1:';

    /** UTF-8 safe base64. btoa() alone throws on any character above U+00FF, and the French
     *  locale is full of them. */
    function encodeShare(value) {
        const json = JSON.stringify(value);
        const bytes = new TextEncoder().encode(json);

        let binary = '';
        for (const byte of bytes) binary += String.fromCharCode(byte);

        return SHARE_PREFIX + btoa(binary).replace(/=+$/, '');
    }

    /** The inverse. Returns null for anything that is not one of our codes, rather than
     *  throwing - a player pasting the wrong thing is a normal event, not an error. */
    function decodeShare(text) {
        if (typeof text !== 'string') return null;

        const trimmed = text.trim().replace(/\s+/g, '');
        if (!trimmed.startsWith(SHARE_PREFIX)) return null;

        try {
            const body = trimmed.slice(SHARE_PREFIX.length);
            const binary = atob(body + '='.repeat((4 - (body.length % 4)) % 4));

            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);

            const parsed = JSON.parse(new TextDecoder().decode(bytes));
            return (parsed && typeof parsed === 'object') ? parsed : null;
        } catch (error) {
            return null;
        }
    }

    /**
     * Put text on the clipboard.
     *
     * `navigator.clipboard` needs a secure context and a permission CEF does not always
     * grant, so the old execCommand path is the one that actually works in NUI. The textarea
     * is off screen and removed immediately.
     */
    function copyText(text) {
        const area = document.createElement('textarea');
        area.value = text;
        area.setAttribute('readonly', '');
        area.style.cssText = 'position:fixed;top:-1000px;left:-1000px;opacity:0;';
        document.body.appendChild(area);

        area.select();
        area.setSelectionRange(0, text.length);

        let ok = false;
        try { ok = document.execCommand('copy'); } catch (error) { ok = false; }

        area.remove();
        return ok;
    }

    /* ------------------------------------------------------------------------------------
       NUI
       ------------------------------------------------------------------------------------ */

    const RESOURCE = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName()
        : 'v-hud';

    /**
     * Post to the Lua side. Failures are swallowed: the page is also opened directly in a
     * browser during development, where there is no NUI endpoint and every fetch rejects.
     */
    function post(name, data = {}) {
        return fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        }).catch(() => {});
    }

    /** Whether the page is running inside the game. False when opened in a plain browser. */
    const inGame = typeof GetParentResourceName === 'function';

    return {
        SVG_NS, el, make, svg, fill, attr, text, cssVar, append, show, asArray,
        clamp, ratio, round, money,
        rgb, alpha, luminance, mix,
        polar, arcPath, circumference,
        debounce, post, inGame, RESOURCE,
        encodeShare, decodeShare, copyText, SHARE_PREFIX,
    };

})();
