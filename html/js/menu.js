/*
    js/menu.js

    The settings panel: ten tabs built from data.

    Every control is one of six kinds - toggle, slider, segmented choice, colour well, card
    grid, button - and every one of them writes through S.set, which applies locally and posts
    to Lua. So a change is visible on the HUD behind the panel on the same frame it is made,
    and the Lua side's re-validated copy comes back a moment later and corrects it if the
    server refused.

    A control whose path the server locked is drawn with a padlock and made inert. The lock is
    enforced server-side; this only draws it.
*/

const Menu = (() => {

    let open = false;
    let active = 'general';
    let providers = {};
    let query = '';

    /* ------------------------------------------------------------------------------------
       Control builders
       ------------------------------------------------------------------------------------ */

    /**
     * The shell every control sits in: a label, an optional help line, a lock state.
     *
     * `stacked` puts the control on its own line under the label instead of beside it. A wide
     * control in the right-hand column squeezes the label into a two-word-per-line sliver and
     * still runs out of room - which is what twelve gauge shapes did to "Forme des jauges".
     */
    function row(label, control, help, path, stacked) {
        const locked = path ? S.isLocked(path) : false;

        // `label` may be a string or a node - the Elements tab passes a node so it can put the
        // gauge's own icon beside the name. The search index needs the text either way.
        const isNode = label && typeof label === 'object' && label.nodeType === 1;
        const text = isNode ? (label.textContent || '') : String(label == null ? '' : label);

        const children = [
            U.make('div', { class: 'row__label' }, [
                label,
                locked ? U.make('span', { class: 'row__lock', title: S.t('menu.locked'), text: '🔒' }) : null,
            ]),
            U.make('div', { class: 'row__control' }, [control]),
        ];

        if (help) children.push(U.make('p', { class: 'row__help', text: help }));

        return U.make('div', {
            class: 'row',
            'data-locked': locked,
            'data-stacked': stacked ? 'true' : 'false',
            'data-search': `${text} ${help || ''}`.toLowerCase(),
        }, children);
    }

    function toggle(path, label, help) {
        const node = U.make('button', {
            class: 'switch',
            'data-on': !!S.get(path, false),
            onclick: () => {
                const next = !S.get(path, false);
                if (S.set(path, next)) {
                    U.attr(node, 'data-on', next);
                    click();
                }
            },
        });

        return row(label, node, help, path);
    }

    function slider(path, label, min, max, step, formatter, help) {
        const readout = U.make('span', { class: 'slider__value' });
        const input = U.make('input', {
            type: 'range', min, max, step,
            value: S.get(path, min),
        });

        const paint = (value) => U.text(readout, formatter ? formatter(value) : value);
        paint(S.get(path, min));

        input.addEventListener('input', () => {
            const value = Number(input.value);
            paint(value);
            S.set(path, value);
        });

        return row(label, U.make('div', { class: 'slider' }, [input, readout]), help, path);
    }

    function segments(path, label, options, help) {
        const nodes = [];
        const wrap = U.make('div', { class: 'segments' });

        for (const option of options) {
            const node = U.make('button', {
                class: 'segment',
                text: option.label,
                'data-active': S.get(path) === option.value,
                onclick: () => {
                    if (!S.set(path, option.value)) return;
                    for (const other of nodes) U.attr(other, 'data-active', false);
                    U.attr(node, 'data-active', true);
                    click();
                },
            });
            nodes.push(node);
            wrap.appendChild(node);
        }

        // Four is where a segmented control stops fitting beside its label at the panel's
        // width. Above that it gets its own line.
        return row(label, wrap, help, path, options.length > 4);
    }

    function colour(path, label) {
        const value = S.get(path, '#ffffff');
        const hex = U.make('span', { class: 'swatch__hex', text: value });

        const input = U.make('input', { type: 'color', value });
        input.addEventListener('input', () => {
            U.text(hex, input.value);
            well.style.background = input.value;
            S.set(path, input.value);
        });

        const well = U.make('label', { class: 'swatch', style: { background: value } }, [input]);

        return row(label, U.make('div', { class: 'row__control' }, [hex, well]), null, path);
    }

    function button(label, kind, onClick) {
        return U.make('button', {
            class: `btn btn--${kind}`,
            text: label,
            onclick: () => { onClick(); click(); },
        });
    }

    function section(title, help, children) {
        return U.make('div', { class: 'section' }, [
            U.make('h2', { class: 'section__title', text: title }),
            help ? U.make('p', { class: 'section__help', text: help }) : null,
            ...children,
        ]);
    }

    const click = () => U.post('sound', { name: 'click', volume: 0.06 });

    /**
     * Export and import, as one panel.
     *
     * The code is a base64 string of the player's whole settings table. Pasting one goes
     * through exactly the same validation as any other save - merged into the schema, coerced,
     * then policed - so a code from a server with different rules cannot smuggle a locked
     * value in. It arrives as a suggestion, not as an instruction.
     */
    function sharePanel() {
        const field = U.make('textarea', {
            class: 'share__field',
            spellcheck: 'false',
            rows: 3,
            placeholder: U.SHARE_PREFIX + '…',
        });

        const status = U.make('p', { class: 'share__status' });

        const say = (text, kind) => {
            U.text(status, text);
            U.attr(status, 'data-kind', kind || 'info');
        };

        return U.make('div', { class: 'share', 'data-search': S.t('share.title').toLowerCase() }, [
            field,
            U.make('div', { class: 'share__actions' }, [
                U.make('button', {
                    class: 'btn btn--ghost',
                    text: S.t('share.export'),
                    onclick: () => {
                        field.value = U.encodeShare(S.settings);
                        field.select();
                        say(U.copyText(field.value) ? S.t('share.copied') : S.t('share.copy_manual'),
                            'ok');
                        click();
                    },
                }),
                U.make('button', {
                    class: 'btn btn--primary',
                    text: S.t('share.import'),
                    onclick: () => {
                        const parsed = U.decodeShare(field.value);
                        if (!parsed) {
                            say(S.t('share.invalid'), 'bad');
                            return;
                        }

                        U.post('import', { settings: parsed });
                        say(S.t('share.imported'), 'ok');
                        click();
                    },
                }),
            ]),
            status,
        ]);
    }

    /**
     * A confirmation the player can actually dismiss.
     *
     * NEVER window.confirm() here. CEF has no chrome to draw a native dialog into: the call
     * blocks the page with NUI focus held, the game keeps the cursor, and the only way out is
     * to restart the client. That is exactly what "Tout réinitialiser" used to do.
     */
    function confirmThen(message, onYes) {
        const panel = U.el('menu');
        if (!panel) return;

        const close = () => { if (sheet.parentNode) sheet.remove(); };

        const sheet = U.make('div', { class: 'confirm' }, [
            U.make('div', { class: 'confirm__box' }, [
                U.make('p', { class: 'confirm__text', text: message }),
                U.make('div', { class: 'confirm__actions' }, [
                    U.make('button', {
                        class: 'btn btn--ghost',
                        text: S.t('menu.cancel'),
                        onclick: () => { close(); click(); },
                    }),
                    U.make('button', {
                        class: 'btn btn--danger',
                        text: S.t('menu.reset'),
                        onclick: () => { close(); onYes(); click(); },
                    }),
                ]),
            ]),
        ]);

        // Clicking the backdrop cancels, so there is always a way out even if a button breaks.
        sheet.addEventListener('click', (event) => { if (event.target === sheet) close(); });
        panel.appendChild(sheet);
    }

    /* ------------------------------------------------------------------------------------
       Tabs
       ------------------------------------------------------------------------------------ */

    const TABS = {

        general: () => {
            const themes = U.make('div', { class: 'themes' });

            for (const theme of (S.statik.themes || [])) {
                // A div, not a <button>. See the note on .speedo-card in menu.css: the UA
                // stylesheet CEF ships puts `align-items: flex-start` on every button, which
                // collapsed this card's colour swatch to a 26px sliver.
                const card = U.make('div', {
                    class: 'theme-card',
                    role: 'button',
                    tabindex: '0',
                    'data-active': S.get('theme') === theme.key,
                    'data-search': theme.label.toLowerCase(),
                    onclick: () => {
                        U.post('applyTheme', { theme: theme.key });
                        for (const other of themes.children) U.attr(other, 'data-active', false);
                        U.attr(card, 'data-active', true);
                        click();
                    },
                }, [
                    U.make('div', { class: 'theme-card__swatch' },
                        (theme.swatch || []).map((hex) => U.make('i', { style: { background: hex } }))),
                    U.make('span', { class: 'theme-card__label', text: theme.label }),
                ]);
                themes.appendChild(card);
            }

            return [
                section(S.t('general.theme'), S.t('general.theme_help'), [themes]),
                section(S.t('tab.general'), null, [
                    toggle('compact', S.t('general.compact'), S.t('general.compact_help')),
                    toggle('immersive', S.t('general.immersive'), S.t('general.immersive_help')),
                    slider('immersiveDelay', S.t('general.immersive_delay'), 2, 30, 1, (v) => `${v} s`),
                    slider('scale', S.t('general.scale'), 0.6, 1.6, 0.05, (v) => `${Math.round(v * 100)} %`),
                    slider('opacity', S.t('general.opacity'), 0.25, 1, 0.05, (v) => `${Math.round(v * 100)} %`),
                    segments('units', S.t('general.units'), [
                        { value: 'kmh', label: S.t('general.units_kmh') },
                        { value: 'mph', label: S.t('general.units_mph') },
                    ]),
                    toggle('cinematic', S.t('general.cinematic'), S.t('general.cinematic_help')),
                ]),
            ];
        },

        elements: () => {
            const keys = [
                'health', 'armor', 'hunger', 'thirst', 'stress', 'oxygen', 'stamina',
                'voice', 'speedometer', 'compass', 'streets', 'minimap',
                'nitro', 'harness', 'engine', 'seatbelt', 'parachute', 'armed', 'dev',
            ];

            // Any gauge the operator added in Config.Status appears here too, with no code
            // change: the boot payload carries the definitions and this reads them.
            for (const status of (S.statik.statuses || [])) {
                if (!keys.includes(status.key)) keys.push(status.key);
            }

            // An element the server removed is not shown as a locked switch - it is not shown
            // at all. A padlock says "you may not have this"; a removed element simply does
            // not exist on this server, and a row for it is a row about nothing.
            const removed = U.asArray(S.choices().removed);

            // Each row carries the gauge's OWN icon.
            //
            // Without it the tab is a list of words, and a player looking at a symbol on screen
            // has no way to tell which switch turns that symbol off - which is exactly the
            // complaint "I can't remove this thing and I don't know what it is". The icon comes
            // from the same Config.Status definition that draws the gauge, so a custom gauge an
            // operator added gets its own icon here with no extra work.
            const icons = {};
            for (const status of (S.statik.statuses || [])) {
                if (status.icon) icons[status.key] = [{ d: status.icon, fill: false }];
            }

            // The speedometer's own switches get their tell-tale symbol, so the row that turns
            // the nitrous lamp off carries the nitrous lamp. `seatbelt` is called `belt` on the
            // cluster; the rest match by name.
            for (const [key, lamp] of Object.entries({
                nitro: 'nitro', harness: 'harness', engine: 'engine', seatbelt: 'belt',
            })) {
                if (!icons[key]) {
                    const parts = Speedo.lampIcon(lamp);
                    if (parts) icons[key] = parts;
                }
            }

            const label = (key) => {
                const parts = icons[key];
                const text = U.make('span', { text: S.t(`element.${key}`) });
                if (!parts) return text;
                return U.make('span', { class: 'element-label' }, [
                    U.svg('svg', { class: 'element-label__icon', viewBox: '0 0 24 24' },
                        parts.map((p) => U.svg('path', {
                            d: p.d, class: p.fill ? 'element-label__solid' : '',
                        }))),
                    text,
                ]);
            };

            return [
                section(S.t('tab.elements'), S.t('elements.help'),
                    keys.filter((key) => !removed.includes(key))
                        .map((key) => toggle(`show.${key}`, label(key)))),
            ];
        },

        style: () => {
            // Every list comes from the server, already narrowed by Config.Policy. A control
            // with one option left is not a choice, so it is not drawn at all.
            const choice = S.choices();
            const pick = (path, label, values, labeller, help) => (values.length > 1
                ? segments(path, label, values.map((v) => ({ value: v, label: labeller(v) })), help)
                : null);

            return [
                section(S.t('style.gauge'), null, [
                    pick('style.gauge', S.t('style.gauge'), choice.gaugeShapes,
                        (v) => S.t(`style.gauge_${v}`)),
                    pick('style.direction', S.t('style.direction'), choice.directions,
                        (v) => S.t(`style.direction_${v}`)),
                ].filter(Boolean)),
                section(S.t('style.surface'), S.t('style.surface_help'), [
                    pick('style.surface', S.t('style.surface'), choice.surfaces,
                        (v) => S.t(`style.surface_${v}`)),
                    slider('style.blur', S.t('style.blur'), 0, 32, 1, (v) => `${v} px`),
                ].filter(Boolean)),
                section(S.t('tab.style'), null, [
                    toggle('style.icons', S.t('style.icons')),
                    toggle('style.values', S.t('style.values')),
                    toggle('style.hideFull', S.t('style.hide_full'), S.t('style.hide_full_help')),
                    toggle('style.outline', S.t('style.outline')),
                    toggle('style.glow', S.t('style.glow')),
                    slider('style.corner', S.t('style.corner'), 0, 24, 1, (v) => `${v} px`),
                    slider('style.gap', S.t('style.gap'), 0, 32, 1, (v) => `${v} px`),
                ]),
            ];
        },

        colours: () => {
            const keys = ['accent', 'health', 'armor', 'hunger', 'thirst', 'stress', 'oxygen',
                'stamina', 'voice', 'money', 'speed', 'fuel', 'rpm', 'warning',
                'background', 'text'];

            for (const status of (S.statik.statuses || [])) {
                if (!keys.includes(status.key)) keys.push(status.key);
            }

            return [
                section(S.t('tab.colours'), S.t('colour.help'), [
                    ...keys.map((key) => colour(`colours.${key}`, S.t(`colour.${key}`))),
                    U.make('div', { class: 'menu__actions', style: { marginTop: '14px' } }, [
                        button(S.t('colour.reset'), 'ghost', () => {
                            const theme = S.get('theme');
                            if (theme && theme !== 'custom') U.post('applyTheme', { theme });
                            else U.post('resetSection', { section: 'colours' });
                        }),
                    ]),
                ]),
            ];
        },

        layout: () => {
            const presets = U.make('div', { class: 'segments' });

            for (const preset of (S.statik.layouts || [])) {
                presets.appendChild(U.make('button', {
                    class: 'segment',
                    text: S.t(preset.label),
                    onclick: () => {
                        U.post('applyLayout', { layout: preset.key });
                        click();
                    },
                }));
            }

            const rows = S.ELEMENTS.map((key) => U.make('div', { class: 'section' }, [
                U.make('h2', { class: 'section__title', text: S.t(`layout.group_${key}`) }),
                slider(`positions.${key}.x`, S.t('layout.x'), 0, 100, 0.5, (v) => `${U.round(v, 1)} %`),
                slider(`positions.${key}.y`, S.t('layout.y'), 0, 100, 0.5, (v) => `${U.round(v, 1)} %`),
            ]));

            return [
                section(S.t('layout.edit'), S.t('layout.edit_help'), [
                    U.make('div', { class: 'menu__actions' }, [
                        button(S.t('layout.edit'), 'primary', () => {
                            close(true);
                            Layout.setOpen(true);
                        }),
                        button(S.t('layout.reset'), 'ghost', () => {
                            U.post('resetSection', { section: 'positions' });
                        }),
                    ]),
                ]),
                section(S.t('layout.preset'), null, [presets]),
                ...rows,
            ];
        },

        minimap: () => [
            section(S.t('tab.minimap'), S.t('minimap.help'), [
                segments('minimap.shape', S.t('minimap.shape'), [
                    { value: 'square', label: S.t('minimap.shape_square') },
                    { value: 'circle', label: S.t('minimap.shape_circle') },
                ]),
                toggle('minimap.borders', S.t('minimap.borders')),
                slider('minimap.x', S.t('minimap.x'), -20, 20, 0.25, (v) => `${U.round(v, 2)} %`),
                slider('minimap.y', S.t('minimap.y'), -20, 20, 0.25, (v) => `${U.round(v, 2)} %`),
                slider('minimap.scale', S.t('minimap.scale'), 0.7, 1.5, 0.02, (v) => `${Math.round(v * 100)} %`),
                toggle('minimap.hide', S.t('minimap.hide')),
                toggle('minimap.vehicleOnly', S.t('minimap.vehicle_only')),
            ]),
        ],

        speedo: () => {
            const cards = U.make('div', { class: 'speedos' });

            // A live sample so each card shows the face doing something, not sitting at zero.
            const sample = { speed: 128, rpm: 0.62, fuel: 68, engine: 88, gear: '4', unitLabel: S.t('unit.kmh') };

            for (const entry of (S.statik.speedometers || [])) {
                const preview = U.make('div', { class: 'spd-preview' });
                // A div, not a <button> - the whole reason these cards were blank in game.
                const card = U.make('div', {
                    class: 'speedo-card',
                    role: 'button',
                    tabindex: '0',
                    'data-active': S.get('speedometer.style') === entry.key,
                    'data-search': S.t(entry.label).toLowerCase(),
                    onclick: () => {
                        if (!S.set('speedometer.style', entry.key)) return;
                        for (const other of cards.children) U.attr(other, 'data-active', false);
                        U.attr(card, 'data-active', true);
                        click();
                    },
                }, [preview, U.make('span', { class: 'speedo-card__label', text: S.t(entry.label) })]);

                cards.appendChild(card);
                // Built synchronously. Deferring this to an animation frame is what left the
                // cards blank in game: the callback ran against a card that had not been laid
                // out, and a scale computed from a zero-width box is a zero scale.
                Speedo.preview(preview, entry.key, sample, entry.size);
            }

            return [
                section(S.t('speedo.style'), null, [cards]),
                section(S.t('tab.speedo'), null, [
                    toggle('speedometer.fuel', S.t('speedo.fuel')),
                    toggle('speedometer.range', S.t('speedo.style')),
                    toggle('speedometer.rpm', S.t('speedo.rpm')),
                    toggle('speedometer.gear', S.t('speedo.gear')),
                    toggle('speedometer.odometer', S.t('speedo.odometer'), S.t('speedo.odometer_help')),
                    toggle('speedometer.engine', S.t('speedo.engine')),
                    toggle('speedometer.belt', S.t('speedo.belt')),
                    toggle('speedometer.nitro', S.t('speedo.nitro')),
                    toggle('speedometer.harness', S.t('speedo.harness')),
                    toggle('speedometer.altitude', S.t('speedo.altitude')),
                    toggle('speedometer.parts', S.t('speedo.parts'), S.t('speedo.parts_help')),
                ]),

                // What every lamp under the cluster means. A row of warning symbols is only
                // obvious to somebody who already drives, and there is nowhere on a HUD to put
                // a caption - so the captions live here.
                section(S.t('speedo.legend'), S.t('speedo.legend_help'), [
                    U.make('div', { class: 'legend' }, Speedo.legend().map((lamp) => {
                        // Lit, so the colour is visible: an unlit row of grey icons says
                        // nothing about which ones are warnings and which are confirmations.
                        U.show(lamp.node, true);
                        U.attr(lamp.node, 'data-on', true);
                        return U.make('div', { class: 'legend__item' }, [
                            lamp.node,
                            U.make('span', { class: 'legend__text', text: S.t(`lamp.${lamp.key}`) }),
                        ]);
                    })),
                ]),
            ];
        },

        compass: () => [
            section(S.t('tab.compass'), null, [
                S.choices().compassStyles.length > 1 ? segments('compass.style', S.t('compass.style'),
                    S.choices().compassStyles.map((v) => ({ value: v, label: S.t(`compass.style_${v}`) }))) : null,
                toggle('compass.degrees', S.t('compass.degrees')),
                toggle('compass.pointer', S.t('compass.pointer')),
                toggle('compass.cardinals', S.t('compass.cardinals')),
                toggle('compass.follow', S.t('compass.follow'), S.t('compass.follow_help')),
                toggle('compass.vehicleOnly', S.t('compass.vehicle_only')),
            ].filter(Boolean)),
        ],

        streets: () => [
            section(S.t('tab.streets'), null, [
                toggle('streets.crossing', S.t('streets.crossing')),
                toggle('streets.zone', S.t('streets.zone')),
                toggle('streets.direction', S.t('streets.direction')),
                toggle('streets.uppercase', S.t('streets.uppercase')),
                toggle('streets.matchMap', S.t('streets.match_map'), S.t('streets.match_map_help')),
                toggle('streets.vehicleOnly', S.t('streets.vehicle_only')),
            ]),
        ],

        advanced: () => {
            const table = U.make('dl', { class: 'providers' });
            for (const [key, value] of Object.entries(providers)) {
                table.appendChild(U.make('dt', { text: key }));
                table.appendChild(U.make('dd', { text: value }));
            }

            return [
                section(S.t('advanced.refresh'), S.t('advanced.refresh_help'), [
                    segments('advanced.refresh', S.t('advanced.refresh'),
                        U.asArray(S.statik.refreshRates).map((rate) => ({
                            value: rate, label: `${rate} fps`,
                        }))),
                ]),
                section(S.t('tab.advanced'), null, [
                    toggle('advanced.sounds', S.t('advanced.sounds')),
                    toggle('advanced.notifications', S.t('advanced.notifications')),
                    toggle('advanced.lowFuel', S.t('advanced.low_fuel')),
                ]),
                S.statik.sharing === false ? null : section(S.t('share.title'), S.t('share.help'), [
                    sharePanel(),
                ]),
                section('Compatibility', null, [table]),

                // About. The authorship row is part of the Software under the licence's
                // attribution clause - see LICENSE. It may be translated and restyled, and
                // your own credits may sit beside it; it may not be removed.
                section(S.t('advanced.about_title'), S.t('advanced.about'), [
                    U.make('dl', { class: 'providers' }, [
                        U.make('dt', { text: S.t('advanced.version') }),
                        U.make('dd', { text: String(S.statik.version || '') }),
                        U.make('dt', { text: S.t('advanced.author') }),
                        U.make('dd', { text: 'vyrriox' }),
                    ]),
                ]),
                section(S.t('advanced.reset_all'), null, [
                    U.make('div', { class: 'menu__actions' }, [
                        button(S.t('advanced.reset_all'), 'danger', () => {
                            confirmThen(S.t('menu.reset_confirm'), () => U.post('reset'));
                        }),
                    ]),
                ]),
            ];
        },
    };

    const TAB_ORDER = ['general', 'elements', 'style', 'colours', 'layout',
        'minimap', 'speedo', 'compass', 'streets', 'advanced'];

    /* ------------------------------------------------------------------------------------
       Rendering
       ------------------------------------------------------------------------------------ */

    function renderTabs() {
        const nav = U.el('menu-tabs');
        if (!nav) return;

        U.fill(nav, TAB_ORDER.map((key) => U.make('button', {
            class: 'tab',
            'data-active': key === active,
            onclick: () => { active = key; renderTabs(); renderContent(); click(); },
        }, [
            U.make('i', { class: 'tab__dot' }),
            U.make('span', { text: S.t(`tab.${key}`) }),
        ])));
    }

    function renderContent() {
        const content = U.el('menu-content');
        if (!content) return;

        const builder = TABS[active] || TABS.general;
        U.fill(content, builder());
        content.scrollTop = 0;
        applyFilter();

        // The speedometer cards are built before this insertion, so their arcs measured zero
        // and drew nothing. Now that they are in the document their paths have a length, so
        // paint them again. Cheap - ten faces, and only on a tab change.
        Speedo.settlePreviews(content);
    }

    /** The search box. Hides rows whose label and help do not contain the query, and hides a
     *  section whose rows have all gone, so filtering never leaves a heading over nothing. */
    function applyFilter() {
        const content = U.el('menu-content');
        if (!content) return;

        const term = query.trim().toLowerCase();
        let anyVisible = false;

        for (const node of content.querySelectorAll('[data-search]')) {
            const match = !term || node.getAttribute('data-search').includes(term);
            node.hidden = !match;
            if (match) anyVisible = true;
        }

        for (const node of content.querySelectorAll('.section')) {
            const searchable = node.querySelectorAll('[data-search]');
            if (!searchable.length) {
                node.hidden = !!term;
                continue;
            }
            node.hidden = Array.from(searchable).every((child) => child.hidden);
        }

        let empty = content.querySelector('.menu__empty');
        if (term && !anyVisible) {
            if (!empty) {
                empty = U.make('p', { class: 'menu__empty', text: S.t('menu.no_results') });
                content.appendChild(empty);
            }
            empty.hidden = false;
        } else if (empty) {
            empty.hidden = true;
        }
    }

    /* ------------------------------------------------------------------------------------
       Open and close
       ------------------------------------------------------------------------------------ */

    function setOpen(payload) {
        const node = U.el('menu');
        if (!node) return;

        providers = (payload && payload.providers) || {};
        open = true;
        node.hidden = false;
        U.attr(node, 'data-out', false);

        U.text(U.el('menu-title'), S.t('menu.title'));
        U.text(U.el('menu-subtitle'), S.t('menu.subtitle'));
        U.text(U.el('menu-reset'), S.t('menu.reset_all'));
        U.text(U.el('menu-done'), S.t('menu.done'));
        U.text(U.el('menu-meta'), `v-hud ${S.statik.version || ''} — ${S.t('advanced.about')}`);

        const search = U.el('menu-search');
        if (search) search.placeholder = S.t('menu.search');

        renderTabs();
        renderContent();
    }

    /** `silent` skips telling Lua, for the case where the layout editor is taking over focus
     *  and closing the menu is a step rather than the player's intent. */
    function close(silent) {
        const node = U.el('menu');
        if (!node || !open) return;

        open = false;
        U.attr(node, 'data-out', true);
        setTimeout(() => { node.hidden = true; }, 140);

        if (!silent) U.post('close');
    }

    function bind() {
        const closeButton = U.el('menu-close');
        if (closeButton) closeButton.addEventListener('click', () => close());

        const done = U.el('menu-done');
        if (done) done.addEventListener('click', () => close());

        const reset = U.el('menu-reset');
        if (reset) {
            reset.addEventListener('click', () => {
                confirmThen(S.t('menu.reset_confirm'), () => U.post('reset'));
            });
        }

        const search = U.el('menu-search');
        if (search) {
            search.addEventListener('input', () => { query = search.value; applyFilter(); });
        }

        document.addEventListener('keydown', (event) => {
            if (event.key !== 'Escape') return;
            if (Layout.open) Layout.setOpen(false);
            else if (open) close();
        });
    }

    /** Rebuild the visible tab after settings changed underneath it - an admin push, a theme
     *  applied, a reset. Without this the switches keep showing the old values. */
    function refresh() {
        if (!open) return;
        renderContent();
    }

    return { bind, setOpen, close, refresh, get open() { return open; } };

})();
