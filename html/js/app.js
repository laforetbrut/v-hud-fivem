/*
    js/app.js

    The message router. One `message` listener, one switch, and every branch is three lines
    that hand off to the module that owns that thing.

    Keeping the routing in one place is what makes the message contract with Lua readable:
    everything the game can say to the page is listed here, in one switch, and a message with
    no branch is a message that was never implemented rather than one that was silently
    swallowed somewhere.
*/

(() => {

    /* ------------------------------------------------------------------------------------
       Per-tick painting
       ------------------------------------------------------------------------------------ */

    let lastVehicle = null;

    function onTick(data) {
        const settings = S.settings;
        if (!settings) return;

        const hud = U.el('hud');
        U.attr(hud, 'data-hidden', data.show === false);
        U.attr(hud, 'data-faded', data.faded === true);

        Status.update(data, settings);

        if (data.vehicle) {
            Speedo.update(data.vehicle, settings);
            lastVehicle = data.vehicle;
        } else if (lastVehicle) {
            Speedo.hide();
            lastVehicle = null;
        }

        // Voice.
        const voice = U.el('voice');
        if (voice) {
            U.attr(voice, 'data-range', Math.round(data.voiceRange || 0));
            U.attr(voice, 'data-talking', !!data.talking);
            U.attr(voice, 'data-radio', !!data.radioActive);
            U.text(U.el('voice-radio'), data.radio ? String(data.radio) : '');
        }

        // The vehicle extras strip: what does not fit on the speedometer face.
        const extras = U.el('el-vehicle');
        if (extras) {
            const relevant = !!data.vehicle || data.parachute >= 0 || data.armed;
            U.attr(extras, 'data-visible', relevant);
            renderExtras(data);
        }
    }

    const EXTRA_ICONS = {
        armed: 'M4 14l7-7 3 3-7 7H4v-3zM14 4l6 6-3 3-6-6 3-3z',
        parachute: 'M12 3a9 9 0 0 0-9 9h18a9 9 0 0 0-9-9zM3 12l9 9 9-9M12 12v9',
        dev: 'M8 6 2 12l6 6M16 6l6 6-6 6M13 4l-2 16',
    };

    let extrasBuilt = false;

    function renderExtras(data) {
        const host = U.el('vehicle-extras');
        if (!host) return;

        if (!extrasBuilt) {
            // Every chip is built hidden. A chip that defaults to visible shows up on the
            // first frame of every spawn and only disappears once something turns it off,
            // which is how the developer marker ended up on screen for players who are not
            // developers.
            U.fill(host, Object.entries(EXTRA_ICONS).map(([key, path]) => U.make('div', {
                class: 'vext__chip', 'data-extra': key, hidden: 'hidden', 'data-on': 'false',
            }, [U.svg('svg', { viewBox: '0 0 24 24' }, [U.svg('path', { d: path })])])));
            extrasBuilt = true;
        }

        const settings = S.settings;
        const chip = (key) => host.querySelector(`[data-extra="${key}"]`);

        const armed = chip('armed');
        if (armed) {
            U.show(armed, settings.show.armed && data.armed);
            U.attr(armed, 'data-on', !!data.armed);
        }

        const parachute = chip('parachute');
        if (parachute) {
            const deployed = data.parachute >= 0;
            U.show(parachute, settings.show.parachute && deployed);
            U.attr(parachute, 'data-on', deployed);
        }
    }

    /* ------------------------------------------------------------------------------------
       Routing
       ------------------------------------------------------------------------------------ */

    const HANDLERS = {

        boot(data) {
            S.boot(data);
            Money.configure(S.statik.money);
            Toast.configure(S.statik.notifications);
        },

        settings(data) {
            S.applySettings(data.settings);
            Menu.refresh();
            Layout.refresh();
        },

        tick: onTick,

        compass(data) {
            Compass.show(data.show !== false);
            if (data.show === false) return;
            Compass.update(data.degrees || 0, data.cardinal || '', S.settings);
        },

        streets(data) {
            const node = U.el('streets');
            if (!node) return;

            U.attr(U.el('el-streets'), 'data-visible', data.show !== false);
            U.attr(node, 'data-empty', data.show === false);
            if (data.show === false) return;

            U.text(U.el('street-name'), data.street || '');
            U.text(U.el('street-cross'), data.crossing || '');
            U.text(U.el('street-zone'), data.zone || '');
            U.attr(node, 'data-upper', !!data.uppercase);
        },

        heading(data) {
            // The street banner's compass letter, sent with the heading rather than the
            // streets so it keeps updating while the street name does not change.
            U.text(U.el('street-dir'), data.cardinal || '');
        },

        money(data) {
            // The change banner obeys the element switch. It is passive - nobody asked for it -
            // so a player who turned the money element off should not see it flash.
            if (!S.settings || !S.settings.show || !S.settings.show.money) return;
            Money.change(data);
        },

        showAccount(data) {
            // `/cash` and `/bank` answer even when the element is off. The player asked.
            Money.reveal(data.duration);
            Money.showAccount(data.account, data.amount, data.duration);
        },

        minimap(data) {
            const frame = U.el('minimap-frame');
            const root = document.documentElement;

            U.cssVar(root, '--map-x', `${data.x || 0}%`);
            U.cssVar(root, '--map-y', `${data.y || 0}%`);
            U.cssVar(root, '--map-scale', data.scale || 1);

            if (!frame) return;
            U.attr(frame, 'data-shape', data.shape || 'square');
            U.attr(frame, 'data-on', data.borders !== false);
        },

        cinematic(data) {
            // The bars only. Whether the HUD itself is drawn is the tick's decision - two
            // writers on one attribute means the loser flickers.
            const hud = U.el('hud');
            U.cssVar(document.documentElement, '--cine-height', `${(data.height || 0.12) * 100}%`);
            U.attr(hud, 'data-cinematic', !!data.on);
        },

        dev(data) {
            const host = U.el('vehicle-extras');
            if (!host) return;
            const chip = host.querySelector('[data-extra="dev"]');
            if (chip) {
                U.show(chip, !!data.on);
                U.attr(chip, 'data-on', !!data.on);
            }
        },

        toast(data) {
            Toast.show(data.message, data.kind, data.duration);
        },

        openMenu(data) {
            Menu.setOpen(data);
        },

        closeMenu() {
            Menu.close(true);
            Layout.setOpen(false);
        },

        layoutMode(data) {
            Layout.setOpen(data.on === true);
        },

        manualHide(data) {
            // Instant feedback for /hidehud; the tick confirms the same state a frame later.
            // Toasts live outside the hidden set, so "type /hidehud to bring it back" shows.
            U.attr(U.el('hud'), 'data-hidden', data.on === true);
        },

        hide() {
            U.attr(U.el('hud'), 'data-ready', false);
        },
    };

    window.addEventListener('message', (event) => {
        const data = event.data;
        if (!data || typeof data.action !== 'string') return;

        const handler = HANDLERS[data.action];
        if (!handler) return;

        try {
            handler(data);
        } catch (error) {
            // A render that throws must not take the message pump with it: one bad payload
            // would otherwise freeze every gauge on screen until the resource restarts.
            console.error('[v-hud]', data.action, error);
        }
    });

    /* ------------------------------------------------------------------------------------
       Startup
       ------------------------------------------------------------------------------------ */

    document.addEventListener('DOMContentLoaded', () => {
        Menu.bind();
        Layout.bind();
        Toast.configure();
    });

    // DOMContentLoaded has usually already fired by the time a NUI page's scripts run, so
    // binding is also attempted immediately. Both paths are idempotent.
    if (document.readyState !== 'loading') {
        Menu.bind();
        Layout.bind();
        Toast.configure();
    }

})();
