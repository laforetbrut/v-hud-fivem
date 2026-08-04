/*
    js/layout.js

    The drag editor.

    Each HUD element gets a ghost drawn over it: a dashed box the player grabs. The ghost is
    separate from the element rather than the element being made draggable, for two reasons.
    An element that is currently invisible - the speedometer while on foot, the money row
    between changes - still has to be movable, and a ghost can be given a minimum size so a
    one-line street name is not a two-pixel drag target.

    Positions are written as a percentage of the viewport, so a layout arranged at 1080p is in
    the same relative place at 1440p and on an ultrawide.
*/

const Layout = (() => {

    const SNAP = 1;                  // percent, when snapping is on
    const MIN_GHOST = 44;            // px, the smallest a drag target may be

    let overlay = null;
    let open = false;
    let snap = true;
    const ghosts = new Map();

    /* ------------------------------------------------------------------------------------
       Ghosts
       ------------------------------------------------------------------------------------ */

    function labelFor(key) {
        return S.t(`layout.group_${key === 'speedo' ? 'speedo' : key}`);
    }

    /**
     * Put a ghost exactly where its element actually IS.
     *
     * Measured from the live element, never rebuilt from the stored x/y. Those two agree only
     * for a free element at scale 1: a docked element ignores its x/y entirely and follows the
     * minimap, a clamped element carries a --fix offset, and everything is scaled by
     * --hud-scale. Reconstructing the position from the settings drew the grab boxes somewhere
     * near the elements rather than on them.
     */
    function position(ghost, key) {
        const node = U.el(`el-${key}`);
        if (!node) return;

        const box = node.getBoundingClientRect();

        // An element with no size right now - the speedometer on foot, a cluster with every
        // gauge switched off - still has to be grabbable, so it gets a minimum box centred on
        // wherever it sits.
        const width = Math.max(box.width, MIN_GHOST);
        const height = Math.max(box.height, MIN_GHOST);
        const left = box.width ? box.left : box.left - (width - box.width) / 2;
        const top = box.height ? box.top : box.top - (height - box.height) / 2;

        ghost.style.left = `${Math.round(left)}px`;
        ghost.style.top = `${Math.round(top)}px`;
        ghost.style.width = `${Math.round(width)}px`;
        ghost.style.height = `${Math.round(height)}px`;
        ghost.style.transform = 'none';

        // A docked element cannot be positioned by dragging until it is let go of the map, so
        // it says which edge it is glued to.
        const dock = node.getAttribute('data-dock') || 'free';
        U.attr(ghost, 'data-docked', dock !== 'free');
    }

    /* The minimap gets a ghost too.
       It is not a `positions` entry - it is the game's own map, moved through
       `minimap.x` / `minimap.y` - so it is dragged separately and writes different settings.
       But from the player's side it is one more box to grab, which is the point: "move the
       HUD" that cannot move the map is a half-finished editor. */
    let mapGhost = null;

    function positionMapGhost() {
        if (!mapGhost) return;
        const frame = U.el('minimap-frame');
        if (!frame) return;

        const box = frame.getBoundingClientRect();
        mapGhost.style.left = `${box.left}px`;
        mapGhost.style.top = `${box.top}px`;
        mapGhost.style.width = `${box.width}px`;
        mapGhost.style.height = `${box.height}px`;
        mapGhost.style.transform = 'none';
    }

    function startMapDrag(event) {
        event.preventDefault();
        const box = mapGhost.getBoundingClientRect();

        drag = {
            map: true,
            ghost: mapGhost,
            offsetX: event.clientX - box.left,
            offsetY: event.clientY - box.top,
            width: box.width,
            height: box.height,
            // The offsets the map already carries; the drag adds its delta to them.
            baseX: S.get('minimap.x', 0),
            baseY: S.get('minimap.y', 0),
            startLeft: box.left,
            startTop: box.top,
        };

        U.attr(mapGhost, 'data-dragging', true);
        mapGhost.setPointerCapture(event.pointerId);
    }

    function build() {
        overlay = U.el('layout');
        if (!overlay) return;

        for (const [, ghost] of ghosts) ghost.remove();
        ghosts.clear();
        if (mapGhost) { mapGhost.remove(); mapGhost = null; }

        mapGhost = U.make('div', { class: 'ghost ghost--map', 'data-key': 'minimap' }, [
            U.make('span', { class: 'ghost__label', text: S.t('element.minimap') }),
        ]);
        mapGhost.addEventListener('pointerdown', startMapDrag);
        overlay.appendChild(mapGhost);
        positionMapGhost();

        for (const key of S.ELEMENTS) {
            const ghost = U.make('div', { class: 'ghost', 'data-key': key }, [
                U.make('span', { class: 'ghost__label', text: labelFor(key) }),
            ]);

            ghost.addEventListener('pointerdown', (event) => startDrag(event, key, ghost));
            overlay.appendChild(ghost);
            ghosts.set(key, ghost);
            position(ghost, key);
        }
    }

    /* ------------------------------------------------------------------------------------
       Dragging
       ------------------------------------------------------------------------------------ */

    let drag = null;

    function startDrag(event, key, ghost) {
        event.preventDefault();

        const box = ghost.getBoundingClientRect();
        drag = {
            key,
            ghost,
            offsetX: event.clientX - box.left,
            offsetY: event.clientY - box.top,
            width: box.width,
            height: box.height,
        };

        U.attr(ghost, 'data-dragging', true);
        ghost.setPointerCapture(event.pointerId);
    }

    function onMove(event) {
        if (!drag) return;

        const width = window.innerWidth;
        const height = window.innerHeight;

        if (drag.map) {
            // The map moves through its own offsets, in percent of the screen, and positive
            // Y means UP - the same convention the sliders and the natives use, so all three
            // agree and the border never leaves the map.
            let left = U.clamp(event.clientX - drag.offsetX, 0, width - drag.width);
            let top = U.clamp(event.clientY - drag.offsetY, 0, height - drag.height);

            const bounds = (S.statik.bounds) || {};
            const bx = bounds.minimapX || { min: -20, max: 20 };
            const by = bounds.minimapY || { min: -20, max: 20 };

            let x = drag.baseX + ((left - drag.startLeft) / width) * 100;
            let y = drag.baseY - ((top - drag.startTop) / height) * 100;

            if (snap) { x = Math.round(x * 4) / 4; y = Math.round(y * 4) / 4; }

            S.setMany({
                'minimap.x': U.round(U.clamp(x, bx.min, bx.max), 2),
                'minimap.y': U.round(U.clamp(y, by.min, by.max), 2),
            });

            // Re-measure rather than trusting the pointer: the offsets are clamped, so the
            // map can stop moving while the mouse keeps going.
            requestAnimationFrame(() => { positionMapGhost(); refresh(); });
            return;
        }

        let left = event.clientX - drag.offsetX;
        let top = event.clientY - drag.offsetY;

        // Keep the element on screen. Clamping the box rather than the anchor point is what
        // stops a right-anchored element being dragged half off the right edge.
        left = U.clamp(left, 0, width - drag.width);
        top = U.clamp(top, 0, height - drag.height);

        // Both anchors are chosen by where the element ended up. An element dropped in the
        // right third pins to its right edge, one dropped in the bottom half pins to its
        // bottom edge - so it stays where the player put it when the window is resized, and
        // grows the right way when its content gets bigger.
        const centreX = (left + drag.width / 2) / width;
        const centreY = (top + drag.height / 2) / height;
        const anchor = centreX > 0.66 ? 'right' : (centreX < 0.34 ? 'left' : 'center');
        const anchorY = centreY > 0.5 ? 'bottom' : 'top';

        // The stored position is the element's ANCHOR POINT. --hud-scale grows the box away
        // from that point rather than moving it, so the ghost's on-screen edges ARE the
        // anchor points and no scale correction is needed: box.left for a left anchor,
        // box.right for a right one, box.bottom for a bottom one.
        let x;
        if (anchor === 'right') x = ((left + drag.width) / width) * 100;
        else if (anchor === 'center') x = ((left + drag.width / 2) / width) * 100;
        else x = (left / width) * 100;

        let y = anchorY === 'bottom'
            ? ((top + drag.height) / height) * 100
            : (top / height) * 100;

        if (snap) {
            x = Math.round(x / SNAP) * SNAP;
            y = Math.round(y / SNAP) * SNAP;
        }

        x = U.round(U.clamp(x, 0, 100), 2);
        y = U.round(U.clamp(y, 0, 100), 2);

        S.setMany({
            [`positions.${drag.key}.x`]: x,
            [`positions.${drag.key}.y`]: y,
            [`positions.${drag.key}.anchor`]: anchor,
            [`positions.${drag.key}.anchorY`]: anchorY,
            // Dragging is how a player says "not there". An element glued to the minimap has
            // to let go the moment it is moved, or it would snap straight back.
            [`positions.${drag.key}.dock`]: 'free',
        });

        position(drag.ghost, drag.key);
    }

    function endDrag() {
        if (!drag) return;
        U.attr(drag.ghost, 'data-dragging', false);
        drag = null;

        // Send the final position now rather than waiting out the coalescing delay. The moves
        // during a drag are merged into one message; letting go is when it is owed.
        S.flushPost();
    }

    /* ------------------------------------------------------------------------------------
       Open and close
       ------------------------------------------------------------------------------------ */

    function setOpen(on) {
        overlay = overlay || U.el('layout');
        if (!overlay) return;

        // Idempotent, because the close path can reach here from three directions and each
        // one used to post `layoutMode` and earn another "layout saved" toast.
        if (!!on === open) return;

        // Whatever direction the close came from, nothing may be left sitting in the
        // coalescing buffer: closing the editor is the last chance to send it.
        if (!on) S.flushPost();

        open = !!on;
        overlay.hidden = !open;
        U.attr(overlay, 'data-snap', snap);

        if (open) {
            build();
            U.text(U.el('layout-hint'), S.t('layout.editing'));
            U.text(U.el('layout-snap-label'), S.t('layout.snap'));
            U.text(U.el('layout-reset'), S.t('layout.reset'));
            U.text(U.el('layout-done'), S.t('menu.done'));
        }

        U.post('layoutMode', { on: open });
    }

    /** Re-place every ghost. Called after a preset is applied while the editor is open. */
    function refresh() {
        if (!open) return;
        for (const [key, ghost] of ghosts) position(ghost, key);
        positionMapGhost();
    }

    function bind() {
        overlay = U.el('layout');
        if (!overlay) return;

        window.addEventListener('pointermove', onMove);
        window.addEventListener('pointerup', endDrag);
        window.addEventListener('pointercancel', endDrag);

        const snapBox = U.el('layout-snap');
        if (snapBox) {
            snapBox.addEventListener('change', () => {
                snap = snapBox.checked;
                U.attr(overlay, 'data-snap', snap);
            });
        }

        const done = U.el('layout-done');
        if (done) done.addEventListener('click', () => setOpen(false));

        const reset = U.el('layout-reset');
        if (reset) {
            reset.addEventListener('click', () => {
                U.post('resetSection', { section: 'positions' });
            });
        }

        // A resize invalidates every ghost box at once.
        window.addEventListener('resize', U.debounce(refresh, 120));
    }

    return { bind, setOpen, refresh, get open() { return open; } };

})();
